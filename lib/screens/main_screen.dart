import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 3; // Defaulting to Profile for testing

  final List<Widget> _screens = [
    Center(child: Text('dashboard'.tr(), style: const TextStyle(color: Colors.white))),
    Center(child: Text('workouts'.tr(), style: const TextStyle(color: Colors.white))),
    Center(child: Text('progress'.tr(), style: const TextStyle(color: Colors.white))),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
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
            _buildNavItem(0, Icons.grid_view_rounded, 'dashboard'.tr()),
            _buildNavItem(1, Icons.fitness_center_rounded, 'workouts'.tr()),
            _buildNavItem(2, Icons.insights_rounded, 'progress'.tr()),
            _buildNavItem(3, Icons.person, 'profile'.tr()),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    const accentColor = Color(0xFFCBF026);
    const textMuted = Color(0xFF9CA3AF);

    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 20.w : 12.w,
          vertical: isSelected ? 8.h : 4.h,
        ),
        decoration: isSelected
            ? BoxDecoration(
          color: accentColor,
          borderRadius: BorderRadius.circular(8.r),
        )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: isSelected ? Colors.black : textMuted, size: 22.sp),
            SizedBox(height: 4.h),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : textMuted,
                fontSize: 9.sp,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}