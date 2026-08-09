import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/calorie_engine.dart';
import '../core/unit_converter.dart';
import '../cubit/onboarding/onboarding_cubit.dart';
import '../go_router/app_routes.dart';
import '../styles/app_color.dart';
import '../widgets/metric_card.dart';
import '../widgets/onboarding_scaffold.dart';
import '../widgets/pace_slider.dart';
import '../widgets/wheel_picker_sheet.dart';

/// Step 4 — where the user defines what success looks like: a target weight
/// and how fast they intend to get there.
class TargetPaceScreen extends StatelessWidget {
  const TargetPaceScreen({super.key});

  /// Slider bounds in kg/week. The floor is slow but real progress; the
  /// ceiling is past the point where extra calories mostly become fat.
  static const double minPaceKg = 0.1;
  static const double maxPaceKg = 0.75;

  /// 0.05 kg steps across the range.
  static const int paceDivisions = 13;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OnboardingCubit, OnboardingState>(
      builder: (context, state) {
        final cubit = context.read<OnboardingCubit>();
        final isMetric = state.unitSystem.isMetric;
        final target = state.effectiveTargetWeightKg;
        final delta = target - state.currentWeightKg;

        return OnboardingScaffold(
          step: 4,
          title: 'target_pace_title'.tr(),
          subtitle: 'target_pace_subtitle'.tr(),
          onBack: () => context.pop(),
          continueLabel: 'continue_to_goal'.tr(),
          onContinue: state.isGoalComplete
              ? () => context.push(AppRoutes.plan)
              : null,
          footnote: state.isGoalComplete
              ? null
              : _TargetTooLowNotice(
                  currentWeight: _weightLabel(state.currentWeightKg, isMetric),
                ),
          children: [
            TargetMassCard(
              targetValue: _weightValue(target, isMetric),
              deltaValue: _weightValue(delta.abs(), isMetric),
              unitLabel: isMetric ? 'kg_unit'.tr() : 'lb_unit'.tr(),
              isGain: delta > 0,
              onTap: () => _pickTargetWeight(context, state, cubit),
            ),
            SizedBox(height: 16.h),

            PaceSlider(
              weeklyGainKg: state.weeklyGainKg,
              unitSystem: state.unitSystem,
              onChanged: (value) => _onPaceChanged(state, cubit, value),
              min: minPaceKg,
              max: maxPaceKg,
              divisions: paceDivisions,
            ),
            SizedBox(height: 12.h),

            // Guidance sits directly under the control it describes, so the
            // consequence of dragging past 0.5 kg/week is visible in place.
            LeanBulkNotice(isWarning: state.exceedsLeanBulkPace),
            SizedBox(height: 12.h),

            _TimeToTargetCard(
              weeksToTarget: delta > 0 ? (delta / state.weeklyGainKg).ceil() : 0,
            ),
          ],
        );
      },
    );
  }

  /// Ticks once as the slider crosses the lean-bulk ceiling in either
  /// direction.
  ///
  /// The threshold is the single most consequential thing on this screen and
  /// it's easy to slide straight past while watching the number. A haptic
  /// marks the boundary without another line of warning text — and it fires
  /// only on the crossing, not on every step, so it stays meaningful.
  static void _onPaceChanged(
    OnboardingState state,
    OnboardingCubit cubit,
    double value,
  ) {
    final wasLean = !state.exceedsLeanBulkPace;
    final isLean = value <= CalorieEngine.leanBulkCeilingKgPerWeek;
    if (wasLean != isLean) HapticFeedback.selectionClick();

    cubit.setWeeklyGainKg(value);
  }

  static String _weightValue(double kg, bool isMetric) => isMetric
      ? kg.toStringAsFixed(1)
      : UnitConverter.kgToLb(kg).toStringAsFixed(1);

  static String _weightLabel(double kg, bool isMetric) => isMetric
      ? '${kg.toStringAsFixed(1)} ${'kg_unit'.tr()}'
      : '${UnitConverter.kgToLb(kg).toStringAsFixed(1)} ${'lb_unit'.tr()}';

  Future<void> _pickTargetWeight(
    BuildContext context,
    OnboardingState state,
    OnboardingCubit cubit,
  ) async {
    final isMetric = state.unitSystem.isMetric;

    final result = await WheelPickerSheet.showValue(
      context: context,
      title: 'target_mass_goal'.tr(),
      initialValue: isMetric
          ? state.effectiveTargetWeightKg
          : UnitConverter.kgToLb(state.effectiveTargetWeightKg),
      min: isMetric ? 35 : 77,
      max: isMetric ? 250 : 550,
      step: isMetric ? 0.5 : 1,
      decimals: isMetric ? 1 : 0,
      unitLabel:
          isMetric ? 'kg_unit'.tr().toLowerCase() : 'lb_unit'.tr().toLowerCase(),
    );

    if (result == null) return;
    cubit.setTargetWeightKg(isMetric ? result : UnitConverter.lbToKg(result));
  }
}

/// Blocks continuing when the target isn't above current weight — this is a
/// bulking app, and a lower target would produce a nonsensical surplus.
class _TargetTooLowNotice extends StatelessWidget {
  const _TargetTooLowNotice({required this.currentWeight});

  final String currentWeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(4.r),
        border: Border.all(color: const Color(0xFFFF5722)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 16.sp, color: const Color(0xFFFF5722)),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              'target_below_current'
                  .tr(namedArgs: {'weight': currentWeight}),
              style: GoogleFonts.inter(
                fontSize: 11.sp,
                height: 1.4,
                color: const Color(0xFFFF5722),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Turns the abstract pace into a date the user can picture.
class _TimeToTargetCard extends StatelessWidget {
  const _TimeToTargetCard({required this.weeksToTarget});

  final int weeksToTarget;

  @override
  Widget build(BuildContext context) {
    if (weeksToTarget <= 0) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(4.r),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today_outlined,
              size: 16.sp, color: AppColors.offWhiteMuted),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              'eta_label'.tr().toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 10.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.offWhiteMuted,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Text(
            'eta_weeks'.tr(namedArgs: {'weeks': '$weeksToTarget'}),
            style: GoogleFonts.anton(
              fontSize: 18.sp,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
