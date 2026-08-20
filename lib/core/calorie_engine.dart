import 'dart:math' as math;

import '../models/activity_level.dart';
import '../models/gender.dart';
import '../models/nutrition_plan.dart';
import '../models/plan_breakdown.dart';

/// Pure calorie math. Deliberately free of Flutter imports so it can be unit
/// tested without a widget binding.
class CalorieEngine {
  const CalorieEngine._();

  /// Energy density of body tissue, kcal per kg. The conventional figure used
  /// to turn a weekly rate of gain into a daily calorie surplus.
  static const double kcalPerKg = 7700;

  /// Grams of protein per kg of current bodyweight on a bulk.
  static const double proteinGPerKg = 1.8;

  /// Share of total calories coming from fat.
  static const double fatCalorieShare = 0.25;

  /// Above this weekly rate, gains skew towards fat. Screen 4 warns past it.
  static const double leanBulkCeilingKgPerWeek = 0.5;

  /// Age in whole years at [asOf], accounting for a birthday that hasn't
  /// happened yet this year.
  static int ageFromDateOfBirth(DateTime dateOfBirth, {DateTime? asOf}) {
    final now = asOf ?? DateTime.now();
    var age = now.year - dateOfBirth.year;
    final hadBirthdayThisYear = now.month > dateOfBirth.month ||
        (now.month == dateOfBirth.month && now.day >= dateOfBirth.day);
    if (!hadBirthdayThisYear) age -= 1;
    return math.max(0, age);
  }

  /// Basal metabolic rate, Mifflin-St Jeor.
  ///
  ///   male:   10*kg + 6.25*cm - 5*age + 5
  ///   female: 10*kg + 6.25*cm - 5*age - 161
  ///
  /// For [Gender.other] there is no published constant. We use the average of
  /// the two (-78) rather than the male figure, which follows the brief's note
  /// about not overestimating.
  static double bmr({
    required Gender gender,
    required double weightKg,
    required double heightCm,
    required int age,
  }) {
    final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
    return base + _genderConstant(gender);
  }

  static double _genderConstant(Gender gender) {
    switch (gender) {
      case Gender.male:
        return 5;
      case Gender.female:
        return -161;
      case Gender.other:
        // (5 + -161) / 2
        return -78;
    }
  }

  /// Maintenance calories.
  static double tdee({required double bmr, required ActivityLevel activityLevel}) =>
      bmr * activityLevel.multiplier;

  /// Daily calories above maintenance needed to gain [weeklyGainKg] per week.
  static double dailySurplus(double weeklyGainKg) => weeklyGainKg * kcalPerKg / 7;

  /// The inverse of [dailySurplus]: the weekly rate a given daily surplus buys.
  static double weeklyGainForSurplus(double dailySurplusKcal) =>
      dailySurplusKcal * 7 / kcalPerKg;

  /// Decomposes an already-stored calorie target against the user's current
  /// numbers, recovering the pace it represents.
  ///
  /// Used by the profile screen to explain the target it displays, and to seed
  /// a recalculation with the pace the user originally chose instead of asking
  /// them for it again.
  static PlanBreakdown breakdown({
    required Gender gender,
    required double weightKg,
    required double heightCm,
    required int age,
    required ActivityLevel activityLevel,
    required int storedCalories,
  }) {
    final basal = bmr(
      gender: gender,
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
    );
    final maintenance = tdee(bmr: basal, activityLevel: activityLevel);
    final surplus = storedCalories - maintenance;

    return PlanBreakdown(
      bmr: basal.round(),
      maintenance: maintenance.round(),
      surplus: surplus.round(),
      calories: storedCalories,
      impliedWeeklyGainKg: weeklyGainForSurplus(surplus),
    );
  }

  /// Runs the whole chain and splits the result into macros.
  ///
  /// Protein is anchored to bodyweight, fat takes a fixed share of total
  /// calories, and carbohydrate absorbs the remainder — the usual ordering for
  /// a bulk, where carbs are the lever that moves.
  static NutritionPlan buildPlan({
    required Gender gender,
    required double weightKg,
    required double heightCm,
    required int age,
    required ActivityLevel activityLevel,
    required double weeklyGainKg,
  }) {
    final basal = bmr(
      gender: gender,
      weightKg: weightKg,
      heightCm: heightCm,
      age: age,
    );
    final maintenance = tdee(bmr: basal, activityLevel: activityLevel);
    final surplus = dailySurplus(weeklyGainKg);

    // Rounded to the nearest 10 — a target of 3,240 reads as a decision,
    // 3,237 reads as a rounding artefact.
    final calories = ((maintenance + surplus) / 10).round() * 10;

    final proteinG = (proteinGPerKg * weightKg).round();
    final fatG = (calories * fatCalorieShare / 9).round();

    // Whatever protein and fat leave behind goes to carbs. Clamped at zero:
    // at very low calories with a heavy person, protein plus fat can exceed
    // the total, and a negative carb target would be nonsense.
    final remainingCalories = calories - (proteinG * 4) - (fatG * 9);
    final carbsG = math.max(0, (remainingCalories / 4).round());

    return NutritionPlan(
      bmr: basal.round(),
      tdee: maintenance.round(),
      dailySurplus: surplus.round(),
      calories: calories,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
    );
  }
}
