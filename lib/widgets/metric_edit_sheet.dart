import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';

/// Bottom sheet used by the pencil affordance on the metric cards.
/// Returns the new value, or null when dismissed.
class MetricEditSheet extends StatefulWidget {
  final String title;
  final double initialValue;
  final String unitLabel;
  final double min;
  final double max;

  /// 0 for whole numbers (age, height), 1 for weights.
  final int decimals;

  const MetricEditSheet({
    super.key,
    required this.title,
    required this.initialValue,
    required this.unitLabel,
    required this.min,
    required this.max,
    this.decimals = 1,
  });

  static Future<double?> show(
    BuildContext context, {
    required String title,
    required double initialValue,
    required String unitLabel,
    required double min,
    required double max,
    int decimals = 1,
  }) {
    return showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MetricEditSheet(
        title: title,
        initialValue: initialValue,
        unitLabel: unitLabel,
        min: min,
        max: max,
        decimals: decimals,
      ),
    );
  }

  @override
  State<MetricEditSheet> createState() => _MetricEditSheetState();
}

class _MetricEditSheetState extends State<MetricEditSheet> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue.toStringAsFixed(widget.decimals),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final double? parsed = double.tryParse(_controller.text.replaceAll(',', '.'));
    if (parsed == null || parsed < widget.min || parsed > widget.max) {
      setState(() {
        _error = 'metric_range_error'.tr(
          namedArgs: {
            'min': widget.min.toStringAsFixed(widget.decimals),
            'max': widget.max.toStringAsFixed(widget.decimals),
            'unit': widget.unitLabel.toUpperCase(),
          },
        );
      });
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: AppColors.cardDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16.r)),
          border: const Border(
            top: BorderSide(color: AppColors.darkBorder),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title.toUpperCase(),
                style: GoogleFonts.anton(
                  fontSize: 20.sp,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: 16.h),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.numberWithOptions(
                  decimal: widget.decimals > 0,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    widget.decimals == 0 ? RegExp(r'[0-9]') : RegExp(r'[0-9.,]'),
                  ),
                ],
                onSubmitted: (_) => _submit(),
                style: GoogleFonts.anton(
                  fontSize: 34.sp,
                  color: AppColors.primaryNeon,
                ),
                cursorColor: AppColors.primaryNeon,
                decoration: InputDecoration(
                  suffixText: widget.unitLabel.toUpperCase(),
                  suffixStyle: GoogleFonts.inter(
                    fontSize: 12.sp,
                    color: AppColors.offWhiteMuted,
                  ),
                  errorText: _error,
                  errorStyle: GoogleFonts.inter(
                    fontSize: 11.sp,
                    color: const Color(0xFFFF5722),
                  ),
                  filled: true,
                  fillColor: AppColors.cardDeep,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4.r),
                    borderSide: const BorderSide(color: AppColors.darkBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4.r),
                    borderSide: const BorderSide(
                      color: AppColors.primaryNeon,
                      width: 2,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4.r),
                    borderSide: const BorderSide(color: Color(0xFFFF5722)),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4.r),
                    borderSide: const BorderSide(
                      color: Color(0xFFFF5722),
                      width: 2,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 20.h),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: AppColors.darkBorder),
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                      ),
                      child: Text(
                        'cancel_btn'.tr().toUpperCase(),
                        style: GoogleFonts.anton(fontSize: 15.sp),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryNeon,
                        foregroundColor: Colors.black,
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4.r),
                        ),
                      ),
                      child: Text(
                        'save_btn'.tr().toUpperCase(),
                        style: GoogleFonts.anton(fontSize: 15.sp),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
