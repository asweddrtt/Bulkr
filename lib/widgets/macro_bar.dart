import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/nutrition_plan.dart';
import '../styles/app_color.dart';
import 'animations/count_up.dart';
import 'animations/motion.dart';

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

    final total = plan.macroCalories;
    final hasSplit = total > 0;

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
                ? LayoutBuilder(
                    // Explicit widths rather than Expanded flex, because a
                    // flex has to be a whole number and can't be animated
                    // partway. Driving pixel widths off a 0..1 factor lets the
                    // three segments grow out together from the left edge.
                    builder: (context, constraints) {
                      final fullWidth = constraints.maxWidth;

                      return TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0, end: 1),
                        duration: Motion.scaled(context, Motion.reveal),
                        curve: Motion.emphasis,
                        builder: (context, grown, _) => Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Segment(
                              width: fullWidth * (proteinKcal / total) * grown,
                              color: proteinColor,
                            ),
                            _Segment(
                              width: fullWidth * (carbsKcal / total) * grown,
                              color: carbsColor,
                            ),
                            _Segment(
                              width: fullWidth * (fatKcal / total) * grown,
                              color: fatColor,
                            ),
                          ],
                        ),
                      );
                    },
                  )
                : const ColoredBox(color: AppColors.darkBorder),
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

class _Segment extends StatelessWidget {
  const _Segment({required this.width, required this.color});

  final double width;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ColoredBox(color: color),
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
        CountUpText(
          value: grams,
          formatter: (value) => '${value}g',
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
