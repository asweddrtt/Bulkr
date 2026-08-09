import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../styles/app_color.dart';

/// The step indicator, extracted from the four hand-rolled copies that used to
/// live inside each onboarding screen.
///
/// Those copies had drifted: the biometrics and activity screens both lit up
/// dot 3, so the flow appeared to stall on step 3 for two screens running.
class OnboardingProgressDots extends StatelessWidget {
  const OnboardingProgressDots({
    super.key,
    required this.step,
    this.total = 5,
  });

  /// 1-based index of the current step.
  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(total, (index) {
        final isActive = index == step - 1;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: EdgeInsets.symmetric(horizontal: 4.w),
          width: isActive ? 24.w : 6.w,
          height: 6.h,
          decoration: BoxDecoration(
            color: isActive ? AppColors.primaryNeon : AppColors.darkBorder,
            borderRadius: BorderRadius.circular(10.r),
          ),
        );
      }),
    );
  }
}
