import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/feed/feed_cubit.dart';
import '../cubit/meals/meals_cubit.dart';
import '../cubit/profile/profile_cubit.dart';
import '../cubit/tracker/tracker_cubit.dart';
import '../widgets/bulkr_nav_bar.dart';
import 'feed_screen.dart';
import 'meals_screen.dart';
import 'profile_screen.dart';
import 'tracker_screen.dart';
import 'dashboard_screen.dart';

/// Post-onboarding shell: bottom navigation over the main sections.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 2;

  static const List<NavDestination> _destinations = [
    NavDestination(Icons.dashboard_sharp, 'Dashboard'),
    NavDestination(Icons.restaurant_sharp, 'Meals'),
    NavDestination(Icons.dynamic_feed_sharp, 'Feed'),
    NavDestination(Icons.electric_bolt_sharp, 'Tracker'),
    NavDestination(Icons.person_sharp, 'profile'),
  ];

  @override
  void initState() {
    super.initState();
    // Fetched once when the shell mounts rather than on each tab switch, so
    // moving between tabs doesn't re-hit the network.
    context.read<ProfileCubit>().load();
    context.read<MealsCubit>().load();
    context.read<FeedCubit>().load();
    context.read<TrackerCubit>().load();
  }

  /// Index of the Tracker tab, which needs a nudge the others do not.
  static const int _trackerIndex = 3;

  void _select(int index) {
    setState(() => _currentIndex = index);

    // Everything here lives in an IndexedStack, so each screen is built once
    // and kept alive — which is what makes switching tabs instant, and what
    // would otherwise let the tracker show yesterday's log under today's
    // heading after the app sat in the background overnight. The cubit does
    // nothing when the day has not turned over, so this is free.
    if (index == _trackerIndex) {
      context.read<TrackerCubit>().refreshIfDayChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      // The bar floats over the content and blurs what is behind it, so there
      // has to be something behind it. Screens that scroll reserve
      // BulkrNavBar.contentInset at the bottom of their list.
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _currentIndex,
          children: const [
            DashboardScreen(),
            MealsScreen(),
            FeedScreen(),
            TrackerScreen(),
            ProfileScreen(),
          ],
        ),
      ),
      bottomNavigationBar: BulkrNavBar(
        destinations: _destinations,
        currentIndex: _currentIndex,
        onSelected: _select,
      ),
    );
  }
}
