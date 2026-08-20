import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_profile.dart';
import '../styles/app_color.dart';

extension FocusIntensityDisplay on FocusIntensity {
  String get label {
    switch (this) {
      case FocusIntensity.heavy:
        return 'focus_heavy'.tr().toUpperCase();
      case FocusIntensity.volume:
        return 'focus_volume'.tr().toUpperCase();
      case FocusIntensity.resting:
        return 'focus_resting'.tr().toUpperCase();
    }
  }

  /// Resting groups are dimmed so the active blocks read first.
  bool get isActive => this != FocusIntensity.resting;
}

class FocusAreaTile extends StatelessWidget {
  final FocusArea area;

  const FocusAreaTile({super.key, required this.area});

  @override
  Widget build(BuildContext context) {
    final bool isActive = area.intensity.isActive;

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(4.r),
        border: Border(
          left: BorderSide(
            color: isActive ? AppColors.primaryNeon : AppColors.darkBorder,
            width: 3.w,
          ),
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
      child: Row(
        children: [
          Expanded(
            child: Text(
              area.nameKey.tr().toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.white : AppColors.textGray,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Text(
            area.intensity.label,
            style: GoogleFonts.anton(
              fontSize: 14.sp,
              color: isActive ? Colors.white : AppColors.textGray,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
