import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../cubit/meal_editor/meal_editor_cubit.dart';
import '../data/food_repository.dart';
import '../data/meal_repository.dart';
import '../models/food_item.dart';
import '../models/macros.dart';
import '../models/meal.dart';
import '../models/meal_ingredient.dart';
import '../styles/app_color.dart';
import '../widgets/animations/press_scale.dart';
import '../widgets/barcode_scanner_sheet.dart';
import '../widgets/food_search_sheet.dart';
import '../widgets/image_source_sheet.dart';
import '../widgets/ingredient_amount_sheet.dart';
import '../widgets/macro_bar.dart';

/// Writes a meal: a photo, a name, what is in it, and how it is made.
///
/// One screen for both jobs. Pass [meal] to edit an existing one; leave it null
/// to write a new one. Pops with the saved [Meal] so the library can show it
/// without waiting for a refetch, or with null if the user backed out.
class MealEditorScreen extends StatelessWidget {
  const MealEditorScreen({super.key, this.meal});

  /// The meal to open. Null writes a new one.
  final Meal? meal;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<MealEditorCubit>(
      create: (_) => MealEditorCubit(
        mealRepository: context.read<MealRepository>(),
        foodRepository: context.read<FoodRepository>(),
        editing: meal,
      ),
      child: const _MealEditorView(),
    );
  }
}

class _MealEditorView extends StatelessWidget {
  const _MealEditorView();

  static const Color _bg = Color(0xFF121212);

  @override
  Widget build(BuildContext context) {
    return BlocListener<MealEditorCubit, MealEditorState>(
      listenWhen: (previous, current) => previous.status != current.status,
      listener: (context, state) {
        final Meal? saved = state.savedMeal;
        if (state.status == MealEditorStatus.saved && saved != null) {
          // Shown before the pop, but it outlives this screen: the messenger
          // belongs to the app, not to the route being closed.
          if (state.savedWithoutIngredients) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF2A2A2A),
                  duration: const Duration(seconds: 6),
                  content: Text(
                    'meal_saved_without_ingredients'.tr(),
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 12.sp,
                    ),
                  ),
                ),
              );
          }

          Navigator.of(context).pop<Meal>(saved);
          return;
        }

        if (state.status == MealEditorStatus.failure) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFF2A2A2A),
                duration: const Duration(seconds: 5),
                content: Text(
                  state.errorDetail ?? state.errorKey!.tr(),
                  style:
                      GoogleFonts.inter(color: Colors.white, fontSize: 12.sp),
                ),
              ),
            );
          context.read<MealEditorCubit>().dismissError();
        }
      },
      child: BlocBuilder<MealEditorCubit, MealEditorState>(
        buildWhen: (previous, current) =>
            previous.isEditing != current.isEditing ||
            previous.isHydrating != current.isHydrating,
        builder: (context, state) => Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            (state.isEditing ? 'edit_meal_title' : 'create_meal_title')
                .tr()
                .toUpperCase(),
            style: GoogleFonts.anton(
              fontSize: 17.sp,
              color: Colors.white,
              letterSpacing: 1,
            ),
          ),
        ),
        // Nothing is built until an edited meal has loaded: the text fields
        // are seeded once, when they are constructed, so building them over an
        // empty draft would leave them empty for good.
        body: state.isHydrating
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primaryNeon),
              )
            : SafeArea(
                top: false,
                child: Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 24.h),
                        children: [
                          const _PhotoPicker(),
                          SizedBox(height: 20.h),
                          const _NameField(),
                          SizedBox(height: 22.h),
                          const _IngredientsSection(),
                          SizedBox(height: 22.h),
                          const _TotalsSection(),
                          SizedBox(height: 22.h),
                          const _RecipeField(),
                          SizedBox(height: 18.h),
                          const _PublicToggle(),
                        ],
                      ),
                    ),
                    const _SaveBar(),
                  ],
                ),
              ),
      ),
      ),
    );
  }
}

/// Tap to attach the user's own photo, from the camera or the library.
///
/// Bytes are read here rather than at save time so the preview and the upload
/// use the same data, and so a file that disappears between picking and saving
/// fails immediately instead of halfway through a write.
class _PhotoPicker extends StatelessWidget {
  const _PhotoPicker();

  /// Re-encoded on the way in. A modern phone camera produces 4-12MB per frame;
  /// nobody needs that behind a 16:10 card, and it is the difference between an
  /// upload that finishes on mobile data and one that times out.
  static const int _maxWidth = 1600;
  static const int _quality = 82;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MealEditorCubit, MealEditorState>(
      buildWhen: (previous, current) =>
          previous.imageBytes != current.imageBytes ||
          previous.draft.existingImageUrl != current.draft.existingImageUrl,
      builder: (context, state) {
        final Uint8List? bytes = state.imageBytes;
        // A meal being edited already has a photo in storage. Freshly picked
        // bytes win, because those are what the user just chose.
        final String? storedUrl = state.draft.existingImageUrl;

        return PressScale(
          child: GestureDetector(
            onTap: () => _pick(context, hasImage: state.draft.hasImage),
            behavior: HitTestBehavior.opaque,
            child: AspectRatio(
              aspectRatio: 16 / 10,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1C),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(
                    color: AppColors.darkBorder,
                    width: 1.5,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: bytes == null && storedUrl == null
                    ? _buildPrompt()
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          if (bytes != null)
                            Image.memory(bytes, fit: BoxFit.cover)
                          else
                            Image.network(
                              storedUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildPrompt(),
                            ),
                          Positioned(
                            right: 8.w,
                            bottom: 8.h,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10.w,
                                vertical: 6.h,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(4.r),
                              ),
                              child: Text(
                                'meal_photo_change'.tr().toUpperCase(),
                                style: GoogleFonts.inter(
                                  fontSize: 9.sp,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPrompt() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.add_a_photo_outlined,
            size: 30.sp,
            color: AppColors.offWhiteMuted,
          ),
          SizedBox(height: 10.h),
          Text(
            'meal_photo_prompt'.tr().toUpperCase(),
            style: GoogleFonts.anton(
              fontSize: 13.sp,
              color: Colors.white,
              letterSpacing: 1,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            'meal_photo_hint'.tr(),
            style: GoogleFonts.inter(
              fontSize: 10.sp,
              color: AppColors.textGray,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pick(BuildContext context, {required bool hasImage}) async {
    final MealEditorCubit cubit = context.read<MealEditorCubit>();

    final ImageSourceChoice? choice =
        await ImageSourceSheet.show(context, canRemove: hasImage);
    if (choice == null) return;

    if (choice == ImageSourceChoice.remove) {
      cubit.removeImage();
      return;
    }

    final ImageSource? source = choice.pluginSource;
    if (source == null) return;

    try {
      final XFile? picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: _maxWidth.toDouble(),
        imageQuality: _quality,
      );
      if (picked == null) return;

      cubit.attachImage(
        path: picked.path,
        bytes: await picked.readAsBytes(),
        extension: _extensionOf(picked.path),
      );
    } catch (error) {
      // A denied camera permission or a cancelled picker throws on some
      // platforms. Neither is worth an error dialog — the user just gets no
      // photo, which they can see for themselves.
      debugPrint('Bulkr: image pick failed — $error');
    }
  }

  /// The picker re-encodes to JPEG when it resizes, but honours the original
  /// extension when it doesn't, so this reads the path rather than assuming.
  static String _extensionOf(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'jpg';
    final String extension = path.substring(dot + 1).toLowerCase();
    return extension.length > 5 ? 'jpg' : extension;
  }
}

/// Seeded once from the draft, which is what makes editing work: these are
/// built after hydration, so the controller starts with the meal's own text
/// rather than being overwritten on every rebuild as the user types.
class _NameField extends StatefulWidget {
  const _NameField();

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: context.read<MealEditorCubit>().state.draft.title,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _LabelledField(
      label: 'meal_name_label'.tr(),
      child: TextField(
        controller: _controller,
        onChanged: context.read<MealEditorCubit>().setTitle,
        textCapitalization: TextCapitalization.words,
        maxLength: 80,
        style: GoogleFonts.anton(color: Colors.white, fontSize: 18.sp),
        decoration: _inputDecoration('meal_name_hint'.tr()).copyWith(
          counterText: '',
        ),
      ),
    );
  }
}

class _RecipeField extends StatefulWidget {
  const _RecipeField();

  @override
  State<_RecipeField> createState() => _RecipeFieldState();
}

class _RecipeFieldState extends State<_RecipeField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: context.read<MealEditorCubit>().state.draft.recipe,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _LabelledField(
      label: 'meal_recipe_label'.tr(),
      helper: 'meal_recipe_helper'.tr(),
      child: TextField(
        controller: _controller,
        onChanged: context.read<MealEditorCubit>().setRecipe,
        minLines: 4,
        maxLines: 10,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 13.sp,
          height: 1.5,
        ),
        decoration: _inputDecoration('meal_recipe_hint'.tr()),
      ),
    );
  }
}

class _IngredientsSection extends StatelessWidget {
  const _IngredientsSection();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MealEditorCubit, MealEditorState>(
      buildWhen: (previous, current) =>
          previous.draft.ingredients != current.draft.ingredients,
      builder: (context, state) {
        final List<MealIngredient> ingredients = state.draft.ingredients;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel(
              label: 'meal_ingredients_label'.tr(),
              trailing: ingredients.isEmpty
                  ? null
                  : 'meal_ingredients_count'
                      .tr(namedArgs: {'count': '${ingredients.length}'}),
            ),
            SizedBox(height: 10.h),
            if (ingredients.isEmpty)
              Text(
                'meal_ingredients_empty'.tr(),
                style: GoogleFonts.inter(
                  fontSize: 11.sp,
                  color: AppColors.textGray,
                  height: 1.5,
                ),
              )
            else
              for (var i = 0; i < ingredients.length; i++)
                _IngredientRow(
                  ingredient: ingredients[i],
                  onEditAmount: () => _editAmount(context, i, ingredients[i]),
                  onRemove: () =>
                      context.read<MealEditorCubit>().removeIngredientAt(i),
                ),
            SizedBox(height: 12.h),
            const _AddIngredientButton(),
          ],
        );
      },
    );
  }
}

/// Opens the amount editor for one ingredient and applies whatever comes back.
Future<void> _editAmount(
  BuildContext context,
  int index,
  MealIngredient ingredient,
) async {
  final MealEditorCubit cubit = context.read<MealEditorCubit>();

  final double? grams = await IngredientAmountSheet.show(
    context,
    food: ingredient.food,
    amountG: ingredient.amountG,
  );

  if (grams != null) cubit.setAmountAt(index, grams);
}

class _IngredientRow extends StatelessWidget {
  const _IngredientRow({
    required this.ingredient,
    required this.onEditAmount,
    required this.onRemove,
  });

  final MealIngredient ingredient;

  /// Tapping the row changes how much of this food is in the meal — the thing
  /// most likely to be wrong right after adding it.
  final VoidCallback onEditAmount;

  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final Macros macros = ingredient.macros;

    return Container(
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.fromLTRB(12.w, 10.h, 4.w, 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(5.r),
        border: Border(
          left: BorderSide(color: AppColors.primaryNeon, width: 2.w),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: PressScale(
              child: GestureDetector(
                onTap: onEditAmount,
                behavior: HitTestBehavior.opaque,
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ingredient.food.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'meal_ingredient_summary'.tr(namedArgs: {
                    'grams': '${ingredient.amountG.round()}',
                    'kcal': '${macros.caloriesRounded}',
                    'protein': '${macros.proteinRounded}',
                    'carbs': '${macros.carbsRounded}',
                    'fat': '${macros.fatRounded}',
                  }),
                  style: GoogleFonts.inter(
                    fontSize: 10.sp,
                    color: AppColors.offWhiteMuted,
                  ),
                ),
              ],
                ),
              ),
            ),
          ),
          Icon(Icons.edit_outlined, size: 15.sp, color: AppColors.textGray),
          IconButton(
            onPressed: onRemove,
            icon: Icon(Icons.close_rounded, size: 18.sp),
            color: AppColors.textGray,
            tooltip: 'meal_ingredient_remove'.tr(),
          ),
        ],
      ),
    );
  }
}

/// The two ways into the ingredient list: search it, or scan it.
///
/// Side by side and equally weighted, because which one is right depends
/// entirely on the food in your hand. A packet has a barcode and scanning it is
/// exact; a chicken breast does not, and typing is the only way.
class _AddIngredientButton extends StatelessWidget {
  const _AddIngredientButton();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _IngredientAction(
            icon: Icons.search,
            label: 'meal_add_ingredient'.tr(),
            onTap: () => FoodSearchSheet.show(
              context,
              context.read<MealEditorCubit>(),
            ),
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: _IngredientAction(
            icon: Icons.qr_code_scanner_rounded,
            label: 'meal_scan_barcode'.tr(),
            onTap: () => _scanBarcode(context),
          ),
        ),
      ],
    );
  }
}

/// Scans a barcode, looks it up, and says what happened either way.
///
/// A scan that silently adds nothing is the worst outcome: the user has no way
/// to tell a product Open Food Facts has never heard of from a scanner that
/// misread the label.
Future<void> _scanBarcode(BuildContext context) async {
  final MealEditorCubit cubit = context.read<MealEditorCubit>();
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

  final String? barcode = await BarcodeScannerSheet.show(context);
  if (barcode == null) return;

  final FoodItem? food = await cubit.addScannedBarcode(barcode);

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor:
            food == null ? const Color(0xFF2A2A2A) : AppColors.primaryNeon,
        duration: const Duration(seconds: 3),
        content: Text(
          food == null
              ? 'barcode_not_found'.tr(namedArgs: {'barcode': barcode})
              : 'barcode_added'.tr(namedArgs: {'food': food.name}),
          style: GoogleFonts.inter(
            color: food == null ? Colors.white : Colors.black,
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
}

class _IngredientAction extends StatelessWidget {
  const _IngredientAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 14.h),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5.r),
            border: Border.all(color: AppColors.primaryNeon, width: 1.5),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16.sp, color: AppColors.primaryNeon),
              SizedBox(width: 8.w),
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.anton(
                    fontSize: 12.sp,
                    color: AppColors.primaryNeon,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The meal's calories and macros — computed from the ingredients when there
/// are any, typed in when there are not.
///
/// Two modes rather than one editable field seeded from the sum, because a
/// figure that stops updating the moment it is touched is the worst of both:
/// it looks live and isn't.
class _TotalsSection extends StatelessWidget {
  const _TotalsSection();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MealEditorCubit, MealEditorState>(
      buildWhen: (previous, current) =>
          previous.draft.totals != current.draft.totals ||
          previous.totalsAreComputed != current.totalsAreComputed,
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel(
              label: 'meal_totals_label'.tr(),
              trailing: state.totalsAreComputed
                  ? 'meal_totals_computed'.tr()
                  : 'meal_totals_manual'.tr(),
            ),
            SizedBox(height: 10.h),
            if (state.totalsAreComputed)
              _ComputedTotals(totals: state.draft.totals)
            else
              const _ManualTotals(),
          ],
        );
      },
    );
  }
}

class _ComputedTotals extends StatelessWidget {
  const _ComputedTotals({required this.totals});

  final Macros totals;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: AppColors.primaryNeon),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                NumberFormat.decimalPattern().format(totals.caloriesRounded),
                style: GoogleFonts.anton(
                  fontSize: 40.sp,
                  color: AppColors.primaryNeon,
                  height: 1,
                ),
              ),
              SizedBox(width: 8.w),
              Padding(
                padding: EdgeInsets.only(bottom: 5.h),
                child: Text(
                  'kcal_short'.tr().toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.offWhiteMuted,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          Row(
            children: [
              _TotalChip(
                color: MacroBreakdown.proteinColor,
                label: 'macro_protein'.tr(),
                grams: totals.proteinRounded,
              ),
              SizedBox(width: 8.w),
              _TotalChip(
                color: MacroBreakdown.carbsColor,
                label: 'macro_carbs'.tr(),
                grams: totals.carbsRounded,
              ),
              SizedBox(width: 8.w),
              _TotalChip(
                color: MacroBreakdown.fatColor,
                label: 'macro_fat'.tr(),
                grams: totals.fatRounded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TotalChip extends StatelessWidget {
  const _TotalChip({
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
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
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
                fontSize: 16.sp,
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

class _ManualTotals extends StatelessWidget {
  const _ManualTotals();

  @override
  Widget build(BuildContext context) {
    final MealEditorCubit cubit = context.read<MealEditorCubit>();
    final Macros typed = cubit.state.draft.manualTotals;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _NumberField(
                label: 'calorie_goal_title'.tr(),
                unit: 'kcal_short'.tr(),
                accent: AppColors.primaryNeon,
                initial: typed.calories,
                onChanged: (value) => cubit.setManualTotals(calories: value),
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: _NumberField(
                label: 'macro_protein'.tr(),
                unit: 'gram_short'.tr(),
                accent: MacroBreakdown.proteinColor,
                initial: typed.proteinG,
                onChanged: (value) => cubit.setManualTotals(proteinG: value),
              ),
            ),
          ],
        ),
        SizedBox(height: 10.h),
        Row(
          children: [
            Expanded(
              child: _NumberField(
                label: 'macro_carbs'.tr(),
                unit: 'gram_short'.tr(),
                accent: MacroBreakdown.carbsColor,
                initial: typed.carbsG,
                onChanged: (value) => cubit.setManualTotals(carbsG: value),
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: _NumberField(
                label: 'macro_fat'.tr(),
                unit: 'gram_short'.tr(),
                accent: MacroBreakdown.fatColor,
                initial: typed.fatG,
                onChanged: (value) => cubit.setManualTotals(fatG: value),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One hand-typed total.
///
/// Stateful, and seeded from the draft, because this field is unmounted whenever
/// an ingredient exists and the totals switch to being computed. The draft keeps
/// the typed numbers across that switch — without seeding the controller from
/// it, pulling the last ingredient back out would show four empty boxes over a
/// draft that still holds the figures.
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.unit,
    required this.accent,
    required this.initial,
    required this.onChanged,
  });

  final String label;
  final String unit;
  final Color accent;
  final double initial;
  final ValueChanged<double> onChanged;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initial > 0 ? '${widget.initial.round()}' : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 4.h),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(5.r),
        border: Border(left: BorderSide(color: widget.accent, width: 2.w)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 9.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.offWhiteMuted,
              letterSpacing: 1.2,
            ),
          ),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (raw) =>
                widget.onChanged(double.tryParse(raw.trim()) ?? 0),
            style: GoogleFonts.anton(color: Colors.white, fontSize: 26.sp),
            decoration: InputDecoration(
              hintText: '0',
              hintStyle: GoogleFonts.anton(
                color: AppColors.darkBorder,
                fontSize: 26.sp,
              ),
              suffixText: widget.unit.toLowerCase(),
              suffixStyle: GoogleFonts.inter(
                fontSize: 10.sp,
                color: AppColors.textGray,
              ),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 4.h),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ],
      ),
    );
  }
}

/// Whether the meal shows up in the feed for other users to save.
class _PublicToggle extends StatelessWidget {
  const _PublicToggle();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MealEditorCubit, MealEditorState>(
      buildWhen: (previous, current) =>
          previous.draft.isPublic != current.draft.isPublic,
      builder: (context, state) => Container(
        padding: EdgeInsets.fromLTRB(14.w, 6.h, 6.w, 6.h),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(5.r),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'meal_public_label'.tr().toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 1,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    'meal_public_helper'.tr(),
                    style: GoogleFonts.inter(
                      fontSize: 10.sp,
                      color: AppColors.textGray,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: state.draft.isPublic,
              onChanged: context.read<MealEditorCubit>().setPublic,
              activeThumbColor: Colors.black,
              activeTrackColor: AppColors.primaryNeon,
            ),
          ],
        ),
      ),
    );
  }
}

/// One button when writing a new meal, two when editing one you own.
///
/// Replace is the primary action — someone who opened the editor on their own
/// meal almost always means to correct it — but saving a copy sits beside it at
/// equal size, because turning one meal into a variant of itself is the other
/// half of why anyone edits. For a meal saved from someone else, only the copy
/// exists: theirs is not yours to overwrite.
class _SaveBar extends StatelessWidget {
  const _SaveBar();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MealEditorCubit, MealEditorState>(
      buildWhen: (previous, current) =>
          previous.canSave != current.canSave ||
          previous.isSaving != current.isSaving ||
          previous.canReplace != current.canReplace ||
          previous.isEditing != current.isEditing,
      builder: (context, state) {
        final MealEditorCubit cubit = context.read<MealEditorCubit>();

        return Container(
          padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 16.h),
          decoration: const BoxDecoration(
            color: Color(0xFF0F0F0F),
            border: Border(top: BorderSide(color: AppColors.darkBorder)),
          ),
          child: Row(
            children: [
              if (state.canReplace) ...[
                Expanded(
                  child: _SaveButton(
                    label: 'meal_replace_btn'.tr(),
                    isPrimary: true,
                    isEnabled: state.canSave,
                    isBusy: state.isSaving,
                    onTap: () => cubit.save(replaceExisting: true),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: _SaveButton(
                    label: 'meal_save_copy_btn'.tr(),
                    isPrimary: false,
                    isEnabled: state.canSave,
                    isBusy: false,
                    onTap: () => cubit.save(),
                  ),
                ),
              ] else
                Expanded(
                  child: _SaveButton(
                    label: (state.isEditing
                            ? 'meal_save_copy_btn'
                            : 'meal_save_btn')
                        .tr(),
                    isPrimary: true,
                    isEnabled: state.canSave,
                    isBusy: state.isSaving,
                    onTap: () => cubit.save(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({
    required this.label,
    required this.isPrimary,
    required this.isEnabled,
    required this.isBusy,
    required this.onTap,
  });

  final String label;
  final bool isPrimary;
  final bool isEnabled;

  /// Only one button shows the spinner, even though both are disabled while a
  /// save runs — two spinners would not say which action is happening.
  final bool isBusy;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool active = isEnabled && !isBusy;

    return PressScale(
      enabled: active,
      child: GestureDetector(
        onTap: active ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 16.h),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // Dimmed rather than hidden while incomplete, so the button is
            // visibly the next step even before it can be taken.
            color: isPrimary
                ? (isEnabled ? AppColors.buttonNeon : AppColors.darkBorder)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5.r),
            border: isPrimary
                ? null
                : Border.all(
                    color: isEnabled
                        ? AppColors.primaryNeon
                        : AppColors.darkBorder,
                    width: 1.5,
                  ),
          ),
          child: isBusy
              ? SizedBox(
                  width: 20.w,
                  height: 20.w,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.anton(
                    fontSize: 14.sp,
                    color: isPrimary
                        ? (isEnabled ? Colors.black : AppColors.textGray)
                        : (isEnabled
                            ? AppColors.primaryNeon
                            : AppColors.textGray),
                    letterSpacing: 1,
                  ),
                ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '# ${label.toUpperCase()}',
          style: GoogleFonts.anton(
            fontSize: 14.sp,
            color: Colors.white,
            letterSpacing: 1,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 9.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.offWhiteMuted,
              letterSpacing: 1.2,
            ),
          ),
      ],
    );
  }
}

class _LabelledField extends StatelessWidget {
  const _LabelledField({
    required this.label,
    required this.child,
    this.helper,
  });

  final String label;
  final Widget child;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(label: label),
        if (helper != null) ...[
          SizedBox(height: 4.h),
          Text(
            helper!,
            style: GoogleFonts.inter(
              fontSize: 10.sp,
              color: AppColors.textGray,
            ),
          ),
        ],
        SizedBox(height: 10.h),
        child,
      ],
    );
  }
}

InputDecoration _inputDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.inter(
      color: AppColors.darkBorder,
      fontSize: 13.sp,
    ),
    filled: true,
    fillColor: const Color(0xFF1A1A1A),
    contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
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
  );
}
