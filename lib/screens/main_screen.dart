import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/conversations/conversations_cubit.dart';
import '../cubit/feed/feed_cubit.dart';
import '../cubit/notifications/notifications_cubit.dart';
import '../data/push_service.dart';
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

  /// The five tabs, in order.
  ///
  /// Public so a test can check that every label is a key the translations
  /// actually carry. Four of these used to be the English word itself, which
  /// easy_localization renders by handing back the key it could not find — so
  /// the bar read correctly in English and read English in every other locale,
  /// silently, with nothing to notice unless you switched language.
  static const List<NavDestination> destinations = [
    NavDestination(Icons.dashboard_sharp, 'nav_dashboard'),
    NavDestination(Icons.restaurant_sharp, 'nav_meals'),
    NavDestination(Icons.dynamic_feed_sharp, 'nav_feed'),
    NavDestination(Icons.electric_bolt_sharp, 'nav_tracker'),
    NavDestination(Icons.person_sharp, 'nav_profile'),
  ];

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 2;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Asked for here rather than at launch. A notification permission prompt
    // on first open, before anyone has seen what the app is, is the one most
    // reliably denied — and on iOS a denial is close to permanent, since the
    // app cannot ask a second time.
    context.read<PushService>().signIn();

    // Fetched once when the shell mounts rather than on each tab switch, so
    // moving between tabs doesn't re-hit the network.
    context.read<ProfileCubit>().load();
    context.read<MealsCubit>().load();
    context.read<FeedCubit>().load();
    context.read<TrackerCubit>().load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Two things that go stale while the app is not being looked at.
  ///
  /// Coming back is the moment they matter and the moment nobody minds a
  /// request, so this is where they are caught rather than on a timer. A timer
  /// would be asking a server the same two questions all day for a user who is
  /// not there — the pattern that makes a small app expensive to run.
  ///
  /// Both are cheap and neither blanks anything: the unread count is one call
  /// that only moves a dot, and the tracker returns immediately unless the day
  /// has actually turned over.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    context.read<ConversationsCubit>().refresh();
    context.read<NotificationsCubit>().refreshBadge();
    context.read<TrackerCubit>().refreshIfDayChanged();
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
        destinations: MainScreen.destinations,
        currentIndex: _currentIndex,
        onSelected: _select,
      ),
    );
  }
}
