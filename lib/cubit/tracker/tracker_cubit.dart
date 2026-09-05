import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/meal_repository.dart';
import '../../data/user_repository.dart';
import '../../models/daily_log_entry.dart';
import '../../models/food_item.dart';
import '../../models/macros.dart';
import '../../models/meal.dart';
import '../../models/meal_slot.dart';
import '../../models/user_profile.dart';

part 'tracker_state.dart';

/// Drives the Tracker tab: one day's food log against the day's targets.
///
/// Reads its own copy of the `users` row rather than sharing [ProfileCubit]'s.
/// That is one extra query when the tab is opened, bought deliberately: the
/// targets are the denominator of everything on this screen, and recalculating
/// a plan on the dashboard has to be reflected here without the two cubits
/// having to know about each other.
class TrackerCubit extends Cubit<TrackerState> {
  TrackerCubit({
    required MealRepository mealRepository,
    required UserRepository userRepository,
  })  : _meals = mealRepository,
        _users = userRepository,
        super(TrackerState(day: _today()));

  final MealRepository _meals;
  final UserRepository _users;

  /// Translation key surfaced when a write fails.
  static const String _saveFailedKey = 'save_failed';

  static DateTime _today() {
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// Loads the day's entries and the targets they are measured against.
  ///
  /// [silent] keeps what is on screen while refetching, so a pull-to-refresh
  /// does not blank the day out and reflow it.
  Future<void> load({bool silent = false}) async {
    if (!silent) {
      emit(state.copyWith(status: TrackerStatus.loading, clearError: true));
    }

    try {
      final UserProfile? profile = await _users.fetchProfile();

      if (profile == null) {
        // Authenticated with no `users` row — onboarding never finished, so
        // there are no targets to measure anything against. Same state
        // [ProfileCubit] reports, and the screen says the same thing.
        emit(state.copyWith(status: TrackerStatus.missing, clearError: true));
        return;
      }

      final List<DailyLogEntry> entries = await _meals.fetchDayLog(state.day);

      if (isClosed) return;
      emit(state.copyWith(
        status: TrackerStatus.ready,
        profile: profile,
        entries: entries,
        clearError: true,
      ));
    } catch (error) {
      if (isClosed) return;
      final String detail = _describe(error);
      debugPrint('Bulkr: tracker failed to load — $detail');
      emit(state.copyWith(
        status: TrackerStatus.failure,
        errorMessage: detail,
      ));
    }
  }

  Future<void> refresh() => load(silent: true);

  /// Re-reads the day if the calendar has moved on since the last load.
  ///
  /// The tracker lives in an [IndexedStack], so it is built once and kept
  /// alive: `initState` fires the first time the tab is opened and never
  /// again. Left alone, an app that sat in the background overnight would show
  /// yesterday's log under today's heading. Called every time the tab is
  /// selected, and does nothing on the same day so switching tabs is free.
  Future<void> refreshIfDayChanged() async {
    final DateTime today = _today();
    if (today == state.day) return;

    emit(state.copyWith(day: today, entries: const []));
    await load(silent: true);
  }

  // --- Writes -------------------------------------------------------------

  /// Logs a whole meal from the library into [slot].
  Future<void> logMeal({required Meal meal, required MealSlot slot}) {
    return _write(() => _meals.logMeal(meal: meal, slot: slot, day: state.day));
  }

  /// Logs [grams] of a searched food into [slot], without creating a meal.
  Future<void> logFood({
    required FoodItem food,
    required double grams,
    required MealSlot slot,
  }) {
    return _write(() => _meals.logFood(
          food: food,
          grams: grams,
          slot: slot,
          day: state.day,
        ));
  }

  /// Moves one entry to a different slot.
  Future<void> moveEntry(DailyLogEntry entry, MealSlot slot) {
    if (entry.slot == slot) return Future<void>.value();
    return _write(() => _meals.updateLogEntry(entry.copyWith(slot: slot)));
  }

  /// Changes how much of an entry was eaten, scaling its macros to match.
  ///
  /// Refuses silently for an entry with no weight recorded, because there is
  /// nothing to scale from — see [DailyLogEntry.canRescale]. The UI does not
  /// offer the field in that case, so this is the backstop rather than the
  /// check.
  Future<void> resizeEntry(DailyLogEntry entry, double grams) {
    if (!entry.canRescale || grams <= 0) return Future<void>.value();
    return _write(() => _meals.updateLogEntry(entry.scaledTo(grams)));
  }

  /// Removes one entry from the day.
  Future<void> deleteEntry(DailyLogEntry entry) {
    return _write(() => _meals.deleteLogEntry(entry));
  }

  /// One write path: flag saving, run it, re-read the day on success, and
  /// surface a message on failure without tearing down what is on screen.
  ///
  /// Every write re-reads rather than patching the list in place, and none of
  /// them is optimistic. Both for the same reason the meals-screen toggle is
  /// not: this screen's whole job is to state a calorie total, and a total the
  /// user believes was recorded and was not is worth waiting half a second to
  /// avoid.
  Future<void> _write(Future<void> Function() write) async {
    if (state.isSaving) return;

    emit(state.copyWith(isSaving: true, clearActionError: true));

    try {
      await write();
      if (isClosed) return;
      await load(silent: true);
      if (isClosed) return;
      emit(state.copyWith(isSaving: false));
    } catch (error) {
      if (isClosed) return;
      final String detail = _describe(error);
      debugPrint('Bulkr: tracker write failed — $detail');
      emit(state.copyWith(
        isSaving: false,
        actionErrorKey: _saveFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  void clearActionError() => emit(state.copyWith(clearActionError: true));

  /// Postgres errors carry the useful part in [PostgrestException.code] —
  /// 42501 is a row-level security refusal, which reads nothing like a network
  /// problem and should never be reported as one.
  static String _describe(Object error) {
    if (error is PostgrestException) {
      return [error.code, error.message].whereType<String>().join(' · ');
    }
    return error.toString();
  }
}
