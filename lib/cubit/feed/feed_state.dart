part of 'feed_cubit.dart';

enum FeedStatus { initial, loading, ready, failure }

/// The two feeds.
///
/// `forYou` is people the user chose — the accounts they follow and the groups
/// they're in — newest first. `discover` is everything public, ranked by
/// engagement decayed by age.
enum FeedTab { forYou, discover }

/// One feed's contents.
///
/// Both feeds get their own copy of this rather than sharing one list, which is
/// what lets switching tabs be instant and keep each one's scroll position and
/// paging cursor.
class FeedSlice extends Equatable {
  const FeedSlice({
    this.status = FeedStatus.initial,
    this.posts = const [],
    this.cursor,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.errorMessage,
  });

  final FeedStatus status;

  final List<Post> posts;

  /// Where the next page starts. Null when this feed has been read to the end,
  /// or has not been read at all.
  final FeedCursor? cursor;

  final bool hasMore;

  /// A page is in flight below the ones on screen. Keeps the spinner at the
  /// bottom rather than over the whole list, and stops the scroll listener
  /// asking for the same page twice.
  final bool isLoadingMore;

  final String? errorMessage;

  /// Nothing to show, and not because it is still loading.
  bool get isEmpty => status == FeedStatus.ready && posts.isEmpty;

  /// This feed without one post, cursor and paging untouched.
  ///
  /// Removing a row does not invalidate the cursor: it still names a real
  /// position in the ordering, and the deleted post is simply not in the pages
  /// after it either.
  FeedSlice without(String postId) {
    return copyWith(
      posts: posts.where((post) => post.id != postId).toList(),
    );
  }

  /// This feed with everything by one author removed.
  ///
  /// For blocking, where one post is what was tapped but the person is what
  /// was meant. Only clears what has already been fetched — from the next
  /// fetch on the policy is what keeps them out, so this is the screen
  /// catching up rather than the mechanism.
  FeedSlice withoutAuthor(String authorId) {
    return copyWith(
      posts: posts.where((post) => post.authorId != authorId).toList(),
    );
  }

  /// This feed with one post replaced, matched on id.
  ///
  /// What like, save and hide all go through once those land: the same post can
  /// be sitting in both feeds at once, and both copies have to move together or
  /// the button changes state depending on which tab you tapped it from.
  FeedSlice withPost(Post updated) {
    if (!posts.any((post) => post.id == updated.id)) return this;

    return copyWith(
      posts: posts
          .map((post) => post.id == updated.id ? updated : post)
          .toList(),
    );
  }

  FeedSlice copyWith({
    FeedStatus? status,
    List<Post>? posts,
    FeedCursor? cursor,
    bool? hasMore,
    bool? isLoadingMore,
    String? errorMessage,
    bool clearError = false,
  }) {
    return FeedSlice(
      status: status ?? this.status,
      posts: posts ?? this.posts,
      cursor: cursor ?? this.cursor,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props =>
      [status, posts, cursor, hasMore, isLoadingMore, errorMessage];
}

class FeedState extends Equatable {
  const FeedState({
    this.tab = FeedTab.forYou,
    this.label,
    this.forYou = const FeedSlice(),
    this.discover = const FeedSlice(),
    this.busyPostId,
    this.actionErrorKey,
    this.actionErrorDetail,
    this.actionMessageKey,
  });

  /// Which feed is showing.
  ///
  /// Opens on For You. Someone who follows nobody lands on an empty tab that
  /// says so and points at Discover, which is a worse first second than opening
  /// on Discover would be — and a better second week, because the feed the user
  /// built is the one the app should default to once they have built it.
  final FeedTab tab;

  /// The label both feeds are narrowed to, or null for all of them.
  final PostLabel? label;

  final FeedSlice forYou;
  final FeedSlice discover;

  /// A post mid-write, so its own card can show a spinner while the rest of
  /// the feed stays interactive.
  ///
  /// Only the slow actions take it. Liking and saving are optimistic and never
  /// busy — a heart that spins is a heart that feels broken — while copying a
  /// meal writes rows the user will go looking for elsewhere and is worth
  /// waiting on visibly.
  final String? busyPostId;

  /// A failed write, for a snack bar. Keyed the way `MealsState` does it: a
  /// translation key plus the raw detail, so the message can be specific
  /// without every failure needing its own string.
  final String? actionErrorKey;
  final String? actionErrorDetail;

  /// A write that succeeded and is worth saying so, for the same snack bar.
  ///
  /// Kept apart from the error keys rather than folded in with a flag, because
  /// the two are shown differently and confusing them means telling someone a
  /// failure went through.
  final String? actionMessageKey;

  FeedSlice get current => sliceFor(tab);

  FeedSlice sliceFor(FeedTab tab) => switch (tab) {
        FeedTab.forYou => forYou,
        FeedTab.discover => discover,
      };

  bool get isFiltered => label != null;

  /// Whether the visible feed is empty *because of the filter* rather than
  /// because there is nothing there.
  ///
  /// The two want different things said about them — one offers to clear the
  /// filter, the other explains what the feed is for — and telling a user
  /// "nothing here yet" while a filter they set is hiding twelve posts is the
  /// kind of thing that gets reported as a bug.
  bool get isFilteredEmpty => current.isEmpty && isFiltered;

  FeedState copyWith({
    FeedTab? tab,
    PostLabel? label,
    bool clearLabel = false,
    FeedSlice? forYou,
    FeedSlice? discover,
    String? busyPostId,
    bool clearBusy = false,
    String? actionErrorKey,
    String? actionErrorDetail,
    String? actionMessageKey,
    bool clearActionError = false,
  }) {
    return FeedState(
      tab: tab ?? this.tab,
      label: clearLabel ? null : (label ?? this.label),
      forYou: forYou ?? this.forYou,
      discover: discover ?? this.discover,
      busyPostId: clearBusy ? null : (busyPostId ?? this.busyPostId),
      actionErrorKey:
          clearActionError ? null : (actionErrorKey ?? this.actionErrorKey),
      actionErrorDetail: clearActionError
          ? null
          : (actionErrorDetail ?? this.actionErrorDetail),
      actionMessageKey: clearActionError
          ? null
          : (actionMessageKey ?? this.actionMessageKey),
    );
  }

  @override
  List<Object?> get props => [
        tab,
        label,
        forYou,
        discover,
        busyPostId,
        actionErrorKey,
        actionErrorDetail,
        actionMessageKey,
      ];
}
