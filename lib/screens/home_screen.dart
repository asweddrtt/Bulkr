import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../cubit/onboarding/onboarding_cubit.dart';
import '../styles/app_color.dart';
import '../widgets/macro_bar.dart';

/// PLACEHOLDER.
///
/// Onboarding has to land somewhere, and a dead button at the end of the flow
/// would be worse than a stub. This confirms the plan was saved and shows the
/// committed targets; the real dashboard (logging, progress, feed) is a
/// separate piece of work.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<OnboardingCubit, OnboardingState>(
      builder: (context, state) {
        final plan = state.nutritionPlan;

        return Scaffold(
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
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle,
                        color: AppColors.primaryNeon, size: 40.sp),
                    SizedBox(height: 16.h),
                    Text(
                      'home_welcome'.tr(
                        namedArgs: {
                          'name': state.displayName ?? state.username,
                        },
                      ),
                      style: GoogleFonts.anton(
                        fontSize: 34.sp,
                        color: Colors.white,
                        height: 1.1,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 10.h),
                    Text(
                      'home_placeholder_body'.tr(),
                      style: GoogleFonts.inter(
                        fontSize: 14.sp,
                        color: AppColors.offWhiteMuted,
                        height: 1.5,
                      ),
                    ),
                    SizedBox(height: 28.h),
                    if (plan != null) ...[
                      Text(
                        NumberFormat('#,###').format(plan.calories),
                        style: GoogleFonts.anton(
                          fontSize: 64.sp,
                          height: 1,
                          color: AppColors.primaryNeon,
                        ),
                      ),
                      Text(
                        'kcal_day'.tr().toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w600,
                          color: AppColors.offWhiteMuted,
                          letterSpacing: 2,
                        ),
                      ),
                      SizedBox(height: 28.h),
                      MacroBreakdown(plan: plan),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
