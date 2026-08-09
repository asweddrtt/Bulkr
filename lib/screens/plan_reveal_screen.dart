import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../cubit/onboarding/onboarding_cubit.dart';
import '../go_router/app_routes.dart';
import '../models/nutrition_plan.dart';
import '../styles/app_color.dart';
import '../widgets/macro_bar.dart';
import '../widgets/onboarding_progress_dots.dart';

/// Step 5 — the reveal.
///
/// Not a data-entry screen: everything here is derived from what the previous
/// four collected. Tapping the button compiles all of it into a single insert
/// and flags `onboarding_completed`.
class PlanRevealScreen extends StatelessWidget {
  const PlanRevealScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OnboardingCubit, OnboardingState>(
      listenWhen: (previous, current) =>
          previous.submission != current.submission,
      listener: (context, state) {
        if (state.submission == SubmissionStatus.failure &&
            state.errorMessage != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFF2A2A2A),
                content: Text(
                  _friendlyError(state.errorMessage!),
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13.sp),
                ),
              ),
            );
        }
      },
      builder: (context, state) {
        final plan = state.nutritionPlan;
        final isSubmitting = state.submission == SubmissionStatus.submitting;

        return Scaffold(
          extendBodyBehindAppBar: true,
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
                  // --- TOP BAR ---
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.w),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back,
                              color: Colors.white, size: 24.sp),
                          onPressed: isSubmitting ? null : () => context.pop(),
                        ),
                        Expanded(
                          child: Center(
                            child: Padding(
                              // Offsets the back button so the dots sit centred.
                              padding: EdgeInsets.only(right: 48.w),
                              child: const OnboardingProgressDots(step: 5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Expanded(
                    child: plan == null
                        ? const _IncompleteDataNotice()
                        : _PlanBody(plan: plan),
                  ),

                  // --- COMMIT ---
                  Padding(
                    padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 20.h),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (plan == null || isSubmitting)
                            ? null
                            : () => _commit(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryNeon,
                          foregroundColor: Colors.black,
                          disabledBackgroundColor: AppColors.darkBorder,
                          disabledForegroundColor: AppColors.textGray,
                          padding: EdgeInsets.symmetric(vertical: 16.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                        ),
                        child: isSubmitting
                            ? SizedBox(
                                height: 26.h,
                                width: 26.h,
                                child: const CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor:
                                      AlwaysStoppedAnimation(Colors.black),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      'start_bulking_btn'.tr().toUpperCase(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.anton(
                                        fontSize: 22.sp,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 8.w),
                                  Icon(Icons.bolt, size: 24.sp),
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
      },
    );
  }

  Future<void> _commit(BuildContext context) async {
    final router = GoRouter.of(context);
    final succeeded = await context.read<OnboardingCubit>().submit();
    if (succeeded) router.go(AppRoutes.home);
  }

  /// Translated keys are our own; anything else came from Postgres and is
  /// shown verbatim so a real failure stays diagnosable.
  String _friendlyError(String message) {
    const known = {'username_taken_error', 'onboarding_error_incomplete'};
    return known.contains(message) ? message.tr() : message;
  }
}

class _PlanBody extends StatelessWidget {
  const _PlanBody({required this.plan});

  final NutritionPlan plan;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 8.h),
      children: [
        Center(
          child: Container(
            padding: EdgeInsets.all(16.w),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: AppColors.primaryNeon, width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryNeon.withValues(alpha: 0.15),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(
              Icons.local_fire_department,
              color: AppColors.primaryNeon,
              size: 34.sp,
            ),
          ),
        ),
        SizedBox(height: 16.h),

        // The number the whole flow has been building towards.
        Center(
          child: Text(
            NumberFormat('#,###').format(plan.calories),
            style: GoogleFonts.anton(
              fontSize: 88.sp,
              height: 1.0,
              letterSpacing: -2,
              color: AppColors.primaryNeon,
              shadows: [
                Shadow(
                  color: AppColors.primaryNeon.withValues(alpha: 0.4),
                  blurRadius: 25,
                ),
              ],
            ),
          ),
        ),
        Center(
          child: Text(
            'calorie_goal_title'.tr().toUpperCase(),
            textAlign: TextAlign.center,
            style: GoogleFonts.anton(
              fontSize: 20.sp,
              color: Colors.white,
              letterSpacing: 1,
            ),
          ),
        ),
        SizedBox(height: 12.h),
        Center(
          child: Text(
            'calorie_goal_desc'.tr(),
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.offWhiteMuted,
              height: 1.5,
            ),
          ),
        ),
        SizedBox(height: 24.h),

        MacroBreakdown(plan: plan),
        SizedBox(height: 20.h),

        // Shows the arithmetic rather than presenting the target as a black
        // box: maintenance plus the surplus the chosen pace requires.
        _MathRow(
          label: 'bmr_label'.tr(),
          value: NumberFormat('#,###').format(plan.bmr),
        ),
        _MathRow(
          label: 'tdee_label'.tr(),
          value: NumberFormat('#,###').format(plan.tdee),
        ),
        _MathRow(
          label: 'surplus_label'.tr(),
          value: '+${NumberFormat('#,###').format(plan.dailySurplus)}',
          isHighlighted: true,
        ),
      ],
    );
  }
}

class _MathRow extends StatelessWidget {
  const _MathRow({
    required this.label,
    required this.value,
    this.isHighlighted = false,
  });

  final String label;
  final String value;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 10.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.offWhiteMuted,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Text(
            '$value ${'kcal_short'.tr()}',
            style: GoogleFonts.anton(
              fontSize: 16.sp,
              color: isHighlighted ? AppColors.primaryNeon : Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Reachable only if the flow is entered mid-way with state missing — a deep
/// link or a hot restart. Better than rendering a plan built on defaults.
class _IncompleteDataNotice extends StatelessWidget {
  const _IncompleteDataNotice();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40.sp, color: AppColors.textGray),
            SizedBox(height: 16.h),
            Text(
              'onboarding_error_incomplete'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14.sp,
                color: AppColors.offWhiteMuted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
