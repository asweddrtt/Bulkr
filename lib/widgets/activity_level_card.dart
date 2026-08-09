import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';

class ActivityLevelCard extends StatelessWidget {
  const ActivityLevelCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.multiplier,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;

  /// Shown on the card so the effect of the choice isn't hidden — picking
  /// "Very Active" over "Sedentary" swings the daily target by hundreds of
  /// calories.
  final double multiplier;

  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(
            color: isSelected ? AppColors.primaryNeon : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: isSelected
                      ? AppColors.primaryNeon
                      : AppColors.offWhiteMuted,
                  size: 26.sp,
                ),
                const Spacer(),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primaryNeon
                        : const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                  child: Text(
                    '${multiplier}x',
                    style: GoogleFonts.inter(
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color:
                          isSelected ? Colors.black : AppColors.offWhiteMuted,
                    ),
                  ),
                ),
                if (isSelected) ...[
                  SizedBox(width: 8.w),
                  Icon(Icons.check_circle,
                      color: AppColors.primaryNeon, size: 18.sp),
                ],
              ],
            ),
            SizedBox(height: 10.h),
            Text(
              title,
              style: GoogleFonts.anton(
                fontSize: 20.sp,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              description,
              style: GoogleFonts.inter(
                fontSize: 11.sp,
                color: AppColors.offWhiteMuted,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
