import 'package:equatable/equatable.dart';

/// Someone else, as the feed knows them.
///
/// Deliberately not [UserProfile]. That class is the signed-in user's own row —
/// biometrics, calorie targets, onboarding state — and none of it belongs on a
/// screen about somebody else. This is the public half: who they are, whether
/// they present as a trainer, and this user's relationship to them.
///
/// The counts are aggregates rather than stored columns, so they cannot drift
/// and cannot be inflated by their owner. See section 3 of
/// `supabase/feed_follows.sql` for why that trade was made.
class Person extends Equatable {
  const Person({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.isTrainer = false,
    this.followerCount = 0,
    this.followingCount = 0,
    this.postCount = 0,
    this.isFollowedByMe = false,
    this.followsMe = false,
    this.isMe = false,
  });

  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;

  /// They have marked themselves a trainer.
  ///
  /// A self-declared claim, not a verified credential — nothing checks it
  /// today, and the schema file says so plainly. It only decides how
  /// prominently the account is suggested, which is why an unverified claim is
  /// survivable for now.
  final bool isTrainer;

  final int followerCount;
  final int followingCount;

  /// How many posts they have written. Shown on a profile, and the one number
  /// on this object that says whether following them will actually put
  /// anything in your feed.
  final int postCount;

  /// The signed-in user follows them.
  final bool isFollowedByMe;

  /// They follow the signed-in user.
  ///
  /// Resolved separately from [isFollowedByMe] because a follow is directional:
  /// two rows, not one, and "follows you" is worth showing on a profile before
  /// you decide whether to follow back.
  final bool followsMe;

  /// This is the signed-in user, so nothing offers to follow them.
  final bool isMe;

  /// What to print. Falls through display name to handle, the same order the
  /// rest of the app uses, so one person reads the same everywhere.
  String get name {
    final String? display = displayName?.trim();
    if (display != null && display.isNotEmpty) return display;

    final String handle = username.trim();
    if (handle.isNotEmpty) return handle;

    return 'someone';
  }

  /// The @handle, or null when there is nothing worth printing.
  ///
  /// Suppressed when it would just repeat [name] — showing "ali" under "ali"
  /// is a line of noise.
  String? get handle {
    final String trimmed = username.trim();
    if (trimmed.isEmpty || trimmed == name) return null;
    return '@$trimmed';
  }

  /// Whether a follow button belongs on this person's row.
  bool get isFollowable => !isMe;

  Person copyWith({
    bool? isTrainer,
    int? followerCount,
    int? followingCount,
    int? postCount,
    bool? isFollowedByMe,
    bool? followsMe,
  }) {
    return Person(
      id: id,
      username: username,
      displayName: displayName,
      avatarUrl: avatarUrl,
      isTrainer: isTrainer ?? this.isTrainer,
      followerCount: followerCount ?? this.followerCount,
      followingCount: followingCount ?? this.followingCount,
      postCount: postCount ?? this.postCount,
      isFollowedByMe: isFollowedByMe ?? this.isFollowedByMe,
      followsMe: followsMe ?? this.followsMe,
      isMe: isMe,
    );
  }

  /// Reads a `users` row, with the count aggregates when they were asked for.
  ///
  /// The aggregate keys are the aliases the query gives them — `followers`,
  /// `following`, `posts` — because `users` is pointed at by `follows` twice
  /// and an unaliased embed would collide.
  factory Person.fromRow(
    Map<String, dynamic> row, {
    String? currentUserId,
    bool isFollowedByMe = false,
    bool followsMe = false,
  }) {
    final String id = '${row['id']}';

    return Person(
      id: id,
      username: '${row['username'] ?? ''}',
      displayName: row['display_name'] as String?,
      avatarUrl: row['avatar_url'] as String?,
      isTrainer: row['is_trainer'] == true,
      followerCount: _aggregate(row['followers']),
      followingCount: _aggregate(row['following']),
      postCount: _aggregate(row['posts']),
      isFollowedByMe: isFollowedByMe,
      followsMe: followsMe,
      isMe: currentUserId != null && id == currentUserId,
    );
  }

  /// The number out of a PostgREST `(count)` embed.
  ///
  /// It arrives as `[{"count": 3}]` — a list, because the relationship is
  /// to-many — and as an empty list when there is nothing to count rather than
  /// as a zero. A bare object is handled too, since which shape comes back
  /// depends on how PostgREST reads the relationship, and that is not worth
  /// depending on.
  static int _aggregate(Object? embedded) {
    if (embedded is List) {
      if (embedded.isEmpty) return 0;
      final Object? first = embedded.first;
      if (first is Map<String, dynamic>) return _asInt(first['count']);
      return 0;
    }
    if (embedded is Map<String, dynamic>) return _asInt(embedded['count']);
    return 0;
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  @override
  List<Object?> get props => [
        id,
        username,
        displayName,
        avatarUrl,
        isTrainer,
        followerCount,
        followingCount,
        postCount,
        isFollowedByMe,
        followsMe,
        isMe,
      ];
}
