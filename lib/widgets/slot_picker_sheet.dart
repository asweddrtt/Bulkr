import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/meal_slot.dart';
import '../styles/app_color.dart';
import 'sheet_action_row.dart';

/// Asks which part of the day something was eaten in.
///
/// One tap between deciding to log something and it being logged, and worth
/// it: without a slot the entry lands in the tracker's unsorted section, which
/// is where history from before slots existed lives. New entries should never
/// go there.
///
/// The clock's guess is offered as the highlighted row rather than applied
/// silently — a night-shift worker's dinner is not the clock's business, and a
/// wrong slot applied without asking has to be noticed before it can be fixed.
class SlotPickerSheet extends StatelessWidget {
  const SlotPickerSheet({super.key, required this.suggested});

  final MealSlot suggested;

  /// Resolves to the chosen slot, or null if the sheet was dismissed —
  /// which the caller must treat as "do not log", not as a default.
  static Future<MealSlot?> show(BuildContext context, {DateTime? now}) {
    return showModalBottomSheet<MealSlot>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SlotPickerSheet(
        suggested: MealSlot.forTimeOfDay(now ?? DateTime.now()),
      ),
    );
  }

  static IconData iconFor(MealSlot slot) {
    switch (slot) {
      case MealSlot.breakfast:
        return Icons.wb_twilight;
      case MealSlot.lunch:
        return Icons.light_mode_outlined;
      case MealSlot.dinner:
        return Icons.nights_stay_outlined;
      case MealSlot.snack:
        return Icons.cookie_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: EdgeInsets.all(16.w),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: const Color(0xFF121212),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'slot_picker_title'.tr().toUpperCase(),
              style: GoogleFonts.anton(
                color: Colors.white,
                fontSize: 16.sp,
                letterSpacing: 1.1,
              ),
            ),
            SizedBox(height: 14.h),
            for (final MealSlot slot in MealSlot.values) ...[
              SheetActionRow(
                icon: iconFor(slot),
                label: slot.labelKey.tr(),
                helper: slot == suggested ? 'slot_picker_now'.tr() : null,
                onTap: () => Navigator.of(context).pop(slot),
              ),
              if (slot != MealSlot.values.last) SizedBox(height: 8.h),
            ],
          ],
        ),
      ),
    );
  }
}
