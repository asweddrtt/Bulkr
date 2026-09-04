import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../cubit/feed/feed_cubit.dart';
import '../cubit/meals/meals_cubit.dart';
import '../cubit/profile/profile_cubit.dart';
import '../styles/app_color.dart';
import '../widgets/animations/motion.dart';
import '../widgets/animations/press_scale.dart';
import 'feed_screen.dart';
import 'meals_screen.dart';
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
            _ComingSoon(labelKey: 'Tracker'),
            _ComingSoon(labelKey: 'Profile'),
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
        onTap: () => setState(() => _currentIndex = index),
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

/// Placeholder for the sections that don't exist yet. Says so plainly rather
/// than showing an empty screen that looks broken.
class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.labelKey});

  final String labelKey;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            labelKey.tr().toUpperCase(),
            style: GoogleFonts.anton(
              color: Colors.white,
              fontSize: 22.sp,
              letterSpacing: 1.5,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'section_coming_soon'.tr(),
            style: GoogleFonts.inter(
              color: _textMuted,
              fontSize: 12.sp,
            ),
          ),
        ],
      ),
    );
  }
}
