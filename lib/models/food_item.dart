import 'package:equatable/equatable.dart';

import 'macros.dart';

/// One food, with its nutrition expressed per 100g.
///
/// The same type covers all three places a food can come from, because they
/// hold the same columns under different names:
///
/// * `public.system_foods` — the curated list, keyed by barcode.
/// * `public.cached_off_foods` — foods pulled from Open Food Facts and kept so
///   a meal's ingredients survive the API being down or a product being
///   delisted.
/// * the Open Food Facts API itself, for anything neither table has yet.
///
/// [cachedId] is the `cached_off_foods.id` that `meal_ingredients.cached_food_id`
/// points at, and is null until the food has been written to the cache — which
/// is what [FoodRepository.ensureCached] is for.
class FoodItem extends Equatable {
  const FoodItem({
    this.cachedId,
    required this.barcode,
    required this.name,
    this.brand,
    this.per100g = Macros.zero,
    this.servingSizeG,
  });

  final String? cachedId;

  /// Open Food Facts product code. The identity of a food across all three
  /// sources, which is what lets results from them be merged.
  final String barcode;

  final String name;
  final String? brand;

  /// Nutrition per 100g — read with [Macros.forGrams].
  final Macros per100g;

  /// The manufacturer's stated serving, when they state one. Offered as the
  /// default amount so "one bar" doesn't have to be guessed in grams.
  final double? servingSizeG;

  /// Whether this food carries any nutrition at all. Open Food Facts has plenty
  /// of products with a name and nothing else, and adding one as an ingredient
  /// would silently contribute zero.
  bool get hasNutrition => !per100g.isEmpty;

  /// Brand and name as one line, for a search result row.
  String get label {
    final String? trimmed = brand?.trim();
    if (trimmed == null || trimmed.isEmpty) return name;
    return '$name · $trimmed';
  }

  FoodItem copyWith({String? cachedId}) => FoodItem(
        cachedId: cachedId ?? this.cachedId,
        barcode: barcode,
        name: name,
        brand: brand,
        per100g: per100g,
        servingSizeG: servingSizeG,
      );

  /// A `cached_off_foods` row.
  factory FoodItem.fromCacheRow(Map<String, dynamic> row) => FoodItem(
        cachedId: row['id'] as String?,
        barcode: '${row['barcode']}',
        name: '${row['product_name'] ?? ''}',
        brand: row['brand_name'] as String?,
        per100g: _macrosFromRow(row),
        servingSizeG: _optionalGrams(row['serving_size_g']),
      );

  /// A `system_foods` row. Same columns, no id and no serving size — the
  /// barcode is that table's primary key.
  factory FoodItem.fromSystemRow(Map<String, dynamic> row) => FoodItem(
        barcode: '${row['barcode']}',
        name: '${row['product_name'] ?? ''}',
        brand: row['brand_name'] as String?,
        per100g: _macrosFromRow(row),
      );

  /// Values for an upsert into `cached_off_foods`. The id is left out: it is
  /// generated on insert, and on conflict the existing row keeps its own.
  Map<String, dynamic> toCacheValues() => {
        'barcode': barcode,
        'product_name': name,
        'brand_name': brand,
        'calories_100g': per100g.calories,
        'protein_100g': per100g.proteinG,
        'carbs_100g': per100g.carbsG,
        'fat_100g': per100g.fatG,
        'serving_size_g': servingSizeG,
      };

  static Macros _macrosFromRow(Map<String, dynamic> row) => Macros(
        calories: parseGrams(row['calories_100g']),
        proteinG: parseGrams(row['protein_100g']),
        carbsG: parseGrams(row['carbs_100g']),
        fatG: parseGrams(row['fat_100g']),
      );

  /// Zero and "not stated" are different things for a serving size, so this
  /// stays null rather than collapsing to 0 the way the macros do.
  static double? _optionalGrams(Object? raw) {
    if (raw == null) return null;
    final double value = parseGrams(raw);
    return value > 0 ? value : null;
  }

  @override
  List<Object?> get props => [barcode, name, brand, per100g, servingSizeG];
}
