import 'package:bulkr/models/daily_log_entry.dart';
import 'package:bulkr/models/meal_slot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('fromRow', () {
    test('reads a food entry, including numerics sent as strings', () {
      // Postgres `numeric` arrives over the wire as a string, which is why
      // every figure goes through parseGrams rather than `as num`. This is the
      // first code in the app to read these columns back at all.
      final entry = DailyLogEntry.fromRow({
        'id': 'e1',
        'log_date': '2026-09-05',
        'meal_type': 'lunch',
        'meal_id': null,
        'cached_food_id': 'f1',
        'item_name': 'Banana',
        'quantity_g': '118',
        'calories_logged': 105,
        'protein_logged_g': '1',
        'carbs_logged_g': 27,
        'fat_logged_g': 0,
      });

      expect(entry.id, 'e1');
      expect(entry.logDate, DateTime(2026, 9, 5));
      expect(entry.slot, MealSlot.lunch);
      expect(entry.quantityG, 118);
      expect(entry.macros.calories, 105);
      expect(entry.macros.carbsG, 27);
      expect(entry.displayName, 'Banana');
      expect(entry.isMeal, isFalse);
    });

    test('prefers the live meal title over the copied name', () {
      // So renaming a meal reads correctly in the log, while the copy is still
      // there for when the meal is gone.
      final entry = DailyLogEntry.fromRow({
        'id': 'e2',
        'log_date': '2026-09-05',
        'meal_id': 'm1',
        'item_name': 'Old name',
        'meals': {'title': 'New name', 'image_url': null},
        'calories_logged': 640,
      });

      expect(entry.displayName, 'New name');
      expect(entry.isMeal, isTrue);
      expect(entry.mealWasDeleted, isFalse);
    });

    test('a deleted meal keeps the name it was logged under', () {
      // meal_id is ON DELETE SET NULL, so this is the state a row lands in
      // when its meal is deleted — the point of copying item_name at all.
      final entry = DailyLogEntry.fromRow({
        'id': 'e3',
        'log_date': '2026-09-05',
        'meal_id': null,
        'cached_food_id': null,
        'item_name': 'Chicken and rice',
        'calories_logged': 640,
      });

      expect(entry.displayName, 'Chicken and rice');
      expect(entry.isMeal, isTrue);
      expect(entry.mealWasDeleted, isTrue);
    });

    test('an embed arriving as a single-element list is still read', () {
      final entry = DailyLogEntry.fromRow({
        'id': 'e4',
        'log_date': '2026-09-05',
        'meal_id': 'm1',
        'meals': [
          {'title': 'Oats', 'image_url': 'https://example.test/o.jpg'},
        ],
        'calories_logged': 520,
      });

      expect(entry.displayName, 'Oats');
      expect(entry.mealImageUrl, 'https://example.test/o.jpg');
    });

    test('a row from before slots existed still counts', () {
      final entry = DailyLogEntry.fromRow({
        'id': 'e5',
        'log_date': '2026-09-05',
        'meal_id': 'm1',
        'calories_logged': 300,
      });

      expect(entry.slot, isNull);
      expect(entry.macros.calories, 300);
      expect(entry.displayName, isNull);
      expect(entry.hasQuantity, isFalse);
    });
  });

  group('scaledTo', () {
    test('scales the macros with the amount', () {
      final entry = DailyLogEntry.fromRow({
        'id': 'e6',
        'log_date': '2026-09-05',
        'quantity_g': 100,
        'calories_logged': 200,
        'protein_logged_g': 10,
        'carbs_logged_g': 20,
        'fat_logged_g': 5,
      });

      final resized = entry.scaledTo(250);

      expect(resized.quantityG, 250);
      expect(resized.macros.calories, 500);
      expect(resized.macros.proteinG, 25);
      expect(resized.macros.fatG, 12.5);
      // Identity is not part of the edit.
      expect(resized.id, entry.id);
    });

    test('refuses when there is no weight to scale from', () {
      // A meal assembled without ingredient weights logs quantity_g as 0.
      // Scaling from zero would either divide by zero or invent a basis, and
      // both rewrite calories the user did not change.
      final entry = DailyLogEntry.fromRow({
        'id': 'e7',
        'log_date': '2026-09-05',
        'quantity_g': 0,
        'calories_logged': 640,
      });

      expect(entry.canRescale, isFalse);
      expect(entry.scaledTo(250), entry);
    });

    test('refuses a non-positive amount', () {
      final entry = DailyLogEntry.fromRow({
        'id': 'e8',
        'log_date': '2026-09-05',
        'quantity_g': 100,
        'calories_logged': 200,
      });

      expect(entry.scaledTo(0), entry);
      expect(entry.scaledTo(-50), entry);
    });
  });
}
