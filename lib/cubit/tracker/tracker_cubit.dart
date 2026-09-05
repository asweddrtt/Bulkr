import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/hydration.dart';
import '../../data/meal_repository.dart';
import '../../data/user_repository.dart';
import '../../models/daily_log_entry.dart';
import '../../models/food_item.dart';
import '../../models/macros.dart';
import '../../models/meal.dart';
import '../../models/meal_slot.dart';
import '../../models/user_profile.dart';
import '../../models/water_entry.dart';

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

      // Together: the day's food and the streak it may or may not be part of.
      // The streak is its own cheap integer and never fails loudly — see
      // [MealRepository.fetchStreak] — so it does not need the guarded shape
      // the water read below has.
      final results = await Future.wait([
        _meals.fetchDayLog(state.day),
        _meals.fetchStreak(),
      ]);

      final List<DailyLogEntry> entries = results[0] as List<DailyLogEntry>;
      final int streak = results[1] as int;

      // Water is secondary: a failure to read `water_logs` — most likely
      // `tracker_water.sql` not having been run — must not take the day's food
      // down with it. Same shape as ProfileCubit's weigh-in history.
      List<WaterEntry> water;
      String? waterError;
      try {
        water = await _users.fetchWaterDay(state.day);
      } catch (error) {
        water = const [];
        waterError = _describe(error);
        debugPrint('Bulkr: water unavailable — $waterError');
      }

      if (isClosed) return;
      emit(state.copyWith(
        status: TrackerStatus.ready,
        profile: profile,
        entries: entries,
        streak: streak,
        water: water,
        waterErrorDetail: waterError,
        clearWaterError: waterError == null,
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

    // Only when the tab is showing today. Someone who left it on last Tuesday
    // and came back should still be on last Tuesday.
    if (!state.isToday) return;

    await showDay(today);
  }

  // --- Which day ----------------------------------------------------------

  /// Shows [day], reloading the log and the water for it.
  ///
  /// Clears the entries first rather than leaving the previous day's on screen
  /// while the new one loads. A silent reload is right for a refresh, where the
  /// data is about to be replaced by the same day's; here it would show
  /// Tuesday's food under Wednesday's heading for as long as the query takes.
  Future<void> showDay(DateTime day) async {
    final DateTime target = DateTime(day.year, day.month, day.day);
    if (target == state.day) return;

    // Never forwards of today. There is nothing to show, and a log for a day
    // that has not happened is not a thing the app should let someone write.
    if (target.isAfter(_today())) return;

    emit(state.copyWith(
      day: target,
      entries: const [],
      water: const [],
      clearWaterError: true,
    ));
    await load(silent: true);
  }

  Future<void> previousDay() =>
      showDay(state.day.subtract(const Duration(days: 1)));

  /// Does nothing on today, which is what keeps the forward arrow from
  /// walking into tomorrow.
  Future<void> nextDay() => showDay(state.day.add(const Duration(days: 1)));

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

  // --- Water --------------------------------------------------------------

  /// Records a drink against the day being shown.
  Future<void> addWater(int millilitres) {
    if (millilitres <= 0) return Future<void>.value();
    return _write(
      () => _users.logWater(millilitres: millilitres, day: state.day),
    );
  }

  /// Takes back the most recent drink.
  ///
  /// The undo for a mis-tap, and the reason `water_logs` holds rows rather
  /// than a running total — there is an actual thing to delete.
  Future<void> undoLastWater() {
    final WaterEntry? last = state.lastWater;
    if (last == null) return Future<void>.value();
    return _write(() => _users.deleteWaterEntry(last));
  }

  /// Sets the daily water goal by hand, or clears it back to the derived one.
  ///
  /// Null means derive. Clearing is a real choice a user can make, not the
  /// absence of one — see [TrackerState.waterTargetMl].
  Future<void> setWaterTarget(int? millilitres) {
    if (millilitres != null &&
        (millilitres <= 0 || millilitres > Hydration.maxTargetMl)) {
      return Future<void>.value();
    }
    return _write(() => _users.updateWaterTarget(millilitres: millilitres));
  }

  // --- Weight -------------------------------------------------------------

  /// Records today's weigh-in.
  ///
  /// Today's only, whichever day the tracker is showing — [UserRepository]
  /// writes `logged_at` from the clock and supersedes the same local day, so
  /// there is no honest way to backdate one through it. The screen only offers
  /// the field on today for the same reason.
  ///
  /// Reloading afterwards is what moves the water goal: the target is derived
  /// from `current_weight_kg`, which this write moves.
  Future<void> logWeight(double weightKg) {
    if (weightKg <= 0 || !state.isToday) return Future<void>.value();
    return _write(() => _users.logWeight(weightKg: weightKg));
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

  /// Copies a past day's entries onto the day being shown.
  ///
  /// Returns how many landed, so the screen can say so — "nothing to copy"
  /// and "copied six things" are different outcomes and a silent reload tells
  /// them apart for nobody.
  ///
  /// Goes through [_write] like every other write here: not optimistic, and
  /// followed by a reload, because this screen's job is to state a calorie
  /// total and a total that is wrong for half a second is a total that was
  /// wrong.
  Future<int> repeatDay({required DateTime from, MealSlot? slot}) async {
    int copied = 0;

    await _write(() async {
      copied = await _meals.repeatDay(from: from, to: state.day, slot: slot);
    });

    return copied;
  }

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
