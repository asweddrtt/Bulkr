import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/calorie_engine.dart';
import '../core/unit_converter.dart';
import '../models/unit_system.dart';
import '../styles/app_color.dart';

/// Weekly rate-of-gain slider, with the resulting daily surplus shown live so
/// the trade-off is visible while dragging rather than only on the next screen.
class PaceSlider extends StatelessWidget {
  const PaceSlider({
    super.key,
    required this.weeklyGainKg,
    required this.unitSystem,
    required this.onChanged,
    required this.min,
    required this.max,
    required this.divisions,
  });

  final double weeklyGainKg;
  final UnitSystem unitSystem;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final int divisions;

  bool get _exceedsLeanBulk =>
      weeklyGainKg > CalorieEngine.leanBulkCeilingKgPerWeek;

  String get _paceLabel {
    if (unitSystem.isMetric) {
      return '+${weeklyGainKg.toStringAsFixed(2)} ${'kg_unit'.tr().toLowerCase()}';
    }
    final lb = UnitConverter.kgToLb(weeklyGainKg);
    return '+${lb.toStringAsFixed(2)} ${'lb_unit'.tr().toLowerCase()}';
  }

  @override
  Widget build(BuildContext context) {
    final surplus = CalorieEngine.dailySurplus(weeklyGainKg).round();
    final accent = _exceedsLeanBulk ? const Color(0xFFFF5722) : AppColors.primaryNeon;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(4.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'pace_label'.tr().toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.offWhiteMuted,
              letterSpacing: 2,
            ),
          ),
          SizedBox(height: 10.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _paceLabel,
                style: GoogleFonts.anton(
                  fontSize: 34.sp,
                  color: accent,
                  height: 1,
                ),
              ),
              SizedBox(width: 8.w),
              Padding(
                padding: EdgeInsets.only(bottom: 4.h),
                child: Text(
                  'per_week'.tr().toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 11.sp,
                    color: AppColors.offWhiteMuted,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 4.h),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accent,
              inactiveTrackColor: AppColors.darkBorder,
              thumbColor: accent,
              overlayColor: accent.withValues(alpha: 0.15),
              valueIndicatorColor: accent,
              trackHeight: 4.h,
            ),
            child: Slider(
              // clamp() is declared on num and returns num, so this needs an
              // explicit conversion to satisfy Slider's double.
              value: weeklyGainKg.clamp(min, max).toDouble(),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),

          // Derived, not chosen: the surplus is a consequence of the pace.
          Row(
            children: [
              Icon(Icons.local_fire_department, size: 16.sp, color: accent),
              SizedBox(width: 6.w),
              Text(
                'surplus_estimate'.tr(namedArgs: {'kcal': '+$surplus'}),
                style: GoogleFonts.inter(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.offWhiteMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The lean-bulk caution shown once the pace passes 0.5 kg (about 1 lb) a week.
class LeanBulkNotice extends StatelessWidget {
  const LeanBulkNotice({super.key, required this.isWarning});

  /// Below the ceiling this is a reassurance; above it, a caution.
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final color = isWarning ? const Color(0xFFFF5722) : AppColors.offWhiteMuted;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(4.r),
        border: Border.all(
          color: isWarning ? color : AppColors.darkBorder,
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isWarning ? Icons.warning_amber_rounded : Icons.info_outline,
            size: 16.sp,
            color: color,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              isWarning ? 'lean_bulk_warning'.tr() : 'lean_bulk_hint'.tr(),
              style: GoogleFonts.inter(
                fontSize: 11.sp,
                height: 1.4,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
