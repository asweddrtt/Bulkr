import 'package:bulkr/screens/baseline_screen.dart';
import 'package:bulkr/screens/calorie_goal_screen.dart';
import 'package:bulkr/screens/define_surplus_screen.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/activity_level.dart';
import 'app_routes.dart';

// Import your screens here
import '../../screens/welcome_screen.dart'; // Adjust import paths

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.welcome,
    debugLogDiagnostics: true,

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
      builder : (context, state) => const CalorieGoalScreen())

    ],

    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Route not found: ${state.uri.toString()}'),
      ),
    ),
  );
}