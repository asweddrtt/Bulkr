import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/nutrition_plan.dart';
import '../styles/app_color.dart';

/// The macro split on the reveal screen: a proportional bar plus the gram
/// targets that get written to `protein_target_g` / `carbs_target_g` /
/// `fat_target_g`.
class MacroBreakdown extends StatelessWidget {
  const MacroBreakdown({super.key, required this.plan});

  final NutritionPlan plan;

  static const Color proteinColor = AppColors.primaryNeon;
  static const Color carbsColor = Color(0xFF6FD3FF);
  static const Color fatColor = Color(0xFFFF9E3D);

  @override
  Widget build(BuildContext context) {
    final proteinKcal = plan.proteinG * 4;
    final carbsKcal = plan.carbsG * 4;
    final fatKcal = plan.fatG * 9;

    // Expanded requires a positive int flex, so a zero-calorie macro (possible
    // only if carbs got clamped) would throw. Floor each at 1.
    final total = plan.macroCalories;
    final hasSplit = total > 0;
    final proteinFlex = proteinKcal > 0 ? proteinKcal : 1;
    final carbsFlex = carbsKcal > 0 ? carbsKcal : 1;
    final fatFlex = fatKcal > 0 ? fatKcal : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'macros_title'.tr().toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 10.sp,
            fontWeight: FontWeight.w700,
            color: AppColors.offWhiteMuted,
            letterSpacing: 2,
          ),
        ),
        SizedBox(height: 10.h),
        ClipRRect(
          borderRadius: BorderRadius.circular(4.r),
          child: SizedBox(
            height: 10.h,
            child: hasSplit
                ? Row(
                    children: [
                      Expanded(
                        flex: proteinFlex,
                        child: Container(color: proteinColor),
                      ),
                      Expanded(
                        flex: carbsFlex,
                        child: Container(color: carbsColor),
                      ),
                      Expanded(
                        flex: fatFlex,
                        child: Container(color: fatColor),
                      ),
                    ],
                  )
                : Container(color: AppColors.darkBorder),
          ),
        ),
        SizedBox(height: 14.h),
        Row(
          children: [
            Expanded(
              child: _MacroTile(
                color: proteinColor,
                label: 'macro_protein'.tr(),
                grams: plan.proteinG,
              ),
            ),
            Expanded(
              child: _MacroTile(
                color: carbsColor,
                label: 'macro_carbs'.tr(),
                grams: plan.carbsG,
              ),
            ),
            Expanded(
              child: _MacroTile(
                color: fatColor,
                label: 'macro_fat'.tr(),
                grams: plan.fatG,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MacroTile extends StatelessWidget {
  const _MacroTile({
    required this.color,
    required this.label,
    required this.grams,
  });

  final Color color;
  final String label;
  final int grams;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8.w,
              height: 8.w,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            SizedBox(width: 6.w),
            Flexible(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.offWhiteMuted,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 4.h),
        Text(
          '${grams}g',
          style: GoogleFonts.anton(
            fontSize: 22.sp,
            color: Colors.white,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}
