import 'package:equatable/equatable.dart';

/// A calorie figure and the three macronutrients that make it up.
///
/// Deliberately unitless about *what* it describes: the same type carries a
/// food's per-100g reference values, one ingredient's contribution, and a whole
/// meal's total. [forGrams] is the only place that reads it as "per 100g", so
/// the scaling rule lives in exactly one spot.
///
/// Kept in doubles rather than the ints the `meals` columns use, because
/// rounding belongs at the edge — summing eight ingredients that were each
/// rounded first drifts by several grams.
class Macros extends Equatable {
  const Macros({
    this.calories = 0,
    this.proteinG = 0,
    this.carbsG = 0,
    this.fatG = 0,
  });

  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;

  static const Macros zero = Macros();

  /// True when there is nothing to show — an unscanned food, or a meal whose
  /// ingredients all came back without nutrition data.
  bool get isEmpty =>
      calories == 0 && proteinG == 0 && carbsG == 0 && fatG == 0;

  Macros operator +(Macros other) => Macros(
        calories: calories + other.calories,
        proteinG: proteinG + other.proteinG,
        carbsG: carbsG + other.carbsG,
        fatG: fatG + other.fatG,
      );

  Macros scaledBy(double factor) => Macros(
        calories: calories * factor,
        proteinG: proteinG * factor,
        carbsG: carbsG * factor,
        fatG: fatG * factor,
      );

  /// Reads this as per-100g reference values and returns what [grams] holds.
  ///
  /// That is the shape Open Food Facts publishes and the shape
  /// `cached_off_foods` stores, so every ingredient contribution in the app
  /// goes through here.
  Macros forGrams(double grams) => scaledBy(grams / 100);

  static Macros sum(Iterable<Macros> parts) =>
      parts.fold(zero, (running, part) => running + part);

  /// Rounded to the integers the `meals` and `daily_logs` columns hold.
  int get caloriesRounded => calories.round();
  int get proteinRounded => proteinG.round();
  int get carbsRounded => carbsG.round();
  int get fatRounded => fatG.round();

  /// Calories the macros themselves account for, at 4/4/9 kcal per gram.
  ///
  /// Rarely equal to [calories]: Open Food Facts reports measured energy, which
  /// includes fibre and alcohol and carries its own rounding. Useful for the
  /// proportional macro bar, which needs a total its three segments actually
  /// add up to.
  double get macroCalories => proteinG * 4 + carbsG * 4 + fatG * 9;

  @override
  List<Object?> get props => [calories, proteinG, carbsG, fatG];

  @override
  String toString() =>
      'Macros(${calories.round()} kcal, P${proteinG.round()} '
      'C${carbsG.round()} F${fatG.round()})';
}

/// Reads a numeric column or JSON field that may arrive as a num, a string, or
/// null. Open Food Facts is inconsistent about all three, and Postgres
/// `numeric` comes back as a string over the wire.
double parseGrams(Object? raw) {
  if (raw is num) return raw.toDouble();
  return double.tryParse('${raw ?? ''}'.trim()) ?? 0;
}
