import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../cubit/feed/feed_cubit.dart';
import '../cubit/meals/meals_cubit.dart';
import '../cubit/profile/profile_cubit.dart';
import '../cubit/tracker/tracker_cubit.dart';
import '../styles/app_color.dart';
import '../widgets/animations/motion.dart';
import '../widgets/animations/press_scale.dart';
import 'feed_screen.dart';
import 'meals_screen.dart';
import 'profile_screen.dart';
import 'tracker_screen.dart';
import 'dashboard_screen.dart';

const Color _textMuted = Color(0xFF9CA3AF);

/// Post-onboarding shell: bottom navigation over the main sections.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 2;

  static const List<_NavDestination> _destinations = [
    _NavDestination(Icons.dashboard_sharp, 'Dashboard'),
    _NavDestination(Icons.restaurant_sharp, 'Meals'),
    _NavDestination(Icons.dynamic_feed_sharp, 'Feed'),
    _NavDestination(Icons.electric_bolt_sharp, 'Tracker'),
    _NavDestination(Icons.person_sharp, 'profile'),

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
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      color: const Color(0xFF0A0A0A),
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (var i = 0; i < _destinations.length; i++)
              _buildNavItem(i, _destinations[i]),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, _NavDestination destination) {
    final isSelected = _currentIndex == index;

    return PressScale(
      child: GestureDetector(
        onTap: () => _select(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: Motion.scaled(context, Motion.fast),
          curve: Motion.enter,
          padding: EdgeInsets.symmetric(
            horizontal: isSelected ? 20.w : 12.w,
            vertical: isSelected ? 8.h : 4.h,
          ),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryNeon : Colors.transparent,
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                destination.icon,
                color: isSelected ? Colors.black : _textMuted,
                size: 22.sp ,
              ),
              SizedBox(height: 4.h),
              Text(
                destination.labelKey.tr(),
                style: GoogleFonts.inter(
                  color: isSelected ? Colors.black : _textMuted,
                  fontSize: 9.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class _NavDestination {
  const _NavDestination(this.icon, this.labelKey);

  final IconData icon;
  final String labelKey;
}
