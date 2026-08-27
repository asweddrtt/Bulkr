import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/food_item.dart';
import '../models/macros.dart';
import '../models/meal.dart';
import '../models/meal_draft.dart';
import '../models/meal_ingredient.dart';
import 'food_repository.dart';

/// Reads and writes the user's meal library.
///
/// "My Meals" is the union of two things the database keeps apart: meals this
/// user created (`meals.creator_id`) and meals they saved from someone else's
/// post (`saved_meals`). Both are one library as far as the user is concerned,
/// so they are merged here rather than in the UI.
class MealRepository {
  MealRepository({SupabaseClient? client, FoodRepository? foodRepository})
      : _client = client ?? Supabase.instance.client,
        _foods = foodRepository ?? FoodRepository();

  final SupabaseClient _client;
  final FoodRepository _foods;

  /// Storage bucket holding the users' own meal photos. Public-read, because
  /// a meal attached to a feed post has to render for everyone who sees it.
  static const String imageBucket = 'meal-images';

  /// Columns of `meals`, plus the author's handle for meals saved from the feed.
  ///
  /// The foreign key is named explicitly, and has to be. `meals` and `users` are
  /// related two ways: directly through `meals.creator_id`, and as a
  /// many-to-many through `saved_meals`, which PostgREST reads as a junction
  /// table because it holds foreign keys to both and nothing else of its own.
  /// A bare `users(...)` is ambiguous between them and fails with PGRST201.
  ///
  /// `daily_logs` is a second such path, so this does not get less ambiguous
  /// over time.
  static const String _mealColumns =
      '*, users!meals_creator_id_fkey(username)';

  /// How many meals a library page holds. Well beyond what anyone curates by
  /// hand, and it keeps a runaway account from pulling thousands of rows.
  static const int _libraryLimit = 200;

  String? get _userId => _client.auth.currentUser?.id;

  /// Every meal in the user's library, newest acquisition first.
  ///
  /// Three round trips rather than one: two because created and saved meals
  /// live in different tables with no view over them, and a third to total each
  /// meal's ingredient weight. That last one is a single batched query, and it
  /// is what makes `daily_logs.quantity_g` a real number when the meal is
  /// logged instead of a placeholder.
  Future<List<Meal>> fetchLibrary() async {
    final String? userId = _userId;
    if (userId == null) return const [];

    final List<Meal> created = await _fetchCreated(userId);
    final List<Meal> saved = await _fetchSaved(userId);

    // Created first: for a meal the user both wrote and favourited, the row
    // from `meals` is the authoritative one, and the saved row only adds flags.
    final Map<String, Meal> byId = <String, Meal>{};
    for (final Meal meal in created) {
      byId[meal.id] = meal;
    }
    for (final Meal meal in saved) {
      final Meal? existing = byId[meal.id];
      byId[meal.id] = existing == null
          ? meal
          : existing.copyWith(
              isSaved: true,
              isFavorite: meal.isFavorite,
              savedAt: meal.savedAt,
            );
    }

    final List<Meal> library = byId.values.toList()
      ..sort((a, b) => b.acquiredAt.compareTo(a.acquiredAt));

    return _withIngredientWeights(library);
  }

  Future<List<Meal>> _fetchCreated(String userId) async {
    final rows = await _client
        .from('meals')
        .select(_mealColumns)
        .eq('creator_id', userId)
        .order('created_at', ascending: false)
        .limit(_libraryLimit);

    return rows
        .map((row) => Meal.fromRow(row, currentUserId: userId))
        .toList();
  }

  Future<List<Meal>> _fetchSaved(String userId) async {
    final rows = await _client
        .from('saved_meals')
        .select('meal_id, is_favorite, saved_at, meals($_mealColumns)')
        .eq('user_id', userId)
        .order('saved_at', ascending: false)
        .limit(_libraryLimit);

    final List<Meal> meals = [];

    for (final Map<String, dynamic> row in rows) {
      final Map<String, dynamic>? mealRow = _embedded(row['meals']);

      // A saved row whose meal has since been deleted. Skipped rather than
      // rendered as a blank card.
      if (mealRow == null) continue;

      meals.add(Meal.fromRow(
        mealRow,
        currentUserId: userId,
        isSaved: true,
        isFavorite: row['is_favorite'] == true,
        savedAt: DateTime.tryParse('${row['saved_at']}')?.toLocal(),
      ));
    }

    return meals;
  }

  /// Fills [Meal.totalGrams] for every meal that was built from ingredients.
  ///
  /// One query for the whole list. Meals with no ingredient rows keep a null
  /// weight, which is the honest answer for a meal whose macros were typed in.
  Future<List<Meal>> _withIngredientWeights(List<Meal> meals) async {
    if (meals.isEmpty) return meals;

    try {
      final rows = await _client
          .from('meal_ingredients')
          .select('meal_id, amount_g')
          .inFilter('meal_id', meals.map((m) => m.id).toList());

      final Map<String, double> gramsByMeal = <String, double>{};
      for (final Map<String, dynamic> row in rows) {
        final String mealId = '${row['meal_id']}';
        gramsByMeal[mealId] =
            (gramsByMeal[mealId] ?? 0) + parseGrams(row['amount_g']);
      }

      return meals
          .map((meal) => gramsByMeal.containsKey(meal.id)
              ? meal.copyWith(totalGrams: gramsByMeal[meal.id])
              : meal)
          .toList();
    } catch (error) {
      // Weights are a nicety; the library is not. A meal logged without them
      // records a quantity of zero, which is recoverable.
      debugPrint('Bulkr: ingredient weights unavailable — $error');
      return meals;
    }
  }

  /// A meal's itemised ingredients, for the detail view.
  Future<List<MealIngredient>> fetchIngredients(String mealId) async {
    final rows = await _client
        .from('meal_ingredients')
        .select('id, amount_g, cached_off_foods(*)')
        .eq('meal_id', mealId)
        .order('created_at', ascending: true);

    return rows
        .map(MealIngredient.fromJoinedRow)
        .whereType<MealIngredient>()
        .toList();
  }

  /// Writes [draft] as a new meal owned by the signed-in user.
  ///
  /// Order matters. The photo goes up first because a failed upload should not
  /// leave a meal row behind; the meal row is next because the ingredient rows
  /// need its id; the ingredients land last.
  ///
  /// The ingredients are the only part allowed to fail without taking the meal
  /// with it, and that is deliberate. They depend on `cached_off_foods`, a table
  /// shared by every user, so they are the step most likely to be refused by a
  /// policy — and the calorie totals are computed on the device from the draft
  /// and do not need them. A meal that saves with the right numbers and no
  /// itemisation can be fixed later; a photo, a name, a recipe and eight
  /// ingredients lost to a permissions error on a cache table have to be typed
  /// again from nothing.
  ///
  /// The returned meal carries its [Meal.ingredients] only when they were
  /// stored, which is how the caller can tell a whole save from a partial one.
  Future<Meal> createMeal({
    required MealDraft draft,
    Uint8List? imageBytes,
    String imageExtension = 'jpg',
  }) async {
    final String? userId = _userId;
    if (userId == null) {
      throw StateError('Cannot create a meal without a signed-in user');
    }

    List<MealIngredient> ingredients;
    try {
      ingredients = await _cacheIngredientFoods(draft);
    } catch (error) {
      debugPrint('Bulkr: ingredients could not be cached — $error');
      ingredients = const [];
    }

    final Macros totals = draft.totals;

    String? imageUrl;
    if (imageBytes != null) {
      imageUrl = await _uploadImage(
        userId: userId,
        bytes: imageBytes,
        extension: imageExtension,
      );
    }

    final Map<String, dynamic> row = await _client
        .from('meals')
        .insert({
          'creator_id': userId,
          'title': draft.title.trim(),
          'description':
              draft.recipe.trim().isEmpty ? null : draft.recipe.trim(),
          'image_url': imageUrl,
          'total_calories': totals.caloriesRounded,
          'total_protein_g': totals.proteinRounded,
          'total_carbs_g': totals.carbsRounded,
          'total_fat_g': totals.fatRounded,
          'is_public': draft.isPublic,
        })
        .select(_mealColumns)
        .single();

    final Meal meal = Meal.fromRow(row, currentUserId: userId);

    if (ingredients.isNotEmpty) {
      try {
        await _client.from('meal_ingredients').insert(
              ingredients.map((i) => i.toRowValues(mealId: meal.id)).toList(),
            );
      } catch (error) {
        debugPrint('Bulkr: meal saved but ingredients failed — $error');
        return meal;
      }
    }

    return meal.copyWith(
      ingredients: ingredients,
      totalGrams: draft.totalGrams,
    );
  }

  /// Every ingredient's food needs a `cached_off_foods` row before it can be
  /// referenced, since results straight from the Open Food Facts API have no id
  /// yet.
  Future<List<MealIngredient>> _cacheIngredientFoods(MealDraft draft) async {
    if (!draft.hasIngredients) return const [];

    final List<FoodItem> cached =
        await _foods.ensureAllCached(draft.ingredients.map((i) => i.food));

    return [
      for (var i = 0; i < draft.ingredients.length; i++)
        draft.ingredients[i].copyWith(food: cached[i]),
    ];
  }

  /// Uploads the user's photo and returns its public URL.
  ///
  /// Pathed under the owner's id so a storage policy can scope writes to
  /// `auth.uid()`, the same shape as the table policies.
  Future<String> _uploadImage({
    required String userId,
    required Uint8List bytes,
    required String extension,
  }) async {
    final String path =
        '$userId/${DateTime.now().toUtc().microsecondsSinceEpoch}.$extension';

    await _client.storage.from(imageBucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: _contentTypeFor(extension),
            upsert: false,
          ),
        );

    return _client.storage.from(imageBucket).getPublicUrl(path);
  }

  static String _contentTypeFor(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  /// Deletes a meal the user created, and its photo.
  ///
  /// The database handles everything pointing at it: ingredients and other
  /// people's `saved_meals` rows go with it, while `daily_logs` and `posts`
  /// keep their rows and lose only the link. A past day's log is a record of
  /// what someone ate and is not the meal's to erase — which is why the log
  /// row carries its own copy of the calories in the first place.
  ///
  /// The photo is removed after the row, and only best-effort: an orphaned file
  /// in the bucket costs a few kilobytes, whereas failing here after the row is
  /// already gone would report a delete that plainly did happen as an error.
  Future<void> deleteMeal(Meal meal) async {
    final String? userId = _userId;
    if (userId == null) return;

    if (meal.creatorId != userId) {
      throw StateError('Only the creator of a meal can delete it');
    }

    await _client.from('meals').delete().eq('id', meal.id);

    final String? path = storagePathFor(meal.imageUrl);
    if (path == null) return;

    try {
      await _client.storage.from(imageBucket).remove([path]);
    } catch (error) {
      debugPrint('Bulkr: meal deleted, its photo was not — $error');
    }
  }

  /// Drops someone else's meal out of this user's library.
  ///
  /// Only the `saved_meals` row goes. The meal belongs to whoever wrote it and
  /// stays exactly where it was, in their library and in the feed.
  Future<void> removeFromLibrary(Meal meal) async {
    final String? userId = _userId;
    if (userId == null) return;

    await _client
        .from('saved_meals')
        .delete()
        .eq('user_id', userId)
        .eq('meal_id', meal.id);
  }

  /// The object path inside [imageBucket] that a public URL points at.
  ///
  /// Returns null for a meal with no photo, and for a URL that does not belong
  /// to this bucket — an image hosted anywhere else is not ours to delete.
  @visibleForTesting
  static String? storagePathFor(String? publicUrl) {
    if (publicUrl == null || publicUrl.isEmpty) return null;

    const String marker = '/public/$imageBucket/';
    final int start = publicUrl.indexOf(marker);
    if (start < 0) return null;

    // Query strings appear on signed and transformed URLs, never on the object
    // path itself.
    final String path = publicUrl.substring(start + marker.length).split('?').first;
    return path.isEmpty ? null : Uri.decodeComponent(path);
  }

  /// Marks a meal as a favourite, or clears the mark.
  ///
  /// Favouriting is recorded on `saved_meals`, which means favouriting a meal
  /// also saves it — deliberate, since a favourite that is not in your library
  /// has nowhere to appear. Clearing the flag keeps the saved row, so the meal
  /// stays in My Meals and only leaves Favorites.
  Future<void> setFavorite({
    required String mealId,
    required bool isFavorite,
  }) async {
    final String? userId = _userId;
    if (userId == null) return;

    await _client.from('saved_meals').upsert(
      {
        'user_id': userId,
        'meal_id': mealId,
        'is_favorite': isFavorite,
      },
      onConflict: 'user_id,meal_id',
    );
  }

  /// Records one serving of [meal] against today in `daily_logs`.
  ///
  /// The meal's macros are copied onto the log row rather than referenced
  /// through `meal_id`, so editing or deleting the meal later cannot rewrite
  /// what the user actually ate on a past day.
  ///
  /// `meal_type` is left null: the schema allows it, and guessing breakfast from
  /// the clock would be wrong often enough to be annoying.
  Future<void> logMealToday(Meal meal) async {
    final String? userId = _userId;
    if (userId == null) return;

    final DateTime now = DateTime.now();

    await _client.from('daily_logs').insert({
      'user_id': userId,
      'log_date': _asDate(now),
      'meal_id': meal.id,
      // Known only for meals built from ingredients. Zero reads as "the whole
      // meal, weight not recorded" — the calorie columns below are the figures
      // the tracker actually sums.
      'quantity_g': meal.totalGrams ?? 0,
      'calories_logged': meal.totals.caloriesRounded,
      'protein_logged_g': meal.totals.proteinRounded,
      'carbs_logged_g': meal.totals.carbsRounded,
      'fat_logged_g': meal.totals.fatRounded,
    });
  }

  /// Reads an embedded row from a Supabase join, which arrives as an object for
  /// a to-one relationship and as a list when the planner cannot tell.
  static Map<String, dynamic>? _embedded(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is List && value.isNotEmpty) {
      final Object? first = value.first;
      if (first is Map<String, dynamic>) return first;
    }
    return null;
  }

  /// `log_date` is a DATE column — send the user's local day, without a time.
  static String _asDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
