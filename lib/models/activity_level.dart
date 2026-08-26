/// Mirrors the Postgres `activity_level` enum, and carries the TDEE multiplier
/// applied on top of BMR.
///
/// The multipliers are the standard Harris-Benedict activity factors used
/// alongside Mifflin-St Jeor.
enum ActivityLevel {
  sedentary('sedentary', 1.2, 'sedentary_title', 'sedentary_desc'),
  lightlyActive('lightly_active', 1.375, 'lightly_active_title', 'lightly_active_desc'),
  moderatelyActive('moderately_active', 1.55, 'moderately_active_title', 'moderately_active_desc'),
  veryActive('very_active', 1.725, 'very_active_title', 'very_active_desc'),
  extraActive('extra_active', 1.9, 'extra_active_title', 'extra_active_desc');

  const ActivityLevel(this.dbValue, this.multiplier, this.titleKey, this.descriptionKey);

  /// Exact label expected by the `activity_level` enum in Supabase.
  final String dbValue;

  /// TDEE = BMR * multiplier.
  final double multiplier;

  final String titleKey;
  final String descriptionKey;

  static ActivityLevel fromDbValue(String value) =>
      ActivityLevel.values.firstWhere((a) => a.dbValue == value);
}
