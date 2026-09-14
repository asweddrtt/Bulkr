import 'dart:convert';
import 'dart:io';

import 'package:bulkr/models/app_notification.dart';
import 'package:bulkr/models/challenge.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a challenge measures, and the three places that have to agree about it.
///
/// A metric exists in the Dart enum, in a CHECK constraint, and in a CASE in
/// `challenge_scores`. Miss the second and every challenge of the new kind is
/// refused on insert; miss the third and they all score null, sort last, and
/// look like a leaderboard that has not loaded. Neither failure is visible
/// from the app until somebody tries it, which is what the last group here is
/// for.
void main() {
  group('writing a score', () {
    test('days are whole and kilograms are not', () {
      expect(ChallengeMetric.daysLogged.format(12), '12');
      expect(ChallengeMetric.daysLogged.format(12.0), '12');
      expect(ChallengeMetric.weightGain.format(2.4), '2.4');
    });

    test('a round number of kilograms drops its decimal', () {
      // "2.0 kg" next to "2.4 kg" reads as a rounding artefact rather than as
      // a measurement.
      expect(ChallengeMetric.weightGain.format(2), '2');
      expect(ChallengeMetric.weightGain.format(-1.5), '-1.5');
    });

    test('only counts are counts', () {
      expect(ChallengeMetric.daysLogged.isCount, isTrue);
      expect(ChallengeMetric.weightGain.isCount, isFalse);
    });
  });

  group('parsing', () {
    test('reads the column value', () {
      for (final ChallengeMetric metric in ChallengeMetric.values) {
        expect(ChallengeMetric.parse(metric.column), metric);
      }
    });

    test('a metric this build has never heard of degrades', () {
      // A client older than the database. Rendering the wrong unit beats a
      // feed that throws halfway down.
      expect(ChallengeMetric.parse('bench_press'), ChallengeMetric.weightGain);
      expect(ChallengeMetric.parse(null), ChallengeMetric.weightGain);
    });
  });

  group('setting one up', () {
    ChallengeDraft draft({
      ChallengeMetric metric = ChallengeMetric.weightGain,
      double? goal,
      int days = 30,
    }) => ChallengeDraft(
      title: 'Bulk together',
      metric: metric,
      goalAmount: goal,
      days: days,
    );

    test('a goal is required and must be positive', () {
      expect(draft(goal: null).canSubmit, isFalse);
      expect(draft(goal: 0).canSubmit, isFalse);
      expect(draft(goal: 4).canSubmit, isTrue);
    });

    test('you cannot log more days than the challenge runs for', () {
      // Reachable by shortening the length after typing the goal, which is the
      // order people do it in. A goal nobody can reach is not a challenge.
      expect(
        draft(metric: ChallengeMetric.daysLogged, goal: 30, days: 7).canSubmit,
        isFalse,
      );
      expect(
        draft(metric: ChallengeMetric.daysLogged, goal: 7, days: 7).canSubmit,
        isTrue,
      );
    });

    test('weight has no such ceiling', () {
      // An ambitious number is a choice, not an impossibility.
      expect(draft(goal: 500, days: 7).canSubmit, isTrue);
    });

    test('the metric reaches the row', () {
      final Map<String, dynamic> values = draft(
        metric: ChallengeMetric.daysLogged,
        goal: 5,
        days: 7,
      ).toRowValues(postId: 'p1', createdBy: 'u1');

      expect(values['metric'], ChallengeMetric.daysLogged.column);
      // Never sent: the server's clock decides when a challenge starts, or a
      // device with a wrong clock could backdate one.
      expect(values.containsKey('starts_at'), isFalse);
    });
  });

  group('where I stand', () {
    MyChallengeStanding standing({
      double? score,
      double? aheadScore,
      String? aheadName,
      double goal = 10,
    }) => MyChallengeStanding(
      challengeId: 'c1',
      postId: 'p1',
      title: 'Bulk together',
      metric: ChallengeMetric.weightGain,
      goalAmount: goal,
      startsAt: DateTime.now().subtract(const Duration(days: 2)),
      endsAt: DateTime.now().add(const Duration(days: 4)),
      participantCount: 7,
      rank: 2,
      score: score,
      hasData: score != null,
      aheadScore: aheadScore,
      aheadName: aheadName,
    );

    test('nobody above means leading', () {
      expect(standing(score: 3).isLeading, isTrue);
      expect(standing(score: 3, aheadScore: 4, aheadName: 'Sara').isLeading,
          isFalse);
    });

    test('the gap is the number the card is for', () {
      expect(
        standing(score: 3, aheadScore: 3.6, aheadName: 'Sara').gapToAhead,
        closeTo(0.6, 0.0001),
      );
    });

    test('level with the person above is not a gap', () {
      // A gap of zero would render as "Sara is 0 kg ahead of you", which is a
      // sentence about nothing.
      expect(
        standing(score: 3, aheadScore: 3, aheadName: 'Sara').gapToAhead,
        isNull,
      );
    });

    test('no score means no gap to report', () {
      expect(
        standing(score: null, aheadScore: 4, aheadName: 'Sara').gapToAhead,
        isNull,
      );
    });

    test('progress is clamped at both ends', () {
      // A bar that runs backwards is not a thing, and overshooting a goal
      // fills it rather than overflowing it.
      expect(standing(score: -2).progress, 0);
      expect(standing(score: 5).progress, closeTo(0.5, 0.0001));
      expect(standing(score: 40).progress, 1);
      expect(standing(score: 3, goal: 0).progress, 0);
    });

    test('reads the row the function returns', () {
      final MyChallengeStanding parsed = MyChallengeStanding.fromRow(
        <String, dynamic>{
          'challenge_id': 'c1',
          'post_id': 'p1',
          'title': 'Bulk together',
          'metric': 'days_logged',
          'goal_amount': 20,
          'starts_at': '2026-09-01T00:00:00Z',
          'ends_at': '2026-10-01T00:00:00Z',
          'participant_count': 7,
          'my_rank': 2,
          'my_score': 11,
          'has_data': true,
          'ahead_score': 14,
          'ahead_name': 'Sara',
        },
      );

      expect(parsed.metric, ChallengeMetric.daysLogged);
      expect(parsed.rank, 2);
      expect(parsed.gapToAhead, 3);
      expect(parsed.aheadName, 'Sara');
    });

    test('an empty name from the server is no name', () {
      // `coalesce(nullif(btrim(display_name), ''), username)` can still come
      // back blank for a row with neither. Blank must read as "no name" and
      // not as somebody called nothing.
      final MyChallengeStanding parsed = MyChallengeStanding.fromRow(
        <String, dynamic>{
          'challenge_id': 'c1',
          'post_id': 'p1',
          'title': 't',
          'metric': 'weight_gain',
          'goal_amount': 4,
          'starts_at': '2026-09-01T00:00:00Z',
          'ends_at': '2026-10-01T00:00:00Z',
          'participant_count': 2,
          'my_rank': 1,
          'my_score': 1,
          'has_data': true,
          'ahead_score': null,
          'ahead_name': '   ',
        },
      );

      expect(parsed.aheadName, isNull);
      expect(parsed.isLeading, isTrue);
    });
  });

  group('a standing row', () {
    test('reads `score`, which is what the function now returns', () {
      // It was `gained_kg` until the column stopped always being kilograms.
      // Reading the old name would give every participant null, which renders
      // as a leaderboard where nobody has any data.
      final ChallengeStanding parsed = ChallengeStanding.fromRow(
        <String, dynamic>{
          'user_id': 'u1',
          'username': 'sara',
          'score': 2.4,
          'joined_at': '2026-09-01T00:00:00Z',
          'has_data': true,
        },
        currentUserId: 'u1',
      );

      expect(parsed.score, 2.4);
      expect(parsed.hasData, isTrue);
      expect(parsed.isMe, isTrue);
    });
  });

  group('the database knows about the same metrics', () {
    late final String sql =
        File('supabase/challenge_metrics.sql').readAsStringSync();

    test('every metric is allowed by the CHECK constraint', () {
      // Missing here means every challenge of that kind is refused on insert,
      // with a constraint-violation message nobody can act on.
      final RegExpMatch? check = RegExp(
        r'add constraint challenges_metric_check\s*check \(metric in \(([^)]*)\)',
        caseSensitive: false,
      ).firstMatch(sql);

      expect(check, isNotNull,
          reason: 'challenge_metrics.sql no longer widens the metric CHECK');

      for (final ChallengeMetric metric in ChallengeMetric.values) {
        expect(check!.group(1), contains("'${metric.column}'"),
            reason: '${metric.name} is not in the CHECK constraint');
      }
    });

    test('every metric is scored', () {
      // Missing here is worse than missing from the CHECK: the challenge is
      // created, and then every participant scores null, sorts last, and the
      // leaderboard looks like it failed to load.
      for (final ChallengeMetric metric in ChallengeMetric.values) {
        expect(sql, contains("when '${metric.column}' then"),
            reason: 'public.challenge_scores has no branch for ${metric.name}');
      }
    });

    test('the leaderboard returns a score, not kilograms', () {
      expect(sql, contains('score numeric'));
      expect(sql, isNot(contains('gained_kg numeric')),
          reason: 'the column was renamed when it stopped always being kg');
    });
  });

  group('the database knows about the same notifications', () {
    late final String sql =
        File('supabase/challenge_notifications.sql').readAsStringSync();
    late final Map<String, dynamic> translations = jsonDecode(
      File('assets/translations/en-US.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    test('every challenge kind is allowed by the CHECK constraint', () {
      // A kind the constraint refuses is a notification that is never written
      // — silently, inside a trigger, where nothing surfaces the failure.
      final Iterable<NotificationKind> challengeKinds =
          NotificationKind.values.where((NotificationKind k) => k.opensPost);

      expect(challengeKinds, isNotEmpty);

      for (final NotificationKind kind in challengeKinds) {
        expect(sql, contains("'${kind.dbValue}'"),
            reason: '${kind.name} is not in the notifications kind CHECK');
      }
    });

    test('every kind still has a sentence', () {
      for (final NotificationKind kind in NotificationKind.values) {
        expect(translations, contains(kind.messageKey),
            reason: '${kind.name} would render its own key');
      }
    });

    test('the sweep is scheduled', () {
      expect(sql, contains('challenge-clock-sweep'));
      expect(sql, contains('challenge_clock_sweep()'));
    });
  });

  group('every kind has push copy', () {
    // The bug this exists for: `notifications_send_push` fires on insert for
    // every row of every kind, and the sentence it sends is a CASE in
    // `push_payload` with an `else 'New activity'`. A kind added without a
    // branch does not fail, does not warn, and does not look wrong anywhere in
    // the schema — it just arrives on somebody's lock screen saying nothing.
    // All five challenge kinds shipped that way for exactly one commit.
    late final String schema = Directory('supabase')
        .listSync()
        .whereType<File>()
        .where((File f) => f.path.endsWith('.sql'))
        .map((File f) => f.readAsStringSync())
        .join('\n');

    test('no kind falls through to "New activity"', () {
      for (final NotificationKind kind in NotificationKind.values) {
        // Whitespace-tolerant: the original four branches are column-aligned
        // with two spaces before `then`, and a literal match would report them
        // as missing.
        expect(
          RegExp("when\\s+'${kind.dbValue}'\\s+then").hasMatch(schema),
          isTrue,
          reason: '${kind.name} has no branch in push_payload, so it would '
              'push as the generic fallback',
        );
      }
    });

    test('the fallback still exists for a kind written by a newer server', () {
      // It is the right answer for a row this schema has never heard of. It is
      // only wrong as the answer for a kind we shipped ourselves.
      expect(schema, contains("else 'New activity'"));
    });
  });
}
