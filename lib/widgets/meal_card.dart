import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/meal.dart';
import '../styles/app_color.dart';
import 'animations/motion.dart';
import 'animations/press_scale.dart';
import 'macro_bar.dart';

/// One meal in the library: photo, what it costs, and the one-tap way to eat it.
///
/// The photo is always the user's own — the Open Food Facts data behind a meal's
/// ingredients never brings an image with it.
class MealCard extends StatelessWidget {
  const MealCard({
    super.key,
    required this.meal,
    required this.onLog,
    required this.onToggleFavorite,
    required this.onShowActions,
    this.onOpen,
    this.isLogging = false,
    this.wasJustLogged = false,
  });

  final Meal meal;

  /// Adds one serving to today's log.
  final VoidCallback onLog;

  final VoidCallback onToggleFavorite;

  /// Opens the overflow menu, which is where removing this meal lives.
  final VoidCallback onShowActions;

  /// Opens the detail view. Null until there is one to open.
  final VoidCallback? onOpen;

  /// This card's log write is in flight.
  final bool isLogging;

  /// Just landed — swaps the + for a tick for a moment.
  final bool wasJustLogged;

  static const Color _cardColor = Color(0xFF1A1A1A);
  static const Color _imageColor = Color(0xFF232323);
  static const double _imageAspect = 16 / 10;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: AppColors.darkBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildImage(),
          Padding(
            padding: EdgeInsets.fromLTRB(14.w, 14.h, 14.w, 14.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTitle(),
                SizedBox(height: 10.h),
                _buildCaloriesRow(context),
                SizedBox(height: 14.h),
                _buildMacros(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage() {
    return GestureDetector(
      onTap: onOpen,
      child: AspectRatio(
        aspectRatio: _imageAspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: _imageColor,
              child: meal.imageUrl == null
                  ? _buildImageFallback()
                  : Image.network(
                      meal.imageUrl!,
                      fit: BoxFit.cover,
                      // A meal photo is decoration, not information: a broken
                      // URL or an offline device gets the same plate icon an
                      // image-less meal does, never a grey error box.
                      errorBuilder: (_, __, ___) => _buildImageFallback(),
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                              ? child
                              : const Center(
                                  child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.darkBorder,
                                    ),
                                  ),
                                ),
                    ),
            ),
            Positioned(top: 10.h, left: 10.w, child: _buildEmphasisChip()),
            Positioned(
              top: 6.h,
              right: 6.w,
              child: Row(
                children: [
                  _buildFavoriteButton(),
                  _buildOverflowButton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageFallback() {
    return Center(
      child: Icon(
        Icons.restaurant_sharp,
        size: 34.sp,
        color: AppColors.darkBorder,
      ),
    );
  }

  Widget _buildEmphasisChip() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(3.r),
      ),
      child: Text(
        _emphasisKey(meal.emphasis).tr().toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 9.sp,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 1.4,
        ),
      ),
    );
  }

  static String _emphasisKey(MealEmphasis emphasis) => switch (emphasis) {
        MealEmphasis.protein => 'meal_tag_protein',
        MealEmphasis.carbs => 'meal_tag_carbs',
        MealEmphasis.fat => 'meal_tag_fat',
        MealEmphasis.balanced => 'meal_tag_balanced',
      };

  Widget _buildFavoriteButton() {
    return PressScale(
      child: GestureDetector(
        onTap: onToggleFavorite,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          // Padding rather than a bigger box: keeps the 44pt touch target
          // without a visible slab sitting over the photo.
          padding: EdgeInsets.all(8.w),
          child: Icon(
            meal.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
            size: 24.sp,
            color: meal.isFavorite ? AppColors.primaryNeon : Colors.white,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
          ),
        ),
      ),
    );
  }

  Widget _buildOverflowButton() {
    return PressScale(
      child: GestureDetector(
        onTap: onShowActions,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.all(8.w),
          child: Icon(
            Icons.more_vert_rounded,
            size: 22.sp,
            color: Colors.white,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          meal.title.toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.anton(
            fontSize: 17.sp,
            color: Colors.white,
            height: 1.15,
            letterSpacing: 0.4,
          ),
        ),
        // Credit stays on meals taken from someone else's post. Absent for the
        // user's own, where it would just be their own handle on every card.
        if (!meal.isMine && meal.creatorUsername != null) ...[
          SizedBox(height: 4.h),
          Text(
            'meal_by_author'.tr(namedArgs: {'author': meal.creatorUsername!}),
            style: GoogleFonts.inter(
              fontSize: 10.sp,
              color: AppColors.textGray,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCaloriesRow(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  NumberFormat.decimalPattern()
                      .format(meal.totals.caloriesRounded),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.anton(
                    fontSize: 32.sp,
                    color: AppColors.primaryNeon,
                    height: 1,
                  ),
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
            ],
          ),
        ),
        _buildLogButton(context),
      ],
    );
  }

  /// The whole point of the card: one tap puts this meal in today's log.
  Widget _buildLogButton(BuildContext context) {
    return PressScale(
      enabled: !isLogging,
      child: GestureDetector(
        onTap: isLogging ? null : onLog,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: Motion.scaled(context, Motion.fast),
          width: 46.w,
          height: 40.h,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: wasJustLogged ? AppColors.primaryNeon : const Color(0xFF2A2A2A),
            borderRadius: BorderRadius.circular(5.r),
          ),
          child: _buildLogButtonChild(),
        ),
      ),
    );
  }

  Widget _buildLogButtonChild() {
    if (isLogging) {
      return SizedBox(
        width: 18.w,
        height: 18.w,
        child: const CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primaryNeon,
        ),
      );
    }

    return Icon(
      wasJustLogged ? Icons.check_rounded : Icons.add_rounded,
      color: wasJustLogged ? Colors.black : Colors.white,
      size: 22.sp,
    );
  }

  Widget _buildMacros() {
    return Row(
      children: [
        _MacroPill(
          color: MacroBreakdown.proteinColor,
          label: 'macro_protein'.tr(),
          grams: meal.totals.proteinRounded,
        ),
        SizedBox(width: 10.w),
        _MacroPill(
          color: MacroBreakdown.carbsColor,
          label: 'macro_carbs'.tr(),
          grams: meal.totals.carbsRounded,
        ),
        SizedBox(width: 10.w),
        _MacroPill(
          color: MacroBreakdown.fatColor,
          label: 'macro_fat'.tr(),
          grams: meal.totals.fatRounded,
        ),
      ],
    );
  }
}

/// One macro figure under the calorie headline.
class _MacroPill extends StatelessWidget {
  const _MacroPill({
    required this.color,
    required this.label,
    required this.grams,
  });

  final Color color;
  final String label;
  final int grams;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 7.h),
        decoration: BoxDecoration(
          color: const Color(0xFF151515),
          borderRadius: BorderRadius.circular(4.r),
          border: Border(left: BorderSide(color: color, width: 2.w)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 8.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.offWhiteMuted,
                letterSpacing: 1,
              ),
            ),
            SizedBox(height: 2.h),
            Text(
              '${grams}g',
              style: GoogleFonts.anton(
                fontSize: 15.sp,
                color: Colors.white,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
