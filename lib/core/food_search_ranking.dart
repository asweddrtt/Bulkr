import '../models/food_item.dart';

/// Where a search result came from, which is the tie-breaker when two foods
/// score the same on the text.
///
/// Our own curated list beats the shared cache, which beats the hosted food
/// database, which beats a cold hit from Open Food Facts — the order of how
/// much the data behind each can be trusted. Declaration order is also the
/// tie-break order.
///
/// [hosted] is deliberately not named after a provider: the app knows only that
/// it called the `food-search` function, and which database sits behind it is
/// that function's business. It has already changed once.
enum FoodSource { system, cached, hosted, openFoodFacts }

/// A candidate result, before it has earned its place in the list.
class ScoredFood {
  const ScoredFood({required this.food, required this.source, required this.score});

  final FoodItem food;
  final FoodSource source;
  final double score;
}

/// Decides which foods a query actually meant, and in what order.
///
/// Open Food Facts is three million crowd-sourced products with a text search
/// that will happily answer "boiled eggs" with Kinder Eggs and "whey" with a
/// lactose-free milk, because it matches loosely and ranks by how completely a
/// product is documented rather than by how well it fits what was typed. So the
/// ordering is redone here, against the query, before anything reaches the user.
///
/// Pure and free of Flutter and of the network, so the rules below can be tested
/// against the exact queries that went wrong.
class FoodSearchRanking {
  const FoodSearchRanking._();

  /// A result has to share at least one word with the query. This is the rule
  /// that throws out the lactose-free milk: not one of its words is "whey".
  static const double _rejected = -1;

  /// Beyond this, extra words in a name are noise. "Egg" should beat "Egg &
  /// Cress Sandwich, Reduced Fat, Family Pack" for the query "egg".
  static const int _lengthPenaltyCap = 12;

  /// No food is more than 900 kcal per 100g — that is pure fat — and the macros
  /// cannot weigh more than the food does. Open Food Facts contains plenty of
  /// entries that fail both, usually a decimal point in the wrong place.
  static const double _maxKcalPer100g = 900;
  static const double _maxMacroGramsPer100g = 105;

  /// Words too generic to count as a match on their own.
  static const Set<String> _stopWords = {
    'and', 'the', 'with', 'of', 'in', 'a', 'an', 'or', 'for',
  };

  /// The score a result reaches when every word typed appears in its name:
  /// full coverage (300) plus the all-words bonus (200).
  ///
  /// Used as the bar for "we already have a good answer for this" — the thing
  /// that lets a search stop at the local cache and make no API call at all.
  static const double strongMatchScore = 500;

  /// Ranks [candidates] against [query] and drops what does not belong.
  static List<FoodItem> rank(
    Iterable<ScoredFood> candidates,
    String query, {
    int limit = 15,
  }) =>
      rankScored(candidates, query, limit: limit).map((c) => c.food).toList();

  /// As [rank], but keeping each result's final score.
  ///
  /// Ties are broken by source, then by the shorter name, so the order is
  /// stable rather than dependent on which network call happened to finish
  /// first.
  static List<ScoredFood> rankScored(
    Iterable<ScoredFood> candidates,
    String query, {
    int limit = 15,
  }) {
    final List<String> queryTokens = tokenize(query);
    if (queryTokens.isEmpty) return const [];

    final List<ScoredFood> scored = [];

    for (final ScoredFood candidate in candidates) {
      if (!isPlausible(candidate.food)) continue;

      final double score = scoreFor(candidate.food, queryTokens);
      if (score == _rejected) continue;

      scored.add(ScoredFood(
        food: candidate.food,
        source: candidate.source,
        score: score + _sourceBonus(candidate.source),
      ));
    }

    scored.sort((a, b) {
      final int byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;

      final int bySource = a.source.index.compareTo(b.source.index);
      if (bySource != 0) return bySource;

      return a.food.name.length.compareTo(b.food.name.length);
    });

    return scored.take(limit).toList();
  }

  /// How well [food] answers [queryTokens], or [_rejected].
  ///
  /// Coverage — how many of the words typed appear in the name — dominates
  /// everything else, because it is what "boiled eggs" versus "Kinder Eggs"
  /// comes down to: one covers both words, the other covers one.
  static double scoreFor(FoodItem food, List<String> queryTokens) {
    final String name = food.name.toLowerCase().trim();
    final List<String> nameTokens = tokenize(name);
    if (nameTokens.isEmpty) return _rejected;

    final String queryText = queryTokens.join(' ');

    int matched = 0;
    for (final String token in queryTokens) {
      if (nameTokens.any((nameToken) => _tokensMatch(token, nameToken))) {
        matched++;
      }
    }

    if (matched == 0) {
      // Last chance for a name whose tokenisation went badly — "wholegrain-oats"
      // against "oats" — before giving up on it.
      if (!name.contains(queryText)) return _rejected;
      matched = queryTokens.length;
    }

    double score = 300 * (matched / queryTokens.length);

    // Every word accounted for is the difference between a good answer and a
    // coincidence, and is worth more than any amount of partial credit.
    if (matched == queryTokens.length) score += 200;

    if (name == queryText) {
      score += 1000;
    } else if (name.startsWith(queryText)) {
      score += 400;
    } else if (nameTokens.first == queryTokens.first) {
      // "Egg, boiled" for "egg" — the food is the subject of its own name
      // rather than an ingredient mentioned in passing.
      score += 150;
    }

    // Shorter names are more generic, and a generic food is almost always what
    // someone typing two plain words meant.
    final int extraWords = nameTokens.length - queryTokens.length;
    if (extraWords > 0) {
      score -= 8 * (extraWords > _lengthPenaltyCap ? _lengthPenaltyCap : extraWords);
    }

    // An unbranded entry is the generic version of the food.
    if (food.brand == null || food.brand!.trim().isEmpty) score += 40;

    return score;
  }

  /// Whether a query word and a name word are the same word.
  ///
  /// Prefix matching in both directions, which is a cheap stand-in for a
  /// stemmer and covers what actually comes up: singular against plural
  /// ("egg"/"eggs"), and a typed stem against a longer form ("chick" against
  /// "chicken"). Three characters minimum, or "oat" would match "oatmeal",
  /// "oats" and also "oa"-anything.
  static bool _tokensMatch(String queryToken, String nameToken) {
    if (queryToken == nameToken) return true;
    if (queryToken.length < 3 || nameToken.length < 3) return false;
    return nameToken.startsWith(queryToken) || queryToken.startsWith(nameToken);
  }

  static double _sourceBonus(FoodSource source) => switch (source) {
        FoodSource.system => 120,
        FoodSource.cached => 60,
        FoodSource.hosted => 40,
        FoodSource.openFoodFacts => 0,
      };

  /// Rejects entries whose numbers cannot describe a food.
  ///
  /// Open Food Facts is crowd-sourced, and a misplaced decimal produces a rice
  /// that is 3,500 kcal per 100g. Adding one to a meal quietly wrecks the day's
  /// total, and the user has no way to tell it was the data and not them.
  static bool isPlausible(FoodItem food) {
    if (!food.hasNutrition) return false;
    if (food.name.trim().isEmpty) return false;

    final double kcal = food.per100g.calories;
    if (kcal <= 0 || kcal > _maxKcalPer100g) return false;

    final double protein = food.per100g.proteinG;
    final double carbs = food.per100g.carbsG;
    final double fat = food.per100g.fatG;

    if (protein < 0 || carbs < 0 || fat < 0) return false;
    if (protein + carbs + fat > _maxMacroGramsPer100g) return false;

    return true;
  }

  /// Splits text into comparable words: lowercase, punctuation gone, stop words
  /// and single characters dropped.
  static List<String> tokenize(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.length > 1 && !_stopWords.contains(token))
        .toList();
  }
}
