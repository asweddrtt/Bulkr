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
    this.errorMessage,
    this.isSaving = false,
    this.actionErrorKey,
    this.actionErrorDetail,
  });

  /// The local day being shown, truncated to midnight. Always today in this
  /// slice; the field exists because every read and write is already scoped by
  /// it, so browsing another day is a change of state rather than of shape.
  final DateTime day;

  final TrackerStatus status;

  /// Where the targets come from — `daily_calorie_target` and the three macro
  /// columns on the user's row.
  final UserProfile? profile;

  final List<DailyLogEntry> entries;
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

  bool get isLoading => status == TrackerStatus.loading;

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
    String? errorMessage,
    bool clearError = false,
    bool? isSaving,
    String? actionErrorKey,
    String? actionErrorDetail,
    bool clearActionError = false,
  }) {
    return TrackerState(
      day: day ?? this.day,
      status: status ?? this.status,
      profile: profile ?? this.profile,
      entries: entries ?? this.entries,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isSaving: isSaving ?? this.isSaving,
      actionErrorKey:
          clearActionError ? null : (actionErrorKey ?? this.actionErrorKey),
      actionErrorDetail: clearActionError
          ? null
          : (actionErrorDetail ?? this.actionErrorDetail),
    );
  }

  @override
  List<Object?> get props => [
        day,
        status,
        profile,
        entries,
        errorMessage,
        isSaving,
        actionErrorKey,
        actionErrorDetail,
      ];
}
