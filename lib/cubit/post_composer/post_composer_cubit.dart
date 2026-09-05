import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/meal_repository.dart';
import '../../data/post_repository.dart';
import '../../models/visibility.dart';
import '../../models/meal.dart';
import '../../models/post.dart';
import '../../models/challenge.dart';
import '../../models/post_draft.dart';
import '../../models/post_label.dart';

part 'post_composer_state.dart';

/// Drives writing a post.
///
/// Built per composer screen rather than living in the shell, so closing the
/// sheet throws the draft away — the same lifetime `MealEditorCubit` has. A
/// half-written post that comes back three days later is a surprise, not a
/// feature.
class PostComposerCubit extends Cubit<PostComposerState> {
  PostComposerCubit({
    required PostRepository postRepository,
    required MealRepository mealRepository,
    PostLabel initialLabel = PostLabel.tip,
    Meal? attachedMeal,
    String? groupId,
    String? groupName,
  })  : _posts = postRepository,
        _meals = mealRepository,
        super(PostComposerState(
          draft: PostDraft(
            label: initialLabel,
            attachedMeal: attachedMeal,
            groupId: groupId,
            // A challenge post opens with a blank challenge already attached,
            // so the fields are there to fill in rather than behind another
            // tap. Switching away from the label drops it again.
            challenge: initialLabel == PostLabel.challenge
                ? const ChallengeDraft()
                : null,
          ),
          groupName: groupName,
        ));

  final PostRepository _posts;
  final MealRepository _meals;

  /// Switches the kind of post.
  ///
  /// Moving to `challenge` attaches a blank challenge; moving away drops it.
  /// Keeping it around would mean a tip post silently carrying a challenge
  /// nobody can see, and the repository would write it.
  void setLabel(PostLabel label) {
    if (state.draft.label == label) return;

    final bool wantsChallenge = label == PostLabel.challenge;

    emit(state.copyWith(
      draft: state.draft.copyWith(
        label: label,
        challenge: wantsChallenge
            ? (state.draft.challenge ?? const ChallengeDraft())
            : null,
        clearChallenge: !wantsChallenge,
      ),
    ));
  }

  /// Updates the challenge being set up.
  ///
  /// A no-op when the label is not `challenge`, so a stale field cannot write
  /// into a draft that has moved on.
  void setChallenge(ChallengeDraft challenge) {
    if (state.draft.label != PostLabel.challenge) return;
    emit(state.copyWith(draft: state.draft.copyWith(challenge: challenge)));
  }

  /// Records what has been typed.
  ///
  /// Untrimmed, deliberately: trimming as the user types eats the space before
  /// the word they are about to write. The trim happens once, on the way to the
  /// database.
  void setVisibility(ContentVisibility visibility) {
    emit(state.copyWith(draft: state.draft.copyWith(visibility: visibility)));
  }

  void setContent(String content) {
    if (state.draft.content == content) return;
    emit(state.copyWith(draft: state.draft.copyWith(content: content)));
  }

  /// Attaches a photo. [bytes] are read by the caller, which is the only part
  /// of this that needs the filesystem.
  ///
  /// The bytes live beside the draft rather than in it, so the draft stays a
  /// plain value object whose rules can be tested without megabytes of image
  /// in the fixture.
  void attachImage({
    required String path,
    required Uint8List bytes,
    String extension = 'jpg',
  }) {
    if (!state.draft.canAddImage) return;
    // Picking the same file twice would put it in the post twice — harmless,
    // but never what anyone meant.
    if (state.draft.imagePaths.contains(path)) return;

    emit(state.copyWith(
      draft: state.draft.withImage(path),
      images: {
        ...state.images,
        path: PostImageUpload(path: path, bytes: bytes, extension: extension),
      },
    ));
  }

  void removeImage(String path) {
    final Map<String, PostImageUpload> images = {...state.images}..remove(path);

    emit(state.copyWith(
      draft: state.draft.withoutImage(path),
      images: images,
    ));
  }

  /// Hangs one of the user's own meals off the post.
  void attachMeal(Meal meal) {
    emit(state.copyWith(draft: state.draft.copyWith(attachedMeal: meal)));
  }

  void removeMeal() {
    emit(state.copyWith(
      draft: state.draft.copyWith(clearAttachedMeal: true),
    ));
  }

  /// Loads the meals this post could carry.
  ///
  /// Only the user's own, because attaching someone else's meal would put this
  /// author's name over their work. Read on demand — when the picker opens —
  /// rather than when the composer does, since most posts do not carry a meal.
  Future<void> loadAttachableMeals() async {
    if (state.mealsStatus == ComposerMealsStatus.loading) return;

    emit(state.copyWith(mealsStatus: ComposerMealsStatus.loading));

    try {
      final List<Meal> library = await _meals.fetchLibrary();
      if (isClosed) return;

      emit(state.copyWith(
        mealsStatus: ComposerMealsStatus.ready,
        attachableMeals:
            library.where((meal) => meal.isMine).toList(growable: false),
      ));
    } catch (error) {
      if (isClosed) return;

      debugPrint('Bulkr: attachable meals failed to load — $error');
      emit(state.copyWith(mealsStatus: ComposerMealsStatus.failure));
    }
  }

  /// Writes the post.
  ///
  /// The created post is put on the state rather than returned, so the screen
  /// reacts to it through the same listener it uses for failures instead of
  /// awaiting a call whose result it has to remember across an async gap.
  Future<void> submit() async {
    if (state.isSubmitting || !state.draft.canSubmit) return;

    emit(state.copyWith(isSubmitting: true, clearError: true));

    try {
      // Ordered by the draft, not by the map: a before and an after are not
      // interchangeable, and a Map's iteration order is not the order the user
      // picked them in.
      final List<PostImageUpload> images = [
        for (final String path in state.draft.imagePaths)
          if (state.images[path] != null) state.images[path]!,
      ];

      // The challenge-aware path either way: it delegates to `createPost`
      // when there is no challenge, so there is one call site rather than a
      // branch that can drift.
      final Post post = await _posts.createPostWithChallenge(
        draft: state.draft,
        images: images,
      );

      if (isClosed) return;
      emit(state.copyWith(isSubmitting: false, created: post));
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: post failed to save — $detail');

      emit(state.copyWith(isSubmitting: false, errorDetail: detail));
    }
  }

  void clearError() {
    if (state.errorDetail == null) return;
    emit(state.copyWith(clearError: true));
  }

  static String _describe(Object error) {
    if (error is PostgrestException) {
      return [error.message, if (error.code != null) '(${error.code})']
          .join(' ');
    }
    if (error is StorageException) return error.message;
    return '$error';
  }
}
