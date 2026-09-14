import 'package:equatable/equatable.dart';

/// What a challenge measures.
///
/// ## Why there is more than one
///
/// Challenges shipped measuring kilograms gained, and the composer offers 7,
/// 14, 30 and 90 days. For the first two that metric does not work: a week of
/// scale movement is water, sodium and what time you weighed yourself, and the
/// person who wins a seven-day weight challenge is the person who drank less
/// on the last morning. A challenge nobody can win on purpose is a challenge
/// nobody enters twice.
///
/// So [daysLogged] exists, and it is the better default for anything short. It
/// is entirely inside the entrant's control, it settles identically for
/// everyone, and the way to win it is to open the app every day — which is the
/// rare leaderboard whose incentive is the thing the product is for.
///
/// Adding another is this enum, one value in the CHECK constraint, and one
/// branch in `public.challenge_scores`. `calories_hit` is the obvious next and
/// is deliberately not here yet — see the header of
/// `supabase/challenge_metrics.sql` for why "your target" turns out not to be
/// one number.
enum ChallengeMetric {
  /// Kilograms gained since joining, read from the weight the app already
  /// tracks. The natural metric for a bulking app over a real span of time.
  weightGain('weight_gain'),

  /// Days you recorded any food, inside the window and since you joined.
  daysLogged('days_logged');

  const ChallengeMetric(this.column);

  /// Exact string in `challenges.metric`.
  final String column;

  /// Translation key for the metric's unit, as it appears next to a number.
  String get unitKey => switch (this) {
        ChallengeMetric.weightGain => 'challenge_unit_kg',
        ChallengeMetric.daysLogged => 'challenge_unit_days',
      };

  /// What the chip in the composer says.
  String get nameKey => switch (this) {
        ChallengeMetric.weightGain => 'challenge_metric_weight',
        ChallengeMetric.daysLogged => 'challenge_metric_days',
      };

  /// The sentence under the picker explaining what entrants are signing up to.
  ///
  /// Shown rather than linked, because a challenge whose metric is a surprise
  /// is a challenge people leave.
  String get blurbKey => switch (this) {
        ChallengeMetric.weightGain => 'challenge_metric_weight_blurb',
        ChallengeMetric.daysLogged => 'challenge_metric_days_blurb',
      };

  /// Label on the goal field, which is asking for a different thing each time.
  String get goalHintKey => switch (this) {
        ChallengeMetric.weightGain => 'challenge_goal_hint',
        ChallengeMetric.daysLogged => 'challenge_goal_hint_days',
      };

  /// What somebody is told the moment they join.
  String get joinedKey => switch (this) {
        ChallengeMetric.weightGain => 'challenge_joined',
        ChallengeMetric.daysLogged => 'challenge_joined_days',
      };

  /// Whether a score is a count rather than a measurement.
  ///
  /// Decides formatting in one place: "12 days" and never "12.0 days", "2.4 kg"
  /// and never "2 kg".
  bool get isCount => this == ChallengeMetric.daysLogged;

  /// A score, written the way this metric is written.
  ///
  /// Kilograms keep one decimal and drop a trailing `.0`, because a scale
  /// reads to 0.1 and "2.0 kg" looks like a rounding artefact next to
  /// "2.4 kg". Days are whole.
  String format(double amount) {
    if (isCount) return '${amount.round()}';

    final String fixed = amount.toStringAsFixed(1);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }

  static ChallengeMetric parse(Object? value) {
    final String raw = '${value ?? ''}'.trim().toLowerCase();

    for (final ChallengeMetric metric in ChallengeMetric.values) {
      if (metric.column == raw) return metric;
    }

    // An unrecognised metric means this client is older than the database.
    // Falling back to the first one renders the challenge with the wrong unit,
    // which beats a feed that throws halfway down.
    return ChallengeMetric.weightGain;
  }
}

/// A `public.challenges` row plus this user's relationship to it.
///
/// Hangs off a post the way a meal does: the post is the announcement, this is
/// the machinery. Which means a challenge post is still an ordinary post
/// everywhere a post appears, and nothing in the feed special-cases it.
class Challenge extends Equatable {
  const Challenge({
    required this.id,
    required this.postId,
    required this.title,
    this.metric = ChallengeMetric.weightGain,
    required this.goalAmount,
    required this.startsAt,
    required this.endsAt,
    required this.createdBy,
    this.participantCount = 0,
    this.hasJoined = false,
    this.isMine = false,
  });

  final String id;
  final String postId;
  final String title;
  final ChallengeMetric metric;

  /// The target, in the metric's units — kilograms for weight gain, always
  /// metric on the wire like every other weight in this app.
  final double goalAmount;

  final DateTime startsAt;
  final DateTime endsAt;
  final String createdBy;

  /// An aggregate, not a stored column.
  final int participantCount;

  /// This user is in it.
  final bool hasJoined;

  /// This user set it up.
  final bool isMine;

  /// Whether it is running now.
  bool get isLive {
    final DateTime now = DateTime.now();
    return now.isAfter(startsAt) && now.isBefore(endsAt);
  }

  bool get hasEnded => DateTime.now().isAfter(endsAt);

  bool get hasNotStarted => DateTime.now().isBefore(startsAt);

  /// Whether this user can still join.
  ///
  /// Not once it has ended — the insert policy refuses it, and a Join button
  /// that fails is worse than no button. Joining before it starts is allowed:
  /// signing up early is the point of announcing a challenge in advance.
  bool get canJoin => !hasJoined && !hasEnded;

  bool get canLeave => hasJoined && !hasEnded;

  /// Whole days left, floored, and never negative.
  ///
  /// Floored rather than rounded because "1 day left" should mean there is
  /// still a day, and rounding up would say that with four hours to go.
  int get daysLeft {
    if (hasEnded) return 0;
    return endsAt.difference(DateTime.now()).inDays;
  }

  /// Whole days until it starts, for a challenge announced in advance.
  int get daysUntilStart {
    if (!hasNotStarted) return 0;
    return startsAt.difference(DateTime.now()).inDays;
  }

  Challenge copyWith({
    int? participantCount,
    bool? hasJoined,
  }) {
    return Challenge(
      id: id,
      postId: postId,
      title: title,
      metric: metric,
      goalAmount: goalAmount,
      startsAt: startsAt,
      endsAt: endsAt,
      createdBy: createdBy,
      participantCount: participantCount ?? this.participantCount,
      hasJoined: hasJoined ?? this.hasJoined,
      isMine: isMine,
    );
  }

  factory Challenge.fromRow(
    Map<String, dynamic> row, {
    String? currentUserId,
    bool hasJoined = false,
  }) {
    final String createdBy = '${row['created_by']}';

    return Challenge(
      id: '${row['id']}',
      postId: '${row['post_id']}',
      title: '${row['title'] ?? ''}',
      metric: ChallengeMetric.parse(row['metric']),
      goalAmount: _asDouble(row['goal_amount']),
      startsAt: DateTime.tryParse('${row['starts_at']}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      endsAt: DateTime.tryParse('${row['ends_at']}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      createdBy: createdBy,
      participantCount: _aggregate(row['challenge_participants']),
      hasJoined: hasJoined,
      isMine: currentUserId != null && createdBy == currentUserId,
    );
  }

  static int _aggregate(Object? embedded) {
    if (embedded is List) {
      if (embedded.isEmpty) return 0;
      final Object? first = embedded.first;
      if (first is Map<String, dynamic>) {
        return _asDouble(first['count']).round();
      }
      return 0;
    }
    if (embedded is Map<String, dynamic>) {
      return _asDouble(embedded['count']).round();
    }
    return 0;
  }

  static double _asDouble(Object? value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  @override
  List<Object?> get props => [
        id,
        postId,
        title,
        metric,
        goalAmount,
        startsAt,
        endsAt,
        createdBy,
        participantCount,
        hasJoined,
        isMine,
      ];
}

/// One row of a challenge's leaderboard.
///
/// Comes from `challenge_leaderboard()`, a SECURITY DEFINER function, and
/// carries a *delta* rather than a weight. That distinction is the whole
/// privacy design: joining a challenge publishes how much you have gained, not
/// what you weigh, and there is no arithmetic that recovers the second from
/// the first.
class ChallengeStanding extends Equatable {
  const ChallengeStanding({
    required this.userId,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.score,
    required this.joinedAt,
    this.hasData = false,
    this.isMe = false,
  });

  final String userId;
  final String username;
  final String? displayName;
  final String? avatarUrl;

  /// What they have scored, in the challenge's own metric — kilograms gained
  /// for `weight_gain`, days recorded for `days_logged`. The metric lives on
  /// the [Challenge], not here: a standing is a number and the challenge says
  /// what kind of number it is.
  ///
  /// Null only when there is nothing to compute from, which today means a
  /// weight-gain participant who has never logged a weight. Reported as "no
  /// data" rather than as zero, because zero would place them ahead of
  /// everyone who has lost weight and behind everyone who has gained, and they
  /// have earned neither position.
  ///
  /// Nothing is null for `days_logged`: nought days logged is a real score,
  /// honestly earned, and the server says so through [hasData].
  final double? score;

  final DateTime joinedAt;

  /// Whether [score] means anything. See the note on it.
  final bool hasData;

  /// This is the signed-in user, so their row can be marked in the list.
  final bool isMe;

  String get name {
    final String? display = displayName?.trim();
    if (display != null && display.isNotEmpty) return display;

    final String handle = username.trim();
    if (handle.isNotEmpty) return handle;

    return 'someone';
  }

  /// Progress towards [goal], clamped to 0..1 for a progress bar.
  ///
  /// Losing weight reads as zero progress rather than as negative — a bar that
  /// runs backwards is not a thing — and overshooting reads as full.
  double progressTowards(double goal) {
    final double? earned = score;
    if (earned == null || goal <= 0) return 0;
    return (earned / goal).clamp(0, 1);
  }

  factory ChallengeStanding.fromRow(
    Map<String, dynamic> row, {
    String? currentUserId,
  }) {
    final String userId = '${row['user_id']}';
    // `score`, not `gained_kg`. The column was renamed in
    // `challenge_metrics.sql` when it stopped always being kilograms.
    final Object? earned = row['score'];

    return ChallengeStanding(
      userId: userId,
      username: '${row['username'] ?? ''}',
      displayName: row['display_name'] as String?,
      avatarUrl: row['avatar_url'] as String?,
      score: earned == null
          ? null
          : (earned is num
              ? earned.toDouble()
              : double.tryParse('$earned')),
      joinedAt: DateTime.tryParse('${row['joined_at']}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      hasData: row['has_data'] == true,
      isMe: currentUserId != null && userId == currentUserId,
    );
  }

  @override
  List<Object?> get props => [
        userId,
        username,
        displayName,
        avatarUrl,
        score,
        joinedAt,
        hasData,
        isMe,
      ];
}

/// One row of `public.my_challenge_standings()`: a challenge the signed-in
/// user is in right now, and where they are in it.
///
/// ## Why this is not just a [Challenge] plus a [ChallengeStanding]
///
/// Because of [aheadName]. "You are third" is a fact; "Sara is 0.4 ahead of
/// you" is a reason to open the app tomorrow, and the second one cannot be
/// assembled on the client without fetching a whole leaderboard to read one
/// line of it. The query that already knows the ranking answers it instead,
/// and this is the shape of that answer.
class MyChallengeStanding extends Equatable {
  const MyChallengeStanding({
    required this.challengeId,
    required this.postId,
    required this.title,
    required this.metric,
    required this.goalAmount,
    required this.startsAt,
    required this.endsAt,
    required this.participantCount,
    required this.rank,
    this.score,
    this.hasData = false,
    this.aheadScore,
    this.aheadName,
  });

  final String challengeId;

  /// The announcement. A challenge has no other address — see the header of
  /// `supabase/challenge_notifications.sql`.
  final String postId;

  final String title;
  final ChallengeMetric metric;
  final double goalAmount;
  final DateTime startsAt;
  final DateTime endsAt;
  final int participantCount;

  /// 1 is first. Ties share a position, so two people level on 3 kg are both
  /// second and the next is fourth.
  final int rank;

  final double? score;
  final bool hasData;

  /// The score of the person directly above, and their name. Both null when
  /// this user is leading — which the card reads as "you are top" rather than
  /// as missing data.
  final double? aheadScore;
  final String? aheadName;

  bool get isLeading => aheadName == null;

  /// How far behind the person above. Null when leading or when either score
  /// is unknown; never negative.
  double? get gapToAhead {
    final double? theirs = aheadScore;
    final double? mine = score;
    if (theirs == null || mine == null) return null;

    final double gap = theirs - mine;
    return gap <= 0 ? null : gap;
  }

  /// Progress towards the goal, clamped to 0..1 for a bar.
  double get progress {
    final double? earned = score;
    if (earned == null || goalAmount <= 0) return 0;
    return (earned / goalAmount).clamp(0, 1);
  }

  bool get hasReachedGoal => (score ?? 0) >= goalAmount && goalAmount > 0;

  /// Whole days left, floored, never negative. Floored because "1 day left"
  /// should mean there is still a day.
  int get daysLeft {
    final Duration left = endsAt.difference(DateTime.now());
    return left.isNegative ? 0 : left.inDays;
  }

  factory MyChallengeStanding.fromRow(Map<String, dynamic> row) {
    double? number(Object? value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      return double.tryParse('$value');
    }

    final String? ahead = (row['ahead_name'] as String?)?.trim();

    return MyChallengeStanding(
      challengeId: '${row['challenge_id']}',
      postId: '${row['post_id']}',
      title: '${row['title'] ?? ''}',
      metric: ChallengeMetric.parse(row['metric']),
      goalAmount: number(row['goal_amount']) ?? 0,
      startsAt: DateTime.tryParse('${row['starts_at']}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      endsAt: DateTime.tryParse('${row['ends_at']}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      participantCount: number(row['participant_count'])?.round() ?? 0,
      rank: number(row['my_rank'])?.round() ?? 0,
      score: number(row['my_score']),
      hasData: row['has_data'] == true,
      aheadScore: number(row['ahead_score']),
      aheadName: ahead == null || ahead.isEmpty ? null : ahead,
    );
  }

  @override
  List<Object?> get props => <Object?>[
        challengeId,
        postId,
        title,
        metric,
        goalAmount,
        startsAt,
        endsAt,
        participantCount,
        rank,
        score,
        hasData,
        aheadScore,
        aheadName,
      ];
}

/// A challenge being set up alongside a post, before it becomes a row.
class ChallengeDraft extends Equatable {
  const ChallengeDraft({
    this.title = '',
    this.metric = ChallengeMetric.weightGain,
    this.goalAmount,
    this.days = defaultDays,
  });

  final String title;

  /// What it measures. Weight gain is the default because it is what this app
  /// is about; [ChallengeMetric.daysLogged] is the one to pick for anything
  /// short, and the composer says so next to the length chips.
  final ChallengeMetric metric;

  /// The target. Null until typed, which is not the same as zero — zero is a
  /// number someone entered and the constraint rejects.
  final double? goalAmount;

  /// How long it runs, in days from now.
  ///
  /// Days rather than an end date, because "30 days" is how anyone describes a
  /// challenge and a date picker for something that always starts today is
  /// two taps for no information.
  final int days;

  static const int defaultDays = 30;
  static const int minDays = 1;
  static const int maxDays = 365;
  static const int minTitleLength = 3;
  static const int maxTitleLength = 80;

  String get trimmedTitle => title.trim();

  bool get isTitleValid =>
      trimmedTitle.length >= minTitleLength &&
      trimmedTitle.length <= maxTitleLength;

  /// A goal of zero is not a challenge, and the database refuses it.
  ///
  /// For [ChallengeMetric.daysLogged] there is a ceiling as well as a floor:
  /// you cannot log thirty days inside a seven-day challenge, and a goal
  /// nobody can reach is not a challenge either. Weight has no such ceiling —
  /// an ambitious number is a choice, not an impossibility.
  bool get isGoalValid {
    final double goal = goalAmount ?? 0;
    if (goal <= 0) return false;

    if (metric.isCount && goal > days) return false;

    return true;
  }

  bool get areDaysValid => days >= minDays && days <= maxDays;

  bool get canSubmit => isTitleValid && isGoalValid && areDaysValid;

  DateTime get endsAt => DateTime.now().add(Duration(days: days));

  ChallengeDraft copyWith({
    String? title,
    ChallengeMetric? metric,
    double? goalAmount,
    bool clearGoal = false,
    int? days,
  }) {
    return ChallengeDraft(
      title: title ?? this.title,
      metric: metric ?? this.metric,
      goalAmount: clearGoal ? null : (goalAmount ?? this.goalAmount),
      days: days ?? this.days,
    );
  }

  /// The `challenges` column values for this draft.
  ///
  /// `starts_at` is left to the column default rather than sent: the server's
  /// clock decides when a challenge starts, and a device with a wrong clock
  /// should not be able to backdate one.
  Map<String, dynamic> toRowValues({
    required String postId,
    required String createdBy,
  }) {
    return {
      'post_id': postId,
      'created_by': createdBy,
      'title': trimmedTitle,
      'metric': metric.column,
      'goal_amount': goalAmount,
      'ends_at': endsAt.toUtc().toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [title, metric, goalAmount, days];
}
