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
      ];
}
