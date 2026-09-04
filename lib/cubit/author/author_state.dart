part of 'author_cubit.dart';

/// Where a profile is up to.
///
/// `notFound` is its own state rather than a flavour of `failure`: one is
/// "there is nobody here", which is a normal thing for a link to mean, and the
/// other is "something broke", which wants a retry button.
enum AuthorStatus { initial, loading, ready, failure, notFound }

class AuthorState extends Equatable {
  const AuthorState({
    required this.personId,
    this.status = AuthorStatus.initial,
    this.person,
    this.posts = const [],
    this.cursor,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.isFollowWriting = false,
    this.errorMessage,
    this.actionErrorKey,
    this.actionErrorDetail,
  });

  /// Whose profile this is. Held separately from [person] because it is known
  /// before the row is, and it is what every fetch is keyed on.
  final String personId;

  final AuthorStatus status;

  /// Their public profile, once read.
  final Person? person;

  /// Their posts, newest first.
  final List<Post> posts;

  final FeedCursor? cursor;
  final bool hasMore;
  final bool isLoadingMore;

  /// A follow write is in flight.
  ///
  /// The button is optimistic, so this is not what draws its state — it only
  /// stops a second tap racing the first, which on a profile is a real risk:
  /// the button is large and it is the main thing on the screen.
  final bool isFollowWriting;

  final String? errorMessage;
  final String? actionErrorKey;
  final String? actionErrorDetail;

  /// This is the signed-in user's own profile.
  bool get isMe => person?.isMe ?? false;

  /// They have written nothing, and not because it is still loading.
  bool get hasNoPosts => status == AuthorStatus.ready && posts.isEmpty;

  AuthorState copyWith({
    AuthorStatus? status,
    Person? person,
    List<Post>? posts,
    FeedCursor? cursor,
    bool? hasMore,
    bool? isLoadingMore,
    bool? isFollowWriting,
    String? errorMessage,
    String? actionErrorKey,
    String? actionErrorDetail,
    bool clearError = false,
  }) {
    return AuthorState(
      personId: personId,
      status: status ?? this.status,
      person: person ?? this.person,
      posts: posts ?? this.posts,
      cursor: cursor ?? this.cursor,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isFollowWriting: isFollowWriting ?? this.isFollowWriting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      actionErrorKey:
          clearError ? null : (actionErrorKey ?? this.actionErrorKey),
      actionErrorDetail:
          clearError ? null : (actionErrorDetail ?? this.actionErrorDetail),
    );
  }

  @override
  List<Object?> get props => [
        personId,
        status,
        person,
        posts,
        cursor,
        hasMore,
        isLoadingMore,
        isFollowWriting,
        errorMessage,
        actionErrorKey,
        actionErrorDetail,
      ];
}
