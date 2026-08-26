import 'dart:async';
import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/food_repository.dart';
import '../../data/meal_repository.dart';
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
  })  : _meals = mealRepository,
        _foods = foodRepository,
        super(const MealEditorState());

  final MealRepository _meals;
  final FoodRepository _foods;

  Timer? _searchDebounce;

  /// Long enough that a typed word is one request rather than five, short
  /// enough that the pause doesn't read as the app ignoring you.
  static const Duration _debounce = Duration(milliseconds: 350);

  static const String _saveFailedKey = 'meal_save_failed';

  @override
  Future<void> close() {
    _searchDebounce?.cancel();
    return super.close();
  }

  void setTitle(String title) =>
      emit(state.copyWith(draft: state.draft.copyWith(title: title)));

  void setRecipe(String recipe) =>
      emit(state.copyWith(draft: state.draft.copyWith(recipe: recipe)));

  void setPublic(bool isPublic) =>
      emit(state.copyWith(draft: state.draft.copyWith(isPublic: isPublic)));

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

  /// Searches for a food to add, debounced.
  ///
  /// The response is dropped if the query moved on while it was in flight —
  /// without that check, a slow request for "chi" can land after a fast one for
  /// "chicken breast" and replace the right results with stale ones.
  void searchFoods(String query) {
    _searchDebounce?.cancel();
    emit(state.copyWith(searchQuery: query));

    if (query.trim().length < FoodRepository.minQueryLength) {
      emit(state.copyWith(
        searchStatus: FoodSearchStatus.idle,
        searchResults: const [],
      ));
      return;
    }

    emit(state.copyWith(searchStatus: FoodSearchStatus.searching));

    _searchDebounce = Timer(_debounce, () async {
      final String inFlight = query;

      try {
        final List<FoodItem> results = await _foods.search(inFlight);
        if (isClosed || state.searchQuery != inFlight) return;

        emit(state.copyWith(
          searchResults: results,
          searchStatus: results.isEmpty
              ? FoodSearchStatus.empty
              : FoodSearchStatus.results,
        ));
      } catch (error) {
        if (isClosed || state.searchQuery != inFlight) return;
        debugPrint('Bulkr: food search failed — $error');
        emit(state.copyWith(
          searchStatus: FoodSearchStatus.empty,
          searchResults: const [],
        ));
      }
    });
  }

  void clearFoodSearch() {
    _searchDebounce?.cancel();
    emit(state.copyWith(
      searchQuery: '',
      searchStatus: FoodSearchStatus.idle,
      searchResults: const [],
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

  void removeIngredientAt(int index) =>
      emit(state.copyWith(draft: state.draft.withoutIngredientAt(index)));

  void setAmountAt(int index, double amountG) {
    if (amountG <= 0) return;
    emit(state.copyWith(draft: state.draft.withAmountAt(index, amountG)));
  }

  /// Writes the meal. On success the state carries the saved meal, which the
  /// screen hands back to the library so it appears without a refetch.
  Future<void> save() async {
    if (!state.canSave) return;

    emit(state.copyWith(status: MealEditorStatus.saving, clearError: true));

    try {
      final Meal meal = await _meals.createMeal(
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
