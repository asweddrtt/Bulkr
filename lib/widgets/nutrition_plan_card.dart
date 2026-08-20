import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';

/// Summary of the active calorie target with a shortcut back into the
/// surplus calculation.
class NutritionPlanCard extends StatelessWidget {
  final int dailyCalories;
  final double weeklyGainKg;
  final VoidCallback onRecalculate;

  const NutritionPlanCard({
    super.key,
    required this.dailyCalories,
    required this.weeklyGainKg,
    required this.onRecalculate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  'nutrition_plan_label'.tr().toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 9.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.offWhiteMuted,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              Icon(
                Icons.fitness_center,
                color: AppColors.darkBorder,
                size: 22.sp,
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            'current_daily_goal'
                .tr(
                  namedArgs: {
                    'kcal': NumberFormat('#,###').format(dailyCalories),
                  },
                )
                .toUpperCase(),
            style: GoogleFonts.anton(
              fontSize: 22.sp,
              color: Colors.white,
              height: 1.15,
              letterSpacing: 0.5,
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            'nutrition_plan_desc'.tr(
              namedArgs: {'rate': weeklyGainKg.toStringAsFixed(1)},
            ),
            style: GoogleFonts.inter(
              fontSize: 12.sp,
              color: AppColors.offWhiteMuted,
              height: 1.4,
            ),
          ),
          SizedBox(height: 16.h),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onRecalculate,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryNeon,
                side: const BorderSide(color: AppColors.primaryNeon),
                padding: EdgeInsets.symmetric(vertical: 12.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4.r),
                ),
              ),
              child: Text(
                'recalculate_btn'.tr().toUpperCase(),
                style: GoogleFonts.anton(
                  fontSize: 16.sp,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
