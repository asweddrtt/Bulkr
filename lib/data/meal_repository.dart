import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'image_uploader.dart';
import '../models/daily_log_entry.dart';
import '../models/food_item.dart';
import '../models/macros.dart';
import '../models/meal.dart';
import '../models/weekly_recap.dart';
import '../models/meal_draft.dart';
import '../models/meal_ingredient.dart';
import '../models/meal_slot.dart';
import '../models/visibility.dart';
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

  /// Both sizes of every meal photo, and the deletes that go with them.
  late final ImageUploader _images =
      ImageUploader(client: _client, bucket: imageBucket);

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
  static const String _mealColumns = '*, '
      'users!meals_creator_id_fkey(username), '
      // Aliased, because `meals` points at `users` twice — `creator_id` and
      // `source_creator_id`. Two unaliased embeds of the same table would both
      // land under the key `users` and one would win.
      'source_author:users!meals_source_creator_id_fkey(username)';

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

    return _withTodaysLogState(await _withIngredientWeights(library));
  }

  /// Marks the meals that are already in today's log.
  ///
  /// One query for the whole list, and the reason the tick on a card survives a
  /// tab switch: the state is read from `daily_logs` rather than remembered
  /// from whatever this session happened to tap.
  Future<List<Meal>> _withTodaysLogState(List<Meal> meals) async {
    final String? userId = _userId;
    if (userId == null || meals.isEmpty) return meals;

    try {
      final Set<String> logged = await loggedMealIdsToday(userId);
      if (logged.isEmpty) return meals;

      return meals
          .map((meal) => meal.copyWith(isLoggedToday: logged.contains(meal.id)))
          .toList();
    } catch (error) {
      // The library is still usable without it; the tick just starts blank.
      debugPrint("Bulkr: today's log state unavailable — $error");
      return meals;
    }
  }

  /// Ids of the meals logged against today.
  Future<Set<String>> loggedMealIdsToday([String? userId]) async {
    final String? id = userId ?? _userId;
    if (id == null) return <String>{};

    final rows = await _client
        .from('daily_logs')
        .select('meal_id')
        .eq('user_id', id)
        .eq('log_date', _asDate(DateTime.now()))
        .not('meal_id', 'is', null);

    return rows.map((row) => '${row['meal_id']}').toSet();
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

  /// The meals [creatorId] has written, for their profile.
  ///
  /// Which of them come back is not decided here. `meals` has a SELECT policy
  /// of `public.can_view(creator_id, visibility)`, so a private meal is
  /// invisible to everyone but its author, a followers-only one needs the
  /// follow, and a blocked author's are gone entirely. The query asks for all
  /// of theirs and the database returns the ones this reader is allowed —
  /// which is why there is no visibility filter in the Dart.
  ///
  /// Saved meals are deliberately absent, and cannot be added without a
  /// decision: `saved_meals` is private to its owner, "no exceptions", per
  /// `meals_policies.sql`. What somebody has bookmarked is a record of what
  /// they are interested in, and making that public is a change to what the
  /// app promises rather than a feature to add quietly.
  Future<List<Meal>> fetchMealsBy(String creatorId) async {
    final rows = await _client
        .from('meals')
        .select(_mealColumns)
        .eq('creator_id', creatorId)
        .order('created_at', ascending: false)
        .limit(_libraryLimit);

    final List<Meal> meals = rows
        .map((row) => Meal.fromRow(row, currentUserId: _userId))
        .toList();

    return _withIngredientWeights(meals);
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

    UploadedImage? uploaded;
    if (imageBytes != null) {
      uploaded = await _images.upload(
        ownerId: userId,
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
          'image_url': uploaded?.url,
          'thumb_url': uploaded?.thumbUrl,
          'total_calories': totals.caloriesRounded,
          'total_protein_g': totals.proteinRounded,
          'total_carbs_g': totals.carbsRounded,
          'total_fat_g': totals.fatRounded,
          'visibility': draft.visibility.dbValue,
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

  /// Copies a meal off someone's post into this user's library.
  ///
  /// A copy, not a reference. `saved_meals` already offers the reference — one
  /// row pointing at the original — and it is the wrong shape for something
  /// taken off a feed: the original's author can edit the recipe under you, or
  /// delete it, and the FK cascade takes your library entry with it. A recipe
  /// someone cooked from and kept should not be able to change or vanish
  /// because its author had second thoughts.
  ///
  /// So the row is duplicated, and `source_meal_id` / `source_creator_id`
  /// carry the credit forward. What is *not* duplicated is the photo: the new
  /// row points at the same file in the `meal-images` bucket. Copying the
  /// bytes would mean downloading and re-uploading someone else's image on a
  /// phone, and the bucket is public-read, so the URL resolves for everyone
  /// either way. The consequence is honest and worth knowing: if the original
  /// author deletes their meal and its image, the copy keeps the recipe and
  /// loses the picture.
  ///
  /// Returns the new meal. Throws if [meal] is already this user's — copying
  /// your own meal from your own post is a duplicate nobody asked for, and the
  /// UI does not offer it.
  Future<Meal> copyFromPost(Meal meal) async {
    final String? userId = _userId;
    if (userId == null) {
      throw StateError('Cannot save a meal without a signed-in user');
    }

    if (meal.creatorId == userId) {
      throw StateError('That meal is already yours');
    }

    // Credit and identity both chain to the root of the copy, not to whoever
    // happened to pass it on. Copying someone's copy of a recipe still points
    // at the recipe and still names the person who wrote it — otherwise credit
    // decays one hop at a time until it is gone.
    final String rootMealId = meal.sourceMealId ?? meal.id;
    final String rootCreatorId = meal.sourceCreatorId ?? meal.creatorId;

    // Already taken. Returned rather than duplicated, so a second tap on a
    // card whose button did not get the news is a no-op instead of a second
    // identical meal in the library — and, because the check is on the root,
    // so is taking the same recipe from two different people's posts.
    final List<Map<String, dynamic>> existing = await _client
        .from('meals')
        .select(_mealColumns)
        .eq('creator_id', userId)
        .eq('source_meal_id', rootMealId)
        .limit(1);

    if (existing.isNotEmpty) {
      return Meal.fromRow(existing.first, currentUserId: userId);
    }

    // Read fresh rather than copied off the model the caller was holding.
    //
    // A meal reached from the feed arrives without its recipe: the feed's
    // embed leaves `description` out, because it is the largest column on the
    // table and no card renders it. Copying from that model would have
    // silently produced a recipe-less copy.
    //
    // It is also the more correct read. A meal is copied as it is now, not as
    // it was when the page it was seen on happened to load.
    final Meal source = await _fetchForCopy(meal);

    final Map<String, dynamic> row = await _client
        .from('meals')
        .insert({
          'creator_id': userId,
          'title': source.title,
          'description': source.description,
          'image_url': source.imageUrl,
          // The same two files, pointed at by a second row. A copy is a new
          // meal, not a new photo — re-uploading the bytes would double the
          // storage to no end.
          'thumb_url': source.thumbUrl,
          'total_calories': meal.totals.caloriesRounded,
          'total_protein_g': meal.totals.proteinRounded,
          'total_carbs_g': meal.totals.carbsRounded,
          'total_fat_g': meal.totals.fatRounded,
          // A copy starts private whatever the original was. The user took it
          // for their own cooking; if they want to share it on a post of their
          // own, that is a decision they make there.
          'visibility': ContentVisibility.private.dbValue,
          'source_meal_id': rootMealId,
          'source_creator_id': rootCreatorId,
        })
        .select(_mealColumns)
        .single();

    final Meal copy = Meal.fromRow(row, currentUserId: userId);

    // The ingredients are the recipe. They are allowed to fail without taking
    // the meal with it — the totals are already on the row above, so a copy
    // that lands un-itemised still logs the right calories — but a save that
    // silently dropped them would leave the user with a meal they cannot see
    // inside.
    try {
      // Copied from the meal in hand, not from the root: the root may have
      // been deleted, and this is the version the user is actually looking at.
      await _copyIngredients(fromMealId: meal.id, toMealId: copy.id);
    } catch (error) {
      debugPrint('Bulkr: meal copied but its ingredients failed — $error');
      return copy;
    }

    return copy;
  }

  /// Duplicates the ingredient rows of one meal onto another.
  ///
  /// The rows point at `cached_off_foods`, a table shared by every user, so
  /// the copy reuses the same food rows rather than re-fetching anything. One
  /// read and one write regardless of how many ingredients there are.
  Future<void> _copyIngredients({
    required String fromMealId,
    required String toMealId,
  }) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('meal_ingredients')
        .select('cached_food_id, amount_g')
        .eq('meal_id', fromMealId)
        .order('created_at', ascending: true);

    if (rows.isEmpty) return;

    await _client.from('meal_ingredients').insert([
      for (final Map<String, dynamic> row in rows)
        {
          'meal_id': toMealId,
          'cached_food_id': row['cached_food_id'],
          'amount_g': row['amount_g'],
        },
    ]);
  }

  /// Writes [draft] over an existing meal the user owns.
  ///
  /// Only the creator can do this, and the check is here rather than only in
  /// the UI: a meal saved from someone else's post is theirs, and editing it
  /// would silently rewrite it for everyone who saved it. Changing a saved meal
  /// means [createMeal] — a copy of your own.
  ///
  /// Already-logged days are untouched. `daily_logs` rows carry their own copy
  /// of the calories precisely so that correcting a meal today cannot rewrite
  /// what was eaten last Tuesday. That includes today's entry: it records what
  /// was logged at the time it was logged.
  Future<Meal> updateMeal({
    required Meal meal,
    required MealDraft draft,
    Uint8List? imageBytes,
    String imageExtension = 'jpg',
  }) async {
    final String? userId = _userId;
    if (userId == null) {
      throw StateError('Cannot edit a meal without a signed-in user');
    }
    if (meal.creatorId != userId) {
      throw StateError('Only the creator of a meal can edit it');
    }

    List<MealIngredient> ingredients;
    try {
      ingredients = await _cacheIngredientFoods(draft);
    } catch (error) {
      debugPrint('Bulkr: ingredients could not be cached — $error');
      ingredients = const [];
    }

    // The photo the meal keeps: a newly picked one, or the one it already had.
    final String? previousUrl = meal.imageUrl;
    String? imageUrl = draft.existingImageUrl;

    String? thumbUrl = meal.thumbUrl;

    if (imageBytes != null) {
      final UploadedImage uploaded = await _images.upload(
        ownerId: userId,
        bytes: imageBytes,
        extension: imageExtension,
      );
      imageUrl = uploaded.url;
      thumbUrl = uploaded.thumbUrl;
    } else if (imageUrl != meal.imageUrl) {
      // The photo was removed rather than replaced, so the thumbnail of the
      // one that is gone must go with it — otherwise the card falls back to a
      // small copy of a picture the meal no longer has.
      thumbUrl = null;
    }

    final Macros totals = draft.totals;

    final Map<String, dynamic> row = await _client
        .from('meals')
        .update({
          'title': draft.title.trim(),
          'description':
              draft.recipe.trim().isEmpty ? null : draft.recipe.trim(),
          'image_url': imageUrl,
          'thumb_url': thumbUrl,
          'total_calories': totals.caloriesRounded,
          'total_protein_g': totals.proteinRounded,
          'total_carbs_g': totals.carbsRounded,
          'total_fat_g': totals.fatRounded,
          'visibility': draft.visibility.dbValue,
        })
        .eq('id', meal.id)
        .eq('creator_id', userId)
        .select(_mealColumns)
        .single();

    await _replaceIngredients(mealId: meal.id, ingredients: ingredients);

    // Only once the row no longer points at it. An orphaned file costs a few
    // kilobytes; deleting one the meal still references costs the photo.
    if (previousUrl != null && previousUrl != imageUrl) {
      await _images.remove([previousUrl, meal.thumbUrl]);
    }

    return Meal.fromRow(row, currentUserId: userId).copyWith(
      isSaved: meal.isSaved,
      isFavorite: meal.isFavorite,
      savedAt: meal.savedAt,
      isLoggedToday: meal.isLoggedToday,
      ingredients: ingredients,
      totalGrams: draft.totalGrams,
    );
  }

  /// Swaps a meal's ingredient rows for a new set.
  ///
  /// Delete then insert, rather than working out which rows changed: the join
  /// row holds only a food and an amount, so there is nothing in it worth
  /// preserving, and a diff would be more code with more ways to be wrong.
  ///
  /// Non-fatal, like the insert on create. The meal's totals are on its own row
  /// and are already correct; losing the itemisation is recoverable by editing
  /// again, whereas failing here would report a save that did happen as an
  /// error.
  Future<void> _replaceIngredients({
    required String mealId,
    required List<MealIngredient> ingredients,
  }) async {
    try {
      await _client.from('meal_ingredients').delete().eq('meal_id', mealId);

      if (ingredients.isEmpty) return;

      await _client.from('meal_ingredients').insert(
            ingredients.map((i) => i.toRowValues(mealId: mealId)).toList(),
          );
    } catch (error) {
      debugPrint('Bulkr: meal updated but ingredients failed — $error');
    }
  }

  // --- Insights -------------------------------------------------------------

  /// How many days in a row this user has logged something.
  ///
  /// One integer off `logging_streak()`, rather than every date they have ever
  /// logged coming back to be counted here — a read that would grow without
  /// bound and get slower for exactly the people who use the app most.
  ///
  /// Yesterday still counts as standing: someone opening the app at nine in
  /// the morning has not broken anything yet. See the note in
  /// `tracker_insights.sql`.
  ///
  /// Zero on any failure, including the migration not having been run. A
  /// streak is an encouragement, and a missing one is an absent card rather
  /// than an error.
  Future<int> fetchStreak() async {
    if (_userId == null) return 0;

    try {
      final Object? value = await _client.rpc('logging_streak');
      if (value is int) return value;
      return int.tryParse('${value ?? ''}') ?? 0;
    } catch (error) {
      debugPrint('Bulkr: streak unavailable — $error');
      return 0;
    }
  }

  /// The last seven days, reduced to one row by `weekly_recap()`.
  ///
  /// Null on failure, which the screen shows as "not available" rather than as
  /// a week in which nothing happened — a recap of zeroes is a claim, and the
  /// wrong one.
  Future<WeeklyRecap?> fetchWeeklyRecap() async {
    if (_userId == null) return null;

    try {
      final Object? result = await _client.rpc('weekly_recap');

      // A `returns table` function comes back as a list of one.
      final Map<String, dynamic>? row = result is List
          ? result.whereType<Map<String, dynamic>>().firstOrNull
          : (result is Map<String, dynamic> ? result : null);

      if (row == null) return null;
      return WeeklyRecap.fromRow(row);
    } catch (error) {
      debugPrint('Bulkr: weekly recap unavailable — $error');
      return null;
    }
  }

  /// The meal being copied, read in full.
  ///
  /// A meal reached from the feed is missing `description` — see
  /// `PostRepository._attachedMealColumns` — so the row is re-read before its
  /// contents are written into somebody else's library.
  ///
  /// Falls back to the model in hand when the read fails. A copy without its
  /// recipe is a worse copy; a copy that did not happen because a second
  /// request timed out is no copy at all, and the totals that make it usable
  /// in the tracker are already on the model.
  Future<Meal> _fetchForCopy(Meal meal) async {
    try {
      final Map<String, dynamic> row = await _client
          .from('meals')
          .select(_mealColumns)
          .eq('id', meal.id)
          .single();

      return Meal.fromRow(row, currentUserId: _userId);
    } catch (error) {
      debugPrint('Bulkr: copying a meal without re-reading it — $error');
      return meal;
    }
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

    await _images.remove([meal.imageUrl, meal.thumbUrl]);
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
  static String? storagePathFor(String? publicUrl) =>
      ImageUploader.storagePathFor(publicUrl, bucket: imageBucket);

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

  /// Removes [meal] from today's log.
  ///
  /// Deletes every row for it today rather than the most recent one: the button
  /// is a toggle, so "off" has to mean the meal is not counted today, not
  /// "counted one time fewer". Only today — a past day's record is not this
  /// button's to touch.
  Future<void> unlogMealToday(Meal meal) async {
    final String? userId = _userId;
    if (userId == null) return;

    await _client
        .from('daily_logs')
        .delete()
        .eq('user_id', userId)
        .eq('meal_id', meal.id)
        .eq('log_date', _asDate(DateTime.now()));
  }

  /// Records one serving of [meal] against [day], in [slot].
  ///
  /// The meal's macros are copied onto the log row rather than referenced
  /// through `meal_id`, so editing or deleting the meal later cannot rewrite
  /// what the user actually ate on a past day. `item_name` is copied for the
  /// same reason: a deleted meal leaves the row with nothing to join a title
  /// from, and the log still has to be readable.
  ///
  /// [slot] may be null, and a null writes null — the tracker shows those
  /// entries in their own section. It is not defaulted from the clock here:
  /// [MealSlot.forTimeOfDay] exists for that, and belongs where the user can
  /// see the guess and change it before it is written.
  Future<void> logMeal({
    required Meal meal,
    MealSlot? slot,
    DateTime? day,
  }) async {
    final String? userId = _userId;
    if (userId == null) return;

    await _client.from('daily_logs').insert({
      'user_id': userId,
      'log_date': _asDate(day ?? DateTime.now()),
      'meal_id': meal.id,
      'meal_type': slot?.dbValue,
      'item_name': meal.title,
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

  /// Records [grams] of [food] against [day], without it becoming a meal.
  ///
  /// This is the "add food" path: someone ate a banana, and a banana is not a
  /// recipe worth keeping in a library. So no `meals` row is created — the log
  /// entry carries the name and the macros itself, and `cached_food_id` records
  /// where the nutrition came from.
  ///
  /// The food is cached first, exactly as an ingredient is. That is what gives
  /// it an id to point at, and it means a food logged once is in the app's own
  /// database for everyone's next search — the same mechanism that makes food
  /// search get faster the more it is used.
  ///
  /// A caching failure is not fatal: the entry is written with a null
  /// `cached_food_id`. Losing the provenance of an eaten banana is a much
  /// smaller problem than refusing to record it.
  Future<void> logFood({
    required FoodItem food,
    required double grams,
    MealSlot? slot,
    DateTime? day,
  }) async {
    final String? userId = _userId;
    if (userId == null) return;

    String? cachedId = food.cachedId;
    if (cachedId == null) {
      try {
        cachedId = (await _foods.ensureCached(food)).cachedId;
      } catch (error) {
        debugPrint('Bulkr: could not cache ${food.name} — $error');
      }
    }

    final Macros eaten = food.per100g.forGrams(grams);

    await _client.from('daily_logs').insert({
      'user_id': userId,
      'log_date': _asDate(day ?? DateTime.now()),
      'meal_type': slot?.dbValue,
      'cached_food_id': cachedId,
      // The brand is deliberately not folded in: `FoodItem.label` is built for
      // a search result, where telling two similar products apart matters. In
      // a day's log the name alone reads better.
      'item_name': food.name,
      'quantity_g': grams,
      'calories_logged': eaten.caloriesRounded,
      'protein_logged_g': eaten.proteinRounded,
      'carbs_logged_g': eaten.carbsRounded,
      'fat_logged_g': eaten.fatRounded,
    });
  }

  /// Everything logged on [day], in the order it should be read.
  ///
  /// The meal's live title and photo are joined so a renamed meal reads
  /// correctly, while the macros come off the log row — the row is the record
  /// of what was eaten, the join is only for presentation.
  ///
  /// The foreign key is named explicitly for the same reason [_mealColumns]
  /// does it: `daily_logs` holds keys to both `meals` and `users` and nothing
  /// else of its own, so PostgREST reads it as a junction table and a bare
  /// embed is ambiguous (PGRST201).
  Future<List<DailyLogEntry>> fetchDayLog(DateTime day) async {
    final String? userId = _userId;
    if (userId == null) return const <DailyLogEntry>[];

    final rows = await _client
        .from('daily_logs')
        .select('*, meals!daily_logs_meal_id_fkey(title, image_url)')
        .eq('user_id', userId)
        .eq('log_date', _asDate(day))
        // No time-of-day column to sort by, so the tracker groups by slot and
        // this only has to be stable. Insertion order is the closest thing to
        // the order things were eaten in.
        .order('id', ascending: true);

    return rows.map(DailyLogEntry.fromRow).toList();
  }

  /// Writes [entry] back over the row it came from.
  ///
  /// Takes a whole entry rather than the fields that changed, so the caller
  /// builds the edit with [DailyLogEntry.copyWith] or
  /// [DailyLogEntry.scaledTo] and the arithmetic stays in the model. What is
  /// sent is only what an edit can legitimately touch: the slot, the amount
  /// and the macros. `meal_id`, `cached_food_id` and `log_date` are the
  /// identity of the entry, not its contents.
  Future<void> updateLogEntry(DailyLogEntry entry) async {
    final String? userId = _userId;
    if (userId == null) return;

    await _client
        .from('daily_logs')
        .update({
          'meal_type': entry.slot?.dbValue,
          'quantity_g': entry.quantityG,
          'calories_logged': entry.macros.caloriesRounded,
          'protein_logged_g': entry.macros.proteinRounded,
          'carbs_logged_g': entry.macros.carbsRounded,
          'fat_logged_g': entry.macros.fatRounded,
        })
        .eq('id', entry.id)
        // Redundant against the RLS policy, which already scopes writes to
        // `auth.uid() = user_id`, and kept because a filter that constrains
        // the statement is worth more than one that constrains only the
        // policy: a wrong id here updates nothing instead of erroring.
        .eq('user_id', userId);
  }

  /// Copies a past day's entries onto [to].
  ///
  /// Most people eat the same five breakfasts. Re-entering Tuesday on
  /// Thursday, item by item, is the friction that makes a tracker get
  /// abandoned in week three — so this is the one action that turns a day, or
  /// one slot of it, back into rows.
  ///
  /// Returns how many entries were copied, so the caller can say so. Zero when
  /// the source day was empty, and nothing is written in that case.
  ///
  /// The copies carry the macros that were recorded then, not recomputed from
  /// today's version of the meal. A log is a record of what was eaten, and a
  /// meal whose recipe has since changed did not retroactively change what was
  /// on the plate. `meal_id` and `cached_food_id` still point where they
  /// pointed, so the entry keeps its provenance and its picture.
  ///
  /// One insert for the whole day rather than one per entry.
  Future<int> repeatDay({
    required DateTime from,
    required DateTime to,
    MealSlot? slot,
  }) async {
    final String? userId = _userId;
    if (userId == null) return 0;

    final List<DailyLogEntry> source = await fetchDayLog(from);

    final List<DailyLogEntry> wanted = slot == null
        ? source
        : source.where((entry) => entry.slot == slot).toList();

    if (wanted.isEmpty) return 0;

    await _client.from('daily_logs').insert([
      for (final DailyLogEntry entry in wanted)
        {
          'user_id': userId,
          'log_date': _asDate(to),
          'meal_id': entry.mealId,
          'cached_food_id': entry.cachedFoodId,
          // Into the same slot it came from, even when one slot was asked for
          // — copying breakfast onto a day puts it at breakfast.
          'meal_type': entry.slot?.dbValue,
          'item_name': entry.itemName,
          'quantity_g': entry.quantityG,
          'calories_logged': entry.macros.caloriesRounded,
          'protein_logged_g': entry.macros.proteinRounded,
          'carbs_logged_g': entry.macros.carbsRounded,
          'fat_logged_g': entry.macros.fatRounded,
        },
    ]);

    return wanted.length;
  }

  /// Removes one entry from the log.
  ///
  /// One row, unlike [unlogMealToday], which clears every row for a meal
  /// today. That is the difference between the tracker and the toggle on a
  /// meal card: the tracker is looking at entries, the card is looking at a
  /// meal.
  Future<void> deleteLogEntry(DailyLogEntry entry) async {
    final String? userId = _userId;
    if (userId == null) return;

    await _client
        .from('daily_logs')
        .delete()
        .eq('id', entry.id)
        .eq('user_id', userId);
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
