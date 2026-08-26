part of 'meal_editor_cubit.dart';

enum MealEditorStatus { editing, saving, saved, failure }

/// Where the ingredient search is up to. Separate from the editor's own status
/// so typing in the search field never looks like the meal is being saved.
enum FoodSearchStatus { idle, searching, results, empty }

class MealEditorState extends Equatable {
  const MealEditorState({
    this.draft = const MealDraft(),
    this.status = MealEditorStatus.editing,
    this.imageBytes,
    this.imageExtension = 'jpg',
    this.searchQuery = '',
    this.searchStatus = FoodSearchStatus.idle,
    this.searchResults = const [],
    this.savedMeal,
    this.errorKey,
    this.errorDetail,
  });

  final MealDraft draft;
  final MealEditorStatus status;

  /// The picked photo, already read off disk so the save path doesn't have to
  /// touch the filesystem. Null when no photo was chosen.
  final Uint8List? imageBytes;
  final String imageExtension;

  final String searchQuery;
  final FoodSearchStatus searchStatus;
  final List<FoodItem> searchResults;

  /// Set once the write lands, so the screen can hand it back to the library.
  final Meal? savedMeal;

  final String? errorKey;
  final String? errorDetail;

  bool get isSaving => status == MealEditorStatus.saving;

  /// Save is offered only when the meal has a name and a calorie figure, and
  /// never while a write is already in flight.
  bool get canSave => draft.canSave && !isSaving;

  /// True when the totals are being computed rather than typed, which is what
  /// decides whether the totals card is inputs or read-only figures.
  bool get totalsAreComputed => draft.hasIngredients;

  MealEditorState copyWith({
    MealDraft? draft,
    MealEditorStatus? status,
    Uint8List? imageBytes,
    bool clearImage = false,
    String? imageExtension,
    String? searchQuery,
    FoodSearchStatus? searchStatus,
    List<FoodItem>? searchResults,
    Meal? savedMeal,
    String? errorKey,
    String? errorDetail,
    bool clearError = false,
  }) {
    return MealEditorState(
      draft: draft ?? this.draft,
      status: status ?? this.status,
      imageBytes: clearImage ? null : (imageBytes ?? this.imageBytes),
      imageExtension: imageExtension ?? this.imageExtension,
      searchQuery: searchQuery ?? this.searchQuery,
      searchStatus: searchStatus ?? this.searchStatus,
      searchResults: searchResults ?? this.searchResults,
      savedMeal: savedMeal ?? this.savedMeal,
      errorKey: clearError ? null : (errorKey ?? this.errorKey),
      errorDetail: clearError ? null : (errorDetail ?? this.errorDetail),
    );
  }

  @override
  List<Object?> get props => [
        draft,
        status,
        imageBytes,
        imageExtension,
        searchQuery,
        searchStatus,
        searchResults,
        savedMeal,
        errorKey,
        errorDetail,
      ];
}
