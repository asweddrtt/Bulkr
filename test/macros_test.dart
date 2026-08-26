import 'package:bulkr/models/macros.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('forGrams', () {
    test('scales per-100g values to an arbitrary amount', () {
      const per100g = Macros(calories: 165, proteinG: 31, carbsG: 0, fatG: 3.6);

      final Macros in200 = per100g.forGrams(200);

      expect(in200.calories, closeTo(330, 0.001));
      expect(in200.proteinG, closeTo(62, 0.001));
      expect(in200.fatG, closeTo(7.2, 0.001));
    });

    test('a partial serving scales down', () {
      const per100g = Macros(calories: 400, proteinG: 20);

      expect(per100g.forGrams(37.5).calories, closeTo(150, 0.001));
      expect(per100g.forGrams(37.5).proteinG, closeTo(7.5, 0.001));
    });

    test('zero grams contributes nothing', () {
      const per100g = Macros(calories: 400, proteinG: 20);

      expect(per100g.forGrams(0), Macros.zero);
    });
  });

  group('sum', () {
    test('adds every part', () {
      final total = Macros.sum(const [
        Macros(calories: 750, proteinG: 62, fatG: 55),
        Macros(calories: 215, proteinG: 5, carbsG: 50),
        Macros(calories: 35, proteinG: 3, carbsG: 7),
      ]);

      expect(total.calories, closeTo(1000, 0.001));
      expect(total.proteinG, closeTo(70, 0.001));
      expect(total.carbsG, closeTo(57, 0.001));
      expect(total.fatG, closeTo(55, 0.001));
    });

    test('an empty meal sums to zero, not to null', () {
      expect(Macros.sum(const []), Macros.zero);
      expect(Macros.sum(const []).isEmpty, isTrue);
    });

    test('sums before rounding, so eight ingredients do not drift', () {
      // Each of these rounds down to 0g on its own; together they are 4g.
      final total = Macros.sum(
        List<Macros>.filled(8, const Macros(proteinG: 0.49)),
      );

      expect(total.proteinRounded, 4);
    });
  });

  test('rounding matches the integer columns the row is written to', () {
    const totals = Macros(
      calories: 1449.6,
      proteinG: 66.5,
      carbsG: 50.4,
      fatG: 54.5,
    );

    expect(totals.caloriesRounded, 1450);
    expect(totals.proteinRounded, 67);
    expect(totals.carbsRounded, 50);
    expect(totals.fatRounded, 55);
  });

  test('macroCalories is the 4/4/9 figure, not the measured one', () {
    // Measured energy and the macro arithmetic disagree in real Open Food Facts
    // data; the bar needs the total its own segments add up to.
    const totals = Macros(calories: 1000, proteinG: 50, carbsG: 100, fatG: 20);

    expect(totals.macroCalories, closeTo(50 * 4 + 100 * 4 + 20 * 9, 0.001));
  });

  group('parseGrams', () {
    test('reads the shapes Postgres and Open Food Facts actually send', () {
      expect(parseGrams(12), 12);
      expect(parseGrams(12.5), 12.5);
      expect(parseGrams('12.5'), 12.5);
      expect(parseGrams(' 12.5 '), 12.5);
    });

    test('missing and unparseable values read as zero', () {
      expect(parseGrams(null), 0);
      expect(parseGrams(''), 0);
      expect(parseGrams('unknown'), 0);
    });
  });
}
