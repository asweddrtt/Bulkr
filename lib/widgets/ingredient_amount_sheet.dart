import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/food_item.dart';
import '../models/macros.dart';
import '../styles/app_color.dart';
import 'animations/press_scale.dart';
import 'macro_bar.dart';

/// Changes how much of one food is in a meal.
///
/// Shows what the amount costs as it is typed, because that is the number the
/// decision is actually about — nobody has an opinion about 165g of chicken,
/// they have an opinion about 270 calories.
class IngredientAmountSheet extends StatefulWidget {
  const IngredientAmountSheet({
    super.key,
    required this.food,
    required this.amountG,
  });

  final FoodItem food;
  final double amountG;

  /// Resolves to the new amount in grams, or null when dismissed.
  static Future<double?> show(
    BuildContext context, {
    required FoodItem food,
    required double amountG,
  }) {
    return showModalBottomSheet<double>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => IngredientAmountSheet(food: food, amountG: amountG),
    );
  }

  @override
  State<IngredientAmountSheet> createState() => _IngredientAmountSheetState();
}

class _IngredientAmountSheetState extends State<IngredientAmountSheet> {
  late final TextEditingController _controller;

  /// Portions worth one tap. A serving is offered only when the manufacturer
  /// stated one in grams — the rest are round numbers people actually weigh to.
  static const List<double> _quickGrams = [50, 100, 150, 200, 250, 300];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.amountG.round()}');
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _grams => double.tryParse(_controller.text.trim()) ?? 0;

  Macros get _macros => widget.food.per100g.forGrams(_grams);

  bool get _canSave => _grams > 0;

  void _setGrams(double grams) {
    _controller.text = '${grams.round()}';
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
  }

  @override
  Widget build(BuildContext context) {
    final double? serving = widget.food.servingSizeG;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 12.h),
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.vertical(top: Radius.circular(14.r)),
          border: Border(top: BorderSide(color: AppColors.darkBorder)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.food.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.anton(
                  fontSize: 16.sp,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              SizedBox(height: 16.h),
              _buildAmountField(),
              SizedBox(height: 12.h),
              _buildQuickAmounts(serving),
              SizedBox(height: 18.h),
              _buildLiveMacros(),
              SizedBox(height: 16.h),
              _buildSaveButton(),
              SizedBox(height: 8.h),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAmountField() {
    return TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: GoogleFonts.anton(color: Colors.white, fontSize: 34.sp),
      decoration: InputDecoration(
        suffixText: 'gram_short'.tr(),
        suffixStyle: GoogleFonts.inter(
          fontSize: 13.sp,
          color: AppColors.offWhiteMuted,
        ),
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5.r),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5.r),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(5.r),
          borderSide: const BorderSide(color: AppColors.primaryNeon),
        ),
      ),
    );
  }

  Widget _buildQuickAmounts(double? serving) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: [
        // The manufacturer's own portion, when they stated one in grams. First,
        // because "one bar" is how the food is eaten and 100g is not.
        if (serving != null)
          _AmountChip(
            label: 'food_one_serving'
                .tr(namedArgs: {'grams': '${serving.round()}'}),
            isSelected: _grams == serving,
            onTap: () => _setGrams(serving),
          ),
        for (final double grams in _quickGrams)
          _AmountChip(
            label: '${grams.round()}${'gram_short'.tr()}',
            isSelected: _grams == grams,
            onTap: () => _setGrams(grams),
          ),
      ],
    );
  }

  Widget _buildLiveMacros() {
    final Macros macros = _macros;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${macros.caloriesRounded}',
            style: GoogleFonts.anton(
              fontSize: 30.sp,
              color: AppColors.primaryNeon,
              height: 1,
            ),
          ),
          SizedBox(width: 6.w),
          Padding(
            padding: EdgeInsets.only(bottom: 3.h),
            child: Text(
              'kcal_short'.tr().toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 10.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.offWhiteMuted,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const Spacer(),
          _MacroFigure(
            color: MacroBreakdown.proteinColor,
            label: 'macro_protein'.tr(),
            grams: macros.proteinRounded,
          ),
          SizedBox(width: 12.w),
          _MacroFigure(
            color: MacroBreakdown.carbsColor,
            label: 'macro_carbs'.tr(),
            grams: macros.carbsRounded,
          ),
          SizedBox(width: 12.w),
          _MacroFigure(
            color: MacroBreakdown.fatColor,
            label: 'macro_fat'.tr(),
            grams: macros.fatRounded,
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return PressScale(
      enabled: _canSave,
      child: GestureDetector(
        onTap: _canSave ? () => Navigator.of(context).pop(_grams) : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: 15.h),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _canSave ? AppColors.buttonNeon : AppColors.darkBorder,
            borderRadius: BorderRadius.circular(5.r),
          ),
          child: Text(
            'food_update_amount'.tr().toUpperCase(),
            style: GoogleFonts.anton(
              fontSize: 14.sp,
              color: _canSave ? Colors.black : AppColors.textGray,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  const _AmountChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryNeon : const Color(0xFF1F1F1F),
            borderRadius: BorderRadius.circular(4.r),
            border: Border.all(
              color: isSelected ? AppColors.primaryNeon : AppColors.darkBorder,
            ),
          ),
          child: Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 10.sp,
              fontWeight: FontWeight.w700,
              color: isSelected ? Colors.black : Colors.white,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}

class _MacroFigure extends StatelessWidget {
  const _MacroFigure({
    required this.color,
    required this.label,
    required this.grams,
  });

  final Color color;
  final String label;
  final int grams;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            fontSize: 8.sp,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.8,
          ),
        ),
        SizedBox(height: 2.h),
        Text(
          '${grams}g',
          style: GoogleFonts.anton(
            fontSize: 14.sp,
            color: Colors.white,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}
