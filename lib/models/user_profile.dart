import 'auth_user.dart';

/// Used by the BMR formula. Onboarding does not ask for it yet, so
/// [Sex.unspecified] applies the midpoint of the male/female constants.
enum Sex { unspecified, male, female }

/// Baseline daily burn multiplier, matching the onboarding activity cards.
enum ActivityLevel {
  sedentary(1.2),
  lightlyActive(1.375),
  moderatelyActive(1.55),
  veryActive(1.725);

  const ActivityLevel(this.burnMultiplier);

  final double burnMultiplier;
}

/// Caloric surplus options from the "define your surplus" step.
enum BulkPlan {
  lean(300, 0.25),
  standard(500, 0.5),
  aggressive(700, 0.75);

  const BulkPlan(this.dailySurplusKcal, this.weeklyGainKg);

  final int dailySurplusKcal;
  final double weeklyGainKg;
}

/// Training load currently programmed for a muscle group.
enum FocusIntensity { heavy, volume, resting }

class FocusArea {
  /// Translation key for the muscle group, e.g. `muscle_quadriceps`.
  final String nameKey;
  final FocusIntensity intensity;

  const FocusArea({required this.nameKey, required this.intensity});

  Map<String, dynamic> toJson() => {
    'nameKey': nameKey,
    'intensity': intensity.name,
  };

  factory FocusArea.fromJson(Map<String, dynamic> json) {
    return FocusArea(
      nameKey: json['nameKey'] as String,
      intensity: _enumByName(
        FocusIntensity.values,
        json['intensity'],
        FocusIntensity.resting,
      ),
    );
  }
}

/// A single logged body weight.
class WeighIn {
  final DateTime date;
  final double kg;

  const WeighIn({required this.date, required this.kg});

  /// Calendar day, used to keep one entry per day.
  DateTime get day => DateTime(date.year, date.month, date.day);

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'kg': kg,
  };

  factory WeighIn.fromJson(Map<String, dynamic> json) {
    return WeighIn(
      date: DateTime.parse(json['date'] as String),
      kg: (json['kg'] as num).toDouble(),
    );
  }
}

/// Everything Bulkr knows about the signed-in athlete.
class UserProfile {
  final String userId;
  final String displayName;
  final AuthProvider provider;
  final Sex sex;
  final int ageYears;
  final int heightCm;
  final double targetWeightKg;
  final ActivityLevel activityLevel;
  final BulkPlan bulkPlan;

  /// Chronological, oldest first, at most one entry per calendar day.
  final List<WeighIn> weighIns;
  final List<FocusArea> focusAreas;
  final bool onboardingComplete;

  const UserProfile({
    required this.userId,
    required this.displayName,
    required this.provider,
    this.sex = Sex.unspecified,
    this.ageYears = 28,
    this.heightCm = 175,
    this.targetWeightKg = 95.0,
    this.activityLevel = ActivityLevel.moderatelyActive,
    this.bulkPlan = BulkPlan.standard,
    this.weighIns = const [],
    this.focusAreas = defaultFocusAreas,
    this.onboardingComplete = false,
  });

  // TODO: derive these from the training programme once workouts exist.
  static const List<FocusArea> defaultFocusAreas = [
    FocusArea(nameKey: 'muscle_quadriceps', intensity: FocusIntensity.heavy),
    FocusArea(nameKey: 'muscle_back', intensity: FocusIntensity.volume),
    FocusArea(nameKey: 'muscle_delts', intensity: FocusIntensity.resting),
  ];

  /// The most recent weigh-in, or null before the athlete logs one.
  double? get currentWeightKg => weighIns.isEmpty ? null : weighIns.last.kg;

  /// Weight still to gain (negative when cutting back down to target).
  double? get remainingKg {
    final double? current = currentWeightKg;
    return current == null ? null : targetWeightKg - current;
  }

  /// Weigh-ins from the last [days] days, oldest first.
  List<WeighIn> recentWeighIns(int days) {
    final DateTime cutoff = DateTime.now().subtract(Duration(days: days));
    return weighIns.where((w) => w.date.isAfter(cutoff)).toList();
  }

  /// Weight change across the last [days] days, or null without two points.
  double? weightDelta(int days) {
    final List<WeighIn> recent = recentWeighIns(days);
    if (recent.length < 2) return null;
    return recent.last.kg - recent.first.kg;
  }

  UserProfile copyWith({
    String? displayName,
    Sex? sex,
    int? ageYears,
    int? heightCm,
    double? targetWeightKg,
    ActivityLevel? activityLevel,
    BulkPlan? bulkPlan,
    List<WeighIn>? weighIns,
    List<FocusArea>? focusAreas,
    bool? onboardingComplete,
  }) {
    return UserProfile(
      userId: userId,
      displayName: displayName ?? this.displayName,
      provider: provider,
      sex: sex ?? this.sex,
      ageYears: ageYears ?? this.ageYears,
      heightCm: heightCm ?? this.heightCm,
      targetWeightKg: targetWeightKg ?? this.targetWeightKg,
      activityLevel: activityLevel ?? this.activityLevel,
      bulkPlan: bulkPlan ?? this.bulkPlan,
      weighIns: weighIns ?? this.weighIns,
      focusAreas: focusAreas ?? this.focusAreas,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    );
  }

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'displayName': displayName,
    'provider': provider.name,
    'sex': sex.name,
    'ageYears': ageYears,
    'heightCm': heightCm,
    'targetWeightKg': targetWeightKg,
    'activityLevel': activityLevel.name,
    'bulkPlan': bulkPlan.name,
    'weighIns': weighIns.map((w) => w.toJson()).toList(),
    'focusAreas': focusAreas.map((f) => f.toJson()).toList(),
    'onboardingComplete': onboardingComplete,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      userId: json['userId'] as String,
      displayName: json['displayName'] as String,
      provider: _enumByName(
        AuthProvider.values,
        json['provider'],
        AuthProvider.email,
      ),
      sex: _enumByName(Sex.values, json['sex'], Sex.unspecified),
      ageYears: json['ageYears'] as int,
      heightCm: json['heightCm'] as int,
      targetWeightKg: (json['targetWeightKg'] as num).toDouble(),
      activityLevel: _enumByName(
        ActivityLevel.values,
        json['activityLevel'],
        ActivityLevel.moderatelyActive,
      ),
      bulkPlan: _enumByName(BulkPlan.values, json['bulkPlan'], BulkPlan.standard),
      weighIns: (json['weighIns'] as List<dynamic>? ?? [])
          .map((w) => WeighIn.fromJson(w as Map<String, dynamic>))
          .toList(),
      focusAreas: (json['focusAreas'] as List<dynamic>?)
              ?.map((f) => FocusArea.fromJson(f as Map<String, dynamic>))
              .toList() ??
          defaultFocusAreas,
      onboardingComplete: json['onboardingComplete'] as bool? ?? false,
    );
  }
}

/// Tolerates renamed or missing enum values in stored profiles.
T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final T value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
