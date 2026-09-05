import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../cubit/food_search/food_search_cubit.dart';
import '../data/food_repository.dart';
import '../models/food_item.dart';
import '../styles/app_color.dart';
import 'animations/press_scale.dart';
import 'barcode_scanner_sheet.dart';

/// What one picked food and amount means to whoever opened the sheet.
///
/// Returning a [Future] rather than void so the sheet can wait for a write
/// before closing: the tracker's pick is a round trip to `daily_logs`, and
/// closing over a failed insert would report success by disappearing.
typedef FoodPicked = Future<void> Function(FoodItem food, double grams);

/// Picks one food and an amount.
///
/// Searches our own `system_foods` and `cached_off_foods` alongside a hosted
/// database and Open Food Facts, so the common things land instantly and the
/// long tail still resolves — all of that lives in [FoodRepository], and this
/// sheet only presents it.
///
/// Generic over what a pick means, which is why [onPicked] is a callback
/// rather than a cubit method. Two callers want the same search and different
/// outcomes: the meal editor adds an ingredient to a draft, the tracker writes
/// a log entry. Neither owns this widget.
class FoodSearchSheet extends StatelessWidget {
  const FoodSearchSheet({
    super.key,
    required this.onPicked,
    this.alreadyAdded = const {},
    this.titleKey = 'food_search_title',
    this.subtitleKey = 'food_search_subtitle',
  });

  /// Called with the chosen food and the grams in the row's amount field.
  final FoodPicked onPicked;

  /// Barcodes already accounted for by the caller, highlighted in the list.
  ///
  /// Empty for the tracker, and meaningfully so rather than by omission:
  /// eating a banana twice in one day is two log entries, not a duplicate, so
  /// there is nothing to warn about. The meal editor passes its draft's
  /// ingredients, where adding the same food twice really is a correction of
  /// the first amount.
  final Set<String> alreadyAdded;

  final String titleKey;
  final String subtitleKey;

  /// Opens the sheet, with its own search cubit for the life of the sheet.
  ///
  /// The cubit is created here rather than passed in so neither caller has to
  /// hold search state it does not otherwise care about, and so the query is
  /// gone when the sheet is — reopening it starts fresh instead of showing
  /// whatever was typed last time.
  static Future<void> show(
    BuildContext context, {
    required FoodPicked onPicked,
    Set<String> alreadyAdded = const {},
    String titleKey = 'food_search_title',
    String subtitleKey = 'food_search_subtitle',
  }) {
    final FoodRepository foods = context.read<FoodRepository>();

    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => BlocProvider<FoodSearchCubit>(
        create: (_) => FoodSearchCubit(foodRepository: foods),
        child: FoodSearchSheet(
          onPicked: onPicked,
          alreadyAdded: alreadyAdded,
          titleKey: titleKey,
          subtitleKey: subtitleKey,
        ),
      ),
    );
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          titleKey.tr().toUpperCase(),
                          style: GoogleFonts.anton(
                            fontSize: 18.sp,
                            color: Colors.white,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      // In the sheet rather than only on the screen behind it,
                      // because a scan and a search answer the same question
                      // and the packet is usually already in your hand.
                      _ScanButton(onPicked: onPicked),
                    ],
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    subtitleKey.tr(),
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
            Expanded(
              child: _FoodResults(
                onPicked: onPicked,
                alreadyAdded: alreadyAdded,
              ),
            ),
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

/// Scans a barcode and picks whatever it resolves to.
///
/// A scan identifies a food exactly, with no spelling and no ranking, so it
/// goes straight through at the manufacturer's serving size — or 100g, the
/// basis nutrition is quoted on, when they state none.
class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.onPicked});

  final FoodPicked onPicked;

  static const double _fallbackAmountG = 100;

  Future<void> _scan(BuildContext context) async {
    final FoodSearchCubit search = context.read<FoodSearchCubit>();
    final NavigatorState navigator = Navigator.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final String? barcode = await BarcodeScannerSheet.show(context);
    if (barcode == null) return;

    final FoodItem? food = await search.lookupBarcode(barcode);

    if (food == null || !food.hasNutrition) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2A2A2A),
            content: Text(
              // Two different failures, one message: a code nothing has heard
              // of and a product logged with no nutrition are the same dead
              // end from here, and the fix for both is to search by name.
              'food_scan_unknown'.tr(),
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13.sp),
            ),
          ),
        );
      return;
    }

    await onPicked(food, food.servingSizeG ?? _fallbackAmountG);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => _scan(context),
      icon: Icon(
        Icons.qr_code_scanner,
        color: AppColors.primaryNeon,
        size: 22.sp,
      ),
      tooltip: 'food_scan_tooltip'.tr(),
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
      onChanged: context.read<FoodSearchCubit>().search,
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
  const _FoodResults({required this.onPicked, required this.alreadyAdded});

  final FoodPicked onPicked;
  final Set<String> alreadyAdded;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FoodSearchCubit, FoodSearchState>(
      buildWhen: (previous, current) =>
          previous.status != current.status ||
          previous.results != current.results,
      builder: (context, state) {
        switch (state.status) {
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
              itemCount: state.results.length,
              separatorBuilder: (_, __) => SizedBox(height: 8.h),
              itemBuilder: (_, index) => _FoodResultRow(
                food: state.results[index],
                alreadyAdded:
                    alreadyAdded.contains(state.results[index].barcode),
                onPicked: onPicked,
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
  const _FoodResultRow({
    required this.food,
    required this.alreadyAdded,
    required this.onPicked,
  });

  final FoodItem food;
  final bool alreadyAdded;
  final FoodPicked onPicked;

  @override
  State<_FoodResultRow> createState() => _FoodResultRowState();
}

class _FoodResultRowState extends State<_FoodResultRow> {
  late final TextEditingController _amount;

  /// Falls back to 100g, which is also the basis the nutrition is quoted on, so
  /// the figures on the row are the figures being added until it is changed.
  static const double _defaultAmountG = 100;

  /// The pick is in flight. Local to the row rather than in the search state,
  /// because it belongs to this row's button and the sheet's other rows should
  /// stay usable if it fails.
  bool _busy = false;

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

  Future<void> _add() async {
    final double grams = _amountG;
    if (grams <= 0 || _busy) return;

    final NavigatorState navigator = Navigator.of(context);

    setState(() => _busy = true);
    try {
      await widget.onPicked(widget.food, grams);
    } finally {
      // Guarded because the callback can outlive the row — a slow insert with
      // the sheet already dismissed.
      if (mounted) setState(() => _busy = false);
    }

    // Only after the pick has actually landed. The meal editor's is
    // synchronous and closes immediately; the tracker's waits on a write, and
    // a sheet that closed first would leave the failure with nowhere to show.
    navigator.pop();
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
                  'food_per_100g'.tr(namedArgs: {
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

  /// The same neon square as before, with a spinner in it while a pick that
  /// writes to the database is in flight. The meal editor's pick is synchronous
  /// and never shows it.
  Widget _buildAddButton() {
    return PressScale(
      enabled: !_busy,
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
          child: _busy
              ? SizedBox(
                  width: 16.sp,
                  height: 16.sp,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.black),
                  ),
                )
              : Icon(Icons.add_rounded, color: Colors.black, size: 20.sp),
        ),
      ),
    );
  }
}
