import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';

class CalorieGoalScreen extends StatelessWidget {
  final int dailyCalories;

  // Defaults to 3200 for UI testing, but you'll pass the real calculation here
  const CalorieGoalScreen({super.key, this.dailyCalories = 3200});

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
      // Setting 5th dot active assuming this is the final onboarding step
      children: [dot(false), dot(false), dot(false), dot(false), dot(true)],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.png'),
            fit: BoxFit.fill,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [

              // --- 1. TOP BAR ---
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.arrow_back, color: Colors.white, size: 24.sp),
                      onPressed: () => context.pop(),
                    ),
                    Expanded(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.only(right: 48.w), // Offsets the back button to center the dots perfectly
                          child: _buildProgressIndicator(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // --- 2. CENTER CONTENT ---
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24.w),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [

                      // Glowing Fire Icon Box
                      Container(
                        padding: EdgeInsets.all(20.w),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A), // Slightly darker center
                          borderRadius: BorderRadius.circular(16.r),
                          border: Border.all(color: AppColors.primaryNeon, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primaryNeon.withOpacity(0.15),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.local_fire_department,
                          color: AppColors.primaryNeon,
                          size: 40.sp,
                        ),
                      ),
                      SizedBox(height: 24.h),

                      // Massive Calorie Number with Drop Shadow
                      Text(
                        NumberFormat('#,###').format(dailyCalories),
                        style: GoogleFonts.anton(
                          fontSize: 110.sp,
                          height: 1.0, // Tightens the vertical space
                          letterSpacing: -2,
                          color: AppColors.primaryNeon,
                          shadows: [
                            Shadow(
                              color: AppColors.primaryNeon.withOpacity(0.4),
                              blurRadius: 25,
                            ),
                          ],
                        ),
                      ),

                      // Subtitle
                      Text(
                        'calorie_goal_title'.tr().toUpperCase(),
                        style: GoogleFonts.anton(
                          fontSize: 24.sp,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                      SizedBox(height: 16.h),

                      // Description Text
                      Text(
                        'calorie_goal_desc'.tr(),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w500,
                          color: AppColors.offWhiteMuted,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // --- 3. BOTTOM BUTTON ---
              Padding(
                padding: EdgeInsets.all(24.w),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      // TODO: Complete onboarding and navigate to Home Dashboard
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryNeon,
                      foregroundColor: Colors.black,
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'start_eating_btn'.tr().toUpperCase(),
                          style: GoogleFonts.anton(
                            fontSize: 22.sp,
                            letterSpacing: 1,
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Icon(Icons.restaurant, size: 24.sp),
                      ],
                    ),
                  ),
                ),
              ),

            ],
          ),
        ),
      ),
    );
  }
}