import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/calorie_engine.dart';
import '../../core/insight_engine.dart';
import '../../core/progress_stats.dart';
import '../../data/user_repository.dart';
import '../../models/gender.dart';
import '../../models/insight.dart';
import '../../models/nutrition_plan.dart';
import '../../models/plan_breakdown.dart';
import '../../models/user_profile.dart';
import '../../models/weight_entry.dart';

part 'profile_state.dart';

/// Loads the signed-in user's row and weigh-in history for the post-onboarding
/// screens.
class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit({
    required UserRepository userRepository,
    InsightEngine insightEngine = const InsightEngine(),
  })  : _userRepository = userRepository,
        _insightEngine = insightEngine,
        super(const ProfileState());

  final UserRepository _userRepository;
  final InsightEngine _insightEngine;

  /// Translation key surfaced when any of the writes below fail.
  static const String _saveFailedKey = 'save_failed';

  /// Pace bounds for a recalculation, matching the target-pace screen.
  static const double minWeeklyGainKg = 0.1;
  static const double maxWeeklyGainKg = 1.0;

  /// Fallback pace when the stored target no longer buys any gain, so a
  /// recalculation has no positive pace to preserve.
  static const double fallbackWeeklyGainKg = 0.25;

  /// Fetches profile and weight history together.
  ///
  /// [silent] keeps the current data on screen while refetching, so a
  /// pull-to-refresh doesn't blank the page out and reflow everything.
  Future<void> load({bool silent = false}) async {
    if (!silent) {
      emit(state.copyWith(status: ProfileStatus.loading, clearError: true));
    }

    try {
      final profile = await _userRepository.fetchProfile();

      if (profile == null) {
        emit(state.copyWith(status: ProfileStatus.missing, clearError: true));
        return;
      }

      // The chart is secondary: a failure to read weight_logs — most likely a
      // missing GRANT on that table — shouldn't take the whole profile down
      // with it.
      List<WeightEntry> history;
      try {
        history = await _userRepository.fetchWeightHistory();
      } catch (_) {
        history = state.weightHistory;
      }

      if (isClosed) return;
      emit(state.copyWith(
        status: ProfileStatus.ready,
        profile: profile,
        weightHistory: history,
        clearError: true,
      ));
    } catch (error) {
      if (isClosed) return;
      emit(state.copyWith(
        status: ProfileStatus.failure,
        errorMessage: error.toString(),
      ));
    }
  }

  Future<void> refresh() => load(silent: true);

  /// Trend figures over the loaded history.
  ProgressStats? get progress {
    final profile = state.profile;
    if (profile == null) return null;
    return ProgressStats(
      history: state.weightHistory,
      targetWeightKg: profile.targetWeightKg,
    );
  }

  /// What the stored calorie target is made of, recovering the pace it
  /// represents. Null when the row lacks the biometrics the formula needs —
  /// `date_of_birth` is nullable and BMR cannot be computed without an age.
  PlanBreakdown? get planBreakdown {
    final profile = state.profile;
    if (profile == null) return null;

    final age = profile.age;
    if (age == null ||
        profile.heightCm <= 0 ||
        profile.currentWeightKg <= 0 ||
        profile.dailyCalorieTarget <= 0) {
      return null;
    }

    return CalorieEngine.breakdown(
      gender: profile.gender ?? Gender.other,
      weightKg: profile.currentWeightKg,
      heightCm: profile.heightCm,
      age: age,
      activityLevel: profile.activityLevel,
      storedCalories: profile.dailyCalorieTarget,
    );
  }

  /// The pace a recalculation starts from: the one the stored target implies,
  /// or the conservative default when that target has gone stale.
  double get suggestedWeeklyGainKg {
    final implied = planBreakdown?.impliedWeeklyGainKg;
    if (implied == null || implied <= 0) return fallbackWeeklyGainKg;
    return implied.clamp(minWeeklyGainKg, maxWeeklyGainKg);
  }

  /// The plan that would be written at [weeklyGainKg], recomputed against the
  /// user's *current* weight. Returned rather than saved so the confirmation
  /// sheet can show the numbers before anything is committed.
  NutritionPlan? planForPace(double weeklyGainKg) {
    final profile = state.profile;
    final age = profile?.age;
    if (profile == null || age == null || profile.heightCm <= 0) return null;

    return CalorieEngine.buildPlan(
      gender: profile.gender ?? Gender.other,
      weightKg: profile.currentWeightKg,
      heightCm: profile.heightCm,
      age: age,
      activityLevel: profile.activityLevel,
      weeklyGainKg: weeklyGainKg,
    );
  }

  /// What the user should act on today, derived from the same data the rest of
  /// the screen displays.
  List<Insight> get insights {
    final profile = state.profile;
    final stats = progress;
    if (profile == null || stats == null) return const [];

    return _insightEngine.build(
      profile: profile,
      progress: stats,
      breakdown: planBreakdown,
    );
  }

  /// Records a weigh-in, then reloads so the chart and headline move together.
  Future<void> logWeight(double weightKg) {
    return _write(() => _userRepository.logWeight(weightKg: weightKg));
  }

  Future<void> updateTargetWeight(double targetWeightKg) {
    return _write(
      () => _userRepository.updateTargetWeight(targetWeightKg: targetWeightKg),
    );
  }

  Future<void> applyPlan(NutritionPlan plan) {
    return _write(() => _userRepository.applyPlan(plan: plan));
  }

  /// One write path: flag saving, run it, reload on success, and surface a
  /// message on failure without tearing down what is already on screen.
  Future<void> _write(Future<void> Function() write) async {
    if (state.profile == null) return;
    emit(state.copyWith(isSaving: true, clearActionError: true));

    try {
      await write();
      if (isClosed) return;
      await load(silent: true);
      if (isClosed) return;
      emit(state.copyWith(isSaving: false));
    } catch (error) {
      if (isClosed) return;

      // Surfaced verbatim as well as prettily: the writes here are the first
      // in the app to UPDATE `users` and to INSERT into `weight_logs` outside
      // onboarding, so a missing RLS policy shows up as a real Postgres error
      // that is worth reading rather than hiding behind "try again".
      final String detail = error is PostgrestException
          ? [error.code, error.message].whereType<String>().join(' · ')
          : error.toString();
      debugPrint('Bulkr: profile write failed — $detail');

      emit(state.copyWith(
        isSaving: false,
        actionErrorKey: _saveFailedKey,
        actionErrorDetail: detail,
      ));
    }
  }

  /// Called once the failure has been shown, so it isn't repeated on rebuild.
  void clearActionError() {
    if (state.actionErrorKey == null) return;
    emit(state.copyWith(clearActionError: true));
  }
}
