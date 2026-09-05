import 'package:equatable/equatable.dart';

import 'macros.dart';
import 'meal.dart';
import 'meal_ingredient.dart';
import 'visibility.dart';

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
    this.existingImageUrl,
    this.ingredients = const [],
    this.manualTotals = Macros.zero,
    this.visibility = ContentVisibility.private,
  });

  /// Opens an existing meal for editing.
  ///
  /// Its totals go into [manualTotals] whether or not it was itemised. If it
  /// was, [totals] ignores them and recomputes from the ingredients — but the
  /// figures are still the right thing to show should every ingredient be
  /// removed, which would otherwise silently reset a saved meal to zero.
  factory MealDraft.fromMeal(Meal meal, List<MealIngredient> ingredients) {
    return MealDraft(
      title: meal.title,
      recipe: meal.description ?? '',
      existingImageUrl: meal.imageUrl,
      ingredients: ingredients,
      manualTotals: meal.totals,
      visibility: meal.visibility,
    );
  }

  final String title;

  /// Free text, stored in `meals.description`. The method, in the user's words.
  final String recipe;

  /// Local file path of the photo the user picked, before it is uploaded.
  final String? imagePath;

  /// The photo an edited meal already has, in storage.
  ///
  /// Kept apart from [imagePath] because they answer different questions: this
  /// is what the meal looks like now, that is what the user just chose. A save
  /// only replaces the stored image when the user actually picked a new one.
  final String? existingImageUrl;

  /// Whether the meal has a photo at all, wherever it came from.
  bool get hasImage => imagePath != null || existingImageUrl != null;

  final List<MealIngredient> ingredients;

  /// Calories and macros typed in by hand. Only used when there are no
  /// ingredients — see [totals].
  final Macros manualTotals;

  /// Whether the meal is visible to other users in the feed.
  /// Who will be able to see it once saved. Private by default: a meal is
  /// something someone builds for themselves, and sharing is the deliberate
  /// act.
  final ContentVisibility visibility;

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
    String? existingImageUrl,
    bool clearImage = false,
    List<MealIngredient>? ingredients,
    Macros? manualTotals,
    ContentVisibility? visibility,
  }) {
    return MealDraft(
      title: title ?? this.title,
      recipe: recipe ?? this.recipe,
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
      // Removing the photo clears both: the picked one and the one already
      // stored, or "remove" would only undo the most recent choice.
      existingImageUrl:
          clearImage ? null : (existingImageUrl ?? this.existingImageUrl),
      ingredients: ingredients ?? this.ingredients,
      manualTotals: manualTotals ?? this.manualTotals,
      visibility: visibility ?? this.visibility,
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
  List<Object?> get props => [
        title,
        recipe,
        imagePath,
        existingImageUrl,
        ingredients,
        manualTotals,
        visibility,
      ];
}
