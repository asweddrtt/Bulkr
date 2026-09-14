import 'package:equatable/equatable.dart';

/// What happened, and — for most of them — who did it.
enum NotificationKind {
  follow('follow', 'notification_follow'),
  like('like', 'notification_like'),
  comment('comment', 'notification_comment'),
  reply('reply', 'notification_reply'),

  /// Somebody joined a challenge you created.
  challengeJoined('challenge_joined', 'notification_challenge_joined'),

  /// One you are in starts within the day.
  challengeStarting('challenge_starting', 'notification_challenge_starting'),

  /// One you are in has a day left. The last day is the last one on which
  /// opening the app still changes the result, which is why it is the only
  /// deadline worth a notification.
  challengeEnding('challenge_ending', 'notification_challenge_ending'),

  /// One you were in has finished.
  challengeEnded('challenge_ended', 'notification_challenge_ended'),

  /// Somebody went past you on a leaderboard. The one that makes a
  /// leaderboard a leaderboard: being third is a fact, being told you *were*
  /// second is an event.
  challengePassed('challenge_passed', 'notification_challenge_passed');

  const NotificationKind(this.dbValue, this.messageKey);

  final String dbValue;

  /// The sentence this reads as, with `{name}` filled in.
  ///
  /// Three of the challenge kinds have no actor — a deadline is not a person —
  /// so their sentences simply do not mention `{name}`, and the argument goes
  /// unused rather than needing a second code path.
  final String messageKey;

  /// Whether this is about a post rather than about a person.
  ///
  /// Decides where a tap goes. Every challenge notification is addressed by
  /// the challenge's announcement post — `challenges.post_id` is unique and
  /// the row cascades from it, so the post *is* the challenge's address, and
  /// it is where the leaderboard is reachable from.
  bool get opensPost => switch (this) {
        NotificationKind.challengeJoined ||
        NotificationKind.challengeStarting ||
        NotificationKind.challengeEnding ||
        NotificationKind.challengeEnded ||
        NotificationKind.challengePassed =>
          true,
        NotificationKind.follow ||
        NotificationKind.like ||
        NotificationKind.comment ||
        NotificationKind.reply =>
          false,
      };

  /// Null for a kind this build does not know about — a row written by a newer
  /// version, or by a trigger added after this shipped. The list skips those
  /// rather than guessing at what they mean.
  static NotificationKind? fromDb(Object? raw) {
    final String value = '${raw ?? ''}'.trim().toLowerCase();
    for (final NotificationKind kind in NotificationKind.values) {
      if (kind.dbValue == value) return kind;
    }
    return null;
  }
}

/// One row of the notifications screen.
///
/// What `public.notification_feed()` returns: the event, who caused it, and
/// enough of the post or comment to recognise which one — not the post itself.
class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.createdAt,
    this.readAt,
    this.actorId,
    this.actorUsername,
    this.actorDisplayName,
    this.actorAvatarUrl,
    this.postId,
    this.postExcerpt,
    this.commentId,
    this.commentExcerpt,
  });

  final String id;
  final NotificationKind kind;
  final DateTime createdAt;

  /// When it was seen. Null is unread.
  final DateTime? readAt;

  /// Null when the person has deleted their account. The row survives them,
  /// because an account going away should not rewrite the history of what
  /// happened to everyone else.
  final String? actorId;
  final String? actorUsername;
  final String? actorDisplayName;
  final String? actorAvatarUrl;

  final String? postId;

  /// The first eighty characters of the post, to tell one from another.
  final String? postExcerpt;

  final String? commentId;
  final String? commentExcerpt;

  bool get isUnread => readAt == null;

  /// Whether there is a profile to open.
  bool get hasActor => actorId != null;

  /// What to call them.
  String get actorName {
    final String? display = actorDisplayName?.trim();
    if (display != null && display.isNotEmpty) return display;

    final String? handle = actorUsername?.trim();
    if (handle != null && handle.isNotEmpty) return handle;

    return '';
  }

  /// The line of context under the sentence, if there is one worth showing.
  ///
  /// A reply shows what was said; a like shows which post. A follow shows
  /// nothing, because there is nothing — the sentence is the whole event.
  String? get detail {
    final String? comment = commentExcerpt?.trim();
    if (comment != null && comment.isNotEmpty) return comment;

    final String? post = postExcerpt?.trim();
    if (post != null && post.isNotEmpty) return post;

    return null;
  }

  AppNotification asRead() => AppNotification(
        id: id,
        kind: kind,
        createdAt: createdAt,
        readAt: readAt ?? DateTime.now(),
        actorId: actorId,
        actorUsername: actorUsername,
        actorDisplayName: actorDisplayName,
        actorAvatarUrl: actorAvatarUrl,
        postId: postId,
        postExcerpt: postExcerpt,
        commentId: commentId,
        commentExcerpt: commentExcerpt,
      );

  /// Null for a row whose `kind` this build does not recognise.
  static AppNotification? fromRow(Map<String, dynamic> row) {
    final NotificationKind? kind = NotificationKind.fromDb(row['kind']);
    if (kind == null) return null;

    return AppNotification(
      id: '${row['id']}',
      kind: kind,
      createdAt:
          DateTime.tryParse('${row['created_at']}')?.toLocal() ?? DateTime.now(),
      readAt: DateTime.tryParse('${row['read_at']}')?.toLocal(),
      actorId: row['actor_id'] as String?,
      actorUsername: row['actor_username'] as String?,
      actorDisplayName: row['actor_display_name'] as String?,
      actorAvatarUrl: row['actor_avatar_url'] as String?,
      postId: row['post_id'] as String?,
      postExcerpt: row['post_excerpt'] as String?,
      commentId: row['comment_id'] as String?,
      commentExcerpt: row['comment_excerpt'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        kind,
        createdAt,
        readAt,
        actorId,
        actorUsername,
        actorDisplayName,
        actorAvatarUrl,
        postId,
        postExcerpt,
        commentId,
        commentExcerpt,
      ];
}
