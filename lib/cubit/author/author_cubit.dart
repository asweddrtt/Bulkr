import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/moderation_repository.dart';
import '../../data/feed_cursor.dart';
import '../../data/follow_repository.dart';
import '../../data/post_repository.dart';
import '../../models/person.dart';
import '../../models/post.dart';

part 'author_state.dart';

/// Drives one person's profile: who they are, and what they have posted.
///
/// Built per profile screen. Two people's profiles are two cubits, which is
/// what keeps "following" state from leaking between them when the user taps
/// through a chain of them.
class AuthorCubit extends Cubit<AuthorState> {
  AuthorCubit({
    required FollowRepository followRepository,
    required PostRepository postRepository,
    required ModerationRepository moderationRepository,
    required String personId,
  })  : _follows = followRepository,
        _posts = postRepository,
        _moderation = moderationRepository,
        super(AuthorState(personId: personId));

  final FollowRepository _follows;
  final PostRepository _posts;
  final ModerationRepository _moderation;

  static const String _actionFailedKey = 'people_action_failed';

  /// Loads the profile and the first page of posts together.
  ///
  /// One await on both rather than one after the other: they are independent,
  /// and a profile that renders its header half a second before its posts looks
  /// like two screens loading.
  Future<void> load({bool silent = false}) async {
    if (!silent) {
      emit(state.copyWith(status: AuthorStatus.loading, clearError: true));
    }

    try {
      final results = await Future.wait([
        _follows.fetchPerson(state.personId),
        _posts.fetchAuthorPosts(state.personId),
      ]);

      if (isClosed) return;

      final Person? person = results[0] as Person?;
      final FeedPage page = results[1] as FeedPage;

      // No readable row. Either the account does not exist or it never
      // finished onboarding, which the read policy treats the same way — and
      // so does this: a profile link to a half-signed-up account wants "not
      // found", not an error.
      if (person == null) {
        emit(state.copyWith(status: AuthorStatus.notFound));
        return;
      }

      // Asked separately, and non-fatally. Whether this person is blocked is
      // a detail of the header; a failure to read it should not turn a profile
      // that loaded into an error screen.
      bool blocked = state.isBlocked;
      try {
        blocked = await _moderation.isBlocked(state.personId);
      } catch (error) {
        debugPrint('Bulkr: block state unavailable — $error');
      }

      if (isClosed) return;

      emit(state.copyWith(
        status: AuthorStatus.ready,
        person: person,
        posts: page.posts,
        cursor: page.nextCursor,
        hasMore: page.hasMore,
        isBlocked: blocked,
        clearError: true,
      ));
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: profile failed to load — $detail');

      if (silent && state.status == AuthorStatus.ready) {
        emit(state.copyWith(
          actionErrorKey: _actionFailedKey,
          actionErrorDetail: detail,
        ));
        return;
      }

      emit(state.copyWith(
        status: AuthorStatus.failure,
        errorMessage: detail,
      ));
    }
  }

  Future<void> refresh() => load(silent: true);

  /// Fetches the next page of their posts.
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.cursor == null) return;
    if (state.status != AuthorStatus.ready) return;

    emit(state.copyWith(isLoadingMore: true));

    try {
      final FeedPage page = await _posts.fetchAuthorPosts(
        state.personId,
        cursor: state.cursor,
      );
      if (isClosed) return;

      emit(state.copyWith(
        posts: _merged(state.posts, page.posts),
        cursor: page.nextCursor ?? state.cursor,
        hasMore: page.hasMore,
        isLoadingMore: false,
      ));
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: profile page failed to load — $detail');

      emit(state.copyWith(
        isLoadingMore: false,
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  /// Likes one of their posts, or takes the like back.
  ///
  /// Duplicates `FeedCubit.toggleLike` rather than delegating to it, and the
  /// duplication is the point: this screen holds posts the feed has never
  /// loaded, so `FeedCubit`'s own update would be a no-op on all of them and
  /// the heart would never fill. Each screen owns the posts it is showing.
  Future<void> toggleLike(Post post) async {
    final bool next = !post.isLiked;

    _replacePost(post.copyWith(
      isLiked: next,
      likeCount: (post.likeCount + (next ? 1 : -1)).clamp(0, 1 << 30),
    ));

    try {
      await _posts.setLiked(postId: post.id, isLiked: next);
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: like failed — $detail');

      _replacePost(post);
      emit(state.copyWith(
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  /// Bookmarks one of their posts, or removes the bookmark.
  Future<void> toggleSave(Post post) async {
    final bool next = !post.isSaved;

    _replacePost(post.copyWith(
      isSaved: next,
      saveCount: (post.saveCount + (next ? 1 : -1)).clamp(0, 1 << 30),
    ));

    try {
      await _posts.setSaved(postId: post.id, isSaved: next);
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: save failed — $detail');

      _replacePost(post);
      emit(state.copyWith(
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  /// Applies a comment count the thread has just changed.
  void setCommentCount(String postId, int count) {
    for (final Post post in state.posts) {
      if (post.id != postId) continue;
      if (post.commentCount == count) return;

      _replacePost(post.copyWith(commentCount: count));
      return;
    }
  }

  /// Removes one of the user's own posts.
  ///
  /// Only reachable on their own profile — the actions sheet offers delete only
  /// to an author — and the post count in the header moves with it, since it is
  /// an aggregate that would otherwise disagree until the next load.
  Future<void> deletePost(Post post) async {
    if (!post.isMine) return;

    final AuthorState before = state;
    final Person? person = state.person;

    emit(state.copyWith(
      posts: state.posts.where((p) => p.id != post.id).toList(),
      person: person?.copyWith(
        postCount: (person.postCount - 1).clamp(0, 1 << 30),
      ),
      clearError: true,
    ));

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

  /// Takes one of the user's own posts off the feed, or puts it back.
  Future<void> setHidden(Post post, {required bool isHidden}) async {
    if (!post.isMine) return;

    _replacePost(post.copyWith(isHidden: isHidden));

    try {
      await _posts.setHidden(postId: post.id, isHidden: isHidden);
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: hide failed — $detail');

      _replacePost(post);
      emit(state.copyWith(
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  /// Swaps one post in the list, matched on id.
  void _replacePost(Post updated) {
    if (!state.posts.any((post) => post.id == updated.id)) return;

    emit(state.copyWith(
      posts: state.posts
          .map((post) => post.id == updated.id ? updated : post)
          .toList(),
    ));
  }

  /// Follows them, or stops.
  ///
  /// Optimistic, follower count included. The count is adjusted locally rather
  /// than refetched — it will disagree with the server by however many other
  /// people followed them in the same second, which is a number nobody is
  /// checking, and the next load reconciles it.
  Future<void> toggleFollow() async {
    final Person? person = state.person;
    if (person == null || !person.isFollowable) return;
    if (state.isFollowWriting) return;

    final bool next = !person.isFollowedByMe;

    emit(state.copyWith(
      person: person.copyWith(
        isFollowedByMe: next,
        followerCount:
            (person.followerCount + (next ? 1 : -1)).clamp(0, 1 << 30),
      ),
      isFollowWriting: true,
      clearError: true,
    ));

    try {
      await _follows.setFollowing(personId: person.id, isFollowing: next);
      if (isClosed) return;

      emit(state.copyWith(isFollowWriting: false));
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: follow failed — $detail');

      emit(state.copyWith(
        person: person,
        isFollowWriting: false,
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  void clearNotice() {
    if (state.actionErrorKey == null) return;
    emit(state.copyWith(clearError: true));
  }

  /// [existing] followed by whatever in [incoming] is not already there.
  static List<Post> _merged(List<Post> existing, List<Post> incoming) {
    final Set<String> seen = existing.map((post) => post.id).toSet();
    return [
      ...existing,
      ...incoming.where((post) => seen.add(post.id)),
    ];
  }

  /// Blocks or unblocks the person whose profile this is.
  ///
  /// Here as well as on a post, and that is the point: someone who has never
  /// posted cannot be blocked from a post, and "has written nothing" is not a
  /// reason to be unreachable by the one control that stops them contacting
  /// you.
  ///
  /// Reloads on success rather than patching the state. Blocking changes what
  /// this screen may read at all — `public.can_view` refuses their posts in
  /// both directions — so the honest thing is to ask again and render whatever
  /// comes back.
  Future<void> setBlocked(bool blocked) async {
    if (state.isBlockWriting) return;

    emit(state.copyWith(isBlockWriting: true, clearError: true));

    try {
      if (blocked) {
        await _moderation.block(state.personId);
      } else {
        await _moderation.unblock(state.personId);
      }

      if (isClosed) return;
      emit(state.copyWith(isBlocked: blocked, isBlockWriting: false));
      await load(silent: true);
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: block failed — $detail');

      emit(state.copyWith(
        isBlockWriting: false,
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  static String _describe(Object error) {
    if (error is PostgrestException) {
      return [error.message, if (error.code != null) '(${error.code})']
          .join(' ');
    }
    return '$error';
  }
}
