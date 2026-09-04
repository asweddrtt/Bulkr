import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/feed_cursor.dart';
import '../../data/post_repository.dart';
import '../../models/post.dart';
import '../../models/post_label.dart';

part 'feed_state.dart';

/// Drives the Feed tab: two feeds, one label filter, and paging over both.
///
/// The two feeds are kept side by side in state rather than one being thrown
/// away when the user switches. Switching tabs is the cheapest gesture on the
/// screen and it has to be instant — refetching on every switch would make the
/// two feel like two screens, and would lose the reader's place in whichever
/// one they came from.
class FeedCubit extends Cubit<FeedState> {
  FeedCubit({required PostRepository postRepository})
      : _posts = postRepository,
        super(const FeedState());

  final PostRepository _posts;

  /// Translation key for a failed write, matching `MealsCubit`'s convention.
  static const String _actionFailedKey = 'feed_action_failed';

  /// Loads the visible tab if it has nothing yet.
  ///
  /// Called when the shell mounts. The other tab stays untouched until the user
  /// goes there — fetching a feed nobody has looked at yet spends their
  /// connection on a screen they may never open.
  Future<void> load({bool silent = false}) => _loadTab(state.tab, silent: silent);

  Future<void> refresh() => _loadTab(state.tab, silent: true);

  /// Switches feeds, fetching the new one only if it is empty.
  void selectTab(FeedTab tab) {
    if (state.tab == tab) return;

    emit(state.copyWith(tab: tab));

    if (state.sliceFor(tab).status == FeedStatus.initial) {
      _loadTab(tab);
    }
  }

  /// Narrows both feeds to one label, or back to all of them.
  ///
  /// Both are reset, not just the visible one. The filter is a property of what
  /// the user wants to read rather than of the tab they happen to be on, so
  /// coming back to the other feed still filtered — but showing rows fetched
  /// under a different filter — would be showing them something they did not
  /// ask for.
  ///
  /// Server-side rather than filtering the loaded page in memory. A feed is
  /// paged, so the rows on the device are the first fifteen of an unbounded
  /// list; filtering those locally would answer "the meal posts among the
  /// fifteen I happen to have" instead of "the meal posts".
  Future<void> selectLabel(PostLabel? label) async {
    if (state.label == label) return;

    emit(state.copyWith(
      label: label,
      clearLabel: label == null,
      forYou: const FeedSlice(),
      discover: const FeedSlice(),
    ));

    await _loadTab(state.tab);
  }

  /// Clears the label filter.
  Future<void> clearLabel() => selectLabel(null);

  /// Fetches the next page of the visible feed.
  ///
  /// Guarded three ways: nothing in flight, something left to fetch, and a
  /// cursor to fetch it from. The scroll listener fires this on every frame
  /// near the bottom, so it is called far more often than it does anything.
  Future<void> loadMore() async {
    final FeedTab tab = state.tab;
    final FeedSlice slice = state.sliceFor(tab);

    if (slice.isLoadingMore || !slice.hasMore || slice.cursor == null) return;
    if (slice.status != FeedStatus.ready) return;

    emit(_withSlice(tab, slice.copyWith(isLoadingMore: true)));

    try {
      final FeedPage page = await _fetch(tab, cursor: slice.cursor);
      if (isClosed) return;

      final FeedSlice current = state.sliceFor(tab);

      emit(_withSlice(
        tab,
        current.copyWith(
          // Appended with the duplicates dropped. Keyset paging does not
          // re-serve rows the way OFFSET does, but a post whose score moved
          // between two pages can still land on both sides of the cursor, and
          // Flutter throws on duplicate keys in a list.
          posts: _merged(current.posts, page.posts),
          cursor: page.nextCursor ?? current.cursor,
          hasMore: page.hasMore,
          isLoadingMore: false,
        ),
      ));
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: feed page failed to load — $detail');

      // The rows already on screen stay. A failed *next* page is not a reason
      // to take away the page the user is reading — they get a snack bar and
      // the scroll simply stops growing.
      emit(_withSlice(
        tab,
        state.sliceFor(tab).copyWith(isLoadingMore: false),
      ).copyWith(
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  /// Puts a just-written post at the top of For You and shows it.
  ///
  /// For You is ordered by recency, so the newest post genuinely belongs first
  /// and prepending it is not a white lie. Discover is ordered by score, where
  /// its true position is somewhere it has to earn, so that feed is marked
  /// stale and refetched rather than being handed a row in a place it has not
  /// reached.
  ///
  /// Dropped silently when the active filter excludes it: a post tagged
  /// `workout` must not appear while the reader is looking at `meal`.
  void postCreated(Post post) {
    final PostLabel? filter = state.label;
    final bool visible = filter == null || filter == post.label;

    final FeedSlice forYou = state.forYou;

    emit(state.copyWith(
      tab: FeedTab.forYou,
      forYou: visible && forYou.status == FeedStatus.ready
          ? forYou.copyWith(posts: [post, ...forYou.posts])
          : forYou,
      // Left as-is if it was never loaded; reset to initial if it was, so the
      // next visit to Discover fetches rather than showing a page written
      // before this post existed.
      discover: state.discover.status == FeedStatus.ready
          ? const FeedSlice()
          : state.discover,
    ));

    if (!visible || forYou.status != FeedStatus.ready) {
      _loadTab(FeedTab.forYou, silent: true);
    }
  }

  /// Deletes one of the user's own posts, taking it off both feeds first.
  ///
  /// Optimistic, unlike logging a meal: the card is gone from the screen before
  /// the write lands, and put back if it fails. The asymmetry is deliberate —
  /// a calorie total the user believes was recorded and was not is worth
  /// waiting on, while a deleted post that reappears for a moment costs
  /// nothing but a flicker.
  Future<void> deletePost(Post post) async {
    if (!post.isMine) return;

    final FeedState before = state;

    emit(state
        .copyWith(
          forYou: state.forYou.without(post.id),
          discover: state.discover.without(post.id),
        )
        .copyWith(clearActionError: true));

    try {
      await _posts.deletePost(post.id);
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: post delete failed — $detail');

      emit(before.copyWith(
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  void clearActionError() {
    if (state.actionErrorKey == null) return;
    emit(state.copyWith(clearActionError: true));
  }

  /// Loads one tab from the top.
  ///
  /// [silent] refreshes underneath what is on screen, so pull-to-refresh does
  /// not blank the list out — the same contract `MealsCubit.load` uses.
  Future<void> _loadTab(FeedTab tab, {bool silent = false}) async {
    final FeedSlice slice = state.sliceFor(tab);

    if (!silent) {
      emit(_withSlice(
        tab,
        slice.copyWith(status: FeedStatus.loading, clearError: true),
      ));
    }

    try {
      final FeedPage page = await _fetch(tab);
      if (isClosed) return;

      emit(_withSlice(
        tab,
        FeedSlice(
          status: FeedStatus.ready,
          posts: page.posts,
          cursor: page.nextCursor,
          hasMore: page.hasMore,
        ),
      ));
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: feed failed to load — $detail');

      // A silent refresh that fails leaves the list alone: the user asked for
      // fresher posts, not for what they were reading to be replaced by an
      // error.
      if (silent && state.sliceFor(tab).status == FeedStatus.ready) {
        emit(state.copyWith(
          actionErrorKey: _actionFailedKey,
          actionErrorDetail: detail,
        ));
        return;
      }

      emit(_withSlice(
        tab,
        FeedSlice(status: FeedStatus.failure, errorMessage: detail),
      ));
    }
  }

  Future<FeedPage> _fetch(FeedTab tab, {FeedCursor? cursor}) {
    return switch (tab) {
      FeedTab.forYou => _posts.fetchForYou(label: state.label, cursor: cursor),
      FeedTab.discover =>
        _posts.fetchDiscover(label: state.label, cursor: cursor),
    };
  }

  FeedState _withSlice(FeedTab tab, FeedSlice slice) {
    return switch (tab) {
      FeedTab.forYou => state.copyWith(forYou: slice),
      FeedTab.discover => state.copyWith(discover: slice),
    };
  }

  /// [existing] followed by whatever in [incoming] is not already there.
  static List<Post> _merged(List<Post> existing, List<Post> incoming) {
    final Set<String> seen = existing.map((post) => post.id).toSet();
    return [
      ...existing,
      ...incoming.where((post) => seen.add(post.id)),
    ];
  }

  /// What went wrong, in words worth showing.
  ///
  /// Postgrest and Storage failures carry a usable message; anything else is
  /// printed as-is, which is more use to a bug report than "something went
  /// wrong".
  static String _describe(Object error) {
    if (error is PostgrestException) {
      return [error.message, if (error.code != null) '(${error.code})']
          .join(' ');
    }
    if (error is StorageException) return error.message;
    return '$error';
  }
}
