import 'package:bulkr/models/visibility.dart';
import 'package:bulkr/models/food_item.dart';
import 'package:bulkr/models/macros.dart';
import 'package:bulkr/models/meal.dart';
import 'package:bulkr/models/meal_draft.dart';
import 'package:bulkr/models/meal_ingredient.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FoodItem food(
    String name, {
    required String barcode,
    double kcal = 100,
    double protein = 10,
    double carbs = 5,
    double fat = 2,
  }) {
    return FoodItem(
      barcode: barcode,
      name: name,
      per100g:
          Macros(calories: kcal, proteinG: protein, carbsG: carbs, fatG: fat),
    );
  }

  MealIngredient ingredient(String name, String barcode, double grams) =>
      MealIngredient(food: food(name, barcode: barcode), amountG: grams);

  group('totals', () {
    test('are summed from the ingredients when there are any', () {
      const draft = MealDraft(title: 'Prep');

      final withFood = draft.withIngredient(
        MealIngredient(
          food: food('Chicken', barcode: '1', kcal: 165, protein: 31, carbs: 0, fat: 3.6),
          amountG: 200,
        ),
      );

      expect(withFood.totals.caloriesRounded, 330);
      expect(withFood.totals.proteinRounded, 62);
    });

    test('fall back to the typed figures when nothing is itemised', () {
      const draft = MealDraft(
        title: 'Shake',
        manualTotals: Macros(calories: 950, proteinG: 60),
      );

      expect(draft.hasIngredients, isFalse);
      expect(draft.totals.caloriesRounded, 950);
      expect(draft.totals.proteinRounded, 60);
    });

    test('ingredients override a stale typed figure rather than the reverse',
        () {
      const draft = MealDraft(
        title: 'Prep',
        manualTotals: Macros(calories: 600),
      );

      final itemised = draft.withIngredient(ingredient('Rice', '1', 1000));

      // 1000g at 100 kcal/100g is 1,000 — the typed 600 is history.
      expect(itemised.totals.caloriesRounded, 1000);
    });

    test('typed figures survive an ingredient being pulled back out', () {
      const draft = MealDraft(
        title: 'Prep',
        manualTotals: Macros(calories: 600),
      );

      final restored =
          draft.withIngredient(ingredient('Rice', '1', 200)).withoutIngredientAt(0);

      expect(restored.totals.caloriesRounded, 600);
    });
  });

  group('ingredients', () {
    test('adding the same food twice corrects the amount, not the count', () {
      final draft = const MealDraft()
          .withIngredient(ingredient('Rice', 'abc', 100))
          .withIngredient(ingredient('Rice', 'abc', 250));

      expect(draft.ingredients, hasLength(1));
      expect(draft.ingredients.single.amountG, 250);
    });

    test('different foods both stay', () {
      final draft = const MealDraft()
          .withIngredient(ingredient('Rice', 'abc', 100))
          .withIngredient(ingredient('Beef', 'def', 100));

      expect(draft.ingredients, hasLength(2));
      expect(draft.contains('abc'), isTrue);
      expect(draft.contains('def'), isTrue);
      expect(draft.contains('ghi'), isFalse);
    });

    test('an out-of-range removal is a no-op, not a crash', () {
      final draft = const MealDraft().withIngredient(ingredient('Rice', 'a', 100));

      expect(draft.withoutIngredientAt(5), draft);
      expect(draft.withoutIngredientAt(-1), draft);
      expect(draft.withAmountAt(9, 200), draft);
    });

    test('amounts can be corrected in place', () {
      final draft = const MealDraft()
          .withIngredient(ingredient('Rice', 'a', 100))
          .withAmountAt(0, 300);

      expect(draft.ingredients.single.amountG, 300);
      expect(draft.totals.caloriesRounded, 300);
    });
  });

  group('totalGrams', () {
    test('sums the ingredient weights', () {
      final draft = const MealDraft()
          .withIngredient(ingredient('Rice', 'a', 250))
          .withIngredient(ingredient('Beef', 'b', 300));

      expect(draft.totalGrams, 550);
    });

    test('is null for a meal that was never itemised', () {
      // Null, not zero: "we did not record the weight" is not "it weighed
      // nothing", and the log row reads differently for each.
      const draft = MealDraft(manualTotals: Macros(calories: 500));

      expect(draft.totalGrams, isNull);
    });
  });

  group('fromMeal', () {
    Meal saved({
      String title = 'Apex Ribeye',
      String? description = 'Sear it.',
      String? imageUrl = 'https://x.test/a.jpg',
      ContentVisibility visibility = ContentVisibility.public,
    }) {
      return Meal(
        id: 'meal-1',
        creatorId: 'user-1',
        title: title,
        description: description,
        imageUrl: imageUrl,
        totals: const Macros(calories: 1450, proteinG: 67),
        visibility: visibility,
        createdAt: DateTime(2026, 8, 20),
        isMine: true,
      );
    }

    test('carries every editable field across', () {
      final draft = MealDraft.fromMeal(saved(), const []);

      expect(draft.title, 'Apex Ribeye');
      expect(draft.recipe, 'Sear it.');
      expect(draft.existingImageUrl, 'https://x.test/a.jpg');
      expect(draft.visibility, ContentVisibility.public);
      expect(draft.canSave, isTrue);
    });

    test('a meal with no recipe opens with an empty one, not null', () {
      expect(MealDraft.fromMeal(saved(description: null), const []).recipe, '');
    });

    test('keeps the stored totals even when ingredients drive them', () {
      // Otherwise removing every ingredient from a saved meal would silently
      // reset it to zero rather than falling back to what it already said.
      final draft = MealDraft.fromMeal(
        saved(),
        [ingredient('Rice', 'a', 200)],
      );

      expect(draft.totals.caloriesRounded, 200);
      expect(draft.withoutIngredientAt(0).totals.caloriesRounded, 1450);
    });

    test('the existing photo survives edits to other fields', () {
      final draft = MealDraft.fromMeal(saved(), const [])
          .copyWith(title: 'Renamed');

      expect(draft.existingImageUrl, 'https://x.test/a.jpg');
      expect(draft.hasImage, isTrue);
    });

    test('removing the photo clears the stored one too', () {
      // Otherwise "remove" would only undo a fresh pick and leave the meal
      // still showing the image it had.
      final draft = MealDraft.fromMeal(saved(), const [])
          .copyWith(clearImage: true);

      expect(draft.existingImageUrl, isNull);
      expect(draft.hasImage, isFalse);
    });

    test('a meal with no photo has none', () {
      expect(MealDraft.fromMeal(saved(imageUrl: null), const []).hasImage,
          isFalse);
    });
  });

  group('canSave', () {
    test('needs a name', () {
      const unnamed = MealDraft(manualTotals: Macros(calories: 500));
      expect(unnamed.canSave, isFalse);

      const whitespace =
          MealDraft(title: '   ', manualTotals: Macros(calories: 500));
      expect(whitespace.canSave, isFalse);
    });

    test('needs calories', () {
      const noCalories = MealDraft(title: 'Mystery plate');
      expect(noCalories.canSave, isFalse);
    });

    test('is satisfied by a name plus a calorie figure', () {
      const ready = MealDraft(
        title: 'Shake',
        manualTotals: Macros(calories: 950),
      );

      expect(ready.canSave, isTrue);
    });

    test('is satisfied by a name plus ingredients', () {
      final ready = const MealDraft(title: 'Prep')
          .withIngredient(ingredient('Rice', 'a', 200));

      expect(ready.canSave, isTrue);
    });
  });
}
