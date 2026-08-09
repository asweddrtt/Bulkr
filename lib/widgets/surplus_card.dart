import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../styles/app_color.dart'; // Adjust path

class SurplusCard extends StatelessWidget {
  final String badgeText;
  final Color badgeBgColor;
  final Color badgeTextColor;
  final IconData? badgeIcon;
  final String title;
  final String description;
  final String calories;
  final Color caloriesColor;
  final bool isSelected;
  final VoidCallback onTap;

  const SurplusCard({
    super.key,
    required this.badgeText,
    required this.badgeBgColor,
    required this.badgeTextColor,
    this.badgeIcon,
    required this.title,
    required this.description,
    required this.calories,
    this.caloriesColor = Colors.white,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(14.w), // Reduced from 16
        margin: EdgeInsets.only(bottom: 10.h), // Reduced from 12
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(4.r),
          border: isSelected
              ? Border.all(color: AppColors.primaryNeon, width: 2)
              : Border.all(color: Colors.transparent, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- BADGE & CHECKMARK ROW ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h), // Scaled down padding
                  decoration: BoxDecoration(
                    color: badgeBgColor,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                  child: Row(
                    children: [
                      if (badgeIcon != null) ...[
                        Icon(badgeIcon, color: badgeTextColor, size: 10.sp), // Reduced from 12
                        SizedBox(width: 4.w),
                      ],
                      Text(
                        badgeText.toUpperCase(),
                        style: GoogleFonts.inter(
                          fontSize: 9.sp, // Reduced from 10
                          fontWeight: FontWeight.w700,
                          color: badgeTextColor,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle, color: AppColors.primaryNeon, size: 18.sp), // Reduced from 20
              ],
            ),
            SizedBox(height: 10.h), // Reduced from 12

            // --- TITLE & DESC ---
            Text(
              title,
              style: GoogleFonts.anton(
                fontSize: 20.sp, // Reduced from 24
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 4.h), // Reduced from 6
            Text(
              description,
              style: GoogleFonts.inter(
                fontSize: 11.sp, // Reduced from 12
                color: AppColors.offWhiteMuted,
                height: 1.3, // Slightly tighter line height
              ),
            ),
            SizedBox(height: 10.h), // Reduced from 12

            // --- CALORIES VALUE ---
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  calories,
                  style: GoogleFonts.anton(
                    fontSize: 36.sp, // Reduced from 42
                    color: caloriesColor,
                    height: 1,
                  ),
                ),
                SizedBox(width: 6.w), // Reduced from 8
                Padding(
                  padding: EdgeInsets.only(bottom: 4.h), // Reduced from 6
                  child: Text(
                    'kcal_day'.tr().toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 9.sp, // Reduced from 10
                      fontWeight: FontWeight.w600,
                      color: AppColors.offWhiteMuted,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}