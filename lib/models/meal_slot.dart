/// Which part of the day a log entry belongs to — `daily_logs.meal_type`.
///
/// Four slots rather than a free-text label, because the tracker groups the
/// day by them and renders a subtotal per group: an open-ended field would
/// mean an open-ended number of sections.
///
/// [fromDbValue] returns null rather than throwing, unlike [Gender.fromDbValue]
/// and [ActivityLevel.fromDbValue]. Those read columns that onboarding always
/// writes, so an unrecognised value there is a bug worth surfacing. This one
/// reads a column that is nullable and *was* left null by every row written
/// before slots existed — an unslotted entry is ordinary history, not
/// corruption, and it still has to appear in the day's total.
enum MealSlot {
  breakfast('breakfast', 'slot_breakfast'),
  lunch('lunch', 'slot_lunch'),
  dinner('dinner', 'slot_dinner'),
  snack('snack', 'slot_snack');

  const MealSlot(this.dbValue, this.labelKey);

  /// Exact value stored in `daily_logs.meal_type`.
  final String dbValue;

  /// easy_localization key for the section heading.
  final String labelKey;

  /// The slot [value] names, or null when it names none.
  ///
  /// Null covers three cases the tracker treats identically: the column was
  /// never set, it holds something this build does not know about, and it
  /// holds a value from a future version of the app.
  static MealSlot? fromDbValue(Object? value) {
    if (value == null) return null;
    final String raw = '$value'.trim().toLowerCase();
    for (final MealSlot slot in values) {
      if (slot.dbValue == raw) return slot;
    }
    return null;
  }

  /// The slot a meal eaten now most likely belongs to.
  ///
  /// Only ever a default the user can change before it is written — never
  /// applied silently.
  ///
  /// The day starts at 04:00, not at midnight. Someone eating at 2am is
  /// finishing the previous evening, not starting the next morning, and
  /// calling that breakfast is wrong in the one case — a night shift, a late
  /// night — where it actually comes up.
  static MealSlot forTimeOfDay(DateTime when) {
    final int hour = when.hour;
    if (hour < 4) return snack;
    if (hour < 11) return breakfast;
    if (hour < 16) return lunch;
    if (hour < 22) return dinner;
    return snack;
  }
}
