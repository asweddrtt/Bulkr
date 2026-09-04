import 'package:equatable/equatable.dart';

/// A `public.post_comments` row plus this user's relationship to it.
///
/// Threads are one level deep: a comment is either top-level or a reply to a
/// top-level comment, and the database refuses anything deeper. [replies] is
/// therefore a flat list and always will be — there is no recursion here, by
/// design rather than by omission.
class PostComment extends Equatable {
  const PostComment({
    required this.id,
    required this.postId,
    required this.authorId,
    this.parentId,
    required this.content,
    required this.createdAt,
    this.authorUsername,
    this.authorDisplayName,
    this.authorAvatarUrl,
    this.isMine = false,
    this.canDelete = false,
    this.replies = const [],
  });

  final String id;
  final String postId;
  final String authorId;

  /// The comment this replies to, or null for a top-level one.
  final String? parentId;

  final String content;
  final DateTime createdAt;

  final String? authorUsername;
  final String? authorDisplayName;
  final String? authorAvatarUrl;

  /// This session wrote it.
  final bool isMine;

  /// Whether this session may delete it.
  ///
  /// Wider than [isMine], and not the same question: the post's author can
  /// delete anything in their own thread. That is the only moderation they
  /// have over a conversation happening under their progress photo, so the
  /// flag is resolved from the post rather than from the comment.
  final bool canDelete;

  /// Replies to this comment, oldest first. Always empty on a reply itself.
  final List<PostComment> replies;

  /// What to print above the comment. Falls through display name to handle,
  /// the same order the rest of the app uses.
  String get authorName {
    final String? display = authorDisplayName?.trim();
    if (display != null && display.isNotEmpty) return display;

    final String? handle = authorUsername?.trim();
    if (handle != null && handle.isNotEmpty) return handle;

    return 'someone';
  }

  bool get isReply => parentId != null;

  /// This comment and its replies, which is what the thread counter counts.
  int get threadLength => 1 + replies.length;

  PostComment copyWith({
    String? content,
    bool? isMine,
    bool? canDelete,
    List<PostComment>? replies,
  }) {
    return PostComment(
      id: id,
      postId: postId,
      authorId: authorId,
      parentId: parentId,
      content: content ?? this.content,
      createdAt: createdAt,
      authorUsername: authorUsername,
      authorDisplayName: authorDisplayName,
      authorAvatarUrl: authorAvatarUrl,
      isMine: isMine ?? this.isMine,
      canDelete: canDelete ?? this.canDelete,
      replies: replies ?? this.replies,
    );
  }

  /// Reads a `post_comments` row, optionally with `users` embedded.
  ///
  /// [postAuthorId] is who owns the post the comment is on, which is what
  /// decides [canDelete] beyond the comment's own author. Null when the caller
  /// does not know — in which case only the comment's author can delete it,
  /// which is the safe way to be wrong: the UI offers less than the policy
  /// allows rather than offering an action the database will refuse.
  factory PostComment.fromRow(
    Map<String, dynamic> row, {
    String? currentUserId,
    String? postAuthorId,
  }) {
    final String authorId = '${row['user_id']}';
    final bool isMine = currentUserId != null && authorId == currentUserId;
    final Map<String, dynamic>? author = _author(row);

    return PostComment(
      id: '${row['id']}',
      postId: '${row['post_id']}',
      authorId: authorId,
      parentId: row['parent_comment_id'] as String?,
      content: '${row['content'] ?? ''}',
      createdAt: DateTime.tryParse('${row['created_at']}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      authorUsername: author?['username'] as String?,
      authorDisplayName: author?['display_name'] as String?,
      authorAvatarUrl: author?['avatar_url'] as String?,
      isMine: isMine,
      canDelete: isMine ||
          (currentUserId != null &&
              postAuthorId != null &&
              postAuthorId == currentUserId),
    );
  }

  /// The embedded `users` row, however PostgREST decided to shape it.
  ///
  /// A to-one embed comes back as an object; the same query against a
  /// relationship PostgREST reads as to-many returns a single-element list.
  /// Both are handled rather than depending on which one today's schema cache
  /// produces.
  static Map<String, dynamic>? _author(Map<String, dynamic> row) {
    final Object? author = row['users'];
    if (author is Map<String, dynamic>) return author;
    if (author is List && author.isNotEmpty) {
      final Object? first = author.first;
      if (first is Map<String, dynamic>) return first;
    }
    return null;
  }

  /// Arranges a flat list of rows into top-level comments carrying their
  /// replies.
  ///
  /// Kept out of the query because there is no way to ask PostgREST for a
  /// self-join shaped like this, and out of the widget because it is a pure
  /// list transformation worth being able to reason about on its own.
  ///
  /// A reply whose parent is missing from [comments] is promoted to top level
  /// rather than dropped. That happens when a page boundary splits a thread,
  /// and losing someone's words to a pagination detail is worse than showing
  /// them slightly out of place.
  static List<PostComment> thread(List<PostComment> comments) {
    final List<PostComment> roots = [];
    final Map<String, List<PostComment>> repliesByParent = {};
    final Set<String> rootIds = comments
        .where((comment) => !comment.isReply)
        .map((comment) => comment.id)
        .toSet();

    for (final PostComment comment in comments) {
      if (!comment.isReply || !rootIds.contains(comment.parentId)) {
        roots.add(comment);
      } else {
        repliesByParent.putIfAbsent(comment.parentId!, () => []).add(comment);
      }
    }

    return roots
        .map((root) => root.copyWith(replies: repliesByParent[root.id] ?? const []))
        .toList(growable: false);
  }

  @override
  List<Object?> get props => [
        id,
        postId,
        authorId,
        parentId,
        content,
        createdAt,
        authorUsername,
        authorDisplayName,
        authorAvatarUrl,
        isMine,
        canDelete,
        replies,
      ];
}
