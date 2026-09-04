part of 'onboarding_cubit.dart';

enum SubmissionStatus { idle, submitting, success, failure }

/// Result of the best-effort username lookup on screen 2.
///
/// [unknown] is the honest default: depending on the RLS policy on `users`,
/// this client may not be able to see other people's rows at all. The unique
/// constraint on insert is what actually decides.
enum UsernameAvailability { unknown, checking, available, taken }

/// Everything gathered across screens 1-5. Held above the router so it
/// survives navigation between steps.
class OnboardingState extends Equatable {
  const OnboardingState({
    this.userId,
    this.displayName,
    this.avatarUrl,
    this.username = '',
    this.usernameWasEdited = false,
    this.usernameAvailability = UsernameAvailability.unknown,
    this.unitSystem = UnitSystem.metric,
    this.gender,
    this.dateOfBirth,
    this.heightCm = defaultHeightCm,
    this.currentWeightKg = defaultWeightKg,
    this.activityLevel = ActivityLevel.moderatelyActive,
    this.targetWeightKg,
    this.weeklyGainKg = defaultWeeklyGainKg,
    this.submission = SubmissionStatus.idle,
    this.submissionAttempt = 0,
    this.errorMessage,
  });

  static const double defaultHeightCm = 175;
  static const double defaultWeightKg = 75;

  /// Opens on the conservative end of the lean-bulk range.
  static const double defaultWeeklyGainKg = 0.25;

  /// How much above current weight the target defaults to, before the user
  /// touches the picker on screen 4.
  static const double defaultTargetOffsetKg = 5;

  // --- Screen 1: identity -------------------------------------------------
  final String? userId;
  final String? displayName;
  final String? avatarUrl;

  // --- Screen 2: biometrics ----------------------------------------------
  final String username;
  final bool usernameWasEdited;
  final UsernameAvailability usernameAvailability;
  final UnitSystem unitSystem;
  final Gender? gender;
  final DateTime? dateOfBirth;
  final double heightCm;
  final double currentWeightKg;

  // --- Screen 3: lifestyle ------------------------------------------------
  final ActivityLevel activityLevel;

  // --- Screen 4: goal -----------------------------------------------------
  final double? targetWeightKg;

  /// Temporary: drives the calorie surplus, never persisted (no column).
  final double weeklyGainKg;

  // --- Screen 5: commit ---------------------------------------------------
  final SubmissionStatus submission;

  /// How many times the final commit has been attempted.
  ///
  /// Only exists to make repeated failures distinguishable. Two taps that fail
  /// the same way produce equal states, and Cubit swallows an emit equal to
  /// the current state — without a counter the screen would report the first
  /// failure and go quiet for every one after it.
  final int submissionAttempt;

  final String? errorMessage;

  /// Falls back to a sensible target rather than forcing the user to set one
  /// before the slider means anything.
  double get effectiveTargetWeightKg =>
      targetWeightKg ?? currentWeightKg + defaultTargetOffsetKg;

  int? get age => dateOfBirth == null
      ? null
      : CalorieEngine.ageFromDateOfBirth(dateOfBirth!);

  /// A `taken` result blocks progress; `unknown` does not, because it usually
  /// means the check couldn't run rather than that anything is wrong.
  bool get isBiometricsComplete =>
      gender != null &&
      dateOfBirth != null &&
      UsernameGenerator.isValid(username) &&
      usernameAvailability != UsernameAvailability.taken;

  bool get isGoalComplete => effectiveTargetWeightKg > currentWeightKg;

  /// True once the pace exceeds what usually stays lean, so screen 4 can warn.
  bool get exceedsLeanBulkPace =>
      weeklyGainKg > CalorieEngine.leanBulkCeilingKgPerWeek;

  /// Calories to add per day at the chosen pace.
  int get dailySurplus => CalorieEngine.dailySurplus(weeklyGainKg).round();

  /// The reveal on screen 5. Null until screens 2-3 have what the maths needs.
  NutritionPlan? get nutritionPlan {
    final currentGender = gender;
    final currentAge = age;
    if (currentGender == null || currentAge == null) return null;

    return CalorieEngine.buildPlan(
      gender: currentGender,
      weightKg: currentWeightKg,
      heightCm: heightCm,
      age: currentAge,
      activityLevel: activityLevel,
      weeklyGainKg: weeklyGainKg,
    );
  }

  OnboardingState copyWith({
    String? userId,
    String? displayName,
    String? avatarUrl,
    String? username,
    bool? usernameWasEdited,
    UsernameAvailability? usernameAvailability,
    UnitSystem? unitSystem,
    Gender? gender,
    DateTime? dateOfBirth,
    double? heightCm,
    double? currentWeightKg,
    ActivityLevel? activityLevel,
    double? targetWeightKg,
    double? weeklyGainKg,
    SubmissionStatus? submission,
    int? submissionAttempt,
    String? errorMessage,
    bool clearError = false,
  }) {
    return OnboardingState(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      username: username ?? this.username,
      usernameWasEdited: usernameWasEdited ?? this.usernameWasEdited,
      usernameAvailability: usernameAvailability ?? this.usernameAvailability,
      unitSystem: unitSystem ?? this.unitSystem,
      gender: gender ?? this.gender,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      heightCm: heightCm ?? this.heightCm,
      currentWeightKg: currentWeightKg ?? this.currentWeightKg,
      activityLevel: activityLevel ?? this.activityLevel,
      targetWeightKg: targetWeightKg ?? this.targetWeightKg,
      weeklyGainKg: weeklyGainKg ?? this.weeklyGainKg,
      submission: submission ?? this.submission,
      submissionAttempt: submissionAttempt ?? this.submissionAttempt,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => [
        userId,
        displayName,
        avatarUrl,
        username,
        usernameWasEdited,
        usernameAvailability,
        unitSystem,
        gender,
        dateOfBirth,
        heightCm,
        currentWeightKg,
        activityLevel,
        targetWeightKg,
        weeklyGainKg,
        submission,
        submissionAttempt,
        errorMessage,
      ];
}
