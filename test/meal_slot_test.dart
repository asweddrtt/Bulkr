import 'package:bulkr/models/meal_slot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fromDbValue', () {
    test('reads the four values the app writes', () {
      expect(MealSlot.fromDbValue('breakfast'), MealSlot.breakfast);
      expect(MealSlot.fromDbValue('lunch'), MealSlot.lunch);
      expect(MealSlot.fromDbValue('dinner'), MealSlot.dinner);
      expect(MealSlot.fromDbValue('snack'), MealSlot.snack);
    });

    test('tolerates casing and padding a hand-written row might carry', () {
      expect(MealSlot.fromDbValue('  Breakfast '), MealSlot.breakfast);
      expect(MealSlot.fromDbValue('SNACK'), MealSlot.snack);
    });

    // The whole reason this returns null instead of throwing: every row
    // written before slots existed has a null meal_type, and those rows still
    // have to be counted.
    test('returns null for an absent or unrecognised value', () {
      expect(MealSlot.fromDbValue(null), isNull);
      expect(MealSlot.fromDbValue(''), isNull);
      expect(MealSlot.fromDbValue('brunch'), isNull);
    });
  });

  group('forTimeOfDay', () {
    test('splits the day at 4, 11, 16 and 22', () {
      expect(MealSlot.forTimeOfDay(DateTime(2026, 1, 1, 4)), MealSlot.breakfast);
      expect(MealSlot.forTimeOfDay(DateTime(2026, 1, 1, 7)), MealSlot.breakfast);
      expect(
        MealSlot.forTimeOfDay(DateTime(2026, 1, 1, 10, 59)),
        MealSlot.breakfast,
      );
      expect(MealSlot.forTimeOfDay(DateTime(2026, 1, 1, 11)), MealSlot.lunch);
      expect(MealSlot.forTimeOfDay(DateTime(2026, 1, 1, 15, 59)), MealSlot.lunch);
      expect(MealSlot.forTimeOfDay(DateTime(2026, 1, 1, 16)), MealSlot.dinner);
      expect(MealSlot.forTimeOfDay(DateTime(2026, 1, 1, 21, 59)), MealSlot.dinner);
      expect(MealSlot.forTimeOfDay(DateTime(2026, 1, 1, 22)), MealSlot.snack);
      // The small hours belong to the evening that is still going, not to the
      // morning that has not started.
      expect(MealSlot.forTimeOfDay(DateTime(2026, 1, 1, 3)), MealSlot.snack);
      expect(MealSlot.forTimeOfDay(DateTime(2026, 1, 1, 0)), MealSlot.snack);
    });

    test('always answers, so the picker always has something highlighted', () {
      for (int hour = 0; hour < 24; hour++) {
        expect(MealSlot.forTimeOfDay(DateTime(2026, 1, 1, hour)), isNotNull);
      }
    });
  });

  test('declaration order is the order a day is eaten in', () {
    expect(MealSlot.values, [
      MealSlot.breakfast,
      MealSlot.lunch,
      MealSlot.dinner,
      MealSlot.snack,
    ]);
  });
}
