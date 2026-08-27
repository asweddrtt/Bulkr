class AppRoutes {
  const AppRoutes._();

  /// Launch. Decides between sign-in, onboarding and the app, then replaces
  /// itself — see [SplashScreen] for why that decision cannot be a redirect.
  static const String splash = '/';

  /// Step 1 — identity.
  static const String welcome = '/welcome';

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
