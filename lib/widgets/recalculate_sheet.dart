import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/nutrition_plan.dart';
import '../models/unit_system.dart';
import '../styles/app_color.dart';
import 'macro_bar.dart';
import 'pace_slider.dart';

/// Recalculates the calorie target against the user's current weight.
///
/// The pace is not stored anywhere, so it starts from whatever the existing
/// target implies and the slider lets the user change their mind. Nothing is
/// written until they confirm, and the numbers on screen are the numbers that
/// will be saved.
class RecalculateSheet extends StatefulWidget {
  const RecalculateSheet({
    super.key,
    required this.initialWeeklyGainKg,
    required this.currentCalories,
    required this.units,
    required this.planForPace,
    required this.minWeeklyGainKg,
    required this.maxWeeklyGainKg,
  });

  final double initialWeeklyGainKg;

  /// The stored target, shown alongside the new one so the change is visible.
  final int currentCalories;

  final UnitSystem units;

  /// Recomputes the plan at a given pace. Owned by the cubit — this sheet does
  /// no calorie maths of its own.
  final NutritionPlan? Function(double weeklyGainKg) planForPace;

  final double minWeeklyGainKg;
  final double maxWeeklyGainKg;

  /// Resolves to the plan to save, or null when dismissed.
  static Future<NutritionPlan?> show(
    BuildContext context, {
    required double initialWeeklyGainKg,
    required int currentCalories,
    required UnitSystem units,
    required NutritionPlan? Function(double weeklyGainKg) planForPace,
    required double minWeeklyGainKg,
    required double maxWeeklyGainKg,
  }) {
    return showModalBottomSheet<NutritionPlan>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => RecalculateSheet(
        initialWeeklyGainKg: initialWeeklyGainKg,
        currentCalories: currentCalories,
        units: units,
        planForPace: planForPace,
        minWeeklyGainKg: minWeeklyGainKg,
        maxWeeklyGainKg: maxWeeklyGainKg,
      ),
    );
  }

  @override
  State<RecalculateSheet> createState() => _RecalculateSheetState();
}

class _RecalculateSheetState extends State<RecalculateSheet> {
  late double _weeklyGainKg = widget.initialWeeklyGainKg;

  @override
  Widget build(BuildContext context) {
    final NutritionPlan? plan = widget.planForPace(_weeklyGainKg);
    final int? delta =
        plan == null ? null : plan.calories - widget.currentCalories;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
          border: Border(
            top: BorderSide(color: AppColors.darkBorder, width: 1.h),
          ),
        ),
        padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 16.h),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: AppColors.darkBorder,
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                'recalculate'.tr().toUpperCase(),
                style: GoogleFonts.anton(
                  fontSize: 20.sp,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                'recalculate_desc'.tr(),
                style: GoogleFonts.inter(
                  fontSize: 12.sp,
                  color: AppColors.offWhiteMuted,
                  height: 1.4,
                ),
              ),
              SizedBox(height: 20.h),

              // --- NEW TARGET ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    plan == null
                        ? '--'
                        : NumberFormat('#,###').format(plan.calories),
                    style: GoogleFonts.anton(
                      fontSize: 44.sp,
                      color: AppColors.primaryNeon,
                      height: 1,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Padding(
                    padding: EdgeInsets.only(bottom: 6.h),
                    child: Text(
                      'kcal_day'.tr().toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w700,
                        color: AppColors.offWhiteMuted,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (delta != null && delta != 0)
                    Padding(
                      padding: EdgeInsets.only(bottom: 8.h),
                      child: Text(
                        '${delta > 0 ? '+' : ''}$delta',
                        style: GoogleFonts.anton(
                          fontSize: 16.sp,
                          color: delta > 0
                              ? AppColors.primaryNeon
                              : const Color(0xFFFF5722),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: 6.h),
              Text(
                'recalculate_from_current'.tr(
                  namedArgs: {
                    'calories':
                        NumberFormat('#,###').format(widget.currentCalories),
                  },
                ),
                style: GoogleFonts.inter(
                  fontSize: 11.sp,
                  color: AppColors.textGray,
                ),
              ),
              SizedBox(height: 20.h),

              PaceSlider(
                weeklyGainKg: _weeklyGainKg,
                unitSystem: widget.units,
                min: widget.minWeeklyGainKg,
                max: widget.maxWeeklyGainKg,
                divisions:
                    (((widget.maxWeeklyGainKg - widget.minWeeklyGainKg) / 0.05)
                            .round())
                        .clamp(1, 100),
                onChanged: (value) => setState(() => _weeklyGainKg = value),
              ),
              SizedBox(height: 16.h),

              if (plan != null) MacroBreakdown(plan: plan),
              SizedBox(height: 20.h),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: plan == null
                      ? null
                      : () => Navigator.of(context).pop(plan),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryNeon,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: AppColors.darkBorder,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                  ),
                  child: Text(
                    'save_plan_btn'.tr().toUpperCase(),
                    style: GoogleFonts.anton(fontSize: 17.sp, letterSpacing: 1),
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
