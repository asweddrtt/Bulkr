import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/gender.dart';
import '../styles/app_color.dart';

/// Three-way selector feeding the `gender_type` column.
///
/// Gender changes the Mifflin-St Jeor constant, which is the only reason the
/// flow asks for it — the label on screen 2 says as much.
class GenderSelector extends StatelessWidget {
  const GenderSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// Null until the user picks — nothing is preselected, so we never guess
  /// and silently bake a wrong BMR constant into their target.
  final Gender? value;
  final ValueChanged<Gender> onChanged;

  static const Map<Gender, IconData> _icons = {
    Gender.male: Icons.male,
    Gender.female: Icons.female,
    Gender.other: Icons.transgender,
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final gender in Gender.values) ...[
          Expanded(
            child: _GenderTile(
              icon: _icons[gender]!,
              label: gender.labelKey.tr(),
              isSelected: value == gender,
              onTap: () => onChanged(gender),
            ),
          ),
          if (gender != Gender.values.last) SizedBox(width: 10.w),
        ],
      ],
    );
  }
}

class _GenderTile extends StatelessWidget {
  const _GenderTile({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
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
        padding: EdgeInsets.symmetric(vertical: 14.h),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(6.r),
          border: Border.all(
            color: isSelected ? AppColors.primaryNeon : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 24.sp,
              color: isSelected ? AppColors.primaryNeon : AppColors.offWhiteMuted,
            ),
            SizedBox(height: 6.h),
            Text(
              label.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 10.sp,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: isSelected ? Colors.white : AppColors.offWhiteMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
