import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/unit_converter.dart';
import '../styles/app_color.dart';

/// Scrolling wheel pickers presented as a dark bottom sheet.
///
/// Wheels rather than text fields: they're quicker to operate one-handed and
/// they make malformed input impossible, so nothing downstream has to parse or
/// sanity-check what the user typed.
class WheelPickerSheet {
  const WheelPickerSheet._();

  static const double itemExtent = 44;
  static const Color sheetBackground = Color(0xFF141414);

  /// A single wheel over a numeric range. Resolves to null if dismissed
  /// without confirming.
  static Future<double?> showValue({
    required BuildContext context,
    required String title,
    required double initialValue,
    required double min,
    required double max,
    required double step,
    required String unitLabel,
    int decimals = 0,
  }) {
    final values = _range(min, max, step);
    final initialIndex = _nearestIndex(values, initialValue);

    // Held as a captured local rather than widget state: the wheel already
    // renders the current value, so nothing needs to rebuild on change. The
    // Done button reads whatever it holds at the moment it's tapped.
    var selected = values[initialIndex];

    return showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _SheetShell(
        title: title,
        onConfirm: () => Navigator.of(sheetContext).pop(selected),
        child: SizedBox(
          height: 220.h,
          child: _Wheel(
            itemCount: values.length,
            initialIndex: initialIndex,
            labelBuilder: (i) =>
                '${values[i].toStringAsFixed(decimals)} $unitLabel',
            onChanged: (i) => selected = values[i],
          ),
        ),
      ),
    );
  }

  /// Two linked wheels for feet and inches. Resolves in centimetres, since
  /// that's the unit actually stored.
  static Future<double?> showFeetInches({
    required BuildContext context,
    required double initialCm,
    required String title,
  }) {
    final start = UnitConverter.cmToFeetInches(initialCm);
    final feet = List<int>.generate(6, (i) => i + 3); // 3ft - 8ft
    final inches = List<int>.generate(12, (i) => i);

    // clamp() returns num; feetInchesToCm and List.indexOf both want int.
    var selectedFeet = start.feet.clamp(feet.first, feet.last).toInt();
    var selectedInches = start.inches.clamp(0, 11).toInt();

    return showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _SheetShell(
        title: title,
        onConfirm: () => Navigator.of(sheetContext).pop(
          UnitConverter.feetInchesToCm(selectedFeet, selectedInches),
        ),
        child: SizedBox(
          height: 220.h,
          child: Row(
            children: [
              Expanded(
                child: _Wheel(
                  itemCount: feet.length,
                  initialIndex: feet.indexOf(selectedFeet),
                  labelBuilder: (i) => '${feet[i]} ft',
                  onChanged: (i) => selectedFeet = feet[i],
                ),
              ),
              Expanded(
                child: _Wheel(
                  itemCount: inches.length,
                  initialIndex: selectedInches,
                  labelBuilder: (i) => '${inches[i]} in',
                  onChanged: (i) => selectedInches = inches[i],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static List<double> _range(double min, double max, double step) {
    final count = ((max - min) / step).round() + 1;
    return List<double>.generate(count, (i) => min + i * step);
  }

  static int _nearestIndex(List<double> values, double target) {
    var bestIndex = 0;
    var bestDelta = double.infinity;
    for (var i = 0; i < values.length; i++) {
      final delta = (values[i] - target).abs();
      if (delta < bestDelta) {
        bestDelta = delta;
        bestIndex = i;
      }
    }
    return bestIndex;
  }
}

class _Wheel extends StatefulWidget {
  const _Wheel({
    required this.itemCount,
    required this.initialIndex,
    required this.labelBuilder,
    required this.onChanged,
  });

  final int itemCount;
  final int initialIndex;
  final String Function(int index) labelBuilder;
  final ValueChanged<int> onChanged;

  @override
  State<_Wheel> createState() => _WheelState();
}

class _WheelState extends State<_Wheel> {
  late final FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    // Owned by the State so it gets disposed; building one inline in build()
    // leaks a controller on every rebuild.
    _controller = FixedExtentScrollController(
      initialItem:
          math.max(0, math.min(widget.initialIndex, widget.itemCount - 1)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPicker(
      scrollController: _controller,
      itemExtent: WheelPickerSheet.itemExtent,
      squeeze: 1.1,
      diameterRatio: 1.6,
      selectionOverlay: Container(
        decoration: const BoxDecoration(
          border: Border.symmetric(
            horizontal: BorderSide(color: AppColors.primaryNeon, width: 1.5),
          ),
        ),
      ),
      onSelectedItemChanged: widget.onChanged,
      children: List.generate(
        widget.itemCount,
        (i) => Center(
          child: Text(
            widget.labelBuilder(i),
            style: GoogleFonts.anton(
              fontSize: 24.sp,
              color: Colors.white,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded dark container, grab handle, title and Done button.
class _SheetShell extends StatelessWidget {
  const _SheetShell({
    required this.title,
    required this.child,
    required this.onConfirm,
  });

  final String title;
  final Widget child;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: WheelPickerSheet.sheetBackground,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
          border: Border(
            top: BorderSide(color: AppColors.darkBorder, width: 1.h),
          ),
        ),
        padding: EdgeInsets.only(bottom: 12.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 10.h),
            Container(
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: AppColors.darkBorder,
                borderRadius: BorderRadius.circular(4.r),
              ),
            ),
            SizedBox(height: 14.h),
            Text(
              title.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 11.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.offWhiteMuted,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 6.h),
            child,
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 8.h),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryNeon,
                    foregroundColor: Colors.black,
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                  ),
                  child: Text(
                    'done_btn'.tr().toUpperCase(),
                    style: GoogleFonts.anton(
                      fontSize: 18.sp,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
