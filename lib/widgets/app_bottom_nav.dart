import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';

/// Main app tabs. Only the profile tab has a destination so far, the other
/// entries stay inert until their screens land.
enum AppTab { dashboard, workouts, progress, profile }

class AppBottomNav extends StatelessWidget {
  final AppTab currentTab;
  final ValueChanged<AppTab> onTabSelected;

  const AppBottomNav({
    super.key,
    required this.currentTab,
    required this.onTabSelected,
  });

  static const Map<AppTab, IconData> _icons = {
    AppTab.dashboard: Icons.grid_view,
    AppTab.workouts: Icons.fitness_center,
    AppTab.progress: Icons.show_chart,
    AppTab.profile: Icons.person,
  };

  static const Map<AppTab, String> _labelKeys = {
    AppTab.dashboard: 'nav_dashboard',
    AppTab.workouts: 'nav_workouts',
    AppTab.progress: 'nav_progress',
    AppTab.profile: 'nav_profile',
  };

  Widget _buildTab(AppTab tab) {
    final bool isSelected = tab == currentTab;

    return Expanded(
      child: GestureDetector(
        onTap: () => onTabSelected(tab),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 10.h),
          color: isSelected ? AppColors.primaryNeon : Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _icons[tab],
                size: 20.sp,
                color: isSelected ? Colors.black : AppColors.textGray,
              ),
              SizedBox(height: 4.h),
              Text(
                _labelKeys[tab]!.tr().toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 8.sp,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.black : AppColors.textGray,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.navBar,
        border: Border(top: BorderSide(color: AppColors.darkBorder)),
      ),
      child: SafeArea(
        top: false,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: AppTab.values.map(_buildTab).toList(),
          ),
        ),
      ),
    );
  }
}
