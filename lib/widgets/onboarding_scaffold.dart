import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';
import 'animations/entrance.dart';
import 'animations/motion.dart';
import 'animations/press_scale.dart';
import 'onboarding_progress_dots.dart';

/// Shared chrome for onboarding steps 2-5: background, progress dots, heading,
/// scrolling body and the back/continue footer.
///
/// Screens supply only their [children]; everything else was duplicated across
/// four files before this existed.
class OnboardingScaffold extends StatelessWidget {
  const OnboardingScaffold({
    super.key,
    required this.step,
    required this.children,
    this.title,
    this.subtitle,
    this.centerHeader = false,
    this.onBack,
    this.onContinue,
    this.continueLabel,
    this.continueIcon = Icons.arrow_forward,
    this.isBusy = false,
    this.footnote,
  });

  final int step;
  final List<Widget> children;
  final String? title;
  final String? subtitle;
  final bool centerHeader;

  /// Omit to hide the back button (step 2 has nowhere to go but sign-in).
  final VoidCallback? onBack;

  /// Null disables the continue button — used for incomplete forms.
  final VoidCallback? onContinue;

  final String? continueLabel;
  final IconData continueIcon;

  /// Swaps the continue button's contents for a spinner and blocks taps.
  final bool isBusy;

  /// Optional widget pinned just above the footer buttons.
  final Widget? footnote;

  @override
  Widget build(BuildContext context) {
    final headerAlign = centerHeader ? TextAlign.center : TextAlign.start;
    final crossAlign =
        centerHeader ? CrossAxisAlignment.center : CrossAxisAlignment.start;

    return Scaffold(
      extendBodyBehindAppBar: true,
      extendBody: true,
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
              SizedBox(height: 15.h),
              OnboardingProgressDots(step: step),
              SizedBox(height: 10.h),
              Expanded(
                // The heading arrives first, then the content behind it in
                // sequence — so the eye lands on what the step is asking
                // before the controls appear.
                child: ListView(
                  padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 10.h),
                  children: [
                    if (title != null) ...[
                      Entrance(
                        child: Column(
                          crossAxisAlignment: crossAlign,
                          children: [
                            Text(
                              title!,
                              textAlign: headerAlign,
                              style: GoogleFonts.anton(
                                fontSize: 30.sp,
                                color: Colors.white,
                                letterSpacing: 1,
                              ),
                            ),
                            if (subtitle != null) ...[
                              SizedBox(height: 8.h),
                              Text(
                                subtitle!,
                                textAlign: headerAlign,
                                style: GoogleFonts.inter(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.offWhiteMuted,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(height: 20.h),
                    ],
                    ...staggered(
                      children,
                      initialDelay: title == null
                          ? Duration.zero
                          : const Duration(milliseconds: 80),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 8.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // A validation notice appearing under the form is new
                    // information, so it slides in rather than blinking into
                    // existence mid-layout.
                    AnimatedSize(
                      duration: Motion.scaled(context, Motion.base),
                      curve: Motion.enter,
                      alignment: Alignment.bottomCenter,
                      child: footnote == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: EdgeInsets.only(bottom: 12.h),
                              child: Entrance(child: footnote!),
                            ),
                    ),
                    if (onBack != null) ...[
                      PressScale(
                        enabled: !isBusy && onBack != null,
                        child: _BackButton(onPressed: isBusy ? null : onBack),
                      ),
                      SizedBox(height: 12.h),
                    ],
                    PressScale(
                      enabled: !isBusy && onContinue != null,
                      child: _ContinueButton(
                        label: continueLabel ?? 'continue_btn'.tr(),
                        icon: continueIcon,
                        isBusy: isBusy,
                        onPressed: isBusy ? null : onContinue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white, width: 1.5),
          padding: EdgeInsets.symmetric(vertical: 14.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.r),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.arrow_back, size: 20.sp),
            SizedBox(width: 8.w),
            Text(
              'back_btn'.tr().toUpperCase(),
              style: GoogleFonts.anton(fontSize: 20.sp, letterSpacing: 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({
    required this.label,
    required this.icon,
    required this.isBusy,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool isBusy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryNeon,
          foregroundColor: Colors.black,
          disabledBackgroundColor: AppColors.darkBorder,
          disabledForegroundColor: AppColors.textGray,
          padding: EdgeInsets.symmetric(vertical: 14.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.r),
          ),
          // Material cross-fades its own colours over this, so the button
          // lighting up as the form becomes valid is a transition rather than
          // a jump cut.
          animationDuration: Motion.base,
        ),
        child: isBusy
            ? SizedBox(
                height: 24.h,
                width: 24.h,
                child: const CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(Colors.black),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.anton(
                        fontSize: 20.sp,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Icon(icon, size: 20.sp),
                ],
              ),
      ),
    );
  }
}
