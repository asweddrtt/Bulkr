import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/food_search_ranking.dart';
import '../models/food_item.dart';
import '../models/macros.dart';

/// Finds foods to put in a meal, and keeps the ones that get used.
///
/// Three sources, in the order of how much the data behind them can be trusted:
///
/// 1. `public.system_foods` — the curated list of whole foods. One round trip
///    to our own database, and the reason typing "egg" offers an egg rather
///    than a chocolate one.
/// 2. `public.cached_off_foods` — anything anyone here has used before.
/// 3. Open Food Facts — the long tail, roughly three million products.
///
/// Whatever the three return is then re-ranked against the query by
/// [FoodSearchRanking], because Open Food Facts' own ordering is not relevance:
/// it matches loosely and sorts by how completely a product is documented, so
/// "boiled eggs" comes back led by Kinder Eggs. That ordering never reaches the
/// user.
///
/// Product **images** from Open Food Facts are deliberately never read. A meal's
/// photo is the user's own.
class FoodRepository {
  FoodRepository({SupabaseClient? client, http.Client? httpClient})
      : _client = client ?? Supabase.instance.client,
        _http = httpClient ?? http.Client();

  final SupabaseClient _client;
  final http.Client _http;

  /// Open Food Facts asks every client to identify itself, and rate-limits or
  /// blocks anonymous traffic. Not a secret — a courtesy and a term of use.
  static const String _userAgent =
      'Bulkr/1.0 (Flutter; +https://github.com/asweddrtt/Bulkr)';

  /// Their current search service, which is what powers search on their own
  /// site. Materially better at relevance than the legacy endpoint below, and
  /// much faster.
  static const String _searchUrl = 'https://search.openfoodfacts.org/search';

  /// The previous endpoint, kept as a fallback. Slower and looser, but it has
  /// been there for years and is a better answer than an empty list when the
  /// newer service is down or has moved.
  static const String _legacySearchUrl =
      'https://world.openfoodfacts.org/cgi/search.pl';

  /// Only what gets stored — this turns a multi-megabyte response into a few
  /// kilobytes, which is most of why the search feels immediate or doesn't.
  static const List<String> _offFields = [
    'code',
    'product_name',
    'brands',
    'serving_quantity',
    'nutriments',
  ];

  /// A search is one keystroke away from the next, so it gets a short deadline:
  /// a result the user has already typed past is worse than no result. The
  /// legacy endpoint is given a little longer because it is genuinely slow, and
  /// by the time it runs it is the only thing left to try.
  static const Duration _networkTimeout = Duration(seconds: 6);
  static const Duration _legacyTimeout = Duration(seconds: 9);

  /// Asked for generously and cut down hard: ranking can only choose from what
  /// it is given, and the good answer is often not in Open Food Facts' first
  /// five.
  static const int _fetchSize = 30;
  static const int _resultLimit = 15;

  /// Below this a query matches half the database and none of it usefully.
  static const int minQueryLength = 2;

  /// Foods matching [query], best answer first.
  ///
  /// Never throws: a failing Open Food Facts call still returns whatever the
  /// two local tables found. A food search that goes blank when a third party
  /// is down is broken, not degraded.
  Future<List<FoodItem>> search(String query) async {
    final String trimmed = query.trim();
    if (trimmed.length < minQueryLength) return const [];

    final List<List<ScoredFood>> batches = await Future.wait([
      _searchSystemFoods(trimmed),
      _searchCachedFoods(trimmed),
      _searchOpenFoodFacts(trimmed),
    ]);

    // Deduplicated by barcode before ranking, keeping the most trusted copy —
    // otherwise a food we curated and the same barcode from Open Food Facts
    // would both take up a row.
    final Map<String, ScoredFood> byBarcode = <String, ScoredFood>{};
    for (final List<ScoredFood> batch in batches) {
      for (final ScoredFood candidate in batch) {
        byBarcode.putIfAbsent(candidate.food.barcode, () => candidate);
      }
    }

    return FoodSearchRanking.rank(
      byBarcode.values,
      trimmed,
      limit: _resultLimit,
    );
  }

  /// Ensures [food] exists in `cached_off_foods` and returns it carrying the row
  /// id that `meal_ingredients.cached_food_id` needs.
  ///
  /// Reads before it writes. A food anyone has used before is already there, and
  /// looking it up costs one cheap indexed select — where an unconditional
  /// upsert would need insert *and* update rights on a table shared by every
  /// user, on every ingredient of every meal.
  Future<FoodItem> ensureCached(FoodItem food) async {
    if (food.cachedId != null) return food;

    final Map<String, dynamic>? existing = await _client
        .from('cached_off_foods')
        .select('id')
        .eq('barcode', food.barcode)
        .maybeSingle();

    final String? existingId = existing?['id'] as String?;
    if (existingId != null) return food.copyWith(cachedId: existingId);

    final Map<String, dynamic> row = await _client
        .from('cached_off_foods')
        .upsert(
          {
            ...food.toCacheValues(),
            'last_fetched_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'barcode',
        )
        .select('id')
        .single();

    return food.copyWith(cachedId: row['id'] as String?);
  }

  /// Caches every food in [foods] concurrently, preserving order.
  Future<List<FoodItem>> ensureAllCached(Iterable<FoodItem> foods) {
    return Future.wait(foods.map(ensureCached));
  }

  Future<List<ScoredFood>> _searchSystemFoods(String query) async {
    try {
      final rows = await _client
          .from('system_foods')
          .select()
          .ilike('product_name', '%$query%')
          .order('popularity_score', ascending: false)
          .limit(_fetchSize);

      return rows
          .map((row) => ScoredFood(
                food: FoodItem.fromSystemRow(row),
                source: FoodSource.system,
                score: 0,
              ))
          .toList();
    } catch (error) {
      debugPrint('Bulkr: system_foods search failed — $error');
      return const [];
    }
  }

  Future<List<ScoredFood>> _searchCachedFoods(String query) async {
    try {
      final rows = await _client
          .from('cached_off_foods')
          .select()
          .ilike('product_name', '%$query%')
          .order('last_fetched_at', ascending: false)
          .limit(_fetchSize);

      return rows
          .map((row) => ScoredFood(
                food: FoodItem.fromCacheRow(row),
                source: FoodSource.cached,
                score: 0,
              ))
          .toList();
    } catch (error) {
      debugPrint('Bulkr: cached_off_foods search failed — $error');
      return const [];
    }
  }

  /// The current search service, falling back to the legacy one.
  ///
  /// The fallback fires on an empty result as well as on an error, so a service
  /// that has moved or changed its response shape degrades to the old endpoint
  /// rather than to nothing.
  Future<List<ScoredFood>> _searchOpenFoodFacts(String query) async {
    final List<FoodItem> primary = await _searchViaSearchService(query);
    if (primary.isNotEmpty) return _asCandidates(primary);

    final List<FoodItem> legacy = await _searchViaLegacyEndpoint(query);
    return _asCandidates(legacy);
  }

  static List<ScoredFood> _asCandidates(List<FoodItem> foods) => foods
      .map((food) => ScoredFood(
            food: food,
            source: FoodSource.openFoodFacts,
            score: 0,
          ))
      .toList();

  Future<List<FoodItem>> _searchViaSearchService(String query) async {
    final Uri uri = Uri.parse(_searchUrl).replace(queryParameters: {
      'q': query,
      'page_size': '$_fetchSize',
      'fields': _offFields.join(','),
    });

    return _fetchProducts(uri, _networkTimeout, 'search service');
  }

  Future<List<FoodItem>> _searchViaLegacyEndpoint(String query) async {
    final Uri uri = Uri.parse(_legacySearchUrl).replace(queryParameters: {
      'search_terms': query,
      'search_simple': '1',
      'action': 'process',
      'json': '1',
      'page_size': '$_fetchSize',
      'fields': _offFields.join(','),
    });

    return _fetchProducts(uri, _legacyTimeout, 'legacy search');
  }

  /// Reads whichever list of products a response carries.
  ///
  /// The two endpoints differ only in what they call it — `hits` on the search
  /// service, `products` on the legacy one — and the product documents inside
  /// are the same shape, so one parser serves both.
  Future<List<FoodItem>> _fetchProducts(
    Uri uri,
    Duration timeout,
    String label,
  ) async {
    try {
      final http.Response response = await _http
          .get(uri, headers: const {'User-Agent': _userAgent})
          .timeout(timeout);

      if (response.statusCode != 200) {
        debugPrint('Bulkr: OFF $label returned ${response.statusCode}');
        return const [];
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];

      final Object? products = decoded['hits'] ?? decoded['products'];
      if (products is! List) return const [];

      return products
          .whereType<Map<String, dynamic>>()
          .map(foodFromOffProduct)
          .whereType<FoodItem>()
          .toList();
    } on TimeoutException {
      debugPrint('Bulkr: OFF $label timed out after ${timeout.inSeconds}s');
      return const [];
    } catch (error) {
      debugPrint('Bulkr: OFF $label failed — $error');
      return const [];
    }
  }

  /// One product document from either endpoint.
  ///
  /// Returns null for the kinds of entry that are worse than absent: no barcode
  /// (nothing to key the cache on), no name (nothing to show), and no nutrition
  /// (would silently add zero calories to a meal). Whether the numbers are
  /// *believable* is [FoodSearchRanking.isPlausible]'s job.
  @visibleForTesting
  static FoodItem? foodFromOffProduct(Map<String, dynamic> product) {
    final String barcode = '${product['code'] ?? ''}'.trim();
    final String name = _cleanName(product['product_name']);
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

  /// Collapses the whitespace and newlines that crowd-sourced names arrive
  /// with, so a name can be compared and measured by its words.
  static String _cleanName(Object? raw) =>
      '${raw ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// `brands` is a comma-separated list, longest-established first. One brand is
  /// enough for a search row.
  static String? _firstBrand(Object? raw) {
    final String value = '${raw ?? ''}'.trim();
    if (value.isEmpty) return null;
    final String first = value.split(',').first.trim();
    return first.isEmpty ? null : first;
  }

  /// Energy in kcal, from whichever field the product carries.
  ///
  /// `energy-kcal_100g` is the one to want, but plenty of European products
  /// declare only kilojoules, so `energy_100g` is converted at 4.184 kJ per
  /// kcal rather than dropped.
  static double _energyKcalPer100g(Map<String, dynamic> nutriments) {
    final double kcal = parseGrams(nutriments['energy-kcal_100g']);
    if (kcal > 0) return kcal;

    final double kj = parseGrams(nutriments['energy_100g']);
    return kj > 0 ? kj / 4.184 : 0;
  }

  /// `serving_quantity` is grams when present, sometimes a string, and
  /// sometimes nonsense like 0. Only a positive number is a serving.
  static double? _servingGrams(Object? raw) {
    final double value = parseGrams(raw);
    return value > 0 ? value : null;
  }

  /// Releases the HTTP client. Called when the app shuts down.
  void dispose() => _http.close();
}
