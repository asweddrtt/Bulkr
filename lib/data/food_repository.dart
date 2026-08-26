import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/food_search_ranking.dart';
import '../core/rate_limiter.dart';
import '../models/food_item.dart';
import '../models/macros.dart';

/// Finds foods to put in a meal.
///
/// Three tiers, tried in order and stopping at the first that answers well:
///
///   1. **Our own database** — `system_foods` (curated whole foods) and
///      `cached_off_foods` (everything anyone here has used before). One round
///      trip, no third party, and it gets better the more the app is used.
///   2. **FatSecret**, through the `food-search` edge function. Good coverage of
///      both generic and branded food. It runs server-side because its client
///      secret cannot ship in an app, and the function writes what it finds
///      straight into tier 1.
///   3. **Open Food Facts** — the long tail and anything international.
///
/// The tiers are sequential rather than parallel, and that is the point: Open
/// Food Facts allows ten searches a minute per IP, so the cheapest way to stay
/// under it is not to make the call. A query the cache can already answer well
/// costs zero API calls, and tier 1 answers more queries as it fills.
///
/// Open Food Facts is called from the device rather than from the function on
/// purpose. Its limit is per IP: routed through a function every user in the app
/// would share one address and one budget of ten a minute between them. Spread
/// across devices it is ten a minute *each*, and [_offLimiter] keeps each device
/// under its own.
///
/// Whatever a tier returns is re-ranked by [FoodSearchRanking] before the user
/// sees it. Open Food Facts in particular matches loosely and sorts by how
/// completely a product is documented rather than by relevance, which is how
/// "boiled eggs" comes back led by Kinder Eggs.
///
/// Product **images** from either provider are deliberately never read. A meal's
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

  /// The edge function holding the FatSecret credentials.
  static const String _fatSecretFunction = 'food-search';

  static const Duration _functionTimeout = Duration(seconds: 8);

  /// What tier 1 has to produce to end the search there: a result matching
  /// every word typed, and enough alternatives beside it that the user is
  /// choosing rather than taking what they are given.
  static const int _cacheIsEnoughCount = 5;

  /// Eight rather than Open Food Facts' ten, so a retry or a stray call still
  /// fits inside the minute.
  static const int _offCallsPerMinute = 8;

  /// One per device — see the note on tier 3 above.
  final RateLimiter _offLimiter = RateLimiter(
    maxCalls: _offCallsPerMinute,
    window: const Duration(minutes: 1),
  );

  /// Foods matching [query], best answer first.
  ///
  /// Walks the tiers until one answers well enough, so a query the cache
  /// already covers never reaches a third party. Never throws: a tier that
  /// fails is an empty tier, and the search moves on. A food search that goes
  /// blank because someone else's service is down is broken, not degraded.
  Future<List<FoodItem>> search(String query) async {
    final String trimmed = query.trim();
    if (trimmed.length < minQueryLength) return const [];

    final Map<String, ScoredFood> found = <String, ScoredFood>{};

    // Tier 1 — our own tables. Run together: they are the same database, and
    // neither is rate limited, so there is nothing to gain by serialising them.
    final List<List<ScoredFood>> local = await Future.wait([
      _searchSystemFoods(trimmed),
      _searchCachedFoods(trimmed),
    ]);
    for (final List<ScoredFood> batch in local) {
      _collect(found, batch);
    }

    List<ScoredFood> ranked = _rank(found, trimmed);
    if (_isEnough(ranked)) return _asFoods(ranked);

    // Tier 2 — FatSecret, which caches into tier 1 as a side effect.
    _collect(found, await _searchFatSecret(trimmed));

    ranked = _rank(found, trimmed);
    if (_isEnough(ranked)) return _asFoods(ranked);

    // Tier 3 — Open Food Facts, for the long tail.
    _collect(found, await _searchOpenFoodFacts(trimmed));

    return _asFoods(_rank(found, trimmed));
  }

  /// Adds candidates the query has not already found.
  ///
  /// First tier to claim a barcode keeps it, so a curated food is never
  /// shadowed by a scrappier copy of itself from further down.
  static void _collect(
    Map<String, ScoredFood> found,
    List<ScoredFood> candidates,
  ) {
    for (final ScoredFood candidate in candidates) {
      found.putIfAbsent(candidate.food.barcode, () => candidate);
    }
  }

  List<ScoredFood> _rank(Map<String, ScoredFood> found, String query) =>
      FoodSearchRanking.rankScored(found.values, query, limit: _resultLimit);

  static List<FoodItem> _asFoods(List<ScoredFood> ranked) =>
      ranked.map((c) => c.food).toList();

  /// Whether to stop here rather than call the next tier.
  ///
  /// Both halves matter. A strong top result on its own is not enough — one
  /// cached hit for "rice" would end every future search for rice at that one
  /// row, and the cache would never grow past whatever landed in it first.
  static bool _isEnough(List<ScoredFood> ranked) {
    if (ranked.length < _cacheIsEnoughCount) return false;
    return ranked.first.score >= FoodSearchRanking.strongMatchScore;
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

  /// Tier 2 — FatSecret, through the edge function that holds its secret.
  ///
  /// The function returns the rows it wrote to `cached_off_foods`, so results
  /// arrive already carrying their cache id and can be referenced by a meal
  /// without the app needing write access to that table.
  Future<List<ScoredFood>> _searchFatSecret(String query) async {
    try {
      final FunctionResponse response = await _client.functions
          .invoke(_fatSecretFunction, body: {'query': query})
          .timeout(_functionTimeout);

      final Object? data = response.data;
      if (data is! Map) return const [];

      // The function reports its own trouble in the body and still answers 200,
      // so the cascade keeps moving instead of stopping on someone else's
      // outage. Worth a line in the log: a missing secret looks exactly like a
      // provider with no results for that word.
      final Object? error = data['error'];
      if (error != null) {
        debugPrint('Bulkr: food-search reported "$error"');
      }

      final Object? foods = data['foods'];
      if (foods is! List) return const [];

      return foods
          .whereType<Map<String, dynamic>>()
          .map(FoodItem.fromCacheRow)
          .map((food) => ScoredFood(
                food: food,
                source: FoodSource.fatSecret,
                score: 0,
              ))
          .toList();
    } on TimeoutException {
      debugPrint('Bulkr: food-search timed out');
      return const [];
    } catch (error) {
      debugPrint('Bulkr: food-search failed — $error');
      return const [];
    }
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
    // Ten searches a minute per IP, and the eleventh fails for the rest of the
    // minute — so the budget is spent deliberately here rather than discovered
    // from a 429 after the user is already waiting.
    if (!_offLimiter.tryCall()) {
      debugPrint(
        'Bulkr: Open Food Facts budget spent, '
        '${_offLimiter.retryAfter.inSeconds}s until the window rolls over',
      );
      return const [];
    }

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
