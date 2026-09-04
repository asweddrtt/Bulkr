import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/post_label.dart';
import '../styles/app_color.dart';
import 'animations/motion.dart';
import 'animations/press_scale.dart';

/// The label on a post, as it appears on a card.
///
/// Tinted rather than filled: on a card the chip is a note about the post, not
/// the loudest thing on it. The filter bar's version fills, because there the
/// chip *is* the control.
class PostLabelChip extends StatelessWidget {
  const PostLabelChip({super.key, required this.label, this.onTap});

  final PostLabel label;

  /// Filters the feed to this label. Null on a card that is not in a feed.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget chip = Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        // A wash of the label's colour, not the colour itself. Six saturated
        // chips down a scrolling feed is a colour chart.
        color: label.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4.r),
        border: Border.all(color: label.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(label.icon, color: label.accent, size: 11.sp),
          SizedBox(width: 5.w),
          Text(
            label.labelKey.tr().toUpperCase(),
            style: GoogleFonts.inter(
              color: label.accent,
              fontSize: 9.sp,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return chip;

    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: chip,
      ),
    );
  }
}

/// The row of label filters above the feed.
///
/// All six plus "all", always visible, never scrolling. That is what caps the
/// label set at six: a filter bar you have to scroll is one whose last option
/// nobody knows exists.
class PostLabelFilterBar extends StatelessWidget {
  const PostLabelFilterBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  /// The active filter, or null for all labels.
  final PostLabel? selected;

  /// Called with the tapped label, or null when "all" is tapped.
  final ValueChanged<PostLabel?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34.h,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 20.w),
        // Horizontally scrollable even though it is meant to fit, because
        // "fits" depends on the text: a translation with longer words, or a
        // large system font, must overflow into a scroll rather than off the
        // edge of the screen.
        children: [
          _FilterChip(
            icon: Icons.all_inclusive_sharp,
            text: 'post_label_all'.tr(),
            accent: AppColors.primaryNeon,
            isSelected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final PostLabel label in PostLabel.values)
            _FilterChip(
              icon: label.icon,
              text: label.labelKey.tr(),
              accent: label.accent,
              isSelected: selected == label,
              // Tapping the active filter clears it. A chip that is already on
              // is the most obvious place to reach for to turn it off.
              onTap: () => onSelected(selected == label ? null : label),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.icon,
    required this.text,
    required this.accent,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final Color accent;
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
          margin: EdgeInsets.only(right: 8.w),
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
          decoration: BoxDecoration(
            color: isSelected ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(6.r),
            border: Border.all(
              color: isSelected ? accent : AppColors.darkBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                // Black on the filled chip: every label accent is a light
                // colour, chosen so this stays legible.
                color: isSelected ? Colors.black : AppColors.textGray,
                size: 13.sp,
              ),
              SizedBox(width: 6.w),
              Text(
                text.toUpperCase(),
                style: GoogleFonts.inter(
                  color: isSelected ? Colors.black : AppColors.textGray,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
