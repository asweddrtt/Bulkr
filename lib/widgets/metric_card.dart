import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';

/// Big-number input card. Tapping it opens a wheel picker rather than a
/// keyboard, so the value can never arrive malformed.
///
/// Renamed from `standardmetriccard.dart`, which was imported elsewhere as
/// `StandardMetricCard.dart` — a mismatch that builds on macOS but fails on
/// any case-sensitive filesystem.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    this.onTap,
    this.isPlaceholder = false,
  });

  final String label;
  final String value;
  final String unit;

  /// Null renders a read-only card (no chevron, no ripple).
  final VoidCallback? onTap;

  /// Dims the value when it's a prompt rather than a real answer — used by the
  /// date-of-birth card before the user has picked one.
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 12.h),
        margin: EdgeInsets.only(bottom: 12.h),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(4.r),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 10.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.offWhiteMuted,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 6.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Value and unit share one Expanded so the chevron sits hard
                // against the right edge without competing with them for space.
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.anton(
                            fontSize: 34.sp,
                            color:
                                isPlaceholder ? AppColors.textGray : Colors.white,
                            height: 1,
                          ),
                        ),
                      ),
                      if (unit.isNotEmpty) ...[
                        SizedBox(width: 12.w),
                        Padding(
                          padding: EdgeInsets.only(bottom: 6.h),
                          child: Text(
                            unit.toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 12.sp,
                              color: AppColors.offWhiteMuted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (onTap != null)
                  Padding(
                    padding: EdgeInsets.only(bottom: 6.h),
                    child: Icon(
                      Icons.unfold_more,
                      size: 20.sp,
                      color: AppColors.offWhiteMuted,
                    ),
                  ),
              ],
            ),
            SizedBox(height: 8.h),
            Divider(color: AppColors.darkBorder, thickness: 2.h, height: 2.h),
          ],
        ),
      ),
    );
  }
}

/// The highlighted goal card on screen 4: target weight plus the delta from
/// where the user is today.
class TargetMassCard extends StatelessWidget {
  const TargetMassCard({
    super.key,
    required this.targetValue,
    required this.deltaValue,
    required this.unitLabel,
    this.isGain = true,
    this.onTap,
  });

  final String targetValue;
  final String deltaValue;
  final String unitLabel;
  final bool isGain;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(4.r),
          border: Border.all(color: AppColors.primaryNeon, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.track_changes,
                    color: AppColors.primaryNeon, size: 16.sp),
                SizedBox(width: 8.w),
                Text(
                  'target_mass_goal'.tr().toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryNeon,
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
                if (onTap != null)
                  Icon(Icons.unfold_more,
                      size: 18.sp, color: AppColors.primaryNeon),
              ],
            ),
            SizedBox(height: 16.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  targetValue,
                  style: GoogleFonts.anton(
                    fontSize: 52.sp,
                    color: Colors.white,
                    height: 1,
                  ),
                ),
                SizedBox(width: 12.w),
                Padding(
                  padding: EdgeInsets.only(bottom: 8.h),
                  child: Text(
                    unitLabel.toUpperCase(),
                    style: GoogleFonts.anton(
                      fontSize: 18.sp,
                      color: AppColors.offWhiteMuted,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            Divider(color: AppColors.primaryNeon, thickness: 3.h, height: 3.h),
            SizedBox(height: 16.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: const BoxDecoration(color: Color(0xFF151515)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'delta_label'.tr().toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 9.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.offWhiteMuted,
                      letterSpacing: 2,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    '${isGain ? '+' : ''}$deltaValue ${unitLabel.toUpperCase()}',
                    style: GoogleFonts.anton(
                      fontSize: 16.sp,
                      color: const Color(0xFFFF5722),
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
