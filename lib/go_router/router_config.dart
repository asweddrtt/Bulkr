import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_repository.dart';
import '../screens/activity_level_screen.dart';
import '../screens/biometrics_screen.dart';
import '../screens/home_screen.dart';
import '../screens/plan_reveal_screen.dart';
import '../screens/target_pace_screen.dart';
import '../screens/welcome_screen.dart';
import 'app_routes.dart';

class AppRouter {
  const AppRouter._();

  static GoRouter build({required AuthRepository authRepository}) {
    return GoRouter(
      initialLocation: AppRoutes.welcome,
      debugLogDiagnostics: true,

      // Steps 2-5 assume a session and in-memory onboarding answers. Without
      // the session there is nothing to attach the data to, so send the user
      // back to sign-in rather than letting them walk a flow that can't be
      // saved. This also makes a hot restart mid-flow behave predictably.
      redirect: (context, state) {
        final isSigningIn = state.matchedLocation == AppRoutes.welcome;
        if (!authRepository.hasSession && !isSigningIn) {
          return AppRoutes.welcome;
        }
        return null;
      },

      routes: [
        GoRoute(
          path: AppRoutes.welcome,
          builder: (context, state) => const WelcomeScreen(),
        ),
        GoRoute(
          path: AppRoutes.biometrics,
          builder: (context, state) => const BiometricsScreen(),
        ),
        GoRoute(
          path: AppRoutes.activityLevel,
          builder: (context, state) => const ActivityLevelScreen(),
        ),
        GoRoute(
          path: AppRoutes.targetPace,
          builder: (context, state) => const TargetPaceScreen(),
        ),
        GoRoute(
          path: AppRoutes.plan,
          builder: (context, state) => const PlanRevealScreen(),
        ),
        GoRoute(
          path: AppRoutes.home,
          builder: (context, state) => const HomeScreen(),
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
