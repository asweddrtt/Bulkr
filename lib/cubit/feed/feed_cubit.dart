import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/challenge_repository.dart';
import '../../data/feed_cursor.dart';
import '../../data/meal_repository.dart';
import '../../data/post_repository.dart';
import '../../models/challenge.dart';
import '../../models/meal.dart';
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
  FeedCubit({
    required PostRepository postRepository,
    required MealRepository mealRepository,
    required ChallengeRepository challengeRepository,
  })  : _posts = postRepository,
        _meals = mealRepository,
        _challenges = challengeRepository,
        super(const FeedState());

  final PostRepository _posts;

  /// Taking a meal off a post is a write to the meal library, not to the feed,
  /// so it goes through the repository that owns meals rather than being
  /// reimplemented here.
  final MealRepository _meals;

  /// Joining a challenge, for the same reason.
  final ChallengeRepository _challenges;

  /// Translation key for a failed write, matching `MealsCubit`'s convention.
  static const String _actionFailedKey = 'feed_action_failed';

  /// Confirmation that a meal landed in the library. Worth saying out loud:
  /// the copy appears on a screen the user is not currently looking at.
  static const String _mealSavedKey = 'post_meal_saved';

  /// Confirmation that a challenge was joined, and what it starts from.
  static const String _challengeJoinedKey = 'challenge_joined';

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

  /// Likes a post, or takes the like back.
  ///
  /// Optimistic, and the count moves with the heart. A like is the cheapest
  /// gesture in the app and the one people repeat fastest, so it cannot wait on
  /// a round trip — and the whole cost of being wrong is putting one number
  /// back.
  ///
  /// The count is adjusted locally rather than refetched. It will disagree with
  /// the server by however many other people liked the post in the same second,
  /// which is a number no reader is checking; the next refresh reconciles it.
  Future<void> toggleLike(Post post) async {
    final bool next = !post.isLiked;

    _replaceEverywhere(post.copyWith(
      isLiked: next,
      likeCount: (post.likeCount + (next ? 1 : -1)).clamp(0, 1 << 30),
    ));

    try {
      await _posts.setLiked(postId: post.id, isLiked: next);
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: like failed — $detail');

      // Put the card back exactly as it was, rather than un-toggling what is
      // on screen now: the user may have tapped twice while this was in
      // flight, and the truth is the state before this attempt.
      _replaceEverywhere(post, actionErrorDetail: detail);
    }
  }

  /// Bookmarks a post, or removes the bookmark.
  ///
  /// A bookmark, not a recipe. Taking the meal off a post is [saveMeal], and
  /// the two are separate on purpose — someone can want to reread a post
  /// without wanting its food in their library, and far more often the other
  /// way round.
  Future<void> toggleSave(Post post) async {
    final bool next = !post.isSaved;

    _replaceEverywhere(post.copyWith(
      isSaved: next,
      saveCount: (post.saveCount + (next ? 1 : -1)).clamp(0, 1 << 30),
    ));

    try {
      await _posts.setSaved(postId: post.id, isSaved: next);
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: save failed — $detail');

      _replaceEverywhere(post, actionErrorDetail: detail);
    }
  }

  /// Copies the meal on a post into the user's own library.
  ///
  /// Not optimistic, unlike liking. This one writes a row the user will go
  /// looking for in their Meals tab, and a button that said "saved" for a meal
  /// that is not there is a worse lie than half a second of waiting. Same
  /// reasoning as `MealsCubit.toggleLoggedToday`.
  ///
  /// [onSaved] fires once the copy exists, so the caller can refresh the meal
  /// library it is sitting next to. The cubit does not reach into `MealsCubit`
  /// itself — one cubit calling another is how two sources of truth start.
  Future<void> saveMeal(Post post, {void Function(Meal copy)? onSaved}) async {
    final Meal? meal = post.attachedMeal;
    if (meal == null || !post.canSaveMeal) return;
    if (state.busyPostId != null) return;

    emit(state.copyWith(busyPostId: post.id, clearActionError: true));

    try {
      final Meal copy = await _meals.copyFromPost(meal);
      if (isClosed) return;

      _replaceEverywhere(
        post.copyWith(attachedMealSaved: true),
        clearBusy: true,
        actionMessageKey: _mealSavedKey,
      );

      onSaved?.call(copy);
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: meal copy failed — $detail');

      emit(state.copyWith(
        clearBusy: true,
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  /// Joins a post's challenge, or leaves it.
  ///
  /// Not optimistic, unlike a like. Joining takes a snapshot of the user's
  /// current weight server-side — it is what every later leaderboard position
  /// is measured from — so a button that said "joined" before the write landed
  /// would be claiming a starting point that does not exist.
  ///
  /// The participant count moves with it, which is safe to do locally: it is
  /// an aggregate the next load recomputes.
  Future<void> toggleChallenge(Post post) async {
    final Challenge? challenge = post.challenge;
    if (challenge == null || state.busyPostId != null) return;
    if (challenge.hasEnded) return;

    final bool next = !challenge.hasJoined;

    emit(state.copyWith(busyPostId: post.id, clearActionError: true));

    try {
      await _challenges.setJoined(
        challengeId: challenge.id,
        hasJoined: next,
      );
      if (isClosed) return;

      _replaceEverywhere(
        post.copyWith(
          challenge: challenge.copyWith(
            hasJoined: next,
            participantCount:
                (challenge.participantCount + (next ? 1 : -1)).clamp(0, 1 << 30),
          ),
        ),
        clearBusy: true,
        actionMessageKey: next ? _challengeJoinedKey : null,
      );
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: challenge join failed — $detail');

      emit(state.copyWith(
        clearBusy: true,
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  /// Applies a comment count that a thread has just changed.
  ///
  /// The comments sheet owns the conversation; the card only shows how long it
  /// is. Passing the number back rather than refetching the post keeps the two
  /// in step without a round trip for a value the sheet already knows.
  void setCommentCount(String postId, int count) {
    final Post? post = _find(postId);
    if (post == null || post.commentCount == count) return;

    _replaceEverywhere(post.copyWith(commentCount: count));
  }

  /// Takes one of the user's own posts off the feed, or puts it back.
  ///
  /// Not a delete. The row stays, the author keeps seeing it — the RLS policy
  /// makes an exception for `auth.uid() = user_id` — and it can be undone,
  /// which is the whole difference between unpublishing and losing something.
  ///
  /// Optimistic, and the card stays where it is rather than disappearing: the
  /// author needs to see the "hidden" marker land to know it worked, and a post
  /// that vanishes from your own feed the moment you hide it looks like a
  /// delete you did not mean to do.
  Future<void> setHidden(Post post, {required bool isHidden}) async {
    if (!post.isMine) return;

    emit(state.copyWith(clearActionError: true));
    _replaceEverywhere(post.copyWith(isHidden: isHidden));

    try {
      await _posts.setHidden(postId: post.id, isHidden: isHidden);
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: hide failed — $detail');

      _replaceEverywhere(post, actionErrorDetail: detail);
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

  /// Forgets whatever the last snack bar said.
  ///
  /// Clears the success message as well as the failure, and has to: the screen
  /// only shows a notice when the key *changes*, so a message left set would
  /// make the second identical one — a second meal saved — show nothing at
  /// all.
  void clearNotice() {
    if (state.actionErrorKey == null && state.actionMessageKey == null) return;
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

  /// Puts an updated post into both feeds at once.
  ///
  /// The same post can be sitting in For You and in Discover simultaneously,
  /// and both copies have to move together — otherwise a heart filled in on
  /// one tab is still empty when the user switches to the other, and tapping
  /// it there sends a second like for something already liked.
  ///
  /// [FeedSlice.withPost] is a no-op on a feed that does not hold the post, so
  /// this does not need to know which feed the tap came from.
  void _replaceEverywhere(
    Post post, {
    bool clearBusy = false,
    String? actionErrorDetail,
    String? actionMessageKey,
  }) {
    emit(state.copyWith(
      forYou: state.forYou.withPost(post),
      discover: state.discover.withPost(post),
      clearBusy: clearBusy,
      clearActionError: actionErrorDetail == null && actionMessageKey == null,
      actionErrorKey: actionErrorDetail == null ? null : _actionFailedKey,
      actionErrorDetail: actionErrorDetail,
      actionMessageKey: actionMessageKey,
    ));
  }

  /// The post with this id, from whichever feed holds it.
  Post? _find(String postId) {
    for (final FeedSlice slice in [state.forYou, state.discover]) {
      for (final Post post in slice.posts) {
        if (post.id == postId) return post;
      }
    }
    return null;
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
