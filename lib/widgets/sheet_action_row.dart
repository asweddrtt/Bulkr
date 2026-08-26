import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';
import 'animations/press_scale.dart';

/// One tappable choice in a bottom sheet.
///
/// Shared so every sheet's options are the same shape and weight — the thing
/// that makes a set of sheets read as one app rather than several.
class SheetActionRow extends StatelessWidget {
  const SheetActionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.helper,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// A second line, for a choice whose consequences are not obvious from its
  /// name — which is most destructive ones.
  final String? helper;

  /// Tints the row red and is the only styling difference. Destructive options
  /// are not hidden or made harder to hit; they are just unmistakable.
  final bool isDestructive;

  static const Color destructive = Color(0xFFFF5722);

  @override
  Widget build(BuildContext context) {
    final Color tint = isDestructive ? destructive : AppColors.primaryNeon;

    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(5.r),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Row(
            children: [
              Icon(icon, color: tint, size: 20.sp),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: 1.2,
                      ),
                    ),
                    if (helper != null) ...[
                      SizedBox(height: 3.h),
                      Text(
                        helper!,
                        style: GoogleFonts.inter(
                          fontSize: 10.sp,
                          color: AppColors.textGray,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The container every one of these sheets sits in: rounded top, hairline
/// border, safe-area padding at the bottom.
class SheetShell extends StatelessWidget {
  const SheetShell({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 12.h),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14.r)),
        border: Border(top: BorderSide(color: AppColors.darkBorder)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.anton(
                fontSize: 16.sp,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
            SizedBox(height: 16.h),
            ...children,
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
  }
}
