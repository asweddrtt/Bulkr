import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';

/// Avatar + athlete name + settings entry point at the top of the profile.
class ProfileHeader extends StatelessWidget {
  final String name;
  final VoidCallback onSettingsTap;

  const ProfileHeader({
    super.key,
    required this.name,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40.w,
          height: 40.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.cardDark,
            border: Border.all(color: AppColors.primaryNeon, width: 2),
          ),
          child: Icon(
            Icons.person,
            color: AppColors.primaryNeon,
            size: 22.sp,
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Text(
            name.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.anton(
              fontSize: 22.sp,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
        ),
        IconButton(
          onPressed: onSettingsTap,
          icon: Icon(Icons.settings, color: Colors.white, size: 22.sp),
        ),
      ],
    );
  }
}
