import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../styles/app_color.dart'; // Adjust path

// For Age and Height cards
class StandardMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const StandardMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 12.h),
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(4.r), // Sharp edges like the design
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
              Text(
                value,
                style: GoogleFonts.anton(
                  fontSize: 38.sp,
                  color: Colors.white,
                  height: 1,
                ),
              ),
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
          ),
          SizedBox(height: 8.h),
          Divider(color: const Color(0xFF333333), thickness: 2.h, height: 2.h),
        ],
      ),
    );
  }
}

// For Current Mass card (horizontal layout)
class InlineMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String unit;

  const InlineMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
      margin: EdgeInsets.only(bottom: 16.h),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(4.r),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: GoogleFonts.anton(
                  fontSize: 20.sp,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 4.w),
              Text(
                unit.toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 10.sp,
                  color: AppColors.offWhiteMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class TargetMassCard extends StatelessWidget {
    final String targetValue;
    final String deltaValue;
    final bool isGain;

  const TargetMassCard({
        super.key,
                required this.targetValue,
                required this.deltaValue,
                this.isGain = true,
    });

    @override
    Widget build(BuildContext context) {
        return Container(
                width: double.infinity,
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A), // Slightly lighter than standard cards
                borderRadius: BorderRadius.circular(4.r),
                border: Border.all(color: AppColors.primaryNeon, width: 2),
      ),
        child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
        Row(
                children: [
        Icon(Icons.track_changes, color: AppColors.primaryNeon, size: 16.sp),
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
                'kg_unit'.tr().toUpperCase(),
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

        // Delta Inner Box
        Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: const BoxDecoration(
                color: Color(0xFF151515), // Very dark inner box
            ),
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
                '${isGain ? '+' : ''}$deltaValue ${'kg_unit'.tr().toUpperCase()}',
                style: GoogleFonts.anton(
                fontSize: 16.sp,
                color: const Color(0xFFFF5722), // Bright orange/red
                letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    }
}