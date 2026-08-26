/// Conversions between the canonical metric storage values and the imperial
/// values shown when the user flips the toggle on screen 2.
///
/// Nothing imperial is ever persisted: `height_cm` and `current_weight_kg` are
/// always metric, and `units` records only how to display them.
class UnitConverter {
  const UnitConverter._();

  static const double cmPerInch = 2.54;
  static const double cmPerFoot = 30.48;
  static const double kgPerPound = 0.45359237;

  static double kgToLb(double kg) => kg / kgPerPound;

  static double lbToKg(double lb) => lb * kgPerPound;

  /// Splits centimetres into whole feet and the remaining whole inches.
  ///
  /// Rounds to the nearest inch first, then carries 12in up into a foot so
  /// callers never receive something like 5ft 12in.
  static ({int feet, int inches}) cmToFeetInches(double cm) {
    final totalInches = (cm / cmPerInch).round();
    final feet = totalInches ~/ 12;
    final inches = totalInches % 12;
    return (feet: feet, inches: inches);
  }

  static double feetInchesToCm(int feet, int inches) =>
      feet * cmPerFoot + inches * cmPerInch;
}
