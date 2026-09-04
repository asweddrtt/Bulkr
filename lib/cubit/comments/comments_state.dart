part of 'comments_cubit.dart';

enum CommentsStatus { initial, loading, ready, failure }

class CommentsState extends Equatable {
  const CommentsState({
    required this.post,
    this.status = CommentsStatus.initial,
    this.threads = const [],
    this.draft = '',
    this.replyingToId,
    this.replyingToName,
    this.isSubmitting = false,
    this.errorMessage,
    this.actionErrorKey,
    this.actionErrorDetail,
  });

  /// The post being discussed.
  ///
  /// Held whole rather than as an id, because two of its fields decide what
  /// the sheet may do: [Post.authorId] resolves who can delete what, and
  /// [Post.isMine] is what makes the author's own moderation powers appear.
  final Post post;

  final CommentsStatus status;

  /// Top-level comments, oldest first, each carrying its replies.
  final List<PostComment> threads;

  /// What is in the field.
  final String draft;

  /// The thread the next comment will land in, or null for the post itself.
  final String? replyingToId;

  /// Who is being replied to, for the label above the field. Their name rather
  /// than their handle, matching how the rest of the app addresses people.
  final String? replyingToName;

  final bool isSubmitting;

  final String? errorMessage;
  final String? actionErrorKey;
  final String? actionErrorDetail;

  /// How long a comment may be. Matches the CHECK constraint on
  /// `post_comments.content`, so the field refuses what the database would.
  static const int maxLength = 2000;

  String get trimmedDraft => draft.trim();

  bool get isReplying => replyingToId != null;

  bool get isTooLong => trimmedDraft.length > maxLength;

  bool get canSubmit =>
      trimmedDraft.isNotEmpty && !isTooLong && !isSubmitting;

  /// Every comment on the post, replies included — which is what the count on
  /// the card means, and what the trigger on `post_comments` counts.
  int get totalCount =>
      threads.fold(0, (sum, thread) => sum + thread.threadLength);

  /// Nothing said yet, and not because it is still loading.
  bool get isEmpty => status == CommentsStatus.ready && threads.isEmpty;

  CommentsState copyWith({
    CommentsStatus? status,
    List<PostComment>? threads,
    String? draft,
    String? replyingToId,
    String? replyingToName,
    bool clearReplyTarget = false,
    bool? isSubmitting,
    String? errorMessage,
    String? actionErrorKey,
    String? actionErrorDetail,
    bool clearError = false,
  }) {
    return CommentsState(
      post: post,
      status: status ?? this.status,
      threads: threads ?? this.threads,
      draft: draft ?? this.draft,
      replyingToId: clearReplyTarget ? null : (replyingToId ?? this.replyingToId),
      replyingToName:
          clearReplyTarget ? null : (replyingToName ?? this.replyingToName),
      isSubmitting: isSubmitting ?? this.isSubmitting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      actionErrorKey:
          clearError ? null : (actionErrorKey ?? this.actionErrorKey),
      actionErrorDetail:
          clearError ? null : (actionErrorDetail ?? this.actionErrorDetail),
    );
  }

  @override
  List<Object?> get props => [
        post,
        status,
        threads,
        draft,
        replyingToId,
        replyingToName,
        isSubmitting,
        errorMessage,
        actionErrorKey,
        actionErrorDetail,
      ];
}
