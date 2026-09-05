import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/food_repository.dart';
import '../../data/meal_repository.dart';
import '../../models/visibility.dart';
import '../../models/food_item.dart';
import '../../models/macros.dart';
import '../../models/meal.dart';
import '../../models/meal_draft.dart';
import '../../models/meal_ingredient.dart';

part 'meal_editor_state.dart';

/// Builds one meal.
///
/// Holds the draft, runs the Open Food Facts ingredient search, and performs the
/// save. The arithmetic all lives on [MealDraft] — this class only decides when
/// the draft changes and talks to the two repositories.
class MealEditorCubit extends Cubit<MealEditorState> {
  MealEditorCubit({
    required MealRepository mealRepository,
    required FoodRepository foodRepository,
    Meal? editing,
    ContentVisibility initialVisibility = ContentVisibility.private,
  })  : _meals = mealRepository,
        _foods = foodRepository,
        super(
          editing == null
              ? MealEditorState(draft: MealDraft(visibility: initialVisibility))
              : MealEditorState(
                  status: MealEditorStatus.hydrating,
                  editing: editing,
                ),
        ) {
    if (editing != null) _hydrate(editing);
  }

  /// Loads an existing meal into the draft.
  ///
  /// The ingredients are a second read — a meal card carries totals, not an
  /// itemisation — and the form waits for them. Opening on an empty ingredient
  /// list and filling it a moment later would show a meal briefly claiming to
  /// have none, and its totals recomputing from nothing.
  Future<void> _hydrate(Meal meal) async {
    try {
      final List<MealIngredient> ingredients =
          await _meals.fetchIngredients(meal.id);
      if (isClosed) return;

      emit(state.copyWith(
        draft: MealDraft.fromMeal(meal, ingredients),
        status: MealEditorStatus.editing,
      ));
    } catch (error) {
      if (isClosed) return;
      debugPrint('Bulkr: could not load meal ingredients — $error');

      // The rest of the meal is still editable, and its stored totals are still
      // right, so this opens without the itemisation rather than not at all.
      emit(state.copyWith(
        draft: MealDraft.fromMeal(meal, const []),
        status: MealEditorStatus.editing,
      ));
    }
  }

  final MealRepository _meals;
  final FoodRepository _foods;

  static const String _saveFailedKey = 'meal_save_failed';

  void setTitle(String title) =>
      emit(state.copyWith(draft: state.draft.copyWith(title: title)));

  void setRecipe(String recipe) =>
      emit(state.copyWith(draft: state.draft.copyWith(recipe: recipe)));

  void setVisibility(ContentVisibility visibility) =>
      emit(state.copyWith(draft: state.draft.copyWith(visibility: visibility)));

  /// Updates one of the four hand-typed totals.
  ///
  /// Only reaches the saved meal when there are no ingredients — see
  /// [MealDraft.totals] — but the values are kept either way, so pulling the
  /// last ingredient out doesn't wipe numbers the user typed earlier.
  void setManualTotals({
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
  }) {
    final Macros current = state.draft.manualTotals;

    emit(state.copyWith(
      draft: state.draft.copyWith(
        manualTotals: Macros(
          calories: calories ?? current.calories,
          proteinG: proteinG ?? current.proteinG,
          carbsG: carbsG ?? current.carbsG,
          fatG: fatG ?? current.fatG,
        ),
      ),
    ));
  }

  /// Attaches a photo the user took or picked. [bytes] are read by the caller,
  /// which is the only part of this that needs the filesystem.
  void attachImage({
    required String path,
    required Uint8List bytes,
    String extension = 'jpg',
  }) {
    emit(state.copyWith(
      draft: state.draft.copyWith(imagePath: path),
      imageBytes: bytes,
      imageExtension: extension,
    ));
  }

  void removeImage() {
    emit(state.copyWith(
      draft: state.draft.copyWith(clearImage: true),
      clearImage: true,
    ));
  }

  /// Adds [food] at [amountG], or corrects the amount if it is already in.
  void addIngredient(FoodItem food, double amountG) {
    if (amountG <= 0) return;

    emit(state.copyWith(
      draft: state.draft.withIngredient(
        MealIngredient(food: food, amountG: amountG),
      ),
    ));
  }

  /// Looks up a scanned barcode and adds it, or reports that nothing knows it.
  ///
  /// Added at 100g rather than opening the amount editor first: a scan is a
  /// confident answer about *what*, and the amount is a separate decision the
  /// user can make by tapping the row. Returns the food so the screen can say
  /// which one landed.
  ///
  /// The lookup itself is [FoodRepository]'s; what is left here is the part
  /// that is about a meal — which amount to add at, given what the draft
  /// already holds. The search that used to live alongside it now belongs to
  /// [FoodSearchCubit], because the tracker wanted the same search and a
  /// different destination.
  Future<FoodItem?> addScannedBarcode(String barcode) async {
    try {
      final FoodItem? food = await _foods.findByBarcode(barcode);
      if (isClosed || food == null) return null;

      // Keeps the existing amount when the food is already in the meal, so
      // re-scanning something does not quietly reset 250g to 100.
      final double amount = _existingAmountFor(food) ?? _defaultScanAmountG;
      addIngredient(food, amount);

      return food;
    } catch (error) {
      if (isClosed) return null;
      debugPrint('Bulkr: barcode lookup failed — $error');
      return null;
    }
  }

  /// The basis nutrition is quoted on, and the honest default when nothing
  /// about the scan says how much was eaten.
  static const double _defaultScanAmountG = 100;

  double? _existingAmountFor(FoodItem food) {
    for (final MealIngredient ingredient in state.draft.ingredients) {
      if (ingredient.food.barcode == food.barcode) return ingredient.amountG;
    }
    return null;
  }

  void removeIngredientAt(int index) =>
      emit(state.copyWith(draft: state.draft.withoutIngredientAt(index)));

  void setAmountAt(int index, double amountG) {
    if (amountG <= 0) return;
    emit(state.copyWith(draft: state.draft.withAmountAt(index, amountG)));
  }

  /// Writes the meal.
  ///
  /// [replaceExisting] overwrites the meal being edited; otherwise this creates
  /// a new one, which is how an edited copy of someone else's meal is kept
  /// without touching theirs. On success the state carries the saved meal, which
  /// the screen hands back to the library so it appears without a refetch.
  Future<void> save({bool replaceExisting = false}) async {
    if (!state.canSave) return;

    final Meal? editing = state.editing;
    final bool replacing = replaceExisting && editing != null;

    // Guarded here as well as in the UI: replacing someone else's meal would
    // rewrite it for everyone who saved it.
    if (replacing && !editing.isMine) return;

    emit(state.copyWith(status: MealEditorStatus.saving, clearError: true));

    try {
      final Meal meal = replacing
          ? await _meals.updateMeal(
              meal: editing,
              draft: state.draft,
              imageBytes: state.imageBytes,
              imageExtension: state.imageExtension,
            )
          : await _meals.createMeal(
              draft: state.draft,
              imageBytes: state.imageBytes,
              imageExtension: state.imageExtension,
            );

      if (isClosed) return;

      // The repository returns the ingredients only when they were stored, so
      // an itemised draft that comes back bare is a partial save.
      final bool lostIngredients =
          state.draft.hasIngredients && meal.ingredients.isEmpty;

      emit(state.copyWith(
        status: MealEditorStatus.saved,
        savedMeal: meal,
        savedWithoutIngredients: lostIngredients,
      ));
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: meal save failed — $detail');

      emit(state.copyWith(
        status: MealEditorStatus.failure,
        errorKey: _saveFailedKey,
        errorDetail: detail,
      ));
    }
  }

  /// Puts the form back in an editable state after a failed save, so the user
  /// can change something and try again.
  void dismissError() {
    if (state.errorKey == null) return;
    emit(state.copyWith(status: MealEditorStatus.editing, clearError: true));
  }

  static String _describe(Object error) {
    if (error is PostgrestException) {
      return [error.code, error.message].whereType<String>().join(' · ');
    }
    if (error is StorageException) {
      return [error.statusCode, error.message].whereType<String>().join(' · ');
    }
    return error.toString();
  }
}
