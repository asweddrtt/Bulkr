import 'package:equatable/equatable.dart';

import 'macros.dart';
import 'meal_slot.dart';

/// One row of `daily_logs` — a single thing eaten on a single day.
///
/// Two kinds of row share this type, and the difference is [mealId]:
///
///   * a **meal** from the library, logged whole. [mealId] points at it, so
///     the entry can offer "open the meal" and can show its photo.
///   * a **one-off food**, searched and logged without ever becoming a meal.
///     [mealId] is null and [cachedFoodId] points at the `cached_off_foods`
///     row the nutrition came from.
///
/// In both cases the macros on this row are the authority, not the meal's
/// current totals. `daily_logs` carries its own copy precisely so that editing
/// or deleting a meal cannot rewrite what someone ate last Tuesday — the
/// reason the foreign key is ON DELETE SET NULL rather than a cascade. Which
/// also means [mealId] can be null for a *meal* entry, when the meal it
/// referred to has since been deleted; [itemName] is what keeps that row
/// readable.
class DailyLogEntry extends Equatable {
  const DailyLogEntry({
    required this.id,
    required this.logDate,
    required this.macros,
    this.slot,
    this.mealId,
    this.cachedFoodId,
    this.itemName,
    this.mealTitle,
    this.mealImageUrl,
    this.quantityG = 0,
  });

  /// `daily_logs.id`. The handle for editing or deleting this one entry —
  /// without it the only available granularity is "everything for this meal
  /// today", which is what the meals-screen toggle does.
  final String id;

  /// The local day this was eaten, from the DATE column. Time-of-day is not
  /// recorded: the slot is what the day is divided by.
  final DateTime logDate;

  /// The figures the tracker sums. Held as doubles like everywhere else, even
  /// though the columns are integers, so a day of twelve entries doesn't drift
  /// from re-rounding at each step.
  final Macros macros;

  /// Null for rows written before slots existed. The tracker shows those in
  /// their own section rather than guessing which meal they were.
  final MealSlot? slot;

  final String? mealId;
  final String? cachedFoodId;

  /// What was eaten, copied onto the row when it was written.
  ///
  /// Written for library meals as well as one-off foods, which looks redundant
  /// next to [mealTitle] and is not: a row whose meal has been deleted has no
  /// title left to join to, and "you ate 640 kcal of something" is a worse
  /// record than the schema can support.
  final String? itemName;

  /// Joined live from `meals`, so a renamed meal reads correctly in the log.
  /// Null for a one-off food and for a meal since deleted.
  final String? mealTitle;
  final String? mealImageUrl;

  /// Grams eaten, when known. Zero means "not recorded" rather than nothing —
  /// meals assembled without ingredient weights have no total to state.
  final double quantityG;

  /// Whether this entry came from a library meal rather than a loose food.
  ///
  /// Reads [cachedFoodId] rather than [mealId] because a deleted meal leaves
  /// [mealId] null on a row that is still, historically, a meal.
  bool get isMeal => cachedFoodId == null;

  /// True when the meal behind this entry is gone, so the UI can stop offering
  /// to open it.
  bool get mealWasDeleted => isMeal && mealId == null;

  /// The best name available, preferring the live title so a rename shows up.
  String? get displayName {
    for (final String? candidate in [mealTitle, itemName]) {
      final String? trimmed = candidate?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  /// Whether a grams figure is worth showing next to the name.
  bool get hasQuantity => quantityG > 0;

  /// Whether the amount can be changed and have the macros follow.
  ///
  /// False for an entry logged with no weight — a meal assembled without
  /// ingredient weights has nothing to scale *from*, and inventing a basis
  /// would silently rewrite the calories. Those entries can still be moved
  /// between slots or deleted.
  bool get canRescale => quantityG > 0;

  /// This entry at a different weight, with the macros scaled to match.
  ///
  /// The scaling is done from what is stored rather than by re-reading the
  /// food's per-100g figures, so an edit cannot pull in a number that has
  /// changed in Open Food Facts since the entry was written. The row stays its
  /// own record.
  ///
  /// Returns this entry unchanged when there is no basis to scale from, so a
  /// caller that forgot to check [canRescale] cannot zero someone's calories.
  DailyLogEntry scaledTo(double grams) {
    if (!canRescale || grams <= 0) return this;
    return copyWith(
      quantityG: grams,
      macros: macros.scaledBy(grams / quantityG),
    );
  }

  DailyLogEntry copyWith({
    MealSlot? slot,
    Macros? macros,
    double? quantityG,
  }) {
    return DailyLogEntry(
      id: id,
      logDate: logDate,
      macros: macros ?? this.macros,
      slot: slot ?? this.slot,
      mealId: mealId,
      cachedFoodId: cachedFoodId,
      itemName: itemName,
      mealTitle: mealTitle,
      mealImageUrl: mealImageUrl,
      quantityG: quantityG ?? this.quantityG,
    );
  }

  /// A `daily_logs` row, with `meals` optionally embedded.
  ///
  /// Forgiving in the same way [Meal.fromRow] is: every field is optional in
  /// practice because a row written by an older build, or one whose meal has
  /// been deleted, is still a row the day's total has to include.
  factory DailyLogEntry.fromRow(Map<String, dynamic> row) {
    final Map<String, dynamic>? meal = _embedded(row['meals']);

    return DailyLogEntry(
      id: '${row['id']}',
      logDate: _parseDate(row['log_date']),
      macros: Macros(
        calories: parseGrams(row['calories_logged']),
        proteinG: parseGrams(row['protein_logged_g']),
        carbsG: parseGrams(row['carbs_logged_g']),
        fatG: parseGrams(row['fat_logged_g']),
      ),
      slot: MealSlot.fromDbValue(row['meal_type']),
      mealId: row['meal_id'] as String?,
      cachedFoodId: row['cached_food_id'] as String?,
      itemName: row['item_name'] as String?,
      mealTitle: meal?['title'] as String?,
      mealImageUrl: meal?['image_url'] as String?,
      quantityG: parseGrams(row['quantity_g']),
    );
  }

  /// A DATE column arrives as `yyyy-MM-dd` with no zone. Parsed as a local
  /// date, because that is what it means: the day the user was having.
  static DateTime _parseDate(Object? raw) {
    final DateTime? parsed = DateTime.tryParse('${raw ?? ''}');
    if (parsed == null) return DateTime.now();
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  /// A to-one embed arrives as an object, or as a single-element list when the
  /// planner cannot tell. Same helper as [MealRepository._embedded].
  static Map<String, dynamic>? _embedded(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is List && value.isNotEmpty) {
      final Object? first = value.first;
      if (first is Map<String, dynamic>) return first;
    }
    return null;
  }

  @override
  List<Object?> get props => [
        id,
        logDate,
        macros,
        slot,
        mealId,
        cachedFoodId,
        itemName,
        mealTitle,
        mealImageUrl,
        quantityG,
      ];
}
