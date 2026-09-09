import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/unit_converter.dart';
import '../models/activity_level.dart';
import '../models/unit_system.dart';
import '../styles/app_color.dart';
import 'activity_level_card.dart';
import 'metric_card.dart';
import 'wheel_picker_sheet.dart';

/// What the user entered at onboarding, and can now correct.
///
/// Height changes rarely and date of birth never, but both get typed once by
/// somebody who has not seen the app yet — so a wrong digit was permanent, and
/// it silently skewed every calorie target derived from it. Activity level is
/// the opposite case: it is meant to change, because the honest answer differs
/// between somebody's off-season and their build.
///
/// Nothing is written until Save. Everything the sheet edits feeds the calorie
/// engine, so a half-applied change is a wrong target rather than an
/// inconvenience.
class BodyStatsEdit {
  const BodyStatsEdit({
    required this.dateOfBirth,
    required this.heightCm,
    required this.activityLevel,
  });

  final DateTime? dateOfBirth;
  final double heightCm;
  final ActivityLevel activityLevel;

  bool differsFrom(BodyStatsEdit other) =>
      dateOfBirth != other.dateOfBirth ||
      heightCm != other.heightCm ||
      activityLevel != other.activityLevel;
}

class BodyStatsSheet extends StatefulWidget {
  const BodyStatsSheet({
    super.key,
    required this.initial,
    required this.units,
  });

  final BodyStatsEdit initial;
  final UnitSystem units;

  /// Resolves to the edited values, or null when dismissed unchanged.
  static Future<BodyStatsEdit?> show(
    BuildContext context, {
    required BodyStatsEdit initial,
    required UnitSystem units,
  }) {
    return showModalBottomSheet<BodyStatsEdit>(
      context: context,
      backgroundColor: Colors.transparent,
      // Five activity cards plus two metric rows is taller than the default
      // nine-sixteenths cap, and past that cap content is unreachable rather
      // than merely clipped.
      isScrollControlled: true,
      builder: (_) => BodyStatsSheet(initial: initial, units: units),
    );
  }

  @override
  State<BodyStatsSheet> createState() => _BodyStatsSheetState();
}

class _BodyStatsSheetState extends State<BodyStatsSheet> {
  static const Map<ActivityLevel, IconData> _icons = {
    ActivityLevel.sedentary: Icons.chair_outlined,
    ActivityLevel.lightlyActive: Icons.directions_walk,
    ActivityLevel.moderatelyActive: Icons.directions_run,
    ActivityLevel.veryActive: Icons.fitness_center,
    ActivityLevel.extraActive: Icons.local_fire_department,
  };

  late DateTime? _dateOfBirth = widget.initial.dateOfBirth;
  late double _heightCm = widget.initial.heightCm;
  late ActivityLevel _activityLevel = widget.initial.activityLevel;

  bool get _isMetric => widget.units.isMetric;

  BodyStatsEdit get _edited => BodyStatsEdit(
        dateOfBirth: _dateOfBirth,
        heightCm: _heightCm,
        activityLevel: _activityLevel,
      );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
          border: Border(
            top: BorderSide(color: AppColors.darkBorder, width: 1.h),
          ),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.only(top: 10.h, bottom: 18.h),
              child: Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: AppColors.darkBorder,
                  borderRadius: BorderRadius.circular(4.r),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'body_stats_title'.tr().toUpperCase(),
                      style: GoogleFonts.anton(
                        fontSize: 18.sp,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16.h),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Date of birth rather than age, matching onboarding: age
                    // drifts, a birthday doesn't, and the engine derives the
                    // age it needs at calculation time.
                    MetricCard(
                      label: 'dob_label'.tr(),
                      value: _dateOfBirth == null
                          ? 'dob_placeholder'.tr()
                          : DateFormat.yMMMd().format(_dateOfBirth!),
                      unit: _dateOfBirth == null
                          ? ''
                          : 'age_years'.tr(
                              namedArgs: {'age': '${_ageOf(_dateOfBirth!)}'},
                            ),
                      isPlaceholder: _dateOfBirth == null,
                      onTap: _pickDateOfBirth,
                    ),
                    MetricCard(
                      label: 'height_label'.tr(),
                      value: _heightValue(),
                      unit: _isMetric ? 'cm_unit'.tr() : '',
                      onTap: _pickHeight,
                    ),
                    SizedBox(height: 12.h),
                    Text(
                      'activity_level_title'.tr(),
                      style: GoogleFonts.inter(
                        color: AppColors.textGray,
                        fontSize: 10.sp,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    SizedBox(height: 10.h),
                    for (final ActivityLevel level in ActivityLevel.values)
                      ActivityLevelCard(
                        icon: _icons[level]!,
                        title: level.titleKey.tr(),
                        description: level.descriptionKey.tr(),
                        multiplier: level.multiplier,
                        isSelected: _activityLevel == level,
                        onTap: () => setState(() => _activityLevel = level),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: AppColors.darkBorder),
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                      ),
                      child: Text(
                        'cancel'.tr(),
                        style: GoogleFonts.inter(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: ElevatedButton(
                      // Disabled while nothing has moved. Saving an unchanged
                      // profile would still cost a write and a reload, and
                      // would still offer to recalculate a plan whose inputs
                      // are identical.
                      onPressed: _edited.differsFrom(widget.initial)
                          ? () => Navigator.of(context).pop(_edited)
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryNeon,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: AppColors.darkBorder,
                        disabledForegroundColor: AppColors.textGray,
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                      ),
                      child: Text(
                        'save'.tr().toUpperCase(),
                        style: GoogleFonts.anton(
                          fontSize: 15.sp,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Height in the user's own units, as the dashboard and onboarding show it.
  String _heightValue() {
    if (_isMetric) return _heightCm.round().toString();
    final imperial = UnitConverter.cmToFeetInches(_heightCm);
    return "${imperial.feet}' ${imperial.inches}\"";
  }

  /// Whole years, for the label beside the date.
  ///
  /// Not `CalorieEngine.ageFromDateOfBirth` only because this runs against a
  /// date the user is still choosing rather than one on their row; the
  /// arithmetic is the same.
  static int _ageOf(DateTime dob) {
    final DateTime now = DateTime.now();
    int years = now.year - dob.year;
    final bool birthdayPassed =
        now.month > dob.month || (now.month == dob.month && now.day >= dob.day);
    return birthdayPassed ? years : --years;
  }

  Future<void> _pickDateOfBirth() async {
    final DateTime now = DateTime.now();

    // The same bounds as onboarding: 13 is the floor most app stores expect,
    // 100 a generous ceiling.
    final DateTime earliest = DateTime(now.year - 100, now.month, now.day);
    final DateTime latest = DateTime(now.year - 13, now.month, now.day);
    final DateTime initial =
        _dateOfBirth ?? DateTime(now.year - 25, now.month, now.day);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: earliest,
      lastDate: latest,
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primaryNeon,
            onPrimary: Colors.black,
            surface: Color(0xFF1A1A1A),
            onSurface: Colors.white,
          ),
          dialogTheme:
              const DialogThemeData(backgroundColor: Color(0xFF141414)),
        ),
        child: child!,
      ),
    );

    if (picked != null && mounted) setState(() => _dateOfBirth = picked);
  }

  Future<void> _pickHeight() async {
    final double? result = _isMetric
        ? await WheelPickerSheet.showValue(
            context: context,
            title: 'height_label'.tr(),
            initialValue: _heightCm,
            min: 120,
            max: 230,
            step: 1,
            unitLabel: 'cm_unit'.tr().toLowerCase(),
          )
        : await WheelPickerSheet.showFeetInches(
            context: context,
            title: 'height_label'.tr(),
            initialCm: _heightCm,
          );

    if (result != null && mounted) setState(() => _heightCm = result);
  }
}
