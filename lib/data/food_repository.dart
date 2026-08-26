import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/food_item.dart';
import '../models/macros.dart';

/// Finds foods to put in a meal, and keeps the ones that get used.
///
/// Three sources, in the order they are cheapest and most trustworthy:
///
/// 1. `public.system_foods` — the curated list. One round trip to our own
///    database, ranked by `popularity_score`, so common foods come back first
///    and instantly.
/// 2. `public.cached_off_foods` — anything anyone here has used before.
/// 3. The Open Food Facts API — the long tail, roughly three million products.
///
/// Results are merged by barcode with the earlier source winning, so a food we
/// curated is never shadowed by a scrappier crowd-sourced version of itself.
///
/// Product **images** from Open Food Facts are deliberately never read. A meal's
/// photo is the user's own, taken or picked on the device.
class FoodRepository {
  FoodRepository({SupabaseClient? client, http.Client? httpClient})
      : _client = client ?? Supabase.instance.client,
        _http = httpClient ?? http.Client();

  final SupabaseClient _client;
  final http.Client _http;

  /// Open Food Facts asks every client to identify itself, and rate-limits or
  /// blocks anonymous traffic. Not a secret — it is a courtesy and a
  /// requirement of their terms.
  static const String _userAgent =
      'Bulkr/1.0 (Flutter; +https://github.com/asweddrtt/Bulkr)';

  /// Their text search. `search_simple=1` + `json=1` is the documented
  /// lightweight form; `fields` keeps the payload to what we store, which turns
  /// a ~2MB response into a few kilobytes.
  static const String _searchUrl =
      'https://world.openfoodfacts.org/cgi/search.pl';

  static const List<String> _offFields = [
    'code',
    'product_name',
    'brands',
    'serving_quantity',
    'nutriments',
  ];

  /// A search is a keystroke away from the next one, so it is capped low and
  /// given a short deadline — a slow result the user has already typed past is
  /// worse than no result.
  static const Duration _networkTimeout = Duration(seconds: 8);
  static const int _pageSize = 20;

  /// Below this a query matches half the database and none of it usefully.
  static const int minQueryLength = 2;

  /// Foods matching [query], best-known first.
  ///
  /// Never throws: a failing Open Food Facts call still returns whatever the
  /// two local tables found, because a food search that goes blank when a third
  /// party is down is a broken app, not a degraded one.
  Future<List<FoodItem>> search(String query) async {
    final String trimmed = query.trim();
    if (trimmed.length < minQueryLength) return const [];

    final List<List<FoodItem>> batches = await Future.wait([
      _searchSystemFoods(trimmed),
      _searchCachedFoods(trimmed),
      _searchOpenFoodFacts(trimmed),
    ]);

    return _mergeByBarcode(batches);
  }

  /// Ensures [food] exists in `cached_off_foods` and returns it carrying the
  /// row id that `meal_ingredients.cached_food_id` needs.
  ///
  /// Idempotent by barcode: the same food used in twenty meals is one cache
  /// row, refreshed each time it is picked. A food already carrying a
  /// [FoodItem.cachedId] is returned untouched.
  Future<FoodItem> ensureCached(FoodItem food) async {
    if (food.cachedId != null) return food;

    final Map<String, dynamic> row = await _client
        .from('cached_off_foods')
        .upsert(
          {
            ...food.toCacheValues(),
            'last_fetched_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'barcode',
        )
        .select()
        .single();

    return food.copyWith(cachedId: row['id'] as String?);
  }

  /// Caches every food in [foods] concurrently, preserving order.
  Future<List<FoodItem>> ensureAllCached(Iterable<FoodItem> foods) {
    return Future.wait(foods.map(ensureCached));
  }

  Future<List<FoodItem>> _searchSystemFoods(String query) async {
    try {
      final rows = await _client
          .from('system_foods')
          .select()
          .ilike('product_name', '%$query%')
          .order('popularity_score', ascending: false)
          .limit(_pageSize);

      return rows.map(FoodItem.fromSystemRow).toList();
    } catch (error) {
      debugPrint('Bulkr: system_foods search failed — $error');
      return const [];
    }
  }

  Future<List<FoodItem>> _searchCachedFoods(String query) async {
    try {
      final rows = await _client
          .from('cached_off_foods')
          .select()
          .ilike('product_name', '%$query%')
          .order('last_fetched_at', ascending: false)
          .limit(_pageSize);

      return rows.map(FoodItem.fromCacheRow).toList();
    } catch (error) {
      debugPrint('Bulkr: cached_off_foods search failed — $error');
      return const [];
    }
  }

  Future<List<FoodItem>> _searchOpenFoodFacts(String query) async {
    final Uri uri = Uri.parse(_searchUrl).replace(queryParameters: {
      'search_terms': query,
      'search_simple': '1',
      'action': 'process',
      'json': '1',
      'page_size': '$_pageSize',
      'fields': _offFields.join(','),
    });

    try {
      final http.Response response = await _http
          .get(uri, headers: const {'User-Agent': _userAgent})
          .timeout(_networkTimeout);

      if (response.statusCode != 200) {
        debugPrint('Bulkr: Open Food Facts returned ${response.statusCode}');
        return const [];
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];

      final Object? products = decoded['products'];
      if (products is! List) return const [];

      return products
          .whereType<Map<String, dynamic>>()
          .map(_foodFromOffProduct)
          .whereType<FoodItem>()
          .toList();
    } on TimeoutException {
      debugPrint('Bulkr: Open Food Facts search timed out');
      return const [];
    } catch (error) {
      debugPrint('Bulkr: Open Food Facts search failed — $error');
      return const [];
    }
  }

  /// One product from their search response.
  ///
  /// Returns null for the two kinds of entry that are worse than absent: no
  /// barcode (nothing to key the cache on) and no name (nothing to show), plus
  /// products with no nutrition at all, which would silently add zero calories
  /// to a meal.
  static FoodItem? _foodFromOffProduct(Map<String, dynamic> product) {
    final String barcode = '${product['code'] ?? ''}'.trim();
    final String name = '${product['product_name'] ?? ''}'.trim();
    if (barcode.isEmpty || name.isEmpty) return null;

    final Object? rawNutriments = product['nutriments'];
    final Map<String, dynamic> nutriments =
        rawNutriments is Map<String, dynamic> ? rawNutriments : const {};

    final FoodItem food = FoodItem(
      barcode: barcode,
      name: name,
      brand: _firstBrand(product['brands']),
      per100g: Macros(
        calories: _energyKcalPer100g(nutriments),
        proteinG: parseGrams(nutriments['proteins_100g']),
        carbsG: parseGrams(nutriments['carbohydrates_100g']),
        fatG: parseGrams(nutriments['fat_100g']),
      ),
      servingSizeG: _servingGrams(product['serving_quantity']),
    );

    return food.hasNutrition ? food : null;
  }

  /// `brands` is a comma-separated list, longest-established first. One brand
  /// is enough for a search row.
  static String? _firstBrand(Object? raw) {
    final String value = '${raw ?? ''}'.trim();
    if (value.isEmpty) return null;
    final String first = value.split(',').first.trim();
    return first.isEmpty ? null : first;
  }

  /// Energy in kcal, from whichever field the product actually carries.
  ///
  /// `energy-kcal_100g` is the one to want, but plenty of European products only
  /// declare kilojoules, so `energy_100g` is converted at the thermochemical
  /// 4.184 kJ per kcal rather than dropped.
  static double _energyKcalPer100g(Map<String, dynamic> nutriments) {
    final double kcal = parseGrams(nutriments['energy-kcal_100g']);
    if (kcal > 0) return kcal;

    final double kj = parseGrams(nutriments['energy_100g']);
    return kj > 0 ? kj / 4.184 : 0;
  }

  /// `serving_quantity` is grams when present, and sometimes a string, and
  /// sometimes nonsense like 0. Only a positive number is a serving.
  static double? _servingGrams(Object? raw) {
    final double value = parseGrams(raw);
    return value > 0 ? value : null;
  }

  /// First source to mention a barcode owns it.
  static List<FoodItem> _mergeByBarcode(List<List<FoodItem>> batches) {
    final Map<String, FoodItem> byBarcode = <String, FoodItem>{};

    for (final List<FoodItem> batch in batches) {
      for (final FoodItem food in batch) {
        byBarcode.putIfAbsent(food.barcode, () => food);
      }
    }

    return byBarcode.values.toList();
  }

  /// Releases the HTTP client. Called when the owning cubit closes.
  void dispose() => _http.close();
}
