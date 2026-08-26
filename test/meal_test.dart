import 'package:bulkr/models/food_item.dart';
import 'package:bulkr/models/macros.dart';
import 'package:bulkr/models/meal.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Meal meal({
    String title = 'Apex Predator Ribeye',
    String? description,
    String? author,
    Macros totals = const Macros(calories: 1450),
  }) {
    return Meal(
      id: 'meal-1',
      creatorId: 'user-1',
      title: title,
      description: description,
      creatorUsername: author,
      totals: totals,
      createdAt: DateTime(2026, 8, 20),
    );
  }

  group('fromRow', () {
    test('reads the row and resolves ownership against the session', () {
      final subject = Meal.fromRow(
        {
          'id': 'meal-1',
          'creator_id': 'user-1',
          'title': 'Anabolic Rigatoni',
          'description': 'Brown the mince first.',
          'image_url': 'https://example.test/a.jpg',
          'total_calories': 1200,
          'total_protein_g': 70,
          'total_carbs_g': 130,
          'total_fat_g': 40,
          'is_public': true,
          'created_at': '2026-08-20T10:00:00Z',
          'users': {'username': 'ali'},
        },
        currentUserId: 'user-1',
      );

      expect(subject.title, 'Anabolic Rigatoni');
      expect(subject.totals.caloriesRounded, 1200);
      expect(subject.totals.proteinRounded, 70);
      expect(subject.isPublic, isTrue);
      expect(subject.isMine, isTrue);
      expect(subject.creatorUsername, 'ali');
    });

    test('someone else\'s meal is not mine', () {
      final subject = Meal.fromRow(
        {
          'id': 'meal-1',
          'creator_id': 'user-2',
          'title': 'Mutant Mass',
          'total_calories': 950,
          'created_at': '2026-08-20T10:00:00Z',
        },
        currentUserId: 'user-1',
        isSaved: true,
        isFavorite: true,
      );

      expect(subject.isMine, isFalse);
      expect(subject.isSaved, isTrue);
      expect(subject.isFavorite, isTrue);
    });

    test('a joined author that arrives as a list is still read', () {
      // Supabase returns an embedded to-one relationship as an object, but as a
      // list when the planner cannot prove it is to-one.
      final subject = Meal.fromRow(
        {
          'id': 'meal-1',
          'creator_id': 'user-2',
          'title': 'Shake',
          'total_calories': 950,
          'created_at': '2026-08-20T10:00:00Z',
          'users': [
            {'username': 'ali'}
          ],
        },
        currentUserId: 'user-1',
      );

      expect(subject.creatorUsername, 'ali');
    });

    test('numeric columns that arrive as strings still parse', () {
      final subject = Meal.fromRow(
        {
          'id': 'meal-1',
          'creator_id': 'user-1',
          'title': 'Shake',
          'total_calories': '950',
          'total_protein_g': '60',
          'created_at': '2026-08-20T10:00:00Z',
        },
        currentUserId: 'user-1',
      );

      expect(subject.totals.caloriesRounded, 950);
      expect(subject.totals.proteinRounded, 60);
    });

    test('nulls read as zero rather than throwing', () {
      final subject = Meal.fromRow(
        {
          'id': 'meal-1',
          'creator_id': 'user-1',
          'title': 'Unlogged',
          'total_calories': 400,
          'total_protein_g': null,
          'total_carbs_g': null,
          'total_fat_g': null,
          'created_at': '2026-08-20T10:00:00Z',
        },
        currentUserId: 'user-1',
      );

      expect(subject.totals.proteinRounded, 0);
      expect(subject.totals.fatRounded, 0);
    });
  });

  group('matches', () {
    test('an empty query matches everything', () {
      expect(meal().matches(''), isTrue);
      expect(meal().matches('   '), isTrue);
    });

    test('matches the title, case insensitively', () {
      expect(meal().matches('ribeye'), isTrue);
      expect(meal().matches('RIBEYE'), isTrue);
      expect(meal().matches('rigatoni'), isFalse);
    });

    test('matches the recipe text too', () {
      final subject = meal(
        title: 'Sunday Prep',
        description: 'Six chicken thighs, rice, broccoli.',
      );

      expect(subject.matches('chicken'), isTrue);
    });

    test('matches the author, for meals saved from the feed', () {
      expect(meal(author: 'bigmike').matches('bigmike'), isTrue);
    });
  });

  group('emphasis', () {
    test('protein-dominant meals are tagged protein', () {
      // 62g protein of 1,000 macro kcal is ~25%... so push it clear of 40%.
      final subject = meal(
        totals: const Macros(calories: 500, proteinG: 90, carbsG: 20, fatG: 5),
      );

      expect(subject.emphasis, MealEmphasis.protein);
    });

    test('a heavy carb load is tagged carbs', () {
      final subject = meal(
        totals: const Macros(calories: 900, proteinG: 15, carbsG: 180, fatG: 8),
      );

      expect(subject.emphasis, MealEmphasis.carbs);
    });

    test('a fat-dense meal is tagged fat', () {
      final subject = meal(
        totals: const Macros(calories: 700, proteinG: 15, carbsG: 10, fatG: 60),
      );

      expect(subject.emphasis, MealEmphasis.fat);
    });

    test('a meal with no clear winner is balanced', () {
      final subject = meal(
        totals: const Macros(calories: 800, proteinG: 40, carbsG: 90, fatG: 25),
      );

      expect(subject.emphasis, MealEmphasis.balanced);
    });

    test('a meal with no macros recorded is balanced, not a division by zero',
        () {
      final subject = meal(totals: const Macros(calories: 500));

      expect(subject.emphasis, MealEmphasis.balanced);
    });
  });

  group('acquiredAt', () {
    test('is when the meal was saved, for meals taken from the feed', () {
      final subject = meal().copyWith(savedAt: DateTime(2026, 8, 25));

      expect(subject.acquiredAt, DateTime(2026, 8, 25));
    });

    test('falls back to creation for the user\'s own meals', () {
      expect(meal().acquiredAt, DateTime(2026, 8, 20));
    });
  });

  test('FoodItem.label pairs the name with one brand', () {
    const food = FoodItem(
      barcode: '1',
      name: 'Greek Yoghurt',
      brand: 'Fage, Total',
      per100g: Macros(calories: 97, proteinG: 10),
    );

    expect(food.label, 'Greek Yoghurt · Fage, Total');
    expect(food.hasNutrition, isTrue);

    const bare = FoodItem(barcode: '2', name: 'Rice');
    expect(bare.label, 'Rice');
    expect(bare.hasNutrition, isFalse);
  });
}
