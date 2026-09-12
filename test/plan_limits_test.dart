import 'dart:io';

import 'package:bulkr/core/plan_limits.dart';
import 'package:bulkr/models/entitlement.dart';
import 'package:flutter_test/flutter_test.dart';

/// What free gets, what premium removes, and the one way this can silently
/// break.
///
/// The numbers exist twice — here in Dart, and in `supabase/premium.sql` where
/// the policies that actually enforce them live — because the client decides
/// what to *show* and the database decides what is *allowed*. Two copies of a
/// pricing number drift: somebody generous raises the client's cap, the
/// database keeps rejecting at the old one, and the user is shown a library
/// they are not permitted to add to, with a 42501 for an explanation.
///
/// So the last group here reads the SQL and fails when the two disagree.
void main() {
  group('which limits apply', () {
    test('a free account gets the free limits', () {
      expect(PlanLimits.of(Entitlement.free), PlanLimits.free);
    });

    test('a premium account gets no ceilings', () {
      const Entitlement paid = Entitlement(tier: Tier.premium);

      expect(PlanLimits.of(paid), PlanLimits.premium);
      expect(PlanLimits.premium.isUnlimited, isTrue);
      expect(PlanLimits.premium.showsAds, isFalse);
    });

    test('an expired premium is charged free\'s limits', () {
      // The row still says premium; the date says otherwise. Reading the tier
      // alone would give a lapsed subscriber an unlimited library until some
      // background refresh got round to it.
      final Entitlement lapsed = Entitlement(
        tier: Tier.premium,
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      expect(PlanLimits.of(lapsed), PlanLimits.free);
      expect(lapsed.hasLapsed, isTrue);
    });

    test('a premium with no end date never expires', () {
      // A promo or a manual grant. Null is not "expired at the epoch".
      const Entitlement promo = Entitlement(tier: Tier.premium, source: 'promo');

      expect(promo.isPremium, isTrue);
      expect(promo.hasLapsed, isFalse);
    });
  });

  group('counting against a limit', () {
    test('unlimited always allows one more', () {
      expect(PlanLimits.allowsAnother(null, 9999), isTrue);
      expect(PlanLimits.remaining(null, 9999), isNull);
    });

    test('the limit is a ceiling, not an off-by-one', () {
      // 19 saved means the 20th may be saved. 20 saved means it may not.
      expect(PlanLimits.free.canSaveAnotherMeal(19), isTrue);
      expect(PlanLimits.free.canSaveAnotherMeal(20), isFalse);
    });

    test('being over the limit reads as zero remaining, never negative', () {
      // Reachable: somebody saves 40 meals on premium and then lets it lapse.
      // "-20 meals remaining" is not a sentence to put on a screen, and the
      // library is not deleted — it simply cannot grow.
      expect(PlanLimits.remaining(20, 26), 0);
    });

    test('one challenge at a time on free', () {
      expect(PlanLimits.free.canJoinAnotherChallenge(0), isTrue);
      expect(PlanLimits.free.canJoinAnotherChallenge(1), isFalse);
      expect(PlanLimits.premium.canJoinAnotherChallenge(50), isTrue);
    });
  });

  group('the history window', () {
    final DateTime now = DateTime(2026, 9, 12, 23, 50);

    test('today counts as one of the seven days', () {
      expect(PlanLimits.free.includesDay(DateTime(2026, 9, 12), now: now),
          isTrue);
      expect(PlanLimits.free.includesDay(DateTime(2026, 9, 6), now: now),
          isTrue);
      expect(PlanLimits.free.includesDay(DateTime(2026, 9, 5), now: now),
          isFalse);
    });

    test('the window is measured in calendar days, not hours', () {
      // Compared at 23:50 and at 00:10 the answer has to be the same, or the
      // tracker loses a day while somebody is looking at it.
      expect(
        PlanLimits.free.includesDay(DateTime(2026, 9, 6),
            now: DateTime(2026, 9, 12, 0, 10)),
        PlanLimits.free.includesDay(DateTime(2026, 9, 6), now: now),
      );
    });

    test('a time of day on the target does not push it out of the window', () {
      expect(
        PlanLimits.free.includesDay(DateTime(2026, 9, 6, 18, 30), now: now),
        isTrue,
      );
    });

    test('tomorrow is never gated', () {
      // Logging a prepped lunch for tomorrow is not a premium feature. The
      // window is about the past.
      expect(PlanLimits.free.includesDay(DateTime(2026, 9, 13), now: now),
          isTrue);
    });

    test('premium reaches the whole history', () {
      expect(PlanLimits.premium.includesDay(DateTime(2019, 1, 1), now: now),
          isTrue);
      expect(PlanLimits.premium.earliestDay(now: now), isNull);
    });

    test('the earliest day is the oldest one that is included', () {
      final DateTime? earliest = PlanLimits.free.earliestDay(now: now);

      expect(earliest, DateTime(2026, 9, 6));
      expect(PlanLimits.free.includesDay(earliest!, now: now), isTrue);
      expect(
        PlanLimits.free
            .includesDay(earliest.subtract(const Duration(days: 1)), now: now),
        isFalse,
      );
    });
  });

  group('the database agrees with the app', () {
    // If this fails, one of the two was changed and the other was not. Change
    // both, then re-run `supabase/premium.sql` against the project — the app
    // shipping a cap the database does not enforce is a free-for-all, and the
    // database enforcing one the app does not show is a 42501 with no
    // explanation.
    late final String sql =
        File('supabase/premium.sql').readAsStringSync();

    void expectSqlConstant(String function, int? value) {
      expect(value, isNotNull,
          reason: '$function has no Dart counterpart any more');

      // `create or replace function public.free_x() returns int language sql
      //  immutable as $$ select 20 $$;`
      final RegExp declaration = RegExp(
        'function\\s+public\\.$function\\s*\\(\\)'
        '.*?select\\s+(\\d+)',
        dotAll: true,
      );

      final RegExpMatch? match = declaration.firstMatch(sql);
      expect(match, isNotNull,
          reason: 'supabase/premium.sql no longer declares $function');

      expect(
        int.parse(match!.group(1)!),
        value,
        reason: '$function in supabase/premium.sql disagrees with '
            'PlanLimits.free in lib/core/plan_limits.dart',
      );
    }

    test('the saved-meal cap matches', () {
      expectSqlConstant('free_saved_meal_limit', PlanLimits.free.savedMeals);
    });

    test('the history window matches', () {
      expectSqlConstant('free_history_days', PlanLimits.free.historyDays);
    });

    test('the challenge cap matches', () {
      expectSqlConstant(
          'free_active_challenge_limit', PlanLimits.free.activeChallenges);
    });

    test('the app cannot write its own subscription', () {
      // The entire security model of this feature in one assertion: the table
      // grants `authenticated` a SELECT and nothing else, so a patched client
      // can lie to itself about ads and cannot lie to the database about
      // anything that costs money.
      final Iterable<String> policies = RegExp(
        r'create policy\s+"[^"]+"\s+on public\.subscriptions\s+for\s+(\w+)',
        caseSensitive: false,
      ).allMatches(sql).map((RegExpMatch m) => m.group(1)!.toLowerCase());

      expect(policies, isNotEmpty);
      expect(
        policies,
        everyElement('select'),
        reason: 'a write policy on subscriptions lets a client grant itself '
            'premium — it needs an edge function with the service key instead',
      );
    });
  });
}
