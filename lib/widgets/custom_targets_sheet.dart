import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/user_profile.dart';
import '../styles/app_color.dart';
import 'sheet_action_row.dart';

/// What a user set out is returned by [CustomTargetsSheet.show].
@immutable
class CustomTargets {
  const CustomTargets({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.trainingDays = const <int>[],
    this.restCalories,
    this.restProteinG,
    this.restCarbsG,
    this.restFatG,
  });

  /// The training-day numbers, and — when day types are off — simply the
  /// numbers.
  final int calories;
  final int proteinG;
  final int carbsG;
  final int fatG;

  /// ISO weekdays the user trains on, or empty when they eat the same every
  /// day. See `supabase/day_targets.sql`.
  final List<int> trainingDays;

  final int? restCalories;
  final int? restProteinG;
  final int? restCarbsG;
  final int? restFatG;

  bool get hasDayTypes => trainingDays.isNotEmpty && (restCalories ?? 0) > 0;

  /// What the macros actually add up to. Protein and carbs are 4 kcal a gram,
  /// fat 9.
  int get macroCalories => proteinG * 4 + carbsG * 4 + fatG * 9;
}

/// Setting your own calories and macro split.
///
/// ## The one thing this screen has to do well
///
/// Four numbers that do not agree with each other are the normal state of a
/// hand-written macro split, and most apps either silently allow it or refuse
/// to save until it is exact. Both are wrong. A split that is 60 kcal off is
/// fine and forcing somebody to fiddle until it is zero is the kind of
/// pedantry that makes people stop using a feature; a split that is 700 kcal
/// off is a typo they would want to know about.
///
/// So the arithmetic is shown live — "your macros add up to 3,140 kcal", and
/// how far that is from the calorie target — and nothing is blocked. The user
/// decides whether the gap matters, which they are better placed to do than
/// this sheet is.
///
/// Premium only, and the *database* says so: the flag this write sets is
/// refused for a free account with SQLSTATE `BLKR2`. The screen is gated too,
/// but that gate is a convenience rather than the rule.
class CustomTargetsSheet extends StatefulWidget {
  const CustomTargetsSheet({super.key, required this.profile});

  final UserProfile profile;

  static Future<CustomTargets?> show(
    BuildContext context,
    UserProfile profile,
  ) {
    return showModalBottomSheet<CustomTargets>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        // Above the keyboard, which four number fields will always summon.
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: CustomTargetsSheet(profile: profile),
      ),
    );
  }

  @override
  State<CustomTargetsSheet> createState() => _CustomTargetsSheetState();
}

class _CustomTargetsSheetState extends State<CustomTargetsSheet> {
  late final TextEditingController _calories;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;

  late final TextEditingController _restCalories;
  late final TextEditingController _restProtein;
  late final TextEditingController _restCarbs;
  late final TextEditingController _restFat;

  /// ISO weekdays, Monday 1 through Sunday 7.
  late Set<int> _trainingDays;
  late bool _dayTypesOn;

  @override
  void initState() {
    super.initState();
    // Pre-filled with what is stored, so the sheet opens on the user's own
    // numbers rather than on an empty form they have to reconstruct.
    _calories = TextEditingController(
      text: '${widget.profile.dailyCalorieTarget}',
    );
    _protein = TextEditingController(text: '${widget.profile.proteinTargetG}');
    _carbs = TextEditingController(text: '${widget.profile.carbsTargetG}');
    _fat = TextEditingController(text: '${widget.profile.fatTargetG}');

    _dayTypesOn = widget.profile.hasDayTypes;
    _trainingDays = <int>{...widget.profile.trainingDays};

    // Seeded from the training numbers rather than left blank when the feature
    // is being switched on for the first time. Somebody turning this on wants
    // to lower a couple of figures, not retype four — and a blank form reads
    // as "you must know what you are doing" on the one screen where most
    // people do not yet.
    _restCalories = TextEditingController(
      text:
          '${widget.profile.restDayCalorieTarget ?? widget.profile.dailyCalorieTarget}',
    );
    _restProtein = TextEditingController(
      text:
          '${widget.profile.restDayProteinG ?? widget.profile.proteinTargetG}',
    );
    _restCarbs = TextEditingController(
      text: '${widget.profile.restDayCarbsG ?? widget.profile.carbsTargetG}',
    );
    _restFat = TextEditingController(
      text: '${widget.profile.restDayFatG ?? widget.profile.fatTargetG}',
    );
  }

  @override
  void dispose() {
    for (final TextEditingController controller in <TextEditingController>[
      _calories,
      _protein,
      _carbs,
      _fat,
      _restCalories,
      _restProtein,
      _restCarbs,
      _restFat,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  int _value(TextEditingController controller) =>
      int.tryParse(controller.text.trim()) ?? 0;

  CustomTargets get _current => CustomTargets(
    calories: _value(_calories),
    proteinG: _value(_protein),
    carbsG: _value(_carbs),
    fatG: _value(_fat),
    trainingDays: _dayTypesOn
        ? (_trainingDays.toList()..sort())
        : const <int>[],
    restCalories: _dayTypesOn ? _value(_restCalories) : null,
    restProteinG: _dayTypesOn ? _value(_restProtein) : null,
    restCarbsG: _dayTypesOn ? _value(_restCarbs) : null,
    restFatG: _dayTypesOn ? _value(_restFat) : null,
  );

  bool get _isUsable {
    final CustomTargets targets = _current;

    final bool trainingIsUsable =
        targets.calories > 0 &&
        targets.proteinG > 0 &&
        targets.carbsG > 0 &&
        targets.fatG > 0;

    if (!_dayTypesOn) return trainingIsUsable;

    // A rest day with no training days is every day, and a rest day with no
    // calories is a goal of zero. Both are half-filled forms rather than
    // choices, so the button waits.
    return trainingIsUsable &&
        _trainingDays.isNotEmpty &&
        (targets.restCalories ?? 0) > 0 &&
        (targets.restProteinG ?? 0) > 0 &&
        (targets.restCarbsG ?? 0) > 0 &&
        (targets.restFatG ?? 0) > 0;
  }

  @override
  Widget build(BuildContext context) {
    final CustomTargets targets = _current;
    final int difference = targets.macroCalories - targets.calories;

    return SheetShell(
      title: 'targets_title'.tr(),
      children: <Widget>[
        // Scrollable, because turning day types on doubles the form and a
        // bottom sheet on a small phone runs out of room well before the save
        // button.
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.55,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'targets_body'.tr(),
                  style: GoogleFonts.inter(
                    color: Colors.white54,
                    fontSize: 11.sp,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 16.h),
                if (_dayTypesOn) ...<Widget>[
                  _Heading(label: 'targets_training_heading'.tr()),
                  SizedBox(height: 8.h),
                ],
                _MacroFields(
                  calories: _calories,
                  protein: _protein,
                  carbs: _carbs,
                  fat: _fat,
                  onChanged: _refresh,
                ),
                SizedBox(height: 14.h),
                // Shown, never enforced. See the note on this class.
                _Reconciliation(targets: targets, difference: difference),
                SizedBox(height: 16.h),
                _DayTypeToggle(
                  value: _dayTypesOn,
                  onChanged: (bool on) => setState(() => _dayTypesOn = on),
                ),
                if (_dayTypesOn) ...<Widget>[
                  SizedBox(height: 14.h),
                  _WeekdayPicker(
                    selected: _trainingDays,
                    onToggle: (int day) => setState(() {
                      _trainingDays.contains(day)
                          ? _trainingDays.remove(day)
                          : _trainingDays.add(day);
                    }),
                  ),
                  if (_trainingDays.isEmpty) ...<Widget>[
                    SizedBox(height: 6.h),
                    Text(
                      'targets_need_a_day'.tr(),
                      style: GoogleFonts.inter(
                        color: const Color(0xFFFF9E3D),
                        fontSize: 10.sp,
                      ),
                    ),
                  ],
                  SizedBox(height: 16.h),
                  _Heading(label: 'targets_rest_heading'.tr()),
                  SizedBox(height: 8.h),
                  _MacroFields(
                    calories: _restCalories,
                    protein: _restProtein,
                    carbs: _restCarbs,
                    fat: _restFat,
                    onChanged: _refresh,
                  ),
                ],
              ],
            ),
          ),
        ),
        SizedBox(height: 16.h),
        SizedBox(
          width: double.infinity,
          height: 46.h,
          child: ElevatedButton(
            onPressed: _isUsable
                ? () => Navigator.of(context).pop(_current)
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryNeon,
              disabledBackgroundColor: const Color(0xFF2A2A2A),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.r),
              ),
            ),
            child: Text(
              _isUsable ? 'targets_save'.tr() : 'targets_invalid'.tr(),
              style: GoogleFonts.inter(
                fontSize: 12.sp,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _refresh() => setState(() {});
}

/// The live arithmetic under the fields.
class _Reconciliation extends StatelessWidget {
  const _Reconciliation({required this.targets, required this.difference});

  final CustomTargets targets;
  final int difference;

  @override
  Widget build(BuildContext context) {
    // Within 50 kcal is "matches" — rounding a macro split to whole grams
    // cannot land exactly, and demanding zero would mean nobody ever sees the
    // reassuring version of this line.
    final bool matches = difference.abs() <= 50;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'targets_from_macros'.tr(
            namedArgs: <String, String>{
              'calories': NumberFormat('#,###').format(targets.macroCalories),
            },
          ),
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 11.sp),
        ),
        SizedBox(height: 3.h),
        Text(
          matches
              ? 'targets_matches'.tr()
              : 'targets_mismatch'.tr(
                  namedArgs: <String, String>{
                    'difference': NumberFormat(
                      '#,###',
                    ).format(difference.abs()),
                  },
                ),
          style: GoogleFonts.inter(
            color: matches ? AppColors.primaryNeon : const Color(0xFFFF9E3D),
            fontSize: 10.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.digitsOnly,
        // Four digits is 9,999 kcal, which is past any plausible bulk and
        // short of the value that would overflow a column.
        LengthLimitingTextInputFormatter(4),
      ],
      onChanged: (_) => onChanged(),
      style: GoogleFonts.inter(color: Colors.white, fontSize: 14.sp),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(color: Colors.white38, fontSize: 10.sp),
        filled: true,
        fillColor: const Color(0xFF1C1C1C),
        contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.r),
          borderSide: BorderSide(color: AppColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.r),
          borderSide: BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10.r),
          borderSide: const BorderSide(color: AppColors.primaryNeon),
        ),
      ),
    );
  }
}

/// A section label, so the two sets of fields are unmistakably two sets.
class _Heading extends StatelessWidget {
  const _Heading({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: GoogleFonts.anton(
        color: Colors.white,
        fontSize: 12.sp,
        letterSpacing: 1.2,
      ),
    );
  }
}

/// The four number fields, used once for training days and once for rest.
class _MacroFields extends StatelessWidget {
  const _MacroFields({
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.onChanged,
  });

  final TextEditingController calories;
  final TextEditingController protein;
  final TextEditingController carbs;
  final TextEditingController fat;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _Field(
          label: 'targets_calories'.tr(),
          controller: calories,
          onChanged: onChanged,
        ),
        SizedBox(height: 10.h),
        Row(
          children: <Widget>[
            Expanded(
              child: _Field(
                label: 'targets_protein'.tr(),
                controller: protein,
                onChanged: onChanged,
              ),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: _Field(
                label: 'targets_carbs'.tr(),
                controller: carbs,
                onChanged: onChanged,
              ),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: _Field(
                label: 'targets_fat'.tr(),
                controller: fat,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DayTypeToggle extends StatelessWidget {
  const _DayTypeToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'targets_day_types'.tr(),
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 2.h),
              Text(
                'targets_day_types_helper'.tr(),
                style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 10.sp,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: Colors.black,
          activeTrackColor: AppColors.primaryNeon,
        ),
      ],
    );
  }
}

/// Monday to Sunday, as seven toggles.
///
/// Weekdays rather than "3 days a week": which days matter, because the
/// targets are applied by the calendar and a user who lifts Tuesday and
/// Thursday needs those exact days, not a count.
class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.selected, required this.onToggle});

  final Set<int> selected;
  final ValueChanged<int> onToggle;

  /// ISO order — Monday first, matching `DateTime.weekday`.
  static const List<String> _keys = <String>[
    'day_mon',
    'day_tue',
    'day_wed',
    'day_thu',
    'day_fri',
    'day_sat',
    'day_sun',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'targets_pick_days'.tr(),
          style: GoogleFonts.inter(color: Colors.white54, fontSize: 10.sp),
        ),
        SizedBox(height: 8.h),
        Row(
          children: <Widget>[
            for (int day = 1; day <= 7; day++) ...<Widget>[
              Expanded(
                child: GestureDetector(
                  onTap: () => onToggle(day),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 38.h,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected.contains(day)
                          ? AppColors.primaryNeon.withValues(alpha: 0.18)
                          : const Color(0xFF1C1C1C),
                      borderRadius: BorderRadius.circular(8.r),
                      border: Border.all(
                        color: selected.contains(day)
                            ? AppColors.primaryNeon
                            : AppColors.darkBorder,
                      ),
                    ),
                    child: Text(
                      _keys[day - 1].tr(),
                      style: GoogleFonts.inter(
                        color: selected.contains(day)
                            ? AppColors.primaryNeon
                            : Colors.white54,
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              if (day < 7) SizedBox(width: 4.w),
            ],
          ],
        ),
      ],
    );
  }
}
