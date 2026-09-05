import 'dart:math' as math;

import '../models/activity_level.dart';
import '../models/insight.dart';
import '../models/plan_breakdown.dart';
import '../models/user_profile.dart';
import 'calorie_engine.dart';
import 'hydration.dart';
import 'progress_stats.dart';

/// Turns the user's own numbers into the advice shown on the profile.
///
/// Replaces the static "focus areas" list, which was invented gym data. Bulkr
/// is not only a lifting app, so this covers the whole day: weighing in,
/// whether the plan still fits, eating enough, and drinking enough.
///
/// Pure and deterministic — given the same profile, history and date it always
/// produces the same advice, which is what makes it testable.
class InsightEngine {
  const InsightEngine();

  /// Nothing logged for this many days and weighing in becomes the priority.
  static const int staleWeighInDays = 4;

  /// Below this share of the target pace, the user is behind.
  static const double behindPaceFactor = 0.5;

  /// Millilitres of water per kg of bodyweight — a general daily guideline.
  ///
  /// Kept as a forwarding constant rather than a literal: the tracker measures
  /// a real day against this same figure, and the advice card and the water
  /// ring disagreeing by 100 ml would be a bug nobody could explain.
  static const double waterMlPerKg = Hydration.mlPerKg;

  /// Meals the protein target is split across in the advice copy.
  static const int proteinMeals = 4;

  /// Builds the advice list, most urgent first, capped at [limit].
  ///
  /// Anything the user should act on comes first; the remaining slots are
  /// filled with general habits, rotated by date so the section doesn't read
  /// the same every day.
  List<Insight> build({
    required UserProfile profile,
    required ProgressStats progress,
    PlanBreakdown? breakdown,
    DateTime? asOf,
    int limit = 4,
  }) {
    final DateTime now = asOf ?? DateTime.now();

    final List<Insight> urgent = [
      ..._weighInAdvice(progress),
      ..._planAdvice(profile, progress, breakdown),
      ..._paceAdvice(progress, breakdown),
    ];

    final List<Insight> habits = _habitAdvice(profile, progress);
    final int remaining = math.max(0, limit - urgent.length);

    return [
      ...urgent.take(limit),
      ..._rotate(habits, now).take(remaining),
    ];
  }

  /// Rotates the general advice by day of year, so a user opening the app on
  /// consecutive days sees different tips without any of it being random.
  List<Insight> _rotate(List<Insight> items, DateTime now) {
    if (items.length < 2) return items;
    final int dayOfYear = now.difference(DateTime(now.year)).inDays;
    final int offset = dayOfYear % items.length;
    return [...items.sublist(offset), ...items.sublist(0, offset)];
  }

  List<Insight> _weighInAdvice(ProgressStats progress) {
    final int? days = progress.daysSinceLastWeighIn;

    if (days == null) {
      return const [
        Insight(
          id: 'weigh_in_first',
          kind: InsightKind.weighIn,
          titleKey: 'insight_first_weigh_in_title',
          bodyKey: 'insight_first_weigh_in_body',
          tone: InsightTone.warning,
          action: InsightAction.logWeight,
        ),
      ];
    }

    if (days >= staleWeighInDays) {
      return [
        Insight(
          id: 'weigh_in_stale',
          kind: InsightKind.weighIn,
          titleKey: 'insight_weigh_in_due_title',
          bodyKey: 'insight_weigh_in_due_body',
          args: {'days': '$days'},
          tone: InsightTone.warning,
          action: InsightAction.logWeight,
        ),
      ];
    }

    // Logged recently and building a habit worth acknowledging.
    if (days <= 1 && progress.logCount >= 4) {
      return [
        Insight(
          id: 'weigh_in_streak',
          kind: InsightKind.milestone,
          titleKey: 'insight_consistency_title',
          bodyKey: 'insight_consistency_body',
          args: {'count': '${progress.logCount}'},
          tone: InsightTone.positive,
        ),
      ];
    }

    return const [];
  }

  List<Insight> _planAdvice(
    UserProfile profile,
    ProgressStats progress,
    PlanBreakdown? breakdown,
  ) {
    if (progress.isTargetReached) {
      return [
        Insight(
          id: 'target_reached',
          kind: InsightKind.milestone,
          titleKey: 'insight_target_reached_title',
          bodyKey: 'insight_target_reached_body',
          args: {'target': profile.targetWeightKg.toStringAsFixed(1)},
          tone: InsightTone.positive,
          action: InsightAction.recalculate,
        ),
      ];
    }

    if (breakdown != null && breakdown.isStale) {
      return [
        Insight(
          id: 'plan_stale',
          kind: InsightKind.plan,
          titleKey: 'insight_plan_stale_title',
          bodyKey: 'insight_plan_stale_body',
          args: {'weight': profile.currentWeightKg.toStringAsFixed(1)},
          tone: InsightTone.warning,
          action: InsightAction.recalculate,
        ),
      ];
    }

    return const [];
  }

  List<Insight> _paceAdvice(ProgressStats progress, PlanBreakdown? breakdown) {
    final double? rate = progress.weeklyRateKg;
    if (rate == null || progress.isTargetReached) return const [];

    if (rate > CalorieEngine.leanBulkCeilingKgPerWeek) {
      return [
        Insight(
          id: 'pace_fast',
          kind: InsightKind.pace,
          titleKey: 'insight_pace_fast_title',
          bodyKey: 'insight_pace_fast_body',
          args: {
            'rate': rate.toStringAsFixed(2),
            'ceiling':
                CalorieEngine.leanBulkCeilingKgPerWeek.toStringAsFixed(1),
          },
          tone: InsightTone.warning,
          action: InsightAction.recalculate,
        ),
      ];
    }

    // The scale is flat or falling while the target is still ahead.
    if (rate <= 0) {
      return [
        Insight(
          id: 'pace_stalled',
          kind: InsightKind.nutrition,
          titleKey: 'insight_pace_stalled_title',
          bodyKey: 'insight_pace_stalled_body',
          tone: InsightTone.warning,
          action: InsightAction.recalculate,
        ),
      ];
    }

    final double? target = breakdown?.impliedWeeklyGainKg;
    if (target != null && target > 0 && rate < target * behindPaceFactor) {
      return [
        Insight(
          id: 'pace_behind',
          kind: InsightKind.nutrition,
          titleKey: 'insight_pace_behind_title',
          bodyKey: 'insight_pace_behind_body',
          args: {
            'rate': rate.toStringAsFixed(2),
            'target': target.toStringAsFixed(2),
          },
        ),
      ];
    }

    return const [];
  }

  /// Day-to-day habits, none of which depend on anything going wrong.
  List<Insight> _habitAdvice(UserProfile profile, ProgressStats progress) {
    final List<Insight> habits = [];

    if (profile.proteinTargetG > 0) {
      habits.add(
        Insight(
          id: 'protein',
          kind: InsightKind.nutrition,
          titleKey: 'insight_protein_title',
          bodyKey: 'insight_protein_body',
          args: {
            'grams': '${profile.proteinTargetG}',
            'perMeal': '${(profile.proteinTargetG / proteinMeals).round()}',
            'meals': '$proteinMeals',
          },
        ),
      );
    }

    final double? weight = progress.latestWeightKg;
    if (weight != null && weight > 0) {
      // Stated in whatever the user reads the rest of the screen in.
      final double millilitres = weight * waterMlPerKg;
      final bool metric = profile.units.isMetric;
      final double fluidOunces = millilitres / Hydration.mlPerFluidOunce;

      habits.add(
        Insight(
          id: 'hydration',
          kind: InsightKind.hydration,
          titleKey: metric ? 'insight_water_title' : 'insight_water_title_oz',
          bodyKey: metric ? 'insight_water_body' : 'insight_water_body_oz',
          args: metric
              ? {
                  'litres': (millilitres / 1000).toStringAsFixed(1),
                  'glasses': '${Hydration.glassesFor(millilitres)}',
                }
              : {
                  'ounces': fluidOunces.round().toString(),
                  'glasses': '${(fluidOunces / Hydration.glassFlOz).round()}',
                },
        ),
      );
    }

    // Early on, how they weigh matters more than what the number says.
    if (progress.logCount < 3) {
      habits.add(
        const Insight(
          id: 'weigh_in_method',
          kind: InsightKind.habit,
          titleKey: 'insight_weigh_method_title',
          bodyKey: 'insight_weigh_method_body',
        ),
      );
    }

    if (profile.activityLevel == ActivityLevel.sedentary) {
      habits.add(
        const Insight(
          id: 'move_more',
          kind: InsightKind.habit,
          titleKey: 'insight_move_title',
          bodyKey: 'insight_move_body',
        ),
      );
    }

    habits.add(
      const Insight(
        id: 'sleep',
        kind: InsightKind.habit,
        titleKey: 'insight_sleep_title',
        bodyKey: 'insight_sleep_body',
      ),
    );

    if (profile.dailyCalorieTarget > 0) {
      habits.add(
        const Insight(
          id: 'consistency',
          kind: InsightKind.nutrition,
          titleKey: 'insight_eat_consistently_title',
          bodyKey: 'insight_eat_consistently_body',
        ),
      );
    }

    return habits;
  }
}
