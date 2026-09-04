import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/post_repository.dart';
import '../../models/post.dart';
import '../../models/post_comment.dart';

part 'comments_state.dart';

/// Drives one post's conversation.
///
/// Built per comments sheet, like the composer's cubit, so closing the sheet
/// throws away the draft reply and whatever was half-typed. A reply that comes
/// back three days later attached to a thread the user has forgotten is not a
/// feature.
class CommentsCubit extends Cubit<CommentsState> {
  CommentsCubit({
    required PostRepository postRepository,
    required Post post,
  })  : _posts = postRepository,
        super(CommentsState(post: post));

  final PostRepository _posts;

  static const String _actionFailedKey = 'comment_action_failed';

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      emit(state.copyWith(status: CommentsStatus.loading, clearError: true));
    }

    try {
      final List<PostComment> threads = await _posts.fetchComments(
        state.post.id,
        postAuthorId: state.post.authorId,
      );
      if (isClosed) return;

      emit(state.copyWith(
        status: CommentsStatus.ready,
        threads: threads,
        clearError: true,
      ));
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: comments failed to load — $detail');

      // A silent refresh that fails leaves the thread alone. The user asked for
      // fresher comments, not for the ones they were reading to disappear.
      if (silent && state.status == CommentsStatus.ready) {
        emit(state.copyWith(
          actionErrorKey: _actionFailedKey,
          actionErrorDetail: detail,
        ));
        return;
      }

      emit(state.copyWith(
        status: CommentsStatus.failure,
        errorMessage: detail,
      ));
    }
  }

  Future<void> refresh() => load(silent: true);

  /// Records what has been typed. Untrimmed, so the space before the next word
  /// survives.
  void setDraft(String draft) {
    if (state.draft == draft) return;
    emit(state.copyWith(draft: draft));
  }

  /// Aims the next comment at a thread, so it posts as a reply.
  ///
  /// Passing null aims it back at the post. The sheet shows which one is
  /// active above the field, because a reply that silently lands as a
  /// top-level comment reads as the app losing it.
  void replyTo(PostComment? comment) {
    // A reply to a reply is not a thing — the database refuses it — so
    // tapping Reply on one aims at its parent instead of at itself. That is
    // what the user meant anyway: they are answering in that thread.
    final String? target =
        comment == null ? null : (comment.parentId ?? comment.id);

    if (state.replyingToId == target) return;

    emit(state.copyWith(
      replyingToId: target,
      clearReplyTarget: target == null,
      replyingToName: comment?.authorName,
    ));
  }

  void cancelReply() => replyTo(null);

  /// Posts what has been typed.
  ///
  /// The field empties immediately and the comment appears when the write
  /// lands, with the send button showing a spinner in between. Not optimistic,
  /// deliberately: rendering the comment before the server has it would mean
  /// inventing the row, and this cubit does not know the current user's handle
  /// or avatar — so the optimistic version would show their own comment
  /// attributed to "someone" for half a second, which is worse than the wait.
  ///
  /// What it will not do is lose the text. A failed post puts it back in the
  /// field, along with whatever thread it was aimed at.
  Future<void> submit() async {
    final String content = state.draft.trim();
    if (content.isEmpty || state.isSubmitting) return;
    if (content.length > CommentsState.maxLength) return;

    final String? parentId = state.replyingToId;

    emit(state.copyWith(
      isSubmitting: true,
      draft: '',
      clearReplyTarget: true,
      clearError: true,
    ));

    try {
      final PostComment comment = await _posts.addComment(
        postId: state.post.id,
        content: content,
        parentId: parentId,
        postAuthorId: state.post.authorId,
      );
      if (isClosed) return;

      emit(state.copyWith(
        isSubmitting: false,
        threads: _inserted(state.threads, comment),
      ));
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: comment failed to post — $detail');

      // The text goes back in the field. Losing what someone wrote because a
      // request failed is the one outcome worth going out of the way to avoid.
      emit(state.copyWith(
        isSubmitting: false,
        draft: content,
        replyingToId: parentId,
        clearReplyTarget: parentId == null,
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  /// Deletes a comment, taking it off the thread first.
  ///
  /// Offered for the user's own comments and, on their own post, for anyone
  /// else's — the only moderation a post's author has over their own thread.
  /// [PostComment.canDelete] carries which, resolved from the policy rather
  /// than guessed here.
  Future<void> delete(PostComment comment) async {
    if (!comment.canDelete) return;

    final List<PostComment> before = state.threads;

    emit(state.copyWith(
      threads: _removed(before, comment.id),
      clearError: true,
    ));

    try {
      await _posts.deleteComment(comment.id);
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: comment delete failed — $detail');

      emit(state.copyWith(
        threads: before,
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  void clearNotice() {
    if (state.actionErrorKey == null) return;
    emit(state.copyWith(clearError: true));
  }

  /// [threads] with [comment] put where it belongs.
  ///
  /// A top-level comment goes at the end, which is where a chronological thread
  /// puts it. A reply goes at the end of its parent's replies, for the same
  /// reason.
  static List<PostComment> _inserted(
    List<PostComment> threads,
    PostComment comment,
  ) {
    if (!comment.isReply) return [...threads, comment];

    return threads
        .map((thread) => thread.id == comment.parentId
            ? thread.copyWith(replies: [...thread.replies, comment])
            : thread)
        .toList(growable: false);
  }

  /// [threads] without the comment with this id, wherever it sits.
  ///
  /// Removing a top-level comment takes its replies with it, which is what the
  /// database does too — the parent foreign key cascades. Leaving them behind
  /// would reattach someone's "same here" to a conversation that is gone.
  static List<PostComment> _removed(List<PostComment> threads, String id) {
    return threads
        .where((thread) => thread.id != id)
        .map((thread) => thread.replies.any((reply) => reply.id == id)
            ? thread.copyWith(
                replies:
                    thread.replies.where((reply) => reply.id != id).toList(),
              )
            : thread)
        .toList(growable: false);
  }

  static String _describe(Object error) {
    if (error is PostgrestException) {
      return [error.message, if (error.code != null) '(${error.code})']
          .join(' ');
    }
    return '$error';
  }
}
