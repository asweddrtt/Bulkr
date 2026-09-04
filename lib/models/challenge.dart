import 'package:equatable/equatable.dart';

/// What a challenge measures.
///
/// One value today. It is an enum rather than a bare assumption so that adding
/// "calories hit" or "workouts completed" later is an additive change here and
/// one new value in the CHECK constraint, rather than a rewrite of everything
/// that touches a challenge.
enum ChallengeMetric {
  /// Kilograms gained since joining, read from the weight the app already
  /// tracks. The natural metric for a bulking app, and the only one whose data
  /// already exists.
  weightGain;

  String get column => switch (this) {
        ChallengeMetric.weightGain => 'weight_gain',
      };

  /// Translation key for the metric's unit, as it appears next to a number.
  String get unitKey => switch (this) {
        ChallengeMetric.weightGain => 'challenge_unit_kg',
      };

  static ChallengeMetric parse(Object? value) {
    final String raw = '${value ?? ''}'.trim().toLowerCase();

    for (final ChallengeMetric metric in ChallengeMetric.values) {
      if (metric.column == raw) return metric;
    }

    // An unrecognised metric means this client is older than the database.
    // Falling back to the only one it knows renders the challenge with the
    // wrong unit, which beats a feed that throws halfway down.
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
    this.gainedKg,
    required this.joinedAt,
    this.hasData = false,
    this.isMe = false,
  });

  final String userId;
  final String username;
  final String? displayName;
  final String? avatarUrl;

  /// Kilograms gained since joining, to one decimal.
  ///
  /// Null when there is nothing to compute from — a participant who has never
  /// logged a weight. Reported as "no data" rather than as zero, because zero
  /// would place them ahead of everyone who has lost weight and behind
  /// everyone who has gained, and they have earned neither position.
  final double? gainedKg;

  final DateTime joinedAt;

  /// Whether [gainedKg] means anything.
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
    final double? gained = gainedKg;
    if (gained == null || goal <= 0) return 0;
    return (gained / goal).clamp(0, 1);
  }

  factory ChallengeStanding.fromRow(
    Map<String, dynamic> row, {
    String? currentUserId,
  }) {
    final String userId = '${row['user_id']}';
    final Object? gained = row['gained_kg'];

    return ChallengeStanding(
      userId: userId,
      username: '${row['username'] ?? ''}',
      displayName: row['display_name'] as String?,
      avatarUrl: row['avatar_url'] as String?,
      gainedKg: gained == null
          ? null
          : (gained is num
              ? gained.toDouble()
              : double.tryParse('$gained')),
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
        gainedKg,
        joinedAt,
        hasData,
        isMe,
      ];
}

/// A challenge being set up alongside a post, before it becomes a row.
class ChallengeDraft extends Equatable {
  const ChallengeDraft({
    this.title = '',
    this.goalAmount,
    this.days = defaultDays,
  });

  final String title;

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

  bool get isGoalValid => (goalAmount ?? 0) > 0;

  bool get areDaysValid => days >= minDays && days <= maxDays;

  bool get canSubmit => isTitleValid && isGoalValid && areDaysValid;

  DateTime get endsAt => DateTime.now().add(Duration(days: days));

  ChallengeDraft copyWith({
    String? title,
    double? goalAmount,
    bool clearGoal = false,
    int? days,
  }) {
    return ChallengeDraft(
      title: title ?? this.title,
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
      'metric': ChallengeMetric.weightGain.column,
      'goal_amount': goalAmount,
      'ends_at': endsAt.toUtc().toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [title, goalAmount, days];
}
