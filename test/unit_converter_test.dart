import 'package:bulkr/core/unit_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('weight', () {
    test('converts kg to lb', () {
      expect(UnitConverter.kgToLb(100), closeTo(220.462, 0.001));
      expect(UnitConverter.kgToLb(0), 0);
    });

    test('converts lb to kg', () {
      expect(UnitConverter.lbToKg(220.462262), closeTo(100, 0.001));
    });

    test('round-trips without drift', () {
      for (final kg in [35.0, 62.5, 80.0, 137.5, 250.0]) {
        expect(UnitConverter.lbToKg(UnitConverter.kgToLb(kg)), closeTo(kg, 1e-9));
      }
    });
  });

  group('height', () {
    test('converts cm to feet and inches', () {
      final result = UnitConverter.cmToFeetInches(180);
      expect(result.feet, 5);
      expect(result.inches, 11);
    });

    test('handles an exact foot boundary', () {
      final result = UnitConverter.cmToFeetInches(182.88); // exactly 6ft
      expect(result.feet, 6);
      expect(result.inches, 0);
    });

    test('carries 12 inches up into a foot rather than reporting 5ft 12in', () {
      // 182.5cm is 71.85in, which rounds to 72 — the case that would produce
      // a nonsense "5' 12"" reading if the carry were missing.
      final result = UnitConverter.cmToFeetInches(182.5);
      expect(result.feet, 6);
      expect(result.inches, 0);
    });

    test('never reports 12 or more inches anywhere in the picker range', () {
      for (var cm = 120.0; cm <= 230.0; cm += 0.5) {
        final result = UnitConverter.cmToFeetInches(cm);
        expect(result.inches, inInclusiveRange(0, 11), reason: '$cm cm');
      }
    });

    test('converts feet and inches back to cm', () {
      expect(UnitConverter.feetInchesToCm(6, 0), closeTo(182.88, 0.001));
      expect(UnitConverter.feetInchesToCm(5, 11), closeTo(180.34, 0.001));
    });

    test('round-trips to within half an inch', () {
      // cmToFeetInches rounds to the nearest whole inch, so the round trip is
      // lossy by design — but never by more than half an inch.
      for (var cm = 120.0; cm <= 230.0; cm += 1) {
        final imperial = UnitConverter.cmToFeetInches(cm);
        final back = UnitConverter.feetInchesToCm(
          imperial.feet,
          imperial.inches,
        );
        expect(back, closeTo(cm, UnitConverter.cmPerInch / 2), reason: '$cm cm');
      }
    });
  });
}
