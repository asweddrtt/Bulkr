class AppRoutes {
  const AppRoutes._();

  /// Step 1 — identity.
  static const String welcome = '/';

  /// Step 2 — biometrics.
  static const String biometrics = '/biometrics';

  /// Step 3 — activity level.
  static const String activityLevel = '/activity-level';

  /// Step 4 — target weight and pace.
  static const String targetPace = '/target-pace';

  /// Step 5 — the calculated plan and the commit.
  static const String plan = '/plan';

  /// Post-onboarding landing (currently a placeholder).
  static const String home = '/home';
}
