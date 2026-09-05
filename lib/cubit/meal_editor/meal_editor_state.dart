part of 'meal_editor_cubit.dart';

enum MealEditorStatus { hydrating, editing, saving, saved, failure }

class MealEditorState extends Equatable {
  const MealEditorState({
    this.draft = const MealDraft(),
    this.baseline = const MealDraft(),
    this.status = MealEditorStatus.editing,
    this.editing,
    this.imageBytes,
    this.imageExtension = 'jpg',
    this.savedMeal,
    this.savedWithoutIngredients = false,
    this.errorKey,
    this.errorDetail,
  });

  final MealDraft draft;

  /// The draft as the form first showed it — empty for a new meal, the stored
  /// meal for an edit.
  ///
  /// Kept so leaving can tell "nothing was touched" from "there is work here",
  /// which a comparison against an empty draft cannot do: an edit starts full.
  final MealDraft baseline;

  final MealEditorStatus status;

  /// The meal being edited, or null when writing a new one.
  ///
  /// Its presence is what turns one save button into two, and
  /// [Meal.isMine] on it is what decides whether "replace" is one of them.
  final Meal? editing;

  bool get isEditing => editing != null;

  /// Replacing is offered only for a meal the user wrote. Someone else's meal
  /// can be edited into a copy, never overwritten — it is theirs, and other
  /// people have saved it.
  bool get canReplace => editing?.isMine ?? false;

  /// The picked photo, already read off disk so the save path doesn't have to
  /// touch the filesystem. Null when no photo was chosen.
  final Uint8List? imageBytes;
  final String imageExtension;

  /// Set once the write lands, so the screen can hand it back to the library.
  final Meal? savedMeal;

  /// The meal saved with the right calories but without its ingredient rows —
  /// almost always `cached_off_foods` refusing the write. Worth telling the
  /// user about, and not worth failing the save over.
  final bool savedWithoutIngredients;

  final String? errorKey;
  final String? errorDetail;

  bool get isSaving => status == MealEditorStatus.saving;

  /// Something has been changed and not saved.
  ///
  /// A photo counts on its own: it is the one edit that leaves the draft's
  /// fields untouched, and picking one and walking away should still ask.
  /// Nothing counts once the save has landed — [savedMeal] means the work is
  /// somewhere safer than this screen.
  bool get hasUnsavedWork =>
      savedMeal == null && (draft != baseline || imageBytes != null);

  /// The form is not built until an edited meal's ingredients have loaded: its
  /// text fields are seeded once, at construction, and building them over an
  /// empty draft would leave them empty.
  bool get isHydrating => status == MealEditorStatus.hydrating;

  /// Save is offered only when the meal has a name and a calorie figure, and
  /// never while a write is already in flight.
  bool get canSave => draft.canSave && !isSaving;

  /// True when the totals are being computed rather than typed, which is what
  /// decides whether the totals card is inputs or read-only figures.
  bool get totalsAreComputed => draft.hasIngredients;

  MealEditorState copyWith({
    MealDraft? draft,
    MealDraft? baseline,
    MealEditorStatus? status,
    Meal? editing,
    Uint8List? imageBytes,
    bool clearImage = false,
    String? imageExtension,
    Meal? savedMeal,
    bool? savedWithoutIngredients,
    String? errorKey,
    String? errorDetail,
    bool clearError = false,
  }) {
    return MealEditorState(
      draft: draft ?? this.draft,
      baseline: baseline ?? this.baseline,
      status: status ?? this.status,
      editing: editing ?? this.editing,
      imageBytes: clearImage ? null : (imageBytes ?? this.imageBytes),
      imageExtension: imageExtension ?? this.imageExtension,
      savedMeal: savedMeal ?? this.savedMeal,
      savedWithoutIngredients:
          savedWithoutIngredients ?? this.savedWithoutIngredients,
      errorKey: clearError ? null : (errorKey ?? this.errorKey),
      errorDetail: clearError ? null : (errorDetail ?? this.errorDetail),
    );
  }

  @override
  List<Object?> get props => [
        draft,
        baseline,
        status,
        editing,
        imageBytes,
        imageExtension,
        savedMeal,
        savedWithoutIngredients,
        errorKey,
        errorDetail,
      ];
}
