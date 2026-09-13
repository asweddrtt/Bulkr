import 'package:flutter/foundation.dart';
import 'package:equatable/equatable.dart';

import '../core/calorie_engine.dart';
import 'activity_level.dart';
import 'gender.dart';
import 'unit_system.dart';

/// A row from `public.users`, read back after onboarding.
///
/// Onboarding writes this table; everything after onboarding reads it. Parsing
/// is deliberately forgiving — a profile that renders with a missing optional
/// field beats a screen that throws.
class UserProfile extends Equatable {
  const UserProfile({
    required this.id,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.gender,
    this.dateOfBirth,
    required this.heightCm,
    required this.currentWeightKg,
    required this.targetWeightKg,
    required this.activityLevel,
    required this.units,
    required this.dailyCalorieTarget,
    required this.proteinTargetG,
    required this.carbsTargetG,
    required this.fatTargetG,
    required this.onboardingCompleted,
    this.targetsAreCustom = false,
    this.restDayCalorieTarget,
    this.restDayProteinG,
    this.restDayCarbsG,
    this.restDayFatG,
    this.trainingDays = const <int>[],
    this.waterTargetMl,
  });

  final String id;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final Gender? gender;
  final DateTime? dateOfBirth;
  final double heightCm;
  final double currentWeightKg;
  final double targetWeightKg;
  final ActivityLevel activityLevel;
  final UnitSystem units;
  final int dailyCalorieTarget;
  final int proteinTargetG;
  final int carbsTargetG;
  final int fatTargetG;
  final bool onboardingCompleted;

  /// Whether the four target numbers were set by hand rather than computed.
  ///
  /// It exists to stop a recalculation quietly throwing away numbers somebody
  /// chose — see `supabase/custom_targets.sql`. Defaults false, which is both
  /// the normal state and the safe reading of a row written before the column
  /// existed.
  final bool targetsAreCustom;

  /// What to eat on a day without training. Null when the feature is off,
  /// which is the normal state.
  ///
  /// The four columns above stay the **training day** targets rather than
  /// becoming an average of the two — so an account that never turns this on
  /// is untouched, and one that turns it off falls back to exactly what it
  /// had.
  final int? restDayCalorieTarget;
  final int? restDayProteinG;
  final int? restDayCarbsG;
  final int? restDayFatG;

  /// Which weekdays are training days, as ISO numbers: Monday 1 through
  /// Sunday 7, which is what `DateTime.weekday` returns, so nothing converts.
  ///
  /// Empty means the feature is off and every day uses the original targets.
  final List<int> trainingDays;

  /// Whether this account has two sets of numbers rather than one.
  ///
  /// Needs both halves: days marked as training, and a rest-day calorie target
  /// to use on the others. Either alone is a half-configured state that would
  /// silently apply zero as a goal.
  bool get hasDayTypes =>
      trainingDays.isNotEmpty && (restDayCalorieTarget ?? 0) > 0;

  /// Whether [day] is one the user lifts on.
  ///
  /// True when the feature is off, because then every day uses the training
  /// numbers — which are simply "the targets".
  bool isTrainingDay(DateTime day) =>
      !hasDayTypes || trainingDays.contains(day.weekday);

  /// The four targets that apply on [day].
  ///
  /// Every screen asks this rather than reading the columns, so adding day
  /// types did not require each of them to learn what a day type is.
  DayTargets targetsFor(DateTime day) {
    if (isTrainingDay(day)) {
      return DayTargets(
        calories: dailyCalorieTarget,
        proteinG: proteinTargetG,
        carbsG: carbsTargetG,
        fatG: fatTargetG,
        isTraining: true,
      );
    }

    // Each macro falls back to its training-day value rather than to zero: a
    // rest day configured with calories but no protein is a half-filled form,
    // and a protein goal of zero would read as "met" the moment anything was
    // logged.
    return DayTargets(
      calories: restDayCalorieTarget ?? dailyCalorieTarget,
      proteinG: restDayProteinG ?? proteinTargetG,
      carbsG: restDayCarbsG ?? carbsTargetG,
      fatG: restDayFatG ?? fatTargetG,
      isTraining: false,
    );
  }

  /// A water goal the user set by hand, or null to derive one from bodyweight.
  ///
  /// Null is the normal state, not a missing value: with nothing stored the
  /// goal follows the weight and keeps moving as they bulk. Which is why this
  /// is `int?` rather than defaulting to 0 the way the calorie targets do —
  /// there, 0 means "onboarding never wrote it"; here it would be
  /// indistinguishable from someone choosing to drink nothing.
  final int? waterTargetMl;

  /// What to greet the user with. Falls back through display name, then
  /// handle, so there's always something.
  String get preferredName =>
      (displayName != null && displayName!.trim().isNotEmpty)
          ? displayName!.trim()
          : username;

  /// Kilograms still to gain. Negative if they've overshot their target.
  double get remainingKg => targetWeightKg - currentWeightKg;

  int? get age => dateOfBirth == null
      ? null
      : CalorieEngine.ageFromDateOfBirth(dateOfBirth!);

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as String,
      username: (map['username'] as String?) ?? '',
      displayName: map['display_name'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      gender: _parseGender(map['gender']),
      dateOfBirth: _parseDate(map['date_of_birth']),
      heightCm: _parseDouble(map['height_cm']) ?? 0,
      currentWeightKg: _parseDouble(map['current_weight_kg']) ?? 0,
      targetWeightKg: _parseDouble(map['target_weight_kg']) ?? 0,
      activityLevel: _parseActivityLevel(map['activity_level']),
      units: _parseUnits(map['units']),
      dailyCalorieTarget: _parseInt(map['daily_calorie_target']) ?? 0,
      proteinTargetG: _parseInt(map['protein_target_g']) ?? 0,
      carbsTargetG: _parseInt(map['carbs_target_g']) ?? 0,
      fatTargetG: _parseInt(map['fat_target_g']) ?? 0,
      onboardingCompleted: map['onboarding_completed'] == true,
      targetsAreCustom: map['targets_are_custom'] == true,
      restDayCalorieTarget: _parseInt(map['rest_day_calorie_target']),
      restDayProteinG: _parseInt(map['rest_day_protein_g']),
      restDayCarbsG: _parseInt(map['rest_day_carbs_g']),
      restDayFatG: _parseInt(map['rest_day_fat_g']),
      trainingDays: _parseDays(map['training_days']),
      waterTargetMl: _parseInt(map['water_target_ml']),
    );
  }

  /// Postgres `numeric` can come back as either a JSON number or a string
  /// depending on how the column is serialised, so both are handled.
  static double? _parseDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// `training_days` as Postgres hands it over.
  ///
  /// PostgREST returns an `int[]` as a JSON list, but a row written before the
  /// column existed answers null, and a hand-edited one could hold anything —
  /// so values outside 1-7 are dropped rather than trusted. A stray 0 would
  /// silently mean "never a training day".
  static List<int> _parseDays(Object? value) {
    if (value is! List) return const <int>[];

    final List<int> days = <int>[
      for (final Object? entry in value)
        if (_parseInt(entry) case final int day when day >= 1 && day <= 7) day,
    ];

    days.sort();
    return days;
  }

  static int? _parseInt(Object? value) {
    if (value == null) return null;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? double.tryParse(value)?.round();
    return null;
  }

  static DateTime? _parseDate(Object? value) {
    if (value is String) return DateTime.tryParse(value);
    if (value is DateTime) return value;
    return null;
  }

  /// Unknown enum labels fall back rather than throwing: a profile that
  /// renders with a default beats a screen that crashes because someone
  /// added a value in the database.
  static Gender? _parseGender(Object? value) {
    if (value is! String) return null;
    for (final gender in Gender.values) {
      if (gender.dbValue == value) return gender;
    }
    return null;
  }

  static ActivityLevel _parseActivityLevel(Object? value) {
    if (value is String) {
      for (final level in ActivityLevel.values) {
        if (level.dbValue == value) return level;
      }
    }
    return ActivityLevel.moderatelyActive;
  }

  static UnitSystem _parseUnits(Object? value) {
    if (value is String) {
      for (final system in UnitSystem.values) {
        if (system.dbValue == value) return system;
      }
    }
    return UnitSystem.metric;
  }

  @override
  List<Object?> get props => [
        id,
        username,
        displayName,
        avatarUrl,
        gender,
        dateOfBirth,
        heightCm,
        currentWeightKg,
        targetWeightKg,
        activityLevel,
        units,
        dailyCalorieTarget,
        proteinTargetG,
        carbsTargetG,
        fatTargetG,
        onboardingCompleted,
        waterTargetMl,
        targetsAreCustom,
        restDayCalorieTarget,
        restDayProteinG,
        restDayCarbsG,
        restDayFatG,
        trainingDays,
      ];
}

/// The targets that apply on one particular day.
///
/// A value rather than four loose ints, because "which day's targets are
/// these" is exactly the question that gets lost when they are passed around
/// separately.
@immutable
class DayTargets {
  const DayTargets({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.isTraining,
  });

  final int calories;
  final int proteinG;
  final int carbsG;
  final int fatG;

  /// Whether this is a training day. Always true for an account with one set
  /// of numbers, where the distinction does not exist.
  final bool isTraining;
}
