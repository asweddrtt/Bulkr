import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';
import 'animations/motion.dart';
import 'animations/press_scale.dart';

class PrimaryIconButton extends StatelessWidget {
  const PrimaryIconButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.customIcon,
    this.isBusy = false,
  });

  final String label;

  /// Null disables the button — used while an OAuth round trip is in flight.
  final VoidCallback? onPressed;

  final IconData? icon;
  final Widget? customIcon;

  /// Shows a spinner in place of the label. Only the provider the user
  /// actually tapped spins; the other simply greys out.
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      enabled: onPressed != null,
      child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.buttonNeon,
        foregroundColor: Colors.black,
        disabledBackgroundColor: AppColors.darkBorder,
        disabledForegroundColor: AppColors.textGray,
        padding: EdgeInsets.symmetric(vertical: 16.h),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.r),
        ),
        animationDuration: Motion.base,
      ),
      child: isBusy
          ? SizedBox(
              height: 28.sp,
              width: 28.sp,
              child: const CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(Colors.black),
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (customIcon != null)
                  customIcon!
                else if (icon != null)
                  Icon(icon, size: 28.sp),
                SizedBox(width: 8.w),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.anton(fontSize: 24.sp),
                  ),
                ),
              ],
            ),
      ),
    );
  }
}
