import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/meal_repository.dart';
import '../../models/meal.dart';
import '../../models/meal_slot.dart';

part 'meals_state.dart';

/// Drives the Meals tab: the library, the two views over it, and the three
/// things a card can do — favourite, log, open.
class MealsCubit extends Cubit<MealsState> {
  MealsCubit({required MealRepository mealRepository})
      : _meals = mealRepository,
        super(const MealsState());

  final MealRepository _meals;

  /// Translation key for a failed write.
  static const String _actionFailedKey = 'meal_action_failed';

  /// Loads the library.
  ///
  /// [silent] refreshes underneath what is on screen, so pull-to-refresh and
  /// the reload after creating a meal don't blank the list out.
  Future<void> load({bool silent = false}) async {
    if (!silent) {
      emit(state.copyWith(status: MealsStatus.loading, errorMessage: null));
    }

    try {
      final List<Meal> library = await _meals.fetchLibrary();
      if (isClosed) return;

      emit(state.copyWith(
        status: MealsStatus.ready,
        library: library,
        errorMessage: null,
      ));
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: meal library failed to load — $detail');

      // A silent refresh that fails leaves the list alone: the user asked for
      // fresher data, not for what they were reading to be replaced by an error.
      if (silent && state.status == MealsStatus.ready) {
        emit(state.copyWith(
          actionErrorKey: _actionFailedKey,
          actionErrorDetail: detail,
        ));
        return;
      }

      emit(state.copyWith(
        status: MealsStatus.failure,
        errorMessage: detail,
      ));
    }
  }

  Future<void> refresh() => load(silent: true);

  void selectTab(MealsTab tab) {
    if (state.tab == tab) return;
    emit(state.copyWith(tab: tab));
  }

  void search(String query) {
    if (state.query == query) return;
    emit(state.copyWith(query: query));
  }

  void clearSearch() => search('');

  /// Flips a meal's favourite mark, updating the card before the write lands.
  ///
  /// Optimistic because a star that waits on the network feels broken, and the
  /// only cost of being wrong is putting the mark back.
  Future<void> toggleFavorite(Meal meal) async {
    final bool next = !meal.isFavorite;

    emit(state.copyWith(
      library: _replace(meal.copyWith(isFavorite: next, isSaved: true)),
      clearActionError: true,
    ));

    try {
      await _meals.setFavorite(mealId: meal.id, isFavorite: next);
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: favourite write failed — $detail');

      emit(state.copyWith(
        library: _replace(meal),
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  /// Puts [meal] in today's log at [slot], or takes it back out.
  ///
  /// A toggle rather than a repeated add, because the button shows a state
  /// rather than firing an event: a card reading "logged" that adds a second
  /// helping when tapped is lying about what it is. Off deletes today's rows
  /// for the meal, so the day's total is what the ticked cards say it is.
  ///
  /// Which is also why the tick keeps meaning "this meal is somewhere in
  /// today's log" now that entries carry a slot. A card cannot show four
  /// states in one checkbox, and the place to see the day broken down by meal
  /// — and to remove one helping without removing the other — is the tracker.
  ///
  /// [slot] is only read when turning the toggle on; the caller collects it
  /// first, so no entry is written slotless. Null is still accepted and still
  /// writes null, because a caller with no way to ask is better off recording
  /// the calories than refusing to.
  ///
  /// Not optimistic, unlike favouriting: a calorie total the user believes was
  /// recorded and was not is worth the half-second of waiting.
  Future<void> toggleLoggedToday(Meal meal, {MealSlot? slot}) async {
    if (state.busyMealId != null) return;

    final bool wasLogged = meal.isLoggedToday;
    emit(state.copyWith(busyMealId: meal.id, clearActionError: true));

    try {
      if (wasLogged) {
        await _meals.unlogMealToday(meal);
      } else {
        await _meals.logMeal(meal: meal, slot: slot);
      }
      if (isClosed) return;

      emit(state.copyWith(
        clearBusy: true,
        library: _replace(meal.copyWith(isLoggedToday: !wasLogged)),
      ));
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: meal log toggle failed — $detail');

      emit(state.copyWith(
        clearBusy: true,
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  /// Takes a meal out of the library.
  ///
  /// Which write that is depends on whose meal it is — the user's own is
  /// deleted outright, someone else's is only unsaved — and [Meal.isMine] is the
  /// single place that decides.
  ///
  /// Optimistic: the card goes immediately and comes back if the write fails.
  /// Restoring the whole previous list rather than re-inserting at an index
  /// keeps the order right even if something else changed the library while the
  /// delete was in flight.
  Future<void> removeMeal(Meal meal) async {
    final List<Meal> before = state.library;

    emit(state.copyWith(
      library: before.where((m) => m.id != meal.id).toList(),
      clearActionError: true,
    ));

    try {
      if (meal.isMine) {
        await _meals.deleteMeal(meal);
      } else {
        await _meals.removeFromLibrary(meal);
      }
    } catch (error) {
      if (isClosed) return;

      final String detail = _describe(error);
      debugPrint('Bulkr: meal removal failed — $detail');

      emit(state.copyWith(
        library: before,
        actionErrorKey: _actionFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  /// Called once a failure has been surfaced, so it isn't repeated on rebuild.
  void clearActionError() {
    if (state.actionErrorKey == null) return;
    emit(state.copyWith(clearActionError: true));
  }

  /// Drops a freshly created meal straight into the library, so the list is
  /// correct before the refetch that follows returns.
  void adopt(Meal meal) {
    emit(state.copyWith(
      library: [meal, ...state.library.where((m) => m.id != meal.id)],
      tab: MealsTab.mine,
      query: '',
    ));
  }

  List<Meal> _replace(Meal updated) {
    return state.library
        .map((meal) => meal.id == updated.id ? updated : meal)
        .toList();
  }

  /// Postgres carries the useful part in the code — 42501 is a row-level
  /// security refusal, which reads nothing like a network problem and should
  /// never be reported as one.
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
