part of 'group_cubit.dart';

/// Where a group screen is up to.
///
/// `notFound` is its own state, not a flavour of `failure`: "there is no such
/// group, or it is private and not yours" is a normal thing for a link to
/// mean, and it wants an explanation rather than a retry button.
enum GroupStatus { initial, loading, ready, failure, notFound }

class GroupState extends Equatable {
  const GroupState({
    required this.groupId,
    this.status = GroupStatus.initial,
    this.group,
    this.posts = const [],
    this.cursor,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.isMembershipWriting = false,
    this.errorMessage,
    this.actionErrorKey,
    this.actionErrorDetail,
  });

  /// Which group. Known before the row is, and what every fetch is keyed on.
  final String groupId;

  final GroupStatus status;
  final Group? group;

  /// Its posts, newest first.
  final List<Post> posts;

  final FeedCursor? cursor;
  final bool hasMore;
  final bool isLoadingMore;

  /// A join or leave is in flight.
  ///
  /// Unlike a follow, this one drives the button: joining changes what the
  /// user is allowed to read, so the screen waits for the write rather than
  /// granting access ahead of it.
  final bool isMembershipWriting;

  final String? errorMessage;
  final String? actionErrorKey;
  final String? actionErrorDetail;

  /// Whether this user may write into the group.
  bool get canPost => group?.canPost ?? false;

  /// Nothing posted yet, and not because it is still loading.
  bool get hasNoPosts => status == GroupStatus.ready && posts.isEmpty;

  GroupState copyWith({
    GroupStatus? status,
    Group? group,
    List<Post>? posts,
    FeedCursor? cursor,
    bool? hasMore,
    bool? isLoadingMore,
    bool? isMembershipWriting,
    String? errorMessage,
    String? actionErrorKey,
    String? actionErrorDetail,
    bool clearError = false,
  }) {
    return GroupState(
      groupId: groupId,
      status: status ?? this.status,
      group: group ?? this.group,
      posts: posts ?? this.posts,
      cursor: cursor ?? this.cursor,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isMembershipWriting: isMembershipWriting ?? this.isMembershipWriting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      actionErrorKey:
          clearError ? null : (actionErrorKey ?? this.actionErrorKey),
      actionErrorDetail:
          clearError ? null : (actionErrorDetail ?? this.actionErrorDetail),
    );
  }

  @override
  List<Object?> get props => [
        groupId,
        status,
        group,
        posts,
        cursor,
        hasMore,
        isLoadingMore,
        isMembershipWriting,
        errorMessage,
        actionErrorKey,
        actionErrorDetail,
      ];
}
