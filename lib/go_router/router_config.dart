import 'package:bulkr/screens/baseline_screen.dart';
import 'package:bulkr/screens/calorie_goal_screen.dart';
import 'package:bulkr/screens/define_surplus_screen.dart';
import 'package:bulkr/screens/profile_screen.dart';
import 'package:bulkr/screens/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/activity_level.dart';
import '../state/profile_controller.dart';
import 'app_routes.dart';

// Import your screens here

class AppRouter {
  /// Routes are guarded by the signed-in athlete's state: the welcome screen
  /// is only for signed-out users, the profile only for onboarded ones.
  static GoRouter build(ProfileController controller) {
    return GoRouter(
      initialLocation: AppRoutes.welcome,
      debugLogDiagnostics: true,
      refreshListenable: controller,

      redirect: (context, state) {
        final String location = state.matchedLocation;

        if (!controller.isSignedIn) {
          return location == AppRoutes.welcome ? null : AppRoutes.welcome;
        }
        if (location == AppRoutes.welcome) {
          return controller.isOnboardingComplete
              ? AppRoutes.profile
              : AppRoutes.baseline;
        }
        if (location == AppRoutes.profile && !controller.isOnboardingComplete) {
          return AppRoutes.baseline;
        }
        return null;
      },

      routes: [
        GoRoute(
          path: AppRoutes.welcome,
          builder: (context, state) => const WelcomeScreen(),
        ),
        GoRoute(
          path: AppRoutes.activityLevel,
          builder: (context, state) => const ActivityLevelScreen(),
        ),
        GoRoute(path: AppRoutes.baseline,
        builder : (context, state) => const BaselineScreen()
        ),
        GoRoute(path: AppRoutes.surplus,
        builder : (context, state) => const DefineSurplusScreen()
        ),
        GoRoute(path: AppRoutes.calorieGoal,
        builder : (context, state) => const CalorieGoalScreen()
        ),
        GoRoute(path: AppRoutes.profile,
        builder : (context, state) => const ProfileScreen())

      ],

      errorBuilder: (context, state) => Scaffold(
        body: Center(
          child: Text('Route not found: ${state.uri.toString()}'),
        ),
      ),
    );
  }
}
