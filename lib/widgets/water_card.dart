import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/hydration.dart';
import '../cubit/tracker/tracker_cubit.dart';
import '../styles/app_color.dart';
import 'animations/motion.dart';
import 'animations/press_scale.dart';

/// Water drunk on the day being shown, against the day's goal.
///
/// The goal comes from bodyweight — 35 ml per kg, the figure the insight card
/// has been quoting all along — so for most people it is never set and moves
/// on its own as they bulk. Tapping the goal is how it gets overridden, and
/// how the override is handed back.
class WaterCard extends StatelessWidget {
  const WaterCard({super.key, required this.state});

  final TrackerState state;

  /// Blue rather than the app's neon: water is not a macro, and the one place
  /// it appears should not read as a fourth nutrient.
  static const Color accent = Color(0xFF6FD3FF);

  @override
  Widget build(BuildContext context) {
    final int drunk = state.waterMl;
    final int? target = state.waterTargetMl;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AppColors.darkBorder),
      ),
      padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 14.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.water_drop_outlined, size: 15.sp, color: accent),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  'water_title'.tr().toUpperCase(),
                  style: GoogleFonts.anton(
                    fontSize: 14.sp,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ),
              // The goal is the tap target, because that is the thing someone
              // wants to change when they look at it and disagree.
              PressScale(
                child: GestureDetector(
                  onTap: () => _editTarget(context),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
                    child: Text(
                      target == null
                          ? 'water_set_goal'.tr()
                          : 'water_progress'.tr(namedArgs: {
                              'drunk': '$drunk',
                              'target': '$target',
                            }),
                      style: GoogleFonts.inter(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w600,
                        color: target == null ? accent : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          if (state.waterErrorDetail != null)
            // An empty glass and a table that does not exist must not look the
            // same. This is what "you have not run tracker_water.sql" looks
            // like, rather than a card that silently reads zero forever.
            Text(
              'water_unavailable'.tr(),
              style: GoogleFonts.inter(
                fontSize: 11.sp,
                color: AppColors.textGray,
                height: 1.4,
              ),
            )
          else ...[
            if (target != null) ...[
              _Glasses(state: state),
              SizedBox(height: 12.h),
            ] else
              Padding(
                padding: EdgeInsets.only(bottom: 10.h),
                child: Text(
                  'water_today'.tr(namedArgs: {'drunk': '$drunk'}),
                  style: GoogleFonts.anton(fontSize: 20.sp, color: Colors.white),
                ),
              ),
            _AddRow(state: state),
          ],
        ],
      ),
    );
  }

  /// A row of cups that fill as the day goes on.
  ///
  /// Cups rather than only a bar because hydration is the one thing on this
  /// screen people count rather than measure — "four glasses in" is how it is
  /// actually thought about.
  Future<void> _editTarget(BuildContext context) async {
    final TrackerCubit cubit = context.read<TrackerCubit>();
    final int? current = state.waterTargetMl;
    final TextEditingController controller =
        TextEditingController(text: current == null ? '' : '$current');

    final _TargetChoice? choice = await showDialog<_TargetChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.r),
          side: const BorderSide(color: AppColors.darkBorder),
        ),
        title: Text(
          'water_goal_title'.tr().toUpperCase(),
          style: GoogleFonts.anton(
            color: Colors.white,
            fontSize: 15.sp,
            letterSpacing: 1,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: GoogleFonts.anton(color: Colors.white, fontSize: 22.sp),
              decoration: InputDecoration(
                suffixText: 'ml_unit'.tr(),
                suffixStyle: GoogleFonts.inter(
                  color: AppColors.textGray,
                  fontSize: 12.sp,
                ),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.darkBorder),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: accent),
                ),
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              'water_goal_derived'.tr(namedArgs: {
                'perKg': '${Hydration.mlPerKg.round()}',
              }),
              style: GoogleFonts.inter(
                fontSize: 11.sp,
                color: AppColors.textGray,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          // Only worth offering when there is an override to give back.
          if (state.hasCustomWaterTarget)
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(const _TargetChoice.derive()),
              child: Text(
                'water_goal_auto'.tr().toUpperCase(),
                style: GoogleFonts.inter(
                  color: AppColors.textGray,
                  fontSize: 11.sp,
                ),
              ),
            ),
          TextButton(
            onPressed: () {
              final int? ml = int.tryParse(controller.text.trim());
              if (ml == null || ml <= 0 || ml > Hydration.maxTargetMl) {
                Navigator.of(dialogContext).pop();
                return;
              }
              Navigator.of(dialogContext).pop(_TargetChoice.set(ml));
            },
            child: Text(
              'save'.tr().toUpperCase(),
              style: GoogleFonts.inter(
                color: accent,
                fontSize: 12.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (choice == null) return;
    await cubit.setWaterTarget(choice.millilitres);
  }
}

/// What came back from the goal dialog. A class rather than a nullable int,
/// because null already means "dismissed" and clearing the goal is also a null
/// — two different outcomes that must not collapse into one.
class _TargetChoice {
  const _TargetChoice.set(this.millilitres);
  const _TargetChoice.derive() : millilitres = null;

  final int? millilitres;
}

class _Glasses extends StatelessWidget {
  const _Glasses({required this.state});

  final TrackerState state;

  @override
  Widget build(BuildContext context) {
    final int total = state.waterGlasses;
    final int filled =
        (state.waterMl / Hydration.glassMl).floor().clamp(0, total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6.w,
          runSpacing: 6.h,
          children: [
            for (int i = 0; i < total; i++)
              AnimatedContainer(
                duration: Motion.scaled(context, Motion.fast),
                width: 14.w,
                height: 18.h,
                decoration: BoxDecoration(
                  color: i < filled
                      ? WaterCard.accent
                      : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(3.r),
                  border: Border.all(
                    color: i < filled ? WaterCard.accent : AppColors.darkBorder,
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: 10.h),
        ClipRRect(
          borderRadius: BorderRadius.circular(3.r),
          child: Container(
            height: 6.h,
            color: AppColors.darkBorder,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: state.waterProgress,
              child: Container(color: WaterCard.accent),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddRow extends StatelessWidget {
  const _AddRow({required this.state});

  final TrackerState state;

  /// A glass, and a bottle. Two amounts rather than a keypad, because
  /// recording a drink has to be faster than remembering to.
  static const List<int> _amounts = [250, 500];

  @override
  Widget build(BuildContext context) {
    final TrackerCubit cubit = context.read<TrackerCubit>();

    return Row(
      children: [
        for (final int ml in _amounts) ...[
          Expanded(
            child: _AmountButton(
              label: 'water_add'.tr(namedArgs: {'ml': '$ml'}),
              onTap: () => cubit.addWater(ml),
            ),
          ),
          SizedBox(width: 8.w),
        ],
        // Undo rather than a minus button: taking back the drink you just
        // recorded is a real action, and subtracting an arbitrary amount from
        // a day's total is not.
        _UndoButton(enabled: state.lastWater != null, onTap: cubit.undoLastWater),
      ],
    );
  }
}

class _AmountButton extends StatelessWidget {
  const _AmountButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          alignment: Alignment.center,
          padding: EdgeInsets.symmetric(vertical: 10.h),
          decoration: BoxDecoration(
            color: WaterCard.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(5.r),
            border: Border.all(color: WaterCard.accent.withValues(alpha: 0.4)),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11.sp,
              fontWeight: FontWeight.w700,
              color: WaterCard.accent,
            ),
          ),
        ),
      ),
    );
  }
}

class _UndoButton extends StatelessWidget {
  const _UndoButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      enabled: enabled,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 40.w,
          padding: EdgeInsets.symmetric(vertical: 10.h),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5.r),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Icon(
            Icons.undo,
            size: 16.sp,
            color: enabled ? Colors.white : AppColors.darkBorder,
          ),
        ),
      ),
    );
  }
}
