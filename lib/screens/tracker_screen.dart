import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../cubit/meals/meals_cubit.dart';
import '../cubit/profile/profile_cubit.dart';
import '../cubit/tracker/tracker_cubit.dart';
import '../models/daily_log_entry.dart';
import '../models/macros.dart';
import '../models/meal.dart';
import '../models/meal_slot.dart';
import '../styles/app_color.dart';
import '../widgets/animations/count_up.dart';
import '../widgets/animations/entrance.dart';
import '../widgets/animations/press_scale.dart';
import '../widgets/calorie_ring.dart';
import '../widgets/food_search_sheet.dart';
import '../widgets/sheet_action_row.dart';
import '../widgets/slot_picker_sheet.dart';
import '../widgets/water_card.dart';

const Color _cardColor = Color(0xFF1A1A1A);
const Color _textMuted = Color(0xFF9CA3AF);

/// Colours the three macros are drawn in everywhere in the app.
const Color _proteinColor = AppColors.primaryNeon;
const Color _carbsColor = Color(0xFF6FD3FF);
const Color _fatColor = Color(0xFFFF9E3D);

/// The Tracker tab: today's food against today's targets.
///
/// The dashboard already shows what the targets *are*. This is the only screen
/// that shows what has been eaten against them — `daily_logs` has been
/// collecting rows since the Meals tab shipped and nothing has ever read them
/// back.
class TrackerScreen extends StatelessWidget {
  const TrackerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<TrackerCubit, TrackerState>(
      listenWhen: (previous, current) =>
          previous.actionErrorKey != current.actionErrorKey &&
          current.actionErrorKey != null,
      listener: (context, state) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF2A2A2A),
              content: Text(
                // The Postgres detail rides along, because 42501 reads
                // nothing like a network problem and the difference is the
                // whole diagnosis.
                [state.actionErrorKey!.tr(), state.actionErrorDetail]
                    .whereType<String>()
                    .join('\n'),
                style: GoogleFonts.inter(color: Colors.white, fontSize: 12.sp),
              ),
            ),
          );
        context.read<TrackerCubit>().clearActionError();
      },
      child: BlocBuilder<TrackerCubit, TrackerState>(
        builder: (context, state) {
          switch (state.status) {
            case TrackerStatus.initial:
            case TrackerStatus.loading:
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primaryNeon),
              );

            case TrackerStatus.missing:
              return _Notice(text: 'tracker_no_profile'.tr());

            case TrackerStatus.failure:
              return _Notice(
                text: [
                  'tracker_load_failed'.tr(),
                  state.errorMessage,
                ].whereType<String>().join('\n\n'),
                onRetry: () => context.read<TrackerCubit>().load(),
              );

            case TrackerStatus.ready:
              return _TrackerView(state: state);
          }
        },
      ),
    );
  }
}

class _TrackerView extends StatelessWidget {
  const _TrackerView({required this.state});

  final TrackerState state;

  @override
  Widget build(BuildContext context) {
    final List<DailyLogEntry> unsorted = state.unsortedEntries;

    return RefreshIndicator(
      onRefresh: () => context.read<TrackerCubit>().refresh(),
      backgroundColor: _cardColor,
      color: AppColors.primaryNeon,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 32.h),
        children: staggered(
          [
            _DayStrip(state: state),
            SizedBox(height: 12.h),
            _CalorieHeadline(state: state),
            SizedBox(height: 18.h),
            _MacroTotals(state: state),
            SizedBox(height: 18.h),
            WaterCard(state: state),
            // Today only. UserRepository writes the weigh-in from the clock and
            // supersedes the same local day, so there is no honest way to
            // backdate one — offering the field on a past day would promise
            // something the write cannot do.
            if (state.isToday) ...[
              SizedBox(height: 14.h),
              _WeightRow(state: state),
            ],
            SizedBox(height: 22.h),
            for (final MealSlot slot in MealSlot.values) ...[
              _SlotSection(
                slot: slot,
                entries: state.entriesIn(slot),
                total: state.totalIn(slot),
              ),
              SizedBox(height: 14.h),
            ],
            // Only when it has something in it. Every row logged before slots
            // existed lands here, so on the day this ships it is where a
            // returning user's whole history is — hiding it would make the
            // day's total disagree with the entries they can see they made.
            if (unsorted.isNotEmpty)
              _SlotSection(
                slot: null,
                entries: unsorted,
                total: state.unsortedTotal,
              ),
          ],
          step: const Duration(milliseconds: 55),
        ),
      ),
    );
  }
}

/// Which day is being shown, and the arrows that move between them.
///
/// Back goes anywhere; forward stops at today. Both reload — every read is
/// already scoped by the day, so browsing is a change of one field.
class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.state});

  final TrackerState state;

  @override
  Widget build(BuildContext context) {
    final TrackerCubit cubit = context.read<TrackerCubit>();
    final bool isToday = state.isToday;

    return Row(
      children: [
        _Arrow(icon: Icons.chevron_left, onTap: cubit.previousDay),
        Expanded(
          child: Column(
            children: [
              Text(
                (isToday ? 'tracker_title'.tr() : DateFormat.MMMd().format(state.day))
                    .toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.anton(
                  fontSize: 24.sp,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
              Text(
                DateFormat.yMMMEd().format(state.day),
                style: GoogleFonts.inter(fontSize: 10.sp, color: _textMuted),
              ),
            ],
          ),
        ),
        // Dimmed rather than removed on today, so the strip does not reflow
        // every time you walk back to it.
        _Arrow(
          icon: Icons.chevron_right,
          onTap: cubit.nextDay,
          enabled: !isToday,
        ),
        // Only worth offering when it would do something.
        if (!isToday)
          PressScale(
            child: GestureDetector(
              onTap: () => cubit.showDay(DateTime.now()),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 8.h),
                child: Text(
                  'tracker_today'.tr().toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 10.sp,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryNeon,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.onTap, this.enabled = true});

  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 26.sp),
      color: Colors.white,
      disabledColor: AppColors.darkBorder,
    );
  }
}

/// Today's weigh-in, from the same field the dashboard writes.
///
/// Here as well as on the dashboard because the tracker is where someone
/// already is at the end of a day, and walking to another tab to record one
/// number is how weigh-ins get skipped. It writes through
/// [UserRepository.logWeight], so a second entry on the same day replaces the
/// first rather than stacking a point on the chart.
class _WeightRow extends StatelessWidget {
  const _WeightRow({required this.state});

  final TrackerState state;

  @override
  Widget build(BuildContext context) {
    final double current = state.profile?.currentWeightKg ?? 0;

    return PressScale(
      child: GestureDetector(
        onTap: () => _logWeight(context, current),
        behavior: HitTestBehavior.opaque,
        child: Container(
          decoration: BoxDecoration(
            color: _cardColor,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: AppColors.darkBorder),
          ),
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
          child: Row(
            children: [
              Icon(Icons.monitor_weight_outlined,
                  size: 15.sp, color: AppColors.primaryNeon),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  'tracker_weigh_in'.tr().toUpperCase(),
                  style: GoogleFonts.anton(
                    fontSize: 14.sp,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Text(
                current > 0
                    ? '${current.toStringAsFixed(1)}${'kg_unit'.tr()}'
                    : 'tracker_weigh_in_none'.tr(),
                style: GoogleFonts.inter(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  color: current > 0 ? Colors.white : _textMuted,
                ),
              ),
              SizedBox(width: 4.w),
              Icon(Icons.chevron_right, size: 18.sp, color: _textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// The ring, and the number the whole screen is about.
class _CalorieHeadline extends StatelessWidget {
  const _CalorieHeadline({required this.state});

  final TrackerState state;

  @override
  Widget build(BuildContext context) {
    final int eaten = state.consumed.calories.round();
    final int? remaining = state.caloriesRemaining;
    final int? target = state.calorieTarget;

    return Center(
      child: CalorieRing(
        progress: state.calorieProgress,
        isOver: state.isOverTarget,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (remaining == null) ...[
              // No target on the row. Showing intake alone is honest; showing
              // it as a fraction of zero would not be.
              CountUpText(
                value: eaten,
                formatter: NumberFormat('#,###').format,
                style: GoogleFonts.anton(
                  fontSize: 40.sp,
                  height: 1,
                  color: Colors.white,
                ),
              ),
              Text(
                'tracker_eaten_label'.tr().toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 9.sp,
                  color: _textMuted,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.4,
                ),
              ),
            ] else ...[
              CountUpText(
                value: remaining.abs(),
                formatter: NumberFormat('#,###').format,
                style: GoogleFonts.anton(
                  fontSize: 44.sp,
                  height: 1,
                  color: state.isOverTarget
                      ? CalorieRing.overColor
                      : AppColors.primaryNeon,
                ),
              ),
              Text(
                (state.isOverTarget
                        ? 'tracker_over_label'.tr()
                        : 'tracker_remaining_label'.tr())
                    .toUpperCase(),
                style: GoogleFonts.inter(
                  fontSize: 9.sp,
                  color: _textMuted,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.4,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'tracker_of_target'.tr(namedArgs: {
                  'eaten': NumberFormat('#,###').format(eaten),
                  'target': NumberFormat('#,###').format(target),
                }),
                style: GoogleFonts.inter(fontSize: 11.sp, color: _textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Protein, carbs and fat eaten against their targets.
class _MacroTotals extends StatelessWidget {
  const _MacroTotals({required this.state});

  final TrackerState state;

  @override
  Widget build(BuildContext context) {
    final Macros eaten = state.consumed;
    final Macros targets = state.macroTargets;

    return Row(
      children: [
        Expanded(
          child: _MacroColumn(
            color: _proteinColor,
            labelKey: 'macro_protein',
            eaten: eaten.proteinG,
            target: targets.proteinG,
            fraction: state.progressFor(eaten.proteinG, targets.proteinG),
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: _MacroColumn(
            color: _carbsColor,
            labelKey: 'macro_carbs',
            eaten: eaten.carbsG,
            target: targets.carbsG,
            fraction: state.progressFor(eaten.carbsG, targets.carbsG),
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: _MacroColumn(
            color: _fatColor,
            labelKey: 'macro_fat',
            eaten: eaten.fatG,
            target: targets.fatG,
            fraction: state.progressFor(eaten.fatG, targets.fatG),
          ),
        ),
      ],
    );
  }
}

class _MacroColumn extends StatelessWidget {
  const _MacroColumn({
    required this.color,
    required this.labelKey,
    required this.eaten,
    required this.target,
    required this.fraction,
  });

  final Color color;
  final String labelKey;
  final double eaten;
  final double target;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelKey.tr().toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 9.sp,
            fontWeight: FontWeight.bold,
            color: _textMuted,
            letterSpacing: 1.2,
          ),
        ),
        SizedBox(height: 6.h),
        ClipRRect(
          borderRadius: BorderRadius.circular(3.r),
          child: Container(
            height: 6.h,
            color: AppColors.darkBorder,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction,
              child: Container(color: color),
            ),
          ),
        ),
        SizedBox(height: 6.h),
        Text(
          target > 0
              ? '${eaten.round()} / ${target.round()}${'gram_short'.tr()}'
              : '${eaten.round()}${'gram_short'.tr()}',
          style: GoogleFonts.inter(
            fontSize: 11.sp,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

/// One part of the day: its entries, its subtotal, and the button that adds to
/// it.
///
/// A null [slot] is the unsorted section — entries from before slots existed.
/// It gets no add button, because nothing should newly write a slotless entry;
/// its rows are editable, and moving one is how a user gives it a slot.
class _SlotSection extends StatelessWidget {
  const _SlotSection({
    required this.slot,
    required this.entries,
    required this.total,
  });

  final MealSlot? slot;
  final List<DailyLogEntry> entries;
  final Macros total;

  @override
  Widget build(BuildContext context) {
    final MealSlot? current = slot;

    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AppColors.darkBorder),
      ),
      padding: EdgeInsets.fromLTRB(14.w, 12.h, 8.w, 12.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (current != null) ...[
                Icon(
                  SlotPickerSheet.iconFor(current),
                  size: 15.sp,
                  color: AppColors.primaryNeon,
                ),
                SizedBox(width: 8.w),
              ],
              Expanded(
                child: Text(
                  (current?.labelKey ?? 'slot_unsorted').tr().toUpperCase(),
                  style: GoogleFonts.anton(
                    fontSize: 14.sp,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ),
              Text(
                entries.isEmpty
                    ? 'tracker_slot_empty'.tr()
                    : 'kcal_value'.tr(namedArgs: {
                        'kcal': NumberFormat('#,###')
                            .format(total.calories.round()),
                      }),
                style: GoogleFonts.inter(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                  color: entries.isEmpty ? _textMuted : Colors.white,
                ),
              ),
              if (current != null)
                _AddButton(slot: current)
              else
                SizedBox(width: 8.w),
            ],
          ),
          if (entries.isNotEmpty) ...[
            SizedBox(height: 6.h),
            for (final DailyLogEntry entry in entries)
              _EntryRow(entry: entry),
          ],
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.slot});

  final MealSlot slot;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => _openAddSheet(context, slot),
      icon: Icon(Icons.add_circle, color: AppColors.primaryNeon, size: 24.sp),
      tooltip: 'tracker_add_to'.tr(namedArgs: {'slot': slot.labelKey.tr()}),
    );
  }
}

/// One thing eaten. Tapping it opens the actions for it.
class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});

  final DailyLogEntry entry;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: () => _openEntryActions(context, entry),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.fromLTRB(0, 7.h, 8.w, 7.h),
          child: Row(
            children: [
              Icon(
                entry.isMeal
                    ? Icons.restaurant_menu_rounded
                    : Icons.eco_outlined,
                size: 14.sp,
                color: _textMuted,
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName ?? 'tracker_entry_unnamed'.tr(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    if (entry.hasQuantity) ...[
                      SizedBox(height: 2.h),
                      Text(
                        '${entry.quantityG.round()}${'gram_short'.tr()}',
                        style: GoogleFonts.inter(
                          fontSize: 10.sp,
                          color: _textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                NumberFormat('#,###').format(entry.macros.calories.round()),
                style: GoogleFonts.anton(
                  fontSize: 15.sp,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 36.sp, color: AppColors.textGray),
            SizedBox(height: 14.h),
            Text(
              text,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12.sp,
                color: AppColors.offWhiteMuted,
                height: 1.5,
              ),
            ),
            if (onRetry != null) ...[
              SizedBox(height: 18.h),
              OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.darkBorder),
                  padding:
                      EdgeInsets.symmetric(horizontal: 22.w, vertical: 12.h),
                ),
                child: Text(
                  'retry'.tr().toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// --- Flows ------------------------------------------------------------------

/// Meal or food, then the thing itself.
///
/// Two routes to one slot because they are genuinely different questions. A
/// meal is something already assembled and reused; a food is a one-off that
/// should not clutter the library with a banana.
Future<void> _openAddSheet(BuildContext context, MealSlot slot) async {
  final TrackerCubit tracker = context.read<TrackerCubit>();
  final MealsCubit meals = context.read<MealsCubit>();

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => SafeArea(
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
              'tracker_add_to'
                  .tr(namedArgs: {'slot': slot.labelKey.tr()}).toUpperCase(),
              style: GoogleFonts.anton(
                color: Colors.white,
                fontSize: 16.sp,
                letterSpacing: 1.1,
              ),
            ),
            SizedBox(height: 14.h),
            SheetActionRow(
              icon: Icons.restaurant_menu_rounded,
              label: 'tracker_add_meal'.tr(),
              helper: 'tracker_add_meal_helper'.tr(),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickMeal(context, tracker, meals, slot);
              },
            ),
            SizedBox(height: 8.h),
            SheetActionRow(
              icon: Icons.search,
              label: 'tracker_add_food'.tr(),
              helper: 'tracker_add_food_helper'.tr(),
              onTap: () {
                Navigator.of(sheetContext).pop();
                FoodSearchSheet.show(
                  context,
                  titleKey: 'tracker_add_food',
                  subtitleKey: 'tracker_add_food_subtitle',
                  onPicked: (food, grams) => tracker.logFood(
                    food: food,
                    grams: grams,
                    slot: slot,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Picks a meal out of the library the Meals tab has already loaded.
///
/// Reads [MealsCubit] rather than fetching again: the shell loads the library
/// once on mount, and a second copy here would be a second source of truth
/// about which meals exist.
Future<void> _pickMeal(
  BuildContext context,
  TrackerCubit tracker,
  MealsCubit meals,
  MealSlot slot,
) async {
  final List<Meal> library = meals.state.library;

  if (library.isEmpty) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF2A2A2A),
          content: Text(
            'tracker_no_meals'.tr(),
            style: GoogleFonts.inter(color: Colors.white, fontSize: 13.sp),
          ),
        ),
      );
    return;
  }

  final Meal? chosen = await showModalBottomSheet<Meal>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => Container(
      height: 0.7.sh,
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.vertical(top: Radius.circular(14.r)),
        border: Border(top: BorderSide(color: AppColors.darkBorder)),
      ),
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'tracker_pick_meal'.tr().toUpperCase(),
            style: GoogleFonts.anton(
              color: Colors.white,
              fontSize: 16.sp,
              letterSpacing: 1.1,
            ),
          ),
          SizedBox(height: 12.h),
          Expanded(
            child: ListView.separated(
              itemCount: library.length,
              separatorBuilder: (_, __) => SizedBox(height: 8.h),
              itemBuilder: (_, index) {
                final Meal meal = library[index];
                return SheetActionRow(
                  icon: Icons.restaurant_menu_rounded,
                  label: meal.title,
                  helper: 'kcal_value'.tr(namedArgs: {
                    'kcal': '${meal.totals.caloriesRounded}',
                  }),
                  onTap: () => Navigator.of(sheetContext).pop(meal),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );

  if (chosen == null) return;
  await tracker.logMeal(meal: chosen, slot: slot);
  // The meal card's tick reads today's log, so it is now out of date.
  await meals.refresh();
}

/// Move it, resize it, or remove it.
Future<void> _openEntryActions(BuildContext context, DailyLogEntry entry) async {
  final TrackerCubit tracker = context.read<TrackerCubit>();
  final MealsCubit meals = context.read<MealsCubit>();

  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => SafeArea(
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
              (entry.displayName ?? 'tracker_entry_unnamed'.tr()).toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.anton(
                color: Colors.white,
                fontSize: 16.sp,
                letterSpacing: 1.1,
              ),
            ),
            SizedBox(height: 14.h),
            // Offered only when there is a weight to scale from. A meal logged
            // without ingredient weights has no basis, and inventing one would
            // rewrite the calories — see DailyLogEntry.canRescale.
            if (entry.canRescale) ...[
              SheetActionRow(
                icon: Icons.straighten,
                label: 'tracker_entry_amount'.tr(),
                helper: '${entry.quantityG.round()}${'gram_short'.tr()}',
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final double? grams = await _askGrams(context, entry);
                  if (grams != null) await tracker.resizeEntry(entry, grams);
                },
              ),
              SizedBox(height: 8.h),
            ],
            SheetActionRow(
              icon: Icons.swap_horiz,
              label: 'tracker_entry_move'.tr(),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final MealSlot? slot = await SlotPickerSheet.show(context);
                if (slot != null) await tracker.moveEntry(entry, slot);
              },
            ),
            SizedBox(height: 8.h),
            SheetActionRow(
              icon: Icons.delete_outline,
              label: 'tracker_entry_delete'.tr(),
              isDestructive: true,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await tracker.deleteEntry(entry);
                // A deleted entry can change whether its meal still counts as
                // logged today, which is what the card's tick shows.
                if (entry.isMeal) await meals.refresh();
              },
            ),
          ],
        ),
      ),
    ),
  );
}

/// Records today's weight, and tells the dashboard about it.
///
/// [ProfileCubit] holds its own copy of the `users` row and drives the whole
/// dashboard — the chart, the headline weight, the percentage to target — so
/// writing a weigh-in from here without refreshing it would leave two screens
/// disagreeing about what the user weighs until the app restarts.
///
/// The tracker reloads too, and not only for the number: the water goal is
/// derived from `current_weight_kg`, so a weigh-in moves it.
Future<void> _logWeight(BuildContext context, double current) async {
  final TrackerCubit tracker = context.read<TrackerCubit>();
  final ProfileCubit profile = context.read<ProfileCubit>();

  final double? weight = await _askWeight(context, current);
  if (weight == null) return;

  await tracker.logWeight(weight);
  await profile.refresh();
}

/// A number field for a weigh-in.
///
/// Always kilograms, unlike the dashboard's wheel picker, which respects the
/// user's unit setting. That is a gap worth naming rather than hiding: this is
/// a shortcut for someone who already knows their number, and converting it
/// silently would be worse than the units being explicit on the field.
Future<double?> _askWeight(BuildContext context, double current) {
  final TextEditingController controller = TextEditingController(
    text: current > 0 ? current.toStringAsFixed(1) : '',
  );

  return showDialog<double>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.r),
        side: const BorderSide(color: AppColors.darkBorder),
      ),
      title: Text(
        'tracker_weigh_in'.tr().toUpperCase(),
        style: GoogleFonts.anton(
          color: Colors.white,
          fontSize: 15.sp,
          letterSpacing: 1,
        ),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: GoogleFonts.anton(color: Colors.white, fontSize: 22.sp),
        decoration: InputDecoration(
          suffixText: 'kg_unit'.tr(),
          suffixStyle: GoogleFonts.inter(color: _textMuted, fontSize: 12.sp),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.darkBorder),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.primaryNeon),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(
            'cancel'.tr().toUpperCase(),
            style: GoogleFonts.inter(color: _textMuted, fontSize: 12.sp),
          ),
        ),
        TextButton(
          onPressed: () {
            final double? kg = double.tryParse(controller.text.trim());
            // An upper bound as well as a lower one: a mistyped 800 would
            // move the calorie plan and the water goal with it.
            Navigator.of(dialogContext)
                .pop(kg != null && kg > 0 && kg < 500 ? kg : null);
          },
          child: Text(
            'save'.tr().toUpperCase(),
            style: GoogleFonts.inter(
              color: AppColors.primaryNeon,
              fontSize: 12.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );
}

/// A number field for a new amount.
///
/// A plain dialog rather than the wheel picker used for height and weight:
/// those are bounded ranges with a natural resolution, and a portion size is
/// neither — 37g of peanut butter is a thing someone weighs and types.
Future<double?> _askGrams(BuildContext context, DailyLogEntry entry) {
  final TextEditingController controller =
      TextEditingController(text: '${entry.quantityG.round()}');

  return showDialog<double>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.r),
        side: const BorderSide(color: AppColors.darkBorder),
      ),
      title: Text(
        'tracker_entry_amount'.tr().toUpperCase(),
        style: GoogleFonts.anton(
          color: Colors.white,
          fontSize: 15.sp,
          letterSpacing: 1,
        ),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        style: GoogleFonts.anton(color: Colors.white, fontSize: 22.sp),
        decoration: InputDecoration(
          suffixText: 'gram_short'.tr(),
          suffixStyle:
              GoogleFonts.inter(color: _textMuted, fontSize: 12.sp),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.darkBorder),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.primaryNeon),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(
            'cancel'.tr().toUpperCase(),
            style: GoogleFonts.inter(color: _textMuted, fontSize: 12.sp),
          ),
        ),
        TextButton(
          onPressed: () {
            final double? grams = double.tryParse(controller.text.trim());
            Navigator.of(dialogContext)
                .pop(grams != null && grams > 0 ? grams : null);
          },
          child: Text(
            'save'.tr().toUpperCase(),
            style: GoogleFonts.inter(
              color: AppColors.primaryNeon,
              fontSize: 12.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );
}
