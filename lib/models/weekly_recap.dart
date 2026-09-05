import 'package:equatable/equatable.dart';

/// The last seven days, as one row.
///
/// What `public.weekly_recap()` returns. Every field is already reduced — the
/// week's `daily_logs`, `water_logs` and `weight_logs` are collapsed in the
/// database and eight numbers come back, rather than a few hundred rows coming
/// back to be added up here.
class WeeklyRecap extends Equatable {
  const WeeklyRecap({
    this.daysLogged = 0,
    this.entries = 0,
    this.avgCalories = 0,
    this.avgProteinG = 0,
    this.avgCarbsG = 0,
    this.avgFatG = 0,
    this.daysOnTarget = 0,
    this.calorieTarget = 0,
    this.avgWaterMl = 0,
    this.weightChangeKg = 0,
    this.firstWeightKg,
    this.lastWeightKg,
  });

  /// Days out of seven with anything logged. The honest denominator for
  /// everything else here — an average over two days is not a week's average,
  /// and the screen says which it is.
  final int daysLogged;

  /// How many individual things were logged across those days.
  final int entries;

  /// Per *logged* day, not per day. Someone who logged four days wants to know
  /// what those four days looked like; dividing by seven would tell them they
  /// are eating half of what they are eating.
  final int avgCalories;
  final int avgProteinG;
  final int avgCarbsG;
  final int avgFatG;

  /// Days that landed within a tenth of the calorie goal either way. Zero when
  /// there is no goal set, which is why [hasTarget] is asked first.
  final int daysOnTarget;

  final int calorieTarget;

  /// Averaged over days with a drink recorded. A day nobody logged is missing,
  /// not zero.
  final int avgWaterMl;

  /// Last weigh-in minus first, over the week. Zero when there are fewer than
  /// two — which is also what "no change" looks like, so [hasWeightTrend] is
  /// what tells them apart.
  final double weightChangeKg;

  final double? firstWeightKg;
  final double? lastWeightKg;

  bool get hasAnything => daysLogged > 0;

  bool get hasTarget => calorieTarget > 0;

  bool get hasWater => avgWaterMl > 0;

  /// Two weigh-ins at different moments, which is the least a trend needs.
  bool get hasWeightTrend => firstWeightKg != null && lastWeightKg != null;

  bool get isGaining => weightChangeKg > 0;

  /// How much of the week was logged, for a meter.
  double get loggedProgress => (daysLogged / 7).clamp(0.0, 1.0);

  factory WeeklyRecap.fromRow(Map<String, dynamic> row) => WeeklyRecap(
        daysLogged: _int(row['days_logged']),
        entries: _int(row['entries']),
        avgCalories: _int(row['avg_calories']),
        avgProteinG: _int(row['avg_protein_g']),
        avgCarbsG: _int(row['avg_carbs_g']),
        avgFatG: _int(row['avg_fat_g']),
        daysOnTarget: _int(row['days_on_target']),
        calorieTarget: _int(row['calorie_target']),
        avgWaterMl: _int(row['avg_water_ml']),
        weightChangeKg: _double(row['weight_change_kg']) ?? 0,
        firstWeightKg: _double(row['first_weight_kg']),
        lastWeightKg: _double(row['last_weight_kg']),
      );

  /// Postgres hands `numeric` back through PostgREST as a string often enough
  /// that parsing it is not optional.
  static int _int(Object? raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.round();
    return int.tryParse('${raw ?? ''}'.trim()) ?? 0;
  }

  static double? _double(Object? raw) {
    if (raw is double) return raw;
    if (raw is num) return raw.toDouble();
    return double.tryParse('${raw ?? ''}'.trim());
  }

  @override
  List<Object?> get props => [
        daysLogged,
        entries,
        avgCalories,
        avgProteinG,
        avgCarbsG,
        avgFatG,
        daysOnTarget,
        calorieTarget,
        avgWaterMl,
        weightChangeKg,
        firstWeightKg,
        lastWeightKg,
      ];
}
