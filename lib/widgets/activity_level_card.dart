import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';

class ActivityLevelCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool isSelected;
  final VoidCallback onTap;

  const ActivityLevelCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(bottom: 12.h), // Reduced from 16
        padding: EdgeInsets.all(16.w), // Reduced from 20
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(8.r),
          border: isSelected
              ? Border.all(color: AppColors.primaryNeon, width: 2)
              : Border.all(color: Colors.transparent, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.offWhiteMuted, size: 28.sp), // Reduced from 32
            SizedBox(height: 8.h), // Reduced from 12
            Text(
              title,
              style: GoogleFonts.anton(
                fontSize: 20.sp, // Reduced from 24
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 4.h), // Reduced from 8
            Text(
              description,
              style: GoogleFonts.inter(
                fontSize: 11.sp, // Reduced from 14
                color: AppColors.offWhiteMuted,
                height: 1.3, // Tighter line height
              ),
            ),
          ],
        ),
      ),
    );
  }
}