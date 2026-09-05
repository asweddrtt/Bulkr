part of 'tracker_cubit.dart';

enum TrackerStatus {
  initial,
  loading,

  /// The day loaded. An empty log is a ready state, not an error — most days
  /// start that way.
  ready,

  /// Authenticated, but no `users` row, so there are no targets.
  missing,

  failure,
}

class TrackerState extends Equatable {
  const TrackerState({
    required this.day,
    this.status = TrackerStatus.initial,
    this.profile,
    this.entries = const [],
    this.water = const [],
    this.errorMessage,
    this.isSaving = false,
    this.actionErrorKey,
    this.actionErrorDetail,
    this.waterErrorDetail,
  });

  /// The local day being shown, truncated to midnight. Every read and write is
  /// scoped by it, so the date strip changes this and reloads rather than
  /// there being a separate notion of "the day being browsed".
  final DateTime day;

  final TrackerStatus status;

  /// Where the targets come from — `daily_calorie_target` and the three macro
  /// columns on the user's row.
  final UserProfile? profile;

  final List<DailyLogEntry> entries;

  /// Every drink recorded on [day].
  final List<WaterEntry> water;

  final String? errorMessage;

  /// A write is in flight. Kept out of [status] so logging something never
  /// blanks the day that is already on screen.
  final bool isSaving;

  /// Translation key for a write that failed, cleared once shown.
  final String? actionErrorKey;

  /// The underlying failure, verbatim — a Postgres code and message says
  /// "row-level security policy" where a friendly string just says
  /// "try again".
  final String? actionErrorDetail;

  /// Why the day's water could not be read, if it could not. The food still
  /// loads without it — but an empty glass and a table that does not exist are
  /// not the same thing and must not look the same.
  final String? waterErrorDetail;

  bool get isLoading => status == TrackerStatus.loading;

  /// Whether [day] is the day it is now.
  ///
  /// Decides more than a heading: weighing in is today-only, and the forward
  /// arrow stops here.
  bool get isToday {
    final DateTime now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  /// Nothing logged yet on this day.
  bool get isEmpty => entries.isEmpty;

  // --- What was eaten -----------------------------------------------------

  /// The day's totals, summed from the entries rather than from a stored
  /// counter. Twelve entries is a cheap sum and a counter is one more thing
  /// that can drift away from the rows it claims to describe.
  Macros get consumed => Macros.sum(entries.map((e) => e.macros));

  /// Entries in [slot], in the order they were logged.
  List<DailyLogEntry> entriesIn(MealSlot slot) =>
      entries.where((e) => e.slot == slot).toList();

  Macros totalIn(MealSlot slot) =>
      Macros.sum(entriesIn(slot).map((e) => e.macros));

  /// Entries written before slots existed, or with a value this build does not
  /// recognise. They still count towards the day, so they still have to be
  /// shown — in their own section, which only appears when it has something in
  /// it.
  List<DailyLogEntry> get unsortedEntries =>
      entries.where((e) => e.slot == null).toList();

  Macros get unsortedTotal =>
      Macros.sum(unsortedEntries.map((e) => e.macros));

  // --- Water --------------------------------------------------------------

  /// Millilitres drunk on this day, summed from the rows.
  int get waterMl =>
      water.fold(0, (running, entry) => running + entry.millilitres);

  /// The most recent drink, which is the one undo takes back.
  WaterEntry? get lastWater => water.isEmpty ? null : water.last;

  /// The daily water goal: what the user set, or 35 ml per kg of bodyweight.
  ///
  /// The stored value wins when there is one, and null there means "derive"
  /// rather than "none" — so someone who never touched it gets a goal that
  /// moves with their weight, and someone who set one keeps it until they
  /// clear it. Null overall means neither is available: no override, and no
  /// usable weight to derive from.
  int? get waterTargetMl {
    final int? stored = profile?.waterTargetMl;
    if (stored != null && stored > 0) return stored;
    return Hydration.targetMlFor(profile?.currentWeightKg);
  }

  /// True when the goal is one the user typed rather than one derived from
  /// their weight, so the UI can offer to hand it back.
  bool get hasCustomWaterTarget => (profile?.waterTargetMl ?? 0) > 0;

  bool get hasWaterTarget => waterTargetMl != null;

  /// Progress towards the water goal, clamped for the meter. Zero when there
  /// is no goal, so an unknown target renders empty rather than full.
  double get waterProgress {
    final int? target = waterTargetMl;
    if (target == null || target <= 0) return 0;
    return (waterMl / target).clamp(0.0, 1.0);
  }

  /// Whole glasses the goal comes to, for the row of cups.
  ///
  /// Bounded so a very large goal cannot draw hundreds of them. Past the
  /// bound the cups stop being a count and become a progress bar, which is
  /// what the meter underneath is for anyway.
  int get waterGlasses {
    final int? target = waterTargetMl;
    if (target == null) return 0;
    return (target / Hydration.glassMl).round().clamp(1, maxGlassesDrawn);
  }

  static const int maxGlassesDrawn = 16;

  // --- What was aimed at --------------------------------------------------

  /// The stored calorie target, or null when there is nothing to compare
  /// against.
  ///
  /// Zero counts as absent. `UserProfile` defaults every target to 0 when the
  /// column is null, and dividing a day's intake by a goal of zero produces
  /// either infinity or a full ring on the first bite — both worse than the
  /// screen admitting it has no target.
  int? get calorieTarget {
    final int? target = profile?.dailyCalorieTarget;
    return (target == null || target <= 0) ? null : target;
  }

  bool get hasTarget => calorieTarget != null;

  /// Macro targets in grams, as a [Macros] so the same arithmetic works on
  /// both sides of the comparison.
  Macros get macroTargets => Macros(
        calories: (profile?.dailyCalorieTarget ?? 0).toDouble(),
        proteinG: (profile?.proteinTargetG ?? 0).toDouble(),
        carbsG: (profile?.carbsTargetG ?? 0).toDouble(),
        fatG: (profile?.fatTargetG ?? 0).toDouble(),
      );

  /// Calories still to eat. Negative once the target is passed, and
  /// deliberately not clamped — "budget spent" and "480 over" are different
  /// facts and the headline says which.
  int? get caloriesRemaining {
    final int? target = calorieTarget;
    if (target == null) return null;
    return target - consumed.calories.round();
  }

  bool get isOverTarget => (caloriesRemaining ?? 0) < 0;

  /// Progress towards the calorie target, clamped to 0..1 for the ring.
  ///
  /// [isOverTarget] is what tells the reader they went past it; a ring that
  /// wrapped round a second time would just look like it had barely started.
  double get calorieProgress {
    final int? target = calorieTarget;
    if (target == null) return 0;
    return (consumed.calories / target).clamp(0.0, 1.0);
  }

  /// Progress towards one macro's target, clamped the same way. Zero when that
  /// target is unset, so a missing column renders an empty bar rather than a
  /// full one.
  double progressFor(double eaten, double target) {
    if (target <= 0) return 0;
    return (eaten / target).clamp(0.0, 1.0);
  }

  TrackerState copyWith({
    DateTime? day,
    TrackerStatus? status,
    UserProfile? profile,
    List<DailyLogEntry>? entries,
    List<WaterEntry>? water,
    String? errorMessage,
    bool clearError = false,
    bool? isSaving,
    String? actionErrorKey,
    String? actionErrorDetail,
    bool clearActionError = false,
    String? waterErrorDetail,
    bool clearWaterError = false,
  }) {
    return TrackerState(
      day: day ?? this.day,
      status: status ?? this.status,
      profile: profile ?? this.profile,
      entries: entries ?? this.entries,
      water: water ?? this.water,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isSaving: isSaving ?? this.isSaving,
      actionErrorKey:
          clearActionError ? null : (actionErrorKey ?? this.actionErrorKey),
      actionErrorDetail: clearActionError
          ? null
          : (actionErrorDetail ?? this.actionErrorDetail),
      waterErrorDetail: clearWaterError
          ? null
          : (waterErrorDetail ?? this.waterErrorDetail),
    );
  }

  @override
  List<Object?> get props => [
        day,
        status,
        profile,
        entries,
        water,
        errorMessage,
        isSaving,
        actionErrorKey,
        actionErrorDetail,
        waterErrorDetail,
      ];
}
