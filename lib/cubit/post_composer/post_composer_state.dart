part of 'post_composer_cubit.dart';

/// Whether the meal picker has its list yet. Separate from the composer's own
/// status because a failed meal lookup must not stop someone posting text.
enum ComposerMealsStatus { initial, loading, ready, failure }

class PostComposerState extends Equatable {
  const PostComposerState({
    required this.draft,
    this.images = const {},
    this.isSubmitting = false,
    this.created,
    this.errorDetail,
    this.mealsStatus = ComposerMealsStatus.initial,
    this.attachableMeals = const [],
  });

  /// The post being written. A plain value object — every rule about when it
  /// can be posted is on it, and testable without a widget or a network.
  final PostDraft draft;

  /// Bytes for each picked photo, keyed by the path the draft refers to it by.
  ///
  /// Kept beside the draft rather than in it. Two reasons: the draft stays
  /// cheap to construct in a test, and equality on the draft stays a comparison
  /// of paths rather than of several megabytes of image.
  final Map<String, PostImageUpload> images;

  final bool isSubmitting;

  /// The post, once it exists.
  ///
  /// The screen watches for this rather than awaiting [PostComposerCubit.submit]
  /// — closing the composer and handing the post to the feed are both things
  /// that happen to a `BuildContext`, and doing them after an await means doing
  /// them across an async gap.
  final Post? created;

  final String? errorDetail;

  final ComposerMealsStatus mealsStatus;

  /// Meals the user could attach: their own, and only their own.
  final List<Meal> attachableMeals;

  bool get canSubmit => draft.canSubmit && !isSubmitting;

  bool get isDone => created != null;

  /// Whether closing now would lose something.
  ///
  /// What the discard warning keys off. A label on its own is not work — it is
  /// the default the composer opened with — so it does not count.
  bool get hasUnsavedWork => draft.isPostable && created == null;

  PostComposerState copyWith({
    PostDraft? draft,
    Map<String, PostImageUpload>? images,
    bool? isSubmitting,
    Post? created,
    String? errorDetail,
    bool clearError = false,
    ComposerMealsStatus? mealsStatus,
    List<Meal>? attachableMeals,
  }) {
    return PostComposerState(
      draft: draft ?? this.draft,
      images: images ?? this.images,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      created: created ?? this.created,
      errorDetail: clearError ? null : (errorDetail ?? this.errorDetail),
      mealsStatus: mealsStatus ?? this.mealsStatus,
      attachableMeals: attachableMeals ?? this.attachableMeals,
    );
  }

  @override
  List<Object?> get props => [
        draft,
        // The paths, not the bytes. Equatable would otherwise compare image
        // buffers on every rebuild, which is a lot of work to conclude that
        // nothing changed.
        images.keys.toList(),
        isSubmitting,
        created,
        errorDetail,
        mealsStatus,
        attachableMeals,
      ];
}
