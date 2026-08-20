import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../styles/app_color.dart';

/// Bottom sheet used by the pencil affordance on the weight cards.
/// Returns the new value in kg, or null when dismissed.
class WeightEditSheet extends StatefulWidget {
  final String title;
  final double initialValue;

  const WeightEditSheet({
    super.key,
    required this.title,
    required this.initialValue,
  });

  static Future<double?> show(
    BuildContext context, {
    required String title,
    required double initialValue,
  }) {
    return showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => WeightEditSheet(
        title: title,
        initialValue: initialValue,
      ),
    );
  }

  @override
  State<WeightEditSheet> createState() => _WeightEditSheetState();
}

class _WeightEditSheetState extends State<WeightEditSheet> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue.toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final double? parsed = double.tryParse(_controller.text.replaceAll(',', '.'));
    // Guard rails wide enough for any athlete, tight enough to catch typos.
    if (parsed == null || parsed < 30 || parsed > 300) {
      setState(() => _error = 'weight_range_error'.tr());
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                onSubmitted: (_) => _submit(),
                style: GoogleFonts.anton(
                  fontSize: 34.sp,
                  color: AppColors.primaryNeon,
                ),
                cursorColor: AppColors.primaryNeon,
                decoration: InputDecoration(
                  suffixText: 'kg_unit'.tr().toUpperCase(),
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
