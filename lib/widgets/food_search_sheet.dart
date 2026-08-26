import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../cubit/meal_editor/meal_editor_cubit.dart';
import '../models/food_item.dart';
import '../styles/app_color.dart';
import 'animations/press_scale.dart';

/// Picks one food and an amount, and hands them back.
///
/// Searches our own `system_foods` and `cached_off_foods` alongside Open Food
/// Facts, so the common things land instantly and the long tail still resolves.
/// Driven through [MealEditorCubit] rather than owning a repository, because the
/// debounce and the stale-response guard belong with the rest of the editor's
/// async state.
class FoodSearchSheet extends StatelessWidget {
  const FoodSearchSheet({super.key});

  /// Resolves once a food has been added, or on dismissal. The cubit already
  /// holds the result, so nothing is returned.
  static Future<void> show(BuildContext context, MealEditorCubit cubit) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: const FoodSearchSheet(),
      ),
    ).whenComplete(cubit.clearFoodSearch);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Lifts the sheet clear of the keyboard, which is up the whole time here.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        height: 0.82.sh,
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.vertical(top: Radius.circular(14.r)),
          border: Border(top: BorderSide(color: AppColors.darkBorder)),
        ),
        child: Column(
          children: [
            _buildGrabber(),
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 12.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'food_search_title'.tr().toUpperCase(),
                    style: GoogleFonts.anton(
                      fontSize: 18.sp,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    'food_search_subtitle'.tr(),
                    style: GoogleFonts.inter(
                      fontSize: 11.sp,
                      color: AppColors.textGray,
                    ),
                  ),
                  SizedBox(height: 14.h),
                  const _FoodSearchField(),
                ],
              ),
            ),
            const Expanded(child: _FoodResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildGrabber() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Container(
        width: 40.w,
        height: 4.h,
        decoration: BoxDecoration(
          color: AppColors.darkBorder,
          borderRadius: BorderRadius.circular(2.r),
        ),
      ),
    );
  }
}

class _FoodSearchField extends StatefulWidget {
  const _FoodSearchField();

  @override
  State<_FoodSearchField> createState() => _FoodSearchFieldState();
}

class _FoodSearchFieldState extends State<_FoodSearchField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: context.read<MealEditorCubit>().searchFoods,
      style: GoogleFonts.inter(color: Colors.white, fontSize: 14.sp),
      decoration: InputDecoration(
        hintText: 'food_search_hint'.tr(),
        hintStyle: GoogleFonts.inter(
          color: AppColors.textGray,
          fontSize: 13.sp,
        ),
        prefixIcon: Icon(Icons.search, color: AppColors.textGray, size: 20.sp),
        filled: true,
        fillColor: const Color(0xFF1F1F1F),
        contentPadding: EdgeInsets.symmetric(vertical: 12.h),
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
}

class _FoodResults extends StatelessWidget {
  const _FoodResults();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MealEditorCubit, MealEditorState>(
      buildWhen: (previous, current) =>
          previous.searchStatus != current.searchStatus ||
          previous.searchResults != current.searchResults,
      builder: (context, state) {
        switch (state.searchStatus) {
          case FoodSearchStatus.idle:
            return _Message(text: 'food_search_prompt'.tr());

          case FoodSearchStatus.searching:
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryNeon),
            );

          case FoodSearchStatus.empty:
            return _Message(text: 'food_search_empty'.tr());

          case FoodSearchStatus.results:
            return ListView.separated(
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 24.h),
              itemCount: state.searchResults.length,
              separatorBuilder: (_, __) => SizedBox(height: 8.h),
              itemBuilder: (_, index) => _FoodResultRow(
                food: state.searchResults[index],
                alreadyAdded:
                    state.draft.contains(state.searchResults[index].barcode),
              ),
            );
        }
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 40.w),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 12.sp,
            color: AppColors.textGray,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}

/// One search hit, with the amount field alongside it.
///
/// The amount lives on the row rather than behind a second step: picking a food
/// and saying how much of it are one decision, and splitting them across two
/// screens is what makes logging food tedious.
class _FoodResultRow extends StatefulWidget {
  const _FoodResultRow({required this.food, required this.alreadyAdded});

  final FoodItem food;
  final bool alreadyAdded;

  @override
  State<_FoodResultRow> createState() => _FoodResultRowState();
}

class _FoodResultRowState extends State<_FoodResultRow> {
  late final TextEditingController _amount;

  /// Falls back to 100g, which is also the basis the nutrition is quoted on, so
  /// the figures on the row are the figures being added until it is changed.
  static const double _defaultAmountG = 100;

  @override
  void initState() {
    super.initState();
    final double initial = widget.food.servingSizeG ?? _defaultAmountG;
    _amount = TextEditingController(text: '${initial.round()}');
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  double get _amountG => double.tryParse(_amount.text.trim()) ?? 0;

  void _add() {
    final double grams = _amountG;
    if (grams <= 0) return;

    context.read<MealEditorCubit>().addIngredient(widget.food, grams);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12.w, 10.h, 8.w, 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1C),
        borderRadius: BorderRadius.circular(5.r),
        border: Border.all(
          color: widget.alreadyAdded
              ? AppColors.primaryNeon
              : AppColors.darkBorder,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.food.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'food_per_100g'.tr(args: {
                    'kcal': '${widget.food.per100g.calories.round()}',
                    'protein': '${widget.food.per100g.proteinG.round()}',
                    'carbs': '${widget.food.per100g.carbsG.round()}',
                    'fat': '${widget.food.per100g.fatG.round()}',
                  }),
                  style: GoogleFonts.inter(
                    fontSize: 10.sp,
                    color: AppColors.offWhiteMuted,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 10.w),
          _buildAmountField(),
          SizedBox(width: 6.w),
          _buildAddButton(),
        ],
      ),
    );
  }

  Widget _buildAmountField() {
    return SizedBox(
      width: 56.w,
      child: TextField(
        controller: _amount,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        style: GoogleFonts.anton(color: Colors.white, fontSize: 15.sp),
        decoration: InputDecoration(
          isDense: true,
          suffixText: 'gram_short'.tr(),
          suffixStyle: GoogleFonts.inter(
            fontSize: 9.sp,
            color: AppColors.textGray,
          ),
          contentPadding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 4.w),
          filled: true,
          fillColor: const Color(0xFF121212),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4.r),
            borderSide: const BorderSide(color: AppColors.darkBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4.r),
            borderSide: const BorderSide(color: AppColors.darkBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4.r),
            borderSide: const BorderSide(color: AppColors.primaryNeon),
          ),
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return PressScale(
      child: GestureDetector(
        onTap: _add,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 38.w,
          height: 38.w,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primaryNeon,
            borderRadius: BorderRadius.circular(4.r),
          ),
          child: Icon(Icons.add_rounded, color: Colors.black, size: 20.sp),
        ),
      ),
    );
  }
}
