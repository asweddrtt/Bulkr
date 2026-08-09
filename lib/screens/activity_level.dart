import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../go_router/app_routes.dart';
import '../styles/app_color.dart';
import '../widgets/activity_level_card.dart';

class ActivityLevelScreen extends StatefulWidget {
  const ActivityLevelScreen({super.key});

  @override
  State<ActivityLevelScreen> createState() => _ActivityLevelScreenState();
}

class _ActivityLevelScreenState extends State<ActivityLevelScreen> {
  int _selectedIndex = 2; // Defaults to "Moderately Active"


  Widget _buildProgressIndicator() {
    Widget dot(bool isActive) {
      return Container(
        margin: EdgeInsets.symmetric(horizontal: 4.w),
        width: isActive ? 24.w : 6.w,
        height: 6.h,
        decoration: BoxDecoration(
          color: isActive ? AppColors.primaryNeon : const Color(0xFF333333),
          borderRadius: BorderRadius.circular(10.r),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot(false),
        dot(false),
        dot(true), // 3rd step active
        dot(false),
        dot(false),
      ],
    );
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.png'),
            fit: BoxFit.fill,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              SizedBox(height: 15.h),
              _buildProgressIndicator(),
              SizedBox(height: 10.h),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 0.h),
                  children: [
                    Text(
                    'activity_level_title'.tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.anton(
                  fontSize: 30.sp, // Reduced from 36
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
            SizedBox(height: 8.h), // Reduced from 12
            Text(
              'activity_level_subtitle'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14.sp, // Reduced from 16
                fontWeight: FontWeight.w500,
                color: AppColors.offWhiteMuted,
                height: 1.4, // Tighter line height
              ),
            ),
            SizedBox(height: 20.h),

                    // --- ACTIVITY CARDS ---
                    ActivityLevelCard(
                      icon: Icons.chair_outlined,
                      title: 'sedentary_title'.tr(),
                      description: 'sedentary_desc'.tr(),
                      isSelected: _selectedIndex == 0,
                      onTap: () => setState(() => _selectedIndex = 0),
                    ),
                    ActivityLevelCard(
                      icon: Icons.directions_walk,
                      title: 'lightly_active_title'.tr(),
                      description: 'lightly_active_desc'.tr(),
                      isSelected: _selectedIndex == 1,
                      onTap: () => setState(() => _selectedIndex = 1),
                    ),
                    ActivityLevelCard(
                      icon: Icons.directions_run,
                      title: 'moderately_active_title'.tr(),
                      description: 'moderately_active_desc'.tr(),
                      isSelected: _selectedIndex == 2,
                      onTap: () => setState(() => _selectedIndex = 2),
                    ),
                    ActivityLevelCard(
                      icon: Icons.fitness_center,
                      title: 'very_active_title'.tr(),
                      description: 'very_active_desc'.tr(),
                      isSelected: _selectedIndex == 3,
                      onTap: () => setState(() => _selectedIndex = 3),
                    ),
                  ],
                ),
              ),

              // --- FOOTER SECTION ---
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 0.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [

                    // Back Button
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => context.pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white, width: 1.5),
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.arrow_back, size: 20.sp),
                            SizedBox(width: 8.w),
                            Text(
                              'back_btn'.tr().toUpperCase(),
                              style: GoogleFonts.anton(
                                fontSize: 20.sp,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 12.h),

                    // Continue Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          context.push(AppRoutes.surplus);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryNeon,
                          foregroundColor: Colors.black,
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'continue_btn'.tr(),
                              style: GoogleFonts.anton(
                                fontSize: 20.sp,
                                letterSpacing: 1,
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Icon(Icons.arrow_forward, size: 20.sp),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}