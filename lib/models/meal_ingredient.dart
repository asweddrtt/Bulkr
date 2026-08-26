import 'package:equatable/equatable.dart';

import 'food_item.dart';
import 'macros.dart';

/// A `meal_ingredients` row: how much of one food goes into a meal.
///
/// The row itself only stores `cached_food_id` and `amount_g` — the nutrition
/// lives on the food. Which means an ingredient's contribution is always
/// derived, never stored, and a corrected food row fixes every meal that uses
/// it.
class MealIngredient extends Equatable {
  const MealIngredient({this.id, required this.food, required this.amountG});

  /// `meal_ingredients.id`. Null for an ingredient in an unsaved draft.
  final String? id;

  final FoodItem food;

  /// Grams of [food]. The column is `numeric`, so fractional amounts are fine.
  final double amountG;

  /// What this ingredient contributes to the meal.
  Macros get macros => food.per100g.forGrams(amountG);

  MealIngredient copyWith({FoodItem? food, double? amountG}) => MealIngredient(
        id: id,
        food: food ?? this.food,
        amountG: amountG ?? this.amountG,
      );

  /// Values for an insert into `meal_ingredients`, given the meal it belongs to.
  ///
  /// Throws when the food was never cached: `cached_food_id` is the only handle
  /// the row has on its nutrition, and a null one would store an ingredient
  /// that reads as zero calories forever.
  Map<String, dynamic> toRowValues({required String mealId}) {
    final String? cachedId = food.cachedId;
    if (cachedId == null) {
      throw StateError(
        'Ingredient "${food.name}" has no cached_off_foods row — '
        'call FoodRepository.ensureCached before saving the meal.',
      );
    }

    return {
      'meal_id': mealId,
      'cached_food_id': cachedId,
      'amount_g': amountG,
    };
  }

  /// A `meal_ingredients` row joined to its `cached_off_foods` row.
  ///
  /// Returns null when the join came back empty, which happens if the cached
  /// food was deleted from under the meal. Dropping the ingredient is better
  /// than rendering a nameless zero-calorie line.
  static MealIngredient? fromJoinedRow(Map<String, dynamic> row) {
    final Object? foodRow = row['cached_off_foods'];
    final Map<String, dynamic>? food = foodRow is Map<String, dynamic>
        ? foodRow
        : (foodRow is List && foodRow.isNotEmpty
            ? foodRow.first as Map<String, dynamic>
            : null);

    if (food == null) return null;

    return MealIngredient(
      id: row['id'] as String?,
      food: FoodItem.fromCacheRow(food),
      amountG: parseGrams(row['amount_g']),
    );
  }

  @override
  List<Object?> get props => [id, food, amountG];
}
