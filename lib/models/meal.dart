import 'package:equatable/equatable.dart';

import 'macros.dart';
import 'meal_ingredient.dart';
import 'visibility.dart';

/// What a meal is mostly made of, for the tag on its card.
///
/// Derived from the macro split rather than stored, so it can never disagree
/// with the numbers printed underneath it.
enum MealEmphasis { protein, carbs, fat, balanced }

/// A `public.meals` row plus this user's relationship to it.
///
/// The relationship flags do not live on the meal row — they come from
/// `saved_meals` and from comparing `creator_id` to the session — but they are
/// what the Meals tab sorts and filters on, so the repository resolves them
/// once and hands over a single object rather than making every widget join
/// three things in its head.
class Meal extends Equatable {
  const Meal({
    required this.id,
    required this.creatorId,
    required this.title,
    this.description,
    this.imageUrl,
    this.totals = Macros.zero,
    this.visibility = ContentVisibility.private,
    required this.createdAt,
    this.creatorUsername,
    this.isMine = false,
    this.isSaved = false,
    this.isFavorite = false,
    this.savedAt,
    this.ingredients = const [],
    this.totalGrams,
    this.isLoggedToday = false,
    this.sourceMealId,
    this.sourceCreatorId,
    this.sourceCreatorUsername,
  });

  final String id;
  final String creatorId;
  final String title;

  /// `meals.description` — the recipe. Free text, written and read as typed.
  final String? description;

  /// Public URL of the user's own photo in the `meal-images` bucket. Never an
  /// Open Food Facts product image.
  final String? imageUrl;

  /// The stored `total_*` columns, denormalised on the row so a meal list is
  /// one query rather than one join per card.
  final Macros totals;

  /// Who can see this meal. Replaces the boolean `is_public` — see
  /// [ContentVisibility] for why a boolean was not enough.
  final ContentVisibility visibility;

  /// Kept as a getter so the several places that only ask "is this shareable"
  /// read the same as they did.
  bool get isPublic => visibility.isPublic;
  final DateTime createdAt;

  /// Author's handle, when the meal was read with its creator joined. Shown on
  /// meals saved from someone else's post so the credit stays visible.
  final String? creatorUsername;

  /// This session created the meal.
  final bool isMine;

  /// There is a `saved_meals` row for this user — the meal was taken from
  /// someone else's post, or the user favourited their own.
  final bool isSaved;

  final bool isFavorite;

  /// When it was saved, for ordering the library by when it entered it rather
  /// than by when its author first created it.
  final DateTime? savedAt;

  /// Populated only when the meal's detail has been read. An empty list means
  /// "not loaded", not "no ingredients" — the card must not read anything into
  /// it.
  final List<MealIngredient> ingredients;

  /// Whether this meal is in today's `daily_logs`.
  ///
  /// Read from the database rather than remembered in the UI, so it survives a
  /// tab switch, a refresh and a restart — the card is showing what today's log
  /// actually contains, not what this session happened to tap.
  final bool isLoggedToday;

  /// The meal this one was copied from, when it was taken off someone's post.
  ///
  /// Saving a meal from the feed copies it rather than referencing it: the
  /// saver gets a row of their own that they can edit and that its original
  /// author can neither change nor delete from under them. The cost is that
  /// `creator_id` becomes the saver, so this is what remembers where the
  /// recipe actually came from.
  final String? sourceMealId;

  /// Id of whoever wrote the original.
  ///
  /// Carried as well as the handle because copying a copy has to credit the
  /// person who wrote the recipe, not the last person to pass it on — and
  /// that needs an id to write, not a name to display.
  final String? sourceCreatorId;

  /// Handle of whoever wrote the original, when the meal was read with
  /// `source_creator_id` joined.
  ///
  /// Not the same as [creatorUsername], which on a copy is the saver — this is
  /// the person owed the credit.
  final String? sourceCreatorUsername;

  /// Whether this meal came from someone else's post.
  bool get isCopy => sourceMealId != null;

  /// Summed ingredient grams, when known.
  ///
  /// Null for a meal whose macros were typed in by hand rather than built from
  /// ingredients, which is a real case and not the same as zero grams.
  final double? totalGrams;

  /// Where the library sorts it: when the user acquired it, falling back to
  /// when it was created for their own meals.
  DateTime get acquiredAt => savedAt ?? createdAt;

  /// Which macro dominates, by share of the calories the macros account for.
  ///
  /// The thresholds are deliberately not equal. Protein is the interesting one
  /// in a bulking app and rarely clears 40% of a real meal's calories, while
  /// carbohydrate routinely does, so calling a meal "carb load" needs to mean
  /// more than "it contains rice". Anything without a clear winner is balanced,
  /// which is most food.
  MealEmphasis get emphasis {
    final double total = totals.macroCalories;
    if (total <= 0) return MealEmphasis.balanced;

    final double protein = totals.proteinG * 4 / total;
    final double carbs = totals.carbsG * 4 / total;
    final double fat = totals.fatG * 9 / total;

    if (protein >= 0.40) return MealEmphasis.protein;
    if (carbs >= 0.55) return MealEmphasis.carbs;
    if (fat >= 0.45) return MealEmphasis.fat;
    return MealEmphasis.balanced;
  }

  /// Whether [title], [description] or the author's handle contains [query].
  ///
  /// Matching the recipe text too is deliberate: "chicken" should find the meal
  /// called "Sunday Prep" whose recipe is mostly chicken.
  bool matches(String query) {
    final String needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;

    return title.toLowerCase().contains(needle) ||
        (description ?? '').toLowerCase().contains(needle) ||
        (creatorUsername ?? '').toLowerCase().contains(needle);
  }

  Meal copyWith({
    String? title,
    String? description,
    String? imageUrl,
    Macros? totals,
    ContentVisibility? visibility,
    bool? isMine,
    bool? isSaved,
    bool? isFavorite,
    DateTime? savedAt,
    List<MealIngredient>? ingredients,
    double? totalGrams,
    String? creatorUsername,
    bool? isLoggedToday,
    String? sourceMealId,
    String? sourceCreatorId,
    String? sourceCreatorUsername,
  }) {
    return Meal(
      id: id,
      creatorId: creatorId,
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      totals: totals ?? this.totals,
      visibility: visibility ?? this.visibility,
      createdAt: createdAt,
      creatorUsername: creatorUsername ?? this.creatorUsername,
      isMine: isMine ?? this.isMine,
      isSaved: isSaved ?? this.isSaved,
      isFavorite: isFavorite ?? this.isFavorite,
      savedAt: savedAt ?? this.savedAt,
      ingredients: ingredients ?? this.ingredients,
      totalGrams: totalGrams ?? this.totalGrams,
      isLoggedToday: isLoggedToday ?? this.isLoggedToday,
      sourceMealId: sourceMealId ?? this.sourceMealId,
      sourceCreatorId: sourceCreatorId ?? this.sourceCreatorId,
      sourceCreatorUsername:
          sourceCreatorUsername ?? this.sourceCreatorUsername,
    );
  }

  factory Meal.fromRow(
    Map<String, dynamic> row, {
    String? currentUserId,
    bool isSaved = false,
    bool isFavorite = false,
    DateTime? savedAt,
  }) {
    final String creatorId = '${row['creator_id']}';

    // Present only when the query asked for `users(username)`. A meal list that
    // does not need the author skips the join.
    final Object? author = row['users'];
    final Map<String, dynamic>? authorRow = author is Map<String, dynamic>
        ? author
        : (author is List && author.isNotEmpty
            ? author.first as Map<String, dynamic>
            : null);

    return Meal(
      id: '${row['id']}',
      creatorId: creatorId,
      title: '${row['title'] ?? ''}',
      description: row['description'] as String?,
      imageUrl: row['image_url'] as String?,
      totals: Macros(
        calories: parseGrams(row['total_calories']),
        proteinG: parseGrams(row['total_protein_g']),
        carbsG: parseGrams(row['total_carbs_g']),
        fatG: parseGrams(row['total_fat_g']),
      ),
      creatorUsername: authorRow?['username'] as String?,
      // Falls back to the old boolean for a row read before
      // `social_privacy.sql` has run, so the meals list is not suddenly all
      // private on the day this ships.
      visibility: row.containsKey('visibility')
          ? ContentVisibility.fromDbValue(row['visibility'])
          : ContentVisibility.fromIsPublic(row['is_public']),
      createdAt: DateTime.tryParse('${row['created_at']}')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isMine: currentUserId != null && creatorId == currentUserId,
      isSaved: isSaved,
      isFavorite: isFavorite,
      savedAt: savedAt,
      sourceMealId: row['source_meal_id'] as String?,
      sourceCreatorId: row['source_creator_id'] as String?,
      // Aliased in the query, and it has to be: `meals` points at `users`
      // twice now, so two embeds of the same table would collide on the key
      // `users` if neither were renamed.
      sourceCreatorUsername: _embeddedUsername(row['source_author']),
    );
  }

  /// A `username` out of an embedded `users` row, whatever shape it arrived in.
  static String? _embeddedUsername(Object? embedded) {
    if (embedded is Map<String, dynamic>) return embedded['username'] as String?;
    if (embedded is List && embedded.isNotEmpty) {
      final Object? first = embedded.first;
      if (first is Map<String, dynamic>) return first['username'] as String?;
    }
    return null;
  }

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        imageUrl,
        totals,
        visibility,
        creatorUsername,
        isMine,
        isSaved,
        isFavorite,
        ingredients,
        totalGrams,
        isLoggedToday,
        sourceMealId,
        sourceCreatorId,
        sourceCreatorUsername,
      ];
}
