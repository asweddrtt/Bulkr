import 'package:bulkr/models/weekly_recap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WeeklyRecap.fromRow', () {
    test('reads the row weekly_recap() returns', () {
      final WeeklyRecap recap = WeeklyRecap.fromRow({
        'days_logged': 5,
        'entries': 23,
        'avg_calories': 2810,
        'avg_protein_g': 168,
        'avg_carbs_g': 310,
        'avg_fat_g': 92,
        'days_on_target': 3,
        'calorie_target': 2900,
        'avg_water_ml': 2400,
        'weight_change_kg': 0.6,
        'first_weight_kg': 78.2,
        'last_weight_kg': 78.8,
      });

      expect(recap.daysLogged, 5);
      expect(recap.avgCalories, 2810);
      expect(recap.hasAnything, isTrue);
      expect(recap.hasTarget, isTrue);
      expect(recap.hasWater, isTrue);
      expect(recap.hasWeightTrend, isTrue);
      expect(recap.isGaining, isTrue);
    });

    // Postgres sends `numeric` through PostgREST as a string more often than
    // people expect, and a weight change that silently reads as zero would be
    // a wrong claim rather than a missing one.
    test('parses numerics that arrive as text', () {
      final WeeklyRecap recap = WeeklyRecap.fromRow({
        'days_logged': '4',
        'weight_change_kg': '-0.7',
        'first_weight_kg': '80.0',
        'last_weight_kg': '79.3',
      });

      expect(recap.daysLogged, 4);
      expect(recap.weightChangeKg, closeTo(-0.7, 0.001));
      expect(recap.isGaining, isFalse);
      expect(recap.hasWeightTrend, isTrue);
    });

    // Each of these gates a line on the sheet. A zero has to read as an
    // absence, not as a fact — nobody drank no water, they did not record any.
    test('an empty week gates every line off', () {
      final WeeklyRecap recap = WeeklyRecap.fromRow({});

      expect(recap.hasAnything, isFalse);
      expect(recap.hasTarget, isFalse);
      expect(recap.hasWater, isFalse);
      expect(recap.hasWeightTrend, isFalse);
      expect(recap.loggedProgress, 0);
    });

    test('one weigh-in is not a trend', () {
      final WeeklyRecap recap = WeeklyRecap.fromRow({
        'days_logged': 2,
        'first_weight_kg': 80.0,
        'last_weight_kg': null,
      });

      expect(recap.hasWeightTrend, isFalse);
    });

    test('the meter is bounded even if the week is not', () {
      expect(WeeklyRecap.fromRow({'days_logged': 7}).loggedProgress, 1);
      expect(WeeklyRecap.fromRow({'days_logged': 9}).loggedProgress, 1);
      expect(
        WeeklyRecap.fromRow({'days_logged': 3}).loggedProgress,
        closeTo(3 / 7, 0.001),
      );
    });
  });
}
