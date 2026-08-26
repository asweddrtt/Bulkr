import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/unit_system.dart';
import '../styles/app_color.dart';

/// Metric / imperial switch pinned above the biometric inputs.
///
/// Display only — height and weight are always stored in cm and kg regardless
/// of what's selected here.
class UnitToggle extends StatelessWidget {
  const UnitToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final UnitSystem value;
  final ValueChanged<UnitSystem> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Segment(
              label: 'unit_metric'.tr(),
              isSelected: value.isMetric,
              onTap: () => onChanged(UnitSystem.metric),
            ),
          ),
          Expanded(
            child: _Segment(
              label: 'unit_imperial'.tr(),
              isSelected: !value.isMetric,
              onTap: () => onChanged(UnitSystem.imperial),
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(vertical: 10.h),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryNeon : Colors.transparent,
          borderRadius: BorderRadius.circular(6.r),
        ),
        child: Center(
          child: Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 12.sp,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: isSelected ? Colors.black : AppColors.offWhiteMuted,
            ),
          ),
        ),
      ),
    );
  }
}
