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
  });

  final int calories;
  final int proteinG;
  final int carbsG;
  final int fatG;

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
  }

  @override
  void dispose() {
    _calories.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    super.dispose();
  }

  int _value(TextEditingController controller) =>
      int.tryParse(controller.text.trim()) ?? 0;

  CustomTargets get _current => CustomTargets(
    calories: _value(_calories),
    proteinG: _value(_protein),
    carbsG: _value(_carbs),
    fatG: _value(_fat),
  );

  bool get _isUsable {
    final CustomTargets targets = _current;
    return targets.calories > 0 &&
        targets.proteinG > 0 &&
        targets.carbsG > 0 &&
        targets.fatG > 0;
  }

  @override
  Widget build(BuildContext context) {
    final CustomTargets targets = _current;
    final int difference = targets.macroCalories - targets.calories;

    return SheetShell(
      title: 'targets_title'.tr(),
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
        _Field(
          label: 'targets_calories'.tr(),
          controller: _calories,
          onChanged: _refresh,
        ),
        SizedBox(height: 10.h),
        Row(
          children: <Widget>[
            Expanded(
              child: _Field(
                label: 'targets_protein'.tr(),
                controller: _protein,
                onChanged: _refresh,
              ),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: _Field(
                label: 'targets_carbs'.tr(),
                controller: _carbs,
                onChanged: _refresh,
              ),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: _Field(
                label: 'targets_fat'.tr(),
                controller: _fat,
                onChanged: _refresh,
              ),
            ),
          ],
        ),
        SizedBox(height: 14.h),
        // Shown, never enforced. See the note on this class.
        _Reconciliation(targets: targets, difference: difference),
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
