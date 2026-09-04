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
/// Icons only, and one fixed row that never scrolls. Seven controls with their
/// names spelled out do not fit across a phone, and the version that scrolled
/// hid its last options behind a swipe nobody makes — a filter you cannot see
/// is a filter you do not use. Dropping the words is what buys every category
/// a place on screen.
///
/// The names are not gone, only quiet: each chip carries its label as a
/// tooltip and as its semantics label, so a long press names it and a screen
/// reader announces it rather than reading out an icon.
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
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Row(
        // Every chip takes an equal share of the width rather than its own
        // intrinsic size. Intrinsic sizing fits at the design scale and stops
        // fitting the moment the system font is turned up — the icons are
        // sized in `.sp`, so seven of them grow together and overflow the row.
        // Sharing the width means the chips get narrower instead, which is the
        // whole point of dropping the text: all seven on screen, always.
        children: [
          Expanded(
            child: _FilterChip(
              icon: Icons.all_inclusive_sharp,
              name: 'post_label_all'.tr(),
              accent: AppColors.primaryNeon,
              isSelected: selected == null,
              onTap: () => onSelected(null),
            ),
          ),
          for (final PostLabel label in PostLabel.values)
            Expanded(
              child: _FilterChip(
                icon: label.icon,
                name: label.labelKey.tr(),
                accent: label.accent,
                isSelected: selected == label,
                // Tapping the active filter clears it. A chip that is already
                // on is the most obvious place to reach for to turn it off.
                onTap: () => onSelected(selected == label ? null : label),
              ),
            ),
        ],
      ),
    );
  }
}

/// One icon in the filter row.
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.icon,
    required this.name,
    required this.accent,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;

  /// The label's name. Never drawn — it is the tooltip and the semantics
  /// label, which is how an icon-only control stays nameable.
  final String name;

  final Color accent;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: name,
      child: Semantics(
        label: name,
        button: true,
        selected: isSelected,
        child: PressScale(
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: Motion.scaled(context, Motion.fast),
              curve: Motion.enter,
              // Margin outside the border so the chips have air between them
              // while the tap target still fills its whole share of the row.
              margin: EdgeInsets.symmetric(horizontal: 3.w),
              padding: EdgeInsets.symmetric(vertical: 9.h),
              decoration: BoxDecoration(
                color: isSelected ? accent : Colors.transparent,
                borderRadius: BorderRadius.circular(6.r),
                border: Border.all(
                  color: isSelected ? accent : AppColors.darkBorder,
                ),
              ),
              child: Icon(
                icon,
                // Black on the filled chip: every label accent is a light
                // colour, chosen so this stays legible.
                color: isSelected ? Colors.black : AppColors.textGray,
                size: 17.sp,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
