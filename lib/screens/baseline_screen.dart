import 'package:bulkr/go_router/app_routes.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';
import '../widgets/StandardMetricCard.dart';

class BaselineScreen extends StatefulWidget {
  const BaselineScreen({super.key});

  @override
  State<BaselineScreen> createState() => _BaselineScreenState();
}

class _BaselineScreenState extends State<BaselineScreen> {
  // Local state initialized with your specific starting metrics
  int _age = 28;
  int _height = 165;
  double _currentMass = 85.0;
  double _targetMass = 95.0;

  double get _deltaMass => _targetMass - _currentMass;

  // Reusing your progress indicator from previous screens
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
        dot(true),
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
              SizedBox(height: 20.h,),
              _buildProgressIndicator(),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
                  children: [
                    // --- HEADER ---
                    Text(
                      'baseline_title'.tr(),
                      style: GoogleFonts.anton(
                        fontSize: 30.sp, // Reduced from 36
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                    SizedBox(height: 8.h), // Reduced from 12
                    Text(
                      'baseline_subtitle'.tr(),
                      style: GoogleFonts.inter(
                        fontSize: 14.sp, // Reduced from 16
                        fontWeight: FontWeight.w500,
                        color: AppColors.offWhiteMuted,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: 22.h),

                    // --- INPUT CARDS ---
                    StandardMetricCard(
                      label: 'age_label'.tr(),
                      value: _age.toString(),
                      unit: 'yrs_unit'.tr(),
                    ),
                    StandardMetricCard(
                      label: 'height_label'.tr(),
                      value: _height.toString(),
                      unit: 'cm_unit'.tr(),
                    ),
                    InlineMetricCard(
                      label: 'current_mass_label'.tr(),
                      value: _currentMass.toStringAsFixed(1),
                      unit: 'kg_unit'.tr(),
                    ),

                    // --- TARGET CARD ---
                    TargetMassCard(
                      targetValue: _targetMass.toStringAsFixed(1),
                      deltaValue: _deltaMass.toStringAsFixed(1),
                      isGain: _deltaMass > 0,
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

                    // Continue Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          context.push(AppRoutes.activityLevel);
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