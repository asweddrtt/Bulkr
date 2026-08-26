import 'package:equatable/equatable.dart';

import 'macros.dart';
import 'meal_ingredient.dart';

/// A meal being written, before it becomes a `meals` row.
///
/// Pure and immutable so the create screen's rules — what the totals are, when
/// Save is allowed — are arithmetic that can be tested without a widget or a
/// network, and so the cubit's only job is to swap one draft for the next.
class MealDraft extends Equatable {
  const MealDraft({
    this.title = '',
    this.recipe = '',
    this.imagePath,
    this.ingredients = const [],
    this.manualTotals = Macros.zero,
    this.isPublic = false,
  });

  final String title;

  /// Free text, stored in `meals.description`. The method, in the user's words.
  final String recipe;

  /// Local file path of the photo the user picked, before it is uploaded.
  final String? imagePath;

  final List<MealIngredient> ingredients;

  /// Calories and macros typed in by hand. Only used when there are no
  /// ingredients — see [totals].
  final Macros manualTotals;

  /// Whether the meal is visible to other users in the feed.
  final bool isPublic;

  bool get hasIngredients => ingredients.isNotEmpty;

  /// What the meal will be saved with.
  ///
  /// Ingredients win whenever there are any: the point of pulling a food from
  /// Open Food Facts is that its numbers are better than a guess, and letting a
  /// stale hand-typed figure override a live sum is how a meal ends up claiming
  /// 600 kcal over eight ingredients that add to 1,900.
  ///
  /// With no ingredients — a meal someone knows the totals for but does not
  /// want to itemise — the typed figures are all there is.
  Macros get totals => hasIngredients
      ? Macros.sum(ingredients.map((i) => i.macros))
      : manualTotals;

  /// Summed ingredient weight, or null when the meal was not itemised.
  double? get totalGrams => hasIngredients
      ? ingredients.fold<double>(0, (sum, i) => sum + i.amountG)
      : null;

  /// A meal needs a name and a calorie figure: `meals.title` and
  /// `meals.total_calories` are both NOT NULL, and a zero-calorie meal in a
  /// bulking app is a data-entry mistake every time.
  bool get canSave => title.trim().isNotEmpty && totals.caloriesRounded > 0;

  /// True when the same food is already in the draft, so the UI can offer to
  /// change the amount instead of adding a second line for it.
  bool contains(String barcode) =>
      ingredients.any((i) => i.food.barcode == barcode);

  MealDraft copyWith({
    String? title,
    String? recipe,
    String? imagePath,
    bool clearImage = false,
    List<MealIngredient>? ingredients,
    Macros? manualTotals,
    bool? isPublic,
  }) {
    return MealDraft(
      title: title ?? this.title,
      recipe: recipe ?? this.recipe,
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
      ingredients: ingredients ?? this.ingredients,
      manualTotals: manualTotals ?? this.manualTotals,
      isPublic: isPublic ?? this.isPublic,
    );
  }

  /// Adds [ingredient], replacing any existing line for the same food.
  ///
  /// Replacing rather than appending because two lines for the same barcode is
  /// almost always a double-tap, and a user who genuinely wants 200g of rice in
  /// two places can say 400g once.
  MealDraft withIngredient(MealIngredient ingredient) {
    final List<MealIngredient> next = List<MealIngredient>.of(ingredients);
    final int existing =
        next.indexWhere((i) => i.food.barcode == ingredient.food.barcode);

    if (existing >= 0) {
      next[existing] = ingredient;
    } else {
      next.add(ingredient);
    }

    return copyWith(ingredients: next);
  }

  MealDraft withoutIngredientAt(int index) {
    if (index < 0 || index >= ingredients.length) return this;
    final List<MealIngredient> next = List<MealIngredient>.of(ingredients)
      ..removeAt(index);
    return copyWith(ingredients: next);
  }

  MealDraft withAmountAt(int index, double amountG) {
    if (index < 0 || index >= ingredients.length) return this;
    final List<MealIngredient> next = List<MealIngredient>.of(ingredients);
    next[index] = next[index].copyWith(amountG: amountG);
    return copyWith(ingredients: next);
  }

  @override
  List<Object?> get props =>
      [title, recipe, imagePath, ingredients, manualTotals, isPublic];
}
