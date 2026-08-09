/// Mirrors the Postgres `unit_preference` enum.
///
/// This is a *display* preference only. Height and weight are always stored in
/// centimetres and kilograms; imperial values are converted at the edge.
enum UnitSystem {
  metric('metric'),
  imperial('imperial');

  const UnitSystem(this.dbValue);

  final String dbValue;

  bool get isMetric => this == UnitSystem.metric;

  static UnitSystem fromDbValue(String value) =>
      UnitSystem.values.firstWhere((u) => u.dbValue == value);
}
