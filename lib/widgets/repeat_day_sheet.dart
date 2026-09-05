import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../cubit/tracker/tracker_cubit.dart';
import '../models/meal_slot.dart';
import '../styles/app_color.dart';
import 'sheet_action_row.dart';
import 'slot_picker_sheet.dart';

/// Copies a previous day onto the one being shown.
///
/// Most people eat the same five breakfasts. Re-entering Tuesday on Thursday
/// item by item is the friction that gets a tracker abandoned in week three,
/// and this is the shortest way out of it: pick a day, optionally pick one
/// part of it, done.
///
/// Offers the last seven days rather than a date picker. Anything further back
/// is not "what I ate recently", it is research, and the date strip at the top
/// of the tracker already goes anywhere.
Future<void> showRepeatDaySheet(BuildContext context) async {
  final TrackerCubit cubit = context.read<TrackerCubit>();
  final DateTime showing = cubit.state.day;

  final List<DateTime> candidates = [
    for (int back = 1; back <= 7; back++)
      showing.subtract(Duration(days: back)),
  ];

  final DateTime? from = await showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => SheetShell(
      title: 'repeat_day_title'.tr(),
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 12.h),
          child: Text(
            'repeat_day_helper'.tr(),
            style: GoogleFonts.inter(
              color: AppColors.textGray,
              fontSize: 11.sp,
              height: 1.5,
            ),
          ),
        ),
        for (final DateTime day in candidates)
          SheetActionRow(
            icon: Icons.calendar_today_outlined,
            label: DateFormat.EEEE().format(day),
            helper: DateFormat.yMMMd().format(day),
            onTap: () => Navigator.of(sheetContext).pop(day),
          ),
      ],
    ),
  );

  if (from == null || !context.mounted) return;

  // Which part of it. "Everything" is first because it is the common answer —
  // the point of this is not having to think about it.
  //
  // Its own sheet rather than SlotPickerSheet, which answers a different
  // question: that one asks where a single new entry belongs and has no
  // "all of them". Here the whole-day answer is the default one.
  final _RepeatChoice? choice = await showModalBottomSheet<_RepeatChoice>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => SheetShell(
      title: 'repeat_day_slot_title'.tr(),
      children: [
        SheetActionRow(
          icon: Icons.today_outlined,
          label: 'repeat_day_all'.tr(),
          helper: 'repeat_day_all_helper'.tr(),
          onTap: () => Navigator.of(sheetContext).pop(const _RepeatChoice()),
        ),
        for (final MealSlot slot in MealSlot.values)
          SheetActionRow(
            icon: SlotPickerSheet.iconFor(slot),
            label: slot.labelKey.tr(),
            onTap: () =>
                Navigator.of(sheetContext).pop(_RepeatChoice(slot: slot)),
          ),
      ],
    ),
  );

  // Dismissing is not "all of it": a null choice means the user backed out,
  // and a whole day copied because somebody swiped a sheet away would be the
  // worst possible reading of that gesture.
  if (choice == null || !context.mounted) return;

  final int copied = await cubit.repeatDay(from: from, slot: choice.slot);
  if (!context.mounted) return;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF2A2A2A),
        content: Text(
          copied == 0
              ? 'repeat_day_nothing'.tr()
              : 'repeat_day_done'.tr(namedArgs: {'count': '$copied'}),
          style: GoogleFonts.inter(color: Colors.white, fontSize: 12.sp),
        ),
      ),
    );
}

/// What the second sheet answered: one slot, or the whole day.
///
/// A class rather than a nullable [MealSlot] because null already means
/// "the whole day" to [TrackerCubit.repeatDay], and it would also be what a
/// dismissed sheet returns. Those must not be the same value.
class _RepeatChoice {
  const _RepeatChoice({this.slot});

  /// Null for the whole day.
  final MealSlot? slot;
}
