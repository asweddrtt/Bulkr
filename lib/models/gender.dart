/// Mirrors the Postgres `gender_type` enum.
enum Gender {
  male('male', 'gender_male'),
  female('female', 'gender_female'),
  other('other', 'gender_other');

  const Gender(this.dbValue, this.labelKey);

  /// Exact label expected by the `gender_type` enum in Supabase.
  final String dbValue;

  /// easy_localization key for the on-screen label.
  final String labelKey;

  static Gender fromDbValue(String value) =>
      Gender.values.firstWhere((g) => g.dbValue == value);
}
