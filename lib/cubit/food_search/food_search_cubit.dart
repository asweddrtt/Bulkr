import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/food_repository.dart';
import '../../models/food_item.dart';

part 'food_search_state.dart';

/// Finding a food. Nothing about what happens to it afterwards.
///
/// Lifted out of [MealEditorCubit], which owned this and the meal being edited
/// together. That was fine while the meal editor was the only place someone
/// looked a food up; the tracker's "add food" is the second, and it wants the
/// same three-tier search, the same debounce and the same stale-response guard
/// while doing something completely different with the answer — writing a log
/// entry rather than adding an ingredient.
///
/// So the search is its own cubit and the sheet is generic over what a pick
/// means. Neither caller reimplements the debounce, and neither can drift from
/// the other.
class FoodSearchCubit extends Cubit<FoodSearchState> {
  FoodSearchCubit({required FoodRepository foodRepository})
      : _foods = foodRepository,
        super(const FoodSearchState());

  final FoodRepository _foods;

  Timer? _debounceTimer;

  /// Long enough that typing a word does not fire a request per letter, short
  /// enough that stopping to think produces results before the pause feels
  /// like a hang.
  static const Duration _debounce = Duration(milliseconds: 350);

  /// Searches for a food, debounced.
  ///
  /// The response is dropped if the query moved on while it was in flight —
  /// without that check, a slow request for "chi" can land after a fast one
  /// for "chicken breast" and replace the right results with stale ones.
  void search(String query) {
    _debounceTimer?.cancel();
    emit(state.copyWith(query: query));

    if (query.trim().length < FoodRepository.minQueryLength) {
      emit(state.copyWith(
        status: FoodSearchStatus.idle,
        results: const [],
      ));
      return;
    }

    emit(state.copyWith(status: FoodSearchStatus.searching));

    _debounceTimer = Timer(_debounce, () async {
      final String inFlight = query;

      try {
        final List<FoodItem> results = await _foods.search(inFlight);
        if (isClosed || state.query != inFlight) return;

        emit(state.copyWith(
          results: results,
          status: results.isEmpty
              ? FoodSearchStatus.empty
              : FoodSearchStatus.results,
        ));
      } catch (error) {
        if (isClosed || state.query != inFlight) return;
        debugPrint('Bulkr: food search failed — $error');
        emit(state.copyWith(
          status: FoodSearchStatus.empty,
          results: const [],
        ));
      }
    });
  }

  void clear() {
    _debounceTimer?.cancel();
    emit(const FoodSearchState());
  }

  /// Resolves a scanned barcode, or null when nothing knows it.
  ///
  /// Shows the searching state while it runs, so a scan that has to reach Open
  /// Food Facts does not look like a sheet that stopped responding. Returns
  /// the food rather than acting on it: what a scan means is the caller's
  /// business, same as a tapped result.
  Future<FoodItem?> lookupBarcode(String barcode) async {
    _debounceTimer?.cancel();
    emit(state.copyWith(status: FoodSearchStatus.searching));

    try {
      final FoodItem? food = await _foods.findByBarcode(barcode);
      if (isClosed) return null;

      emit(state.copyWith(
        status: food == null ? FoodSearchStatus.empty : state.restingStatus,
      ));
      return food;
    } catch (error) {
      if (isClosed) return null;
      debugPrint('Bulkr: barcode lookup failed — $error');
      emit(state.copyWith(status: state.restingStatus));
      return null;
    }
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    return super.close();
  }
}
