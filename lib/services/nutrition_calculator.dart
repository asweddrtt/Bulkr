import '../models/user_profile.dart';

/// Calorie target derived from the athlete's baseline and chosen surplus.
class NutritionPlan {
  /// Basal metabolic rate (Mifflin-St Jeor).
  final int bmrKcal;

  /// BMR scaled by the activity multiplier.
  final int maintenanceKcal;
  final int surplusKcal;

  const NutritionPlan({
    required this.bmrKcal,
    required this.maintenanceKcal,
    required this.surplusKcal,
  });

  int get dailyGoalKcal => maintenanceKcal + surplusKcal;
}

class NutritionCalculator {
  const NutritionCalculator();

  /// Mifflin-St Jeor sex constant. Onboarding does not collect sex yet, so
  /// the unspecified case uses the midpoint of the male/female constants.
  static double _sexConstant(Sex sex) {
    switch (sex) {
      case Sex.male:
        return 5;
      case Sex.female:
        return -161;
      case Sex.unspecified:
        return -78;
    }
  }

  /// Returns null until the athlete has logged a weight to calculate from.
  NutritionPlan? planFor(UserProfile profile) {
    final double? weight = profile.currentWeightKg;
    if (weight == null) return null;

    final double bmr = 10 * weight +
        6.25 * profile.heightCm -
        5 * profile.ageYears +
        _sexConstant(profile.sex);
    final double maintenance = bmr * profile.activityLevel.burnMultiplier;

    return NutritionPlan(
      bmrKcal: bmr.round(),
      // Rounded to the nearest 10 kcal; the extra precision is noise.
      maintenanceKcal: (maintenance / 10).round() * 10,
      surplusKcal: profile.bulkPlan.dailySurplusKcal,
    );
  }
}
