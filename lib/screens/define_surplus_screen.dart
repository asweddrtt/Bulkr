import 'package:bulkr/go_router/app_routes.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user_profile.dart';
import '../state/profile_scope.dart';

import '../styles/app_color.dart';
import '../widgets/surplus_card.dart';

class DefineSurplusScreen extends StatefulWidget {
  const DefineSurplusScreen({super.key});

  @override
  State<DefineSurplusScreen> createState() => _DefineSurplusScreenState();
}

class _DefineSurplusScreenState extends State<DefineSurplusScreen> {
  int _selectedIndex = BulkPlan.standard.index;
  bool _seededFromProfile = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seededFromProfile) return;

    final profile = ProfileScope.read(context).profile;
    if (profile != null) _selectedIndex = profile.bulkPlan.index;
    _seededFromProfile = true;
  }

  Future<void> _continue() async {
    await ProfileScope.read(context)
        .setBulkPlan(BulkPlan.values[_selectedIndex]);
    if (!mounted) return;
    context.push(AppRoutes.calorieGoal);
  }

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
        dot(false),
        dot(true), // 4th step active
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
                  padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 10.h),
                  children: [
                    // --- HEADER ---
                    Text(
                      'surplus_title'.tr(),
                      style: GoogleFonts.anton(
                        fontSize: 30.sp,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      'surplus_subtitle'.tr(),
                      style: GoogleFonts.inter(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                        color: AppColors.offWhiteMuted,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: 20.h),

                    // --- CARDS ---
                    SurplusCard(
                      badgeText: 'badge_conservative'.tr(),
                      badgeBgColor: const Color(0xFF333333),
                      badgeTextColor: Colors.white,
                      title: 'lean_bulk_title'.tr(),
                      description: 'lean_bulk_desc'.tr(),
                      calories: '+${BulkPlan.lean.dailySurplusKcal}',
                      isSelected: _selectedIndex == BulkPlan.lean.index,
                      onTap: () => setState(() => _selectedIndex = BulkPlan.lean.index),
                    ),
                    SurplusCard(
                      badgeText: 'badge_recommended'.tr(),
                      badgeBgColor: const Color(0xFF333333),
                      badgeTextColor: Colors.white,
                      title: 'standard_bulk_title'.tr(),
                      description: 'standard_bulk_desc'.tr(),
                      calories: '+${BulkPlan.standard.dailySurplusKcal}',
                      isSelected: _selectedIndex == BulkPlan.standard.index,
                      onTap: () => setState(() => _selectedIndex = BulkPlan.standard.index),
                    ),
                    SurplusCard(
                      badgeText: 'badge_max_mass'.tr(),
                      badgeBgColor: AppColors.primaryNeon,
                      badgeTextColor: Colors.black,
                      badgeIcon: Icons.local_fire_department, // Small fire icon
                      title: 'aggressive_bulk_title'.tr(),
                      description: 'aggressive_bulk_desc'.tr(),
                      calories: '+${BulkPlan.aggressive.dailySurplusKcal}',
                      caloriesColor: AppColors.primaryNeon, // Highlighting the 700
                      isSelected: _selectedIndex == BulkPlan.aggressive.index,
                      onTap: () => setState(() => _selectedIndex = BulkPlan.aggressive.index),
                    ),
                  ],
                ),
              ),

              // --- FOOTER SECTION ---
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 0.h),

                child: Column(
                  children: [
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
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _continue,
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
                              'continue_to_goal'.tr(),
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