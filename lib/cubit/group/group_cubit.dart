import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/feed_cursor.dart';
import '../../data/group_repository.dart';
import '../../data/post_repository.dart';
import '../../models/group.dart';
import '../../models/post.dart';

part 'group_state.dart';

/// Drives one group: what it is, who is in it, and what has been posted there.
///
/// Built per group screen, so tapping through several does not leak one
/// group's membership state into another's.
class GroupCubit extends Cubit<GroupState> {
  GroupCubit({
    required GroupRepository groupRepository,
    required PostRepository postRepository,
    required String groupId,
  })  : _groups = groupRepository,
        _posts = postRepository,
        super(GroupState(groupId: groupId));

  final GroupRepository _groups;
  final PostRepository _posts;

  static const String _actionFailedKey = 'groups_action_failed';

  /// Loads the group and its first page of posts together.
  Future<void> load({bool silent = false}) async {
    if (!silent) {
      emit(state.copyWith(status: GroupStatus.loading, clearError: true));
    }

    try {
      final results = await Future.wait([
        _groups.fetchGroup(state.groupId),
        _posts.fetchGroupPosts(state.groupId),
      ]);

      if (isClosed) return;

      final Group? group = results[0] as Group?;
      final FeedPage page = results[1] as FeedPage;

      // Not readable. Either it does not exist or it is private and this user
      // is not in it — and telling those apart would itself confirm that a
      // private group exists, so both get "not found".
      if (group == null) {
        emit(state.copyWith(status: GroupStatus.notFound));
        return;
      }

      emit(state.copyWith(
        status: GroupStatus.ready,
        group: group,
        posts: page.posts,
        cursor: page.nextCursor,
        hasMore: page.hasMore,
        clearError: true,
      ));
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: group failed to load — $detail');

      if (silent && state.status == GroupStatus.ready) {
        emit(state.copyWith(
          actionErrorKey: _actionFailedKey,
          actionErrorDetail: detail,
        ));
        return;
      }

      emit(state.copyWith(status: GroupStatus.failure, errorMessage: detail));
    }
  }

  Future<void> refresh() => load(silent: true);

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || state.cursor == null) return;
    if (state.status != GroupStatus.ready) return;

    emit(state.copyWith(isLoadingMore: true));

    try {
      final FeedPage page = await _posts.fetchGroupPosts(
        state.groupId,
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
      debugPrint('Bulkr: group page failed to load — $detail');

      emit(state.copyWith(
        isLoadingMore: false,
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  /// Joins the group, or leaves it.
  ///
  /// Not optimistic, unlike a follow. Joining changes what the user can read —
  /// a private group's posts appear, and the composer starts offering to post
  /// here — and a screen that grants access before the write lands would show
  /// a post button that then fails.
  Future<void> toggleMembership() async {
    final Group? group = state.group;
    if (group == null || group.isOwner || state.isMembershipWriting) return;

    final bool next = !group.isMember;

    emit(state.copyWith(isMembershipWriting: true, clearError: true));

    try {
      await _groups.setMembership(groupId: group.id, isMember: next);
      if (isClosed) return;

      emit(state.copyWith(
        group: group.copyWith(
          isMember: next,
          memberCount: (group.memberCount + (next ? 1 : -1)).clamp(0, 1 << 30),
        ),
        isMembershipWriting: false,
      ));

      // Joining a private group makes its posts readable for the first time,
      // and leaving one makes them unreadable — so the list has to be refetched
      // rather than kept. Leaving with the posts still on screen would show
      // content the policy no longer permits.
      await load(silent: true);
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: group membership failed — $detail');

      emit(state.copyWith(
        isMembershipWriting: false,
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  /// Puts a just-written post at the top.
  ///
  /// A group's feed is ordered by recency, so the newest post genuinely
  /// belongs first. Dropped when the post was not written into this group.
  void postCreated(Post post) {
    if (post.groupId != state.groupId) return;
    if (state.status != GroupStatus.ready) return;

    final Group? group = state.group;

    emit(state.copyWith(
      posts: [post, ...state.posts],
      group: group?.copyWith(postCount: group.postCount + 1),
    ));
  }

  /// Likes one of the group's posts, or takes the like back.
  ///
  /// Owns its own copy for the same reason the profile screen does: the feed
  /// has never loaded these posts, so its update would no-op on all of them.
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
      _revert(post, error);
    }
  }

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
      _revert(post, error);
    }
  }

  void setCommentCount(String postId, int count) {
    for (final Post post in state.posts) {
      if (post.id != postId) continue;
      if (post.commentCount == count) return;

      _replacePost(post.copyWith(commentCount: count));
      return;
    }
  }

  /// Removes one of the user's own posts from the group.
  Future<void> deletePost(Post post) async {
    if (!post.isMine) return;

    final GroupState before = state;
    final Group? group = state.group;

    emit(state.copyWith(
      posts: state.posts.where((p) => p.id != post.id).toList(),
      group: group?.copyWith(
        postCount: (group.postCount - 1).clamp(0, 1 << 30),
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

  Future<void> setHidden(Post post, {required bool isHidden}) async {
    if (!post.isMine) return;

    _replacePost(post.copyWith(isHidden: isHidden));

    try {
      await _posts.setHidden(postId: post.id, isHidden: isHidden);
    } catch (error) {
      if (isClosed) return;
      _revert(post, error);
    }
  }

  void clearNotice() {
    if (state.actionErrorKey == null) return;
    emit(state.copyWith(clearError: true));
  }

  void _revert(Post post, Object error) {
    final String detail = _describe(error);
    debugPrint('Bulkr: group post write failed — $detail');

    _replacePost(post);
    emit(state.copyWith(
      actionErrorKey: _actionFailedKey,
      actionErrorDetail: detail,
    ));
  }

  void _replacePost(Post updated) {
    if (!state.posts.any((post) => post.id == updated.id)) return;

    emit(state.copyWith(
      posts: state.posts
          .map((post) => post.id == updated.id ? updated : post)
          .toList(),
    ));
  }

  static List<Post> _merged(List<Post> existing, List<Post> incoming) {
    final Set<String> seen = existing.map((post) => post.id).toSet();
    return [
      ...existing,
      ...incoming.where((post) => seen.add(post.id)),
    ];
  }

  static String _describe(Object error) {
    if (error is PostgrestException) {
      return [error.message, if (error.code != null) '(${error.code})']
          .join(' ');
    }
    return '$error';
  }
}
