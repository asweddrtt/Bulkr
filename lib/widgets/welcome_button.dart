import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../styles/app_color.dart';

class PrimaryIconButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final Widget? customIcon;

  const PrimaryIconButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.customIcon,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.buttonNeon,
        foregroundColor: Colors.black,
        padding: EdgeInsets.symmetric(vertical: 16.h),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.r),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (customIcon != null) customIcon! else if (icon != null) Icon(icon, size: 28.sp),
          SizedBox(width: 8.w),
          Text(
            label,
            style: GoogleFonts.anton(
              fontSize: 24.sp,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}