import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';

/// Compact stat card with a pencil affordance, used for the current and
/// target weight tiles on the profile screen.
class EditableMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final VoidCallback onEdit;

  const EditableMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(14.w, 12.h, 8.w, 14.h),
      decoration: BoxDecoration(
        color: AppColors.cardDark,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 6.h),
                  child: Text(
                    label.toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 9.sp,
                      fontWeight: FontWeight.w600,
                      color: AppColors.offWhiteMuted,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
              GestureDetector(
                onTap: onEdit,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: EdgeInsets.all(6.w),
                  child: Icon(
                    Icons.edit,
                    color: AppColors.offWhiteMuted,
                    size: 14.sp,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 6.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: GoogleFonts.anton(
                  fontSize: 34.sp,
                  color: Colors.white,
                  height: 1,
                ),
              ),
              SizedBox(width: 6.w),
              Padding(
                padding: EdgeInsets.only(bottom: 4.h),
                child: Text(
                  unit.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 11.sp,
                    color: AppColors.offWhiteMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
