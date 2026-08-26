import 'package:bulkr/core/food_search_ranking.dart';
import 'package:bulkr/models/food_item.dart';
import 'package:bulkr/models/macros.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ScoredFood candidate(
    String name, {
    FoodSource source = FoodSource.openFoodFacts,
    String? barcode,
    String? brand,
    double kcal = 150,
    double protein = 10,
    double carbs = 10,
    double fat = 5,
  }) {
    return ScoredFood(
      food: FoodItem(
        barcode: barcode ?? name,
        name: name,
        brand: brand,
        per100g:
            Macros(calories: kcal, proteinG: protein, carbsG: carbs, fatG: fat),
      ),
      source: source,
      score: 0,
    );
  }

  List<String> names(List<FoodItem> foods) => foods.map((f) => f.name).toList();

  group('the results that went wrong in testing', () {
    test('"boiled eggs" leads with an egg, not a Kinder Egg', () {
      final ranked = FoodSearchRanking.rank([
        candidate('Kinder Surprise Eggs', brand: 'Kinder'),
        candidate('Chocolate Eggs, Milk', brand: 'Cadbury'),
        candidate('Egg, whole, boiled', source: FoodSource.system),
      ], 'boiled eggs');

      expect(names(ranked).first, 'Egg, whole, boiled');
    });

    test('"whey" throws out results that never mention whey', () {
      final ranked = FoodSearchRanking.rank([
        candidate('Minus L Classic Laktosefrei', brand: 'Minus L'),
        candidate('Whey protein isolate, powder', source: FoodSource.system),
      ], 'whey');

      // Not merely ranked lower — gone. Nothing in that name is the word typed.
      expect(names(ranked), ['Whey protein isolate, powder']);
    });

    test('a generic food outranks a product that merely contains it', () {
      final ranked = FoodSearchRanking.rank([
        candidate('Chicken & Bacon Sandwich Meal Deal', brand: 'Tesco'),
        candidate('Chicken breast, cooked, skinless',
            source: FoodSource.system),
      ], 'chicken');

      expect(names(ranked).first, 'Chicken breast, cooked, skinless');
    });
  });

  group('matching', () {
    test('covering every word typed beats covering one of them', () {
      final ranked = FoodSearchRanking.rank([
        candidate('Peanut Butter Cups', brand: 'Reese'),
        candidate('Peanut butter, smooth'),
      ], 'peanut butter');

      expect(names(ranked).first, 'Peanut butter, smooth');
    });

    test('an exact name match wins outright', () {
      final ranked = FoodSearchRanking.rank([
        candidate('Banana Bread Protein Loaf', source: FoodSource.system),
        candidate('Banana'),
      ], 'banana');

      expect(names(ranked).first, 'Banana');
    });

    test('singular and plural are the same word', () {
      final ranked = FoodSearchRanking.rank([
        candidate('Almonds, raw'),
      ], 'almond');

      expect(ranked, hasLength(1));
    });

    test('a typed stem matches the longer word', () {
      expect(
        FoodSearchRanking.rank([candidate('Chicken breast')], 'chick'),
        hasLength(1),
      );
    });

    test('two-letter fragments do not match everything', () {
      // "oa" is not enough to claim "oats" — the minimum keeps prefix matching
      // from turning into a wildcard.
      expect(
        FoodSearchRanking.rank([candidate('Oats, rolled, dry')], 'ox'),
        isEmpty,
      );
    });

    test('a result sharing no word with the query is dropped', () {
      expect(
        FoodSearchRanking.rank([candidate('Sparkling Water')], 'ribeye steak'),
        isEmpty,
      );
    });

    test('a shorter name beats a longer one at the same coverage', () {
      final ranked = FoodSearchRanking.rank([
        candidate('Egg & Cress Sandwich, Reduced Fat, Family Pack'),
        candidate('Egg, whole, raw'),
      ], 'egg');

      expect(names(ranked).first, 'Egg, whole, raw');
    });
  });

  group('source', () {
    test('breaks a tie towards the source we trust most', () {
      final ranked = FoodSearchRanking.rank([
        candidate('Olive oil', barcode: 'off', source: FoodSource.openFoodFacts),
        candidate('Olive oil', barcode: 'system', source: FoodSource.system),
        candidate('Olive oil', barcode: 'fatsecret',
            source: FoodSource.fatSecret),
        candidate('Olive oil', barcode: 'cached', source: FoodSource.cached),
      ], 'olive oil');

      // Identical text, identical names — only the source separates them.
      expect(
        ranked.map((f) => f.barcode).toList(),
        ['system', 'cached', 'fatsecret', 'off'],
      );
    });

    test('a full-coverage match clears the bar for stopping the cascade', () {
      // strongMatchScore is what lets a search end at the local cache and make
      // no API call at all, so it has to be reachable by a real result.
      final ranked = FoodSearchRanking.rankScored([
        candidate('Rice, white, cooked', source: FoodSource.cached),
      ], 'rice');

      expect(ranked.first.score,
          greaterThanOrEqualTo(FoodSearchRanking.strongMatchScore));
    });

    test('a partial match does not clear it', () {
      final ranked = FoodSearchRanking.rankScored([
        candidate('Rice Krispies Squares', brand: 'Kelloggs'),
      ], 'brown rice');

      expect(ranked.first.score,
          lessThan(FoodSearchRanking.strongMatchScore));
    });
  });

  group('isPlausible', () {
    FoodItem food({
      double kcal = 150,
      double protein = 10,
      double carbs = 10,
      double fat = 5,
      String name = 'Rice',
    }) {
      return FoodItem(
        barcode: '1',
        name: name,
        per100g: Macros(
          calories: kcal,
          proteinG: protein,
          carbsG: carbs,
          fatG: fat,
        ),
      );
    }

    test('accepts an ordinary food', () {
      expect(FoodSearchRanking.isPlausible(food()), isTrue);
    });

    test('rejects more energy than pure fat contains', () {
      // A misplaced decimal in crowd-sourced data. Adding this to a meal wrecks
      // the day's total and looks like the user's mistake.
      expect(FoodSearchRanking.isPlausible(food(kcal: 3500)), isFalse);
    });

    test('rejects macros that weigh more than the food', () {
      expect(
        FoodSearchRanking.isPlausible(food(protein: 60, carbs: 60, fat: 40)),
        isFalse,
      );
    });

    test('rejects negative and zero energy', () {
      expect(FoodSearchRanking.isPlausible(food(kcal: 0)), isFalse);
      expect(FoodSearchRanking.isPlausible(food(kcal: -5)), isFalse);
    });

    test('rejects a nameless entry', () {
      expect(FoodSearchRanking.isPlausible(food(name: '  ')), isFalse);
    });

    test('implausible entries never reach the ranking', () {
      final ranked = FoodSearchRanking.rank([
        candidate('Rice, white, cooked', kcal: 3500),
        candidate('Rice, white, cooked, correct', kcal: 130),
      ], 'rice');

      expect(names(ranked), ['Rice, white, cooked, correct']);
    });
  });

  group('tokenize', () {
    test('lowercases and drops punctuation', () {
      expect(
        FoodSearchRanking.tokenize('Egg, whole — BOILED!'),
        ['egg', 'whole', 'boiled'],
      );
    });

    test('drops stop words and single characters', () {
      expect(
        FoodSearchRanking.tokenize('Chicken and rice with a sauce'),
        ['chicken', 'rice', 'sauce'],
      );
    });

    test('an empty query ranks nothing rather than everything', () {
      expect(FoodSearchRanking.rank([candidate('Banana')], '   '), isEmpty);
    });
  });

  test('the list is capped', () {
    final many = List.generate(40, (i) => candidate('Chicken variant $i'));

    expect(FoodSearchRanking.rank(many, 'chicken', limit: 15), hasLength(15));
  });
}
