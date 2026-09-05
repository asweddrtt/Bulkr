import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/visibility.dart';
import '../styles/app_color.dart';
import 'animations/motion.dart';
import 'animations/press_scale.dart';

/// Picks who can see one post or one meal.
///
/// Three rows rather than a switch, because the middle option is the whole
/// reason this exists and a switch cannot hold it. Shared by the composer and
/// the meal editor so the choice reads the same in both — the two things a user
/// publishes should not ask the question two different ways.
class VisibilityPicker extends StatelessWidget {
  const VisibilityPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.titleKey = 'visibility_title',
  });

  final ContentVisibility value;
  final ValueChanged<ContentVisibility> onChanged;
  final String titleKey;

  static IconData iconFor(ContentVisibility level) {
    switch (level) {
      case ContentVisibility.public:
        return Icons.public;
      case ContentVisibility.followers:
        return Icons.group_outlined;
      case ContentVisibility.private:
        return Icons.lock_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titleKey.tr().toUpperCase(),
          style: GoogleFonts.inter(
            color: AppColors.textGray,
            fontSize: 10.sp,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        SizedBox(height: 8.h),
        for (final ContentVisibility level in ContentVisibility.values) ...[
          _Option(
            level: level,
            isSelected: level == value,
            onTap: () => onChanged(level),
          ),
          if (level != ContentVisibility.values.last) SizedBox(height: 8.h),
        ],
      ],
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.level,
    required this.isSelected,
    required this.onTap,
  });

  final ContentVisibility level;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: Motion.scaled(context, Motion.fast),
          curve: Motion.enter,
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(6.r),
            border: Border.all(
              color: isSelected ? AppColors.primaryNeon : AppColors.darkBorder,
            ),
          ),
          child: Row(
            children: [
              Icon(
                VisibilityPicker.iconFor(level),
                size: 18.sp,
                color: isSelected ? AppColors.primaryNeon : AppColors.textGray,
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      level.labelKey.tr(),
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      level.helperKey.tr(),
                      style: GoogleFonts.inter(
                        color: AppColors.textGray,
                        fontSize: 10.sp,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18.sp,
                color: isSelected ? AppColors.primaryNeon : AppColors.darkBorder,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
