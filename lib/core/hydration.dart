/// How much water a day should hold, and what a drink is measured in.
///
/// Lifted out of [InsightEngine], which has been quoting these figures as
/// advice since before anything could record a drink. Now that the tracker
/// measures against them, the advice and the goal have to be the same number —
/// two copies of 35 that drift apart would have the insight card telling
/// someone to drink 3.1 L while the ring beside it fills at 3.0.
class Hydration {
  const Hydration._();

  /// Millilitres per kg of bodyweight — a general daily guideline, and the
  /// reason the goal moves on its own as someone bulks.
  static const double mlPerKg = 35;

  /// Glass sizes people actually picture: 250 ml, or 8 fl oz.
  static const double glassMl = 250;
  static const double glassFlOz = 8;

  static const double mlPerFluidOunce = 29.5735;

  /// What a hard cap on the stored override is. Mirrors the CHECK constraint
  /// in `tracker_water.sql`, so the field refuses what the database would.
  static const int maxTargetMl = 20000;

  /// The derived daily goal for someone at [weightKg].
  ///
  /// Returns null rather than zero when the weight is unknown or nonsense: a
  /// goal of zero would render as a full ring on the first sip, and "we don't
  /// know yet" is a state the UI can show honestly.
  static int? targetMlFor(double? weightKg) {
    if (weightKg == null || weightKg <= 0) return null;
    return (weightKg * mlPerKg).round();
  }

  /// Glasses that much water comes to, for the advice copy.
  static int glassesFor(double millilitres) => (millilitres / glassMl).round();
}
