import 'package:equatable/equatable.dart';

/// The output of [CalorieEngine] — everything screen 5 reveals, and everything
/// written to the `daily_calorie_target` / `*_target_g` columns.
class NutritionPlan extends Equatable {
  const NutritionPlan({
    required this.bmr,
    required this.tdee,
    required this.dailySurplus,
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  /// Basal metabolic rate, Mifflin-St Jeor. Not persisted — shown as context.
  final int bmr;

  /// Maintenance calories: BMR x activity multiplier. Not persisted.
  final int tdee;

  /// Calories per day above maintenance, derived from the weekly gain pace.
  final int dailySurplus;

  /// The number the user commits to. Persisted as `daily_calorie_target`.
  final int calories;

  final int proteinG;
  final int carbsG;
  final int fatG;

  /// Calories actually accounted for by the macro split. Used by the macro bar
  /// to size each segment, and by tests to check the split reconciles.
  int get macroCalories => proteinG * 4 + carbsG * 4 + fatG * 9;

  @override
  List<Object?> get props => [
        bmr,
        tdee,
        dailySurplus,
        calories,
        proteinG,
        carbsG,
        fatG,
      ];
}
