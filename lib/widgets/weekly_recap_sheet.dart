import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/meal_repository.dart';
import '../models/weekly_recap.dart';
import '../styles/app_color.dart';
import 'sheet_action_row.dart';

/// The last seven days, in eight numbers.
///
/// Everything here is computed by `public.weekly_recap()` and arrives as one
/// row. Nothing on this sheet does arithmetic — deliberately, because the
/// alternative is downloading a week of `daily_logs` to add it up on a phone,
/// which is paying to move data to its own summary.
class WeeklyRecapSheet extends StatelessWidget {
  const WeeklyRecapSheet({super.key, required this.recap});

  final WeeklyRecap? recap;

  static Future<void> show(BuildContext context) async {
    final MealRepository meals = context.read<MealRepository>();

    // Fetched before the sheet opens rather than inside it. It is one small
    // request, and a sheet that slides up onto a spinner and then reflows is
    // worse than one that arrives finished.
    final WeeklyRecap? recap = await meals.fetchWeeklyRecap();
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => WeeklyRecapSheet(recap: recap),
    );
  }

  @override
  Widget build(BuildContext context) {
    final WeeklyRecap? recap = this.recap;

    return SheetShell(
      title: 'recap_title'.tr(),
      children: [
        if (recap == null)
          // Unavailable, not empty. A recap of zeroes is a claim about the
          // week, and the wrong one.
          _Message(text: 'recap_unavailable'.tr())
        else if (!recap.hasAnything)
          _Message(text: 'recap_empty'.tr())
        else ...[
          _DaysLogged(recap: recap),
          SizedBox(height: 18.h),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'recap_avg_calories'.tr(),
                  value: '${recap.avgCalories}',
                  unit: 'kcal_short'.tr(),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'recap_entries'.tr(),
                  value: '${recap.entries}',
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'macro_protein'.tr(),
                  value: '${recap.avgProteinG}',
                  unit: 'gram_short'.tr(),
                  color: const Color(0xFF4FC3F7),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'macro_carbs'.tr(),
                  value: '${recap.avgCarbsG}',
                  unit: 'gram_short'.tr(),
                  color: const Color(0xFFFFB74D),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: 'macro_fat'.tr(),
                  value: '${recap.avgFatG}',
                  unit: 'gram_short'.tr(),
                  color: const Color(0xFFE57373),
                ),
              ),
            ],
          ),

          // Each of these is present only when there is something behind it.
          // A zero here would read as a fact rather than as an absence — nobody
          // drank no water, they just did not record any.
          if (recap.hasTarget) ...[
            SizedBox(height: 18.h),
            _Line(
              icon: Icons.track_changes_rounded,
              text: 'recap_on_target'.tr(namedArgs: {
                'days': '${recap.daysOnTarget}',
                'logged': '${recap.daysLogged}',
              }),
            ),
          ],
          if (recap.hasWater) ...[
            SizedBox(height: 10.h),
            _Line(
              icon: Icons.water_drop_outlined,
              text: 'recap_water'.tr(namedArgs: {'ml': '${recap.avgWaterMl}'}),
            ),
          ],
          if (recap.hasWeightTrend) ...[
            SizedBox(height: 10.h),
            _Line(
              icon: recap.isGaining
                  ? Icons.trending_up_rounded
                  : Icons.trending_down_rounded,
              text: 'recap_weight'.tr(namedArgs: {
                'change': recap.weightChangeKg.abs().toStringAsFixed(1),
                'direction': (recap.isGaining ? 'recap_up' : 'recap_down').tr(),
              }),
            ),
          ],
        ],
      ],
    );
  }
}

/// Days out of seven, as a meter and a sentence.
///
/// The denominator for everything under it, so it is at the top: an average
/// over two days is not a week's average and the sheet should not let anyone
/// read it as one.
class _DaysLogged extends StatelessWidget {
  const _DaysLogged({required this.recap});

  final WeeklyRecap recap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'recap_days_logged'.tr(namedArgs: {'days': '${recap.daysLogged}'}),
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 8.h),
        ClipRRect(
          borderRadius: BorderRadius.circular(3.r),
          child: LinearProgressIndicator(
            value: recap.loggedProgress,
            minHeight: 6.h,
            backgroundColor: AppColors.darkBorder,
            valueColor:
                const AlwaysStoppedAnimation<Color>(AppColors.primaryNeon),
          ),
        ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.unit,
    this.color,
  });

  final String label;
  final String value;
  final String? unit;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            color: AppColors.textGray,
            fontSize: 9.sp,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
        SizedBox(height: 4.h),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: GoogleFonts.anton(
                color: color ?? Colors.white,
                fontSize: 20.sp,
                letterSpacing: 0.5,
              ),
            ),
            if (unit != null) ...[
              SizedBox(width: 3.w),
              Text(
                unit!,
                style: GoogleFonts.inter(
                  color: AppColors.textGray,
                  fontSize: 10.sp,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textGray, size: 15.sp),
        SizedBox(width: 10.w),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.inter(
              color: AppColors.offWhiteMuted,
              fontSize: 12.sp,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12.h),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: AppColors.textGray,
          fontSize: 12.sp,
          height: 1.5,
        ),
      ),
    );
  }
}
