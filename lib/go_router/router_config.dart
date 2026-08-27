import 'package:bulkr/screens/main_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/app_preferences.dart';
import '../data/auth_repository.dart';
import '../screens/activity_level_screen.dart';
import '../screens/biometrics_screen.dart';
import '../screens/plan_reveal_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/target_pace_screen.dart';
import '../screens/welcome_screen.dart';
import '../widgets/animations/motion.dart';
import 'app_routes.dart';

/// Directional slide + fade between onboarding steps.
///
/// The incoming screen enters from the right while the outgoing one drifts
/// slightly left, which reads as one continuous flow rather than five
/// unrelated screens. Going back reverses it, so the gesture and the motion
/// agree about which way through the flow you're moving.
///
/// Built with `animation.drive(...)` rather than CurvedAnimation because
/// transitionsBuilder runs every frame, and a CurvedAnimation allocated there
/// would need disposing.
CustomTransitionPage<void> _stepTransition(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: Motion.base,
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (Motion.reduced(context)) return child;

      final incoming = animation.drive(
        Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero)
            .chain(CurveTween(curve: Motion.enter)),
      );
      final fade = animation.drive(CurveTween(curve: Motion.enter));

      // Small counter-move on the screen being covered — enough to suggest
      // depth without it looking like two screens racing each other.
      final outgoing = secondaryAnimation.drive(
        Tween<Offset>(begin: Offset.zero, end: const Offset(-0.03, 0))
            .chain(CurveTween(curve: Motion.enter)),
      );

      return SlideTransition(
        position: outgoing,
        child: SlideTransition(
          position: incoming,
          child: FadeTransition(opacity: fade, child: child),
        ),
      );
    },
  );
}

class AppRouter {
  const AppRouter._();

  static GoRouter build({
    required AuthRepository authRepository,
    required AppPreferences preferences,
  }) {
    return GoRouter(
      initialLocation: AppRoutes.splash,
      debugLogDiagnostics: true,

      // Steps 2-5 assume a session and in-memory onboarding answers. Without
      // the session there is nothing to attach the data to, so send the user
      // back to sign-in rather than letting them walk a flow that can't be
      // saved. This also makes a hot restart mid-flow behave predictably.
      redirect: (context, state) {
        // Splash is exempt as well as the sign-in screen: it is what decides
        // where a session goes, and bouncing it to sign-in would defeat the
        // point of having one.
        final location = state.matchedLocation;
        final isEntry =
            location == AppRoutes.welcome || location == AppRoutes.splash;

        if (!authRepository.hasSession && !isEntry) {
          return AppRoutes.welcome;
        }
        return null;
      },

      routes: [
        GoRoute(
          path: AppRoutes.splash,
          builder: (context, state) => SplashScreen(
            authRepository: authRepository,
            preferences: preferences,
          ),
        ),
        GoRoute(
          path: AppRoutes.welcome,
          builder: (context, state) => const WelcomeScreen(),
        ),
        GoRoute(
          path: AppRoutes.biometrics,
          pageBuilder: (context, state) =>
              _stepTransition(state, const BiometricsScreen()),
        ),
        GoRoute(
          path: AppRoutes.activityLevel,
          pageBuilder: (context, state) =>
              _stepTransition(state, const ActivityLevelScreen()),
        ),
        GoRoute(
          path: AppRoutes.targetPace,
          pageBuilder: (context, state) =>
              _stepTransition(state, const TargetPaceScreen()),
        ),
        GoRoute(
          path: AppRoutes.plan,
          pageBuilder: (context, state) =>
              _stepTransition(state, const PlanRevealScreen()),
        ),
        GoRoute(
          path: AppRoutes.home,
          pageBuilder: (context, state) =>
              _stepTransition(state, const MainScreen()),
        ),
      ],

      errorBuilder: (context, state) => Scaffold(
        body: Center(
          child: Text('Route not found: ${state.uri}'),
        ),
      ),
    );
  }
}
