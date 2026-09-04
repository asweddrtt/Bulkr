import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../cubit/feed/feed_cubit.dart';
import '../cubit/meals/meals_cubit.dart';
import '../cubit/post_composer/post_composer_cubit.dart';
import '../data/meal_repository.dart';
import '../data/post_repository.dart';
import '../models/meal.dart';
import '../models/post_draft.dart';
import '../models/post_label.dart';
import '../styles/app_color.dart';
import '../widgets/animations/press_scale.dart';
import '../widgets/image_source_sheet.dart';
import '../widgets/sheet_action_row.dart';
import 'meal_editor_screen.dart';

/// Writing a post.
///
/// A full screen rather than a sheet: a post can be a label, a couple of
/// hundred words, four photos and a meal, and none of that fits in something
/// half the height of the display with a keyboard over it.
class PostComposerScreen extends StatelessWidget {
  const PostComposerScreen({super.key, this.initialLabel, this.attachedMeal});

  /// The label to open under. Null starts on [PostLabel.tip], matching the
  /// column default.
  final PostLabel? initialLabel;

  /// A meal to arrive pre-attached, for "post this meal" from the Meals tab.
  final Meal? attachedMeal;

  /// Opens the composer, and hands whatever gets written to the feed.
  ///
  /// The cubit is built here rather than provided by the shell, so closing the
  /// screen throws the draft away — the same lifetime the meal editor has.
  static Future<void> open(
    BuildContext context, {
    PostLabel? initialLabel,
    Meal? attachedMeal,
  }) {
    final FeedCubit feed = context.read<FeedCubit>();
    final PostRepository posts = context.read<PostRepository>();
    final MealRepository meals = context.read<MealRepository>();

    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => PostComposerCubit(
            postRepository: posts,
            mealRepository: meals,
            initialLabel: initialLabel ?? PostLabel.tip,
            attachedMeal: attachedMeal,
          ),
          // The feed cubit is passed down rather than re-read inside, because
          // the composer is pushed above the shell and its own context does not
          // sit under the tab that owns the feed.
          child: BlocProvider.value(
            value: feed,
            child: PostComposerScreen(
              initialLabel: initialLabel,
              attachedMeal: attachedMeal,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        // The post landed. Hand it to the feed and close.
        BlocListener<PostComposerCubit, PostComposerState>(
          listenWhen: (previous, current) =>
              previous.created == null && current.created != null,
          listener: (context, state) {
            context.read<FeedCubit>().postCreated(state.created!);
            Navigator.of(context).pop();
          },
        ),
        BlocListener<PostComposerCubit, PostComposerState>(
          listenWhen: (previous, current) =>
              current.errorDetail != null &&
              previous.errorDetail != current.errorDetail,
          listener: (context, state) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF2A2A2A),
                  content: Text(
                    state.errorDetail!,
                    style:
                        GoogleFonts.inter(color: Colors.white, fontSize: 12.sp),
                  ),
                ),
              );
            context.read<PostComposerCubit>().clearError();
          },
        ),
      ],
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        body: SafeArea(
          child: Column(
            children: [
              const _ComposerHeader(),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 40.h),
                  children: const [
                    _LabelPicker(),
                    _ContentField(),
                    _ImageStrip(),
                    _MealAttachment(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Close, title, and the Post button.
class _ComposerHeader extends StatelessWidget {
  const _ComposerHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 20.w, 8.h),
      child: Row(
        children: [
          PressScale(
            child: GestureDetector(
              onTap: () => _confirmClose(context),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.all(8.w),
                child: Icon(Icons.close, color: Colors.white, size: 20.sp),
              ),
            ),
          ),
          Expanded(
            child: Text(
              'post_composer_title'.tr().toUpperCase(),
              style: GoogleFonts.anton(
                color: Colors.white,
                fontSize: 17.sp,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const _SubmitButton(),
        ],
      ),
    );
  }

  /// Asks before throwing away something written.
  ///
  /// Only when there is something to lose — a composer opened and closed
  /// without a word typed just closes, because a confirmation for nothing
  /// teaches people to dismiss confirmations.
  static Future<void> _confirmClose(BuildContext context) async {
    final PostComposerCubit cubit = context.read<PostComposerCubit>();
    final NavigatorState navigator = Navigator.of(context);

    if (!cubit.state.hasUnsavedWork) {
      navigator.pop();
      return;
    }

    final bool? discard = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SheetShell(
        title: 'post_discard_title'.tr(),
        children: [
          SheetActionRow(
            icon: Icons.delete_outline,
            label: 'post_discard_confirm'.tr(),
            helper: 'post_discard_helper'.tr(),
            isDestructive: true,
            onTap: () => Navigator.of(sheetContext).pop(true),
          ),
          SheetActionRow(
            icon: Icons.edit_outlined,
            label: 'post_discard_keep'.tr(),
            onTap: () => Navigator.of(sheetContext).pop(false),
          ),
        ],
      ),
    );

    if (discard == true) navigator.pop();
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PostComposerCubit, PostComposerState>(
      buildWhen: (previous, current) =>
          previous.canSubmit != current.canSubmit ||
          previous.isSubmitting != current.isSubmitting,
      builder: (context, state) {
        return PressScale(
          child: GestureDetector(
            onTap: state.canSubmit
                ? () => context.read<PostComposerCubit>().submit()
                : null,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 9.h),
              decoration: BoxDecoration(
                // Dimmed rather than hidden when there is nothing to post, so
                // the button's position never moves.
                color: state.canSubmit
                    ? AppColors.buttonNeon
                    : const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(6.r),
              ),
              child: state.isSubmitting
                  ? SizedBox(
                      width: 13.sp,
                      height: 13.sp,
                      child: const CircularProgressIndicator(
                        color: Colors.black,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'post_submit'.tr().toUpperCase(),
                      style: GoogleFonts.inter(
                        color: state.canSubmit
                            ? Colors.black
                            : AppColors.textGray,
                        fontSize: 11.sp,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// Which of the six kinds of post this is.
///
/// Asked first, and never left unanswered — it opens on a default rather than
/// on nothing, because a required question with no answer is a wall in front of
/// a text field.
class _LabelPicker extends StatelessWidget {
  const _LabelPicker();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PostComposerCubit, PostComposerState>(
      buildWhen: (previous, current) =>
          previous.draft.label != current.draft.label,
      builder: (context, state) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'post_label_prompt'.tr().toUpperCase(),
            style: GoogleFonts.inter(
              color: AppColors.textGray,
              fontSize: 10.sp,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          SizedBox(height: 10.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              for (final PostLabel label in PostLabel.values)
                _LabelOption(
                  label: label,
                  isSelected: state.draft.label == label,
                  onTap: () =>
                      context.read<PostComposerCubit>().setLabel(label),
                ),
            ],
          ),
          SizedBox(height: 18.h),
        ],
      ),
    );
  }
}

class _LabelOption extends StatelessWidget {
  const _LabelOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final PostLabel label;
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
            color: isSelected ? label.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(6.r),
            border: Border.all(
              color: isSelected ? label.accent : AppColors.darkBorder,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                label.icon,
                color: isSelected ? Colors.black : AppColors.textGray,
                size: 13.sp,
              ),
              SizedBox(width: 6.w),
              Text(
                label.labelKey.tr().toUpperCase(),
                style: GoogleFonts.inter(
                  color: isSelected ? Colors.black : AppColors.textGray,
                  fontSize: 10.sp,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What they want to say.
class _ContentField extends StatefulWidget {
  const _ContentField();

  @override
  State<_ContentField> createState() => _ContentFieldState();
}

class _ContentFieldState extends State<_ContentField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Seeded once from the draft rather than rebuilt from state on every
    // keystroke: a controller re-set from state fights the cursor.
    _controller.text = context.read<PostComposerCubit>().state.draft.content;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PostComposerCubit, PostComposerState>(
      buildWhen: (previous, current) =>
          previous.draft.label != current.draft.label ||
          previous.draft.showsCharacterCount !=
              current.draft.showsCharacterCount ||
          previous.draft.remainingCharacters !=
              current.draft.remainingCharacters,
      builder: (context, state) {
        final PostDraft draft = state.draft;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: AppColors.darkBorder),
              ),
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
              child: TextField(
                controller: _controller,
                onChanged: (value) =>
                    context.read<PostComposerCubit>().setContent(value),
                maxLines: null,
                minLines: 5,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 13.sp,
                  height: 1.45,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  // The hint changes with the label, which is the cheapest way
                  // to make six kinds of post feel like six kinds of post
                  // rather than one box with a tag on it.
                  hintText: draft.label.promptKey.tr(),
                  hintStyle: GoogleFonts.inter(
                    color: AppColors.textGray,
                    fontSize: 13.sp,
                  ),
                ),
              ),
            ),
            if (draft.showsCharacterCount) ...[
              SizedBox(height: 6.h),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${draft.remainingCharacters}',
                  style: GoogleFonts.inter(
                    color: draft.isTooLong
                        ? const Color(0xFFFF5722)
                        : AppColors.textGray,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            SizedBox(height: 18.h),
          ],
        );
      },
    );
  }
}

/// The photos, and the way to add one.
class _ImageStrip extends StatelessWidget {
  const _ImageStrip();

  static const int _maxWidth = 1600;
  static const int _quality = 82;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PostComposerCubit, PostComposerState>(
      buildWhen: (previous, current) =>
          previous.draft.imagePaths != current.draft.imagePaths ||
          previous.draft.label != current.draft.label,
      builder: (context, state) {
        final PostDraft draft = state.draft;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'post_photos_prompt'.tr().toUpperCase(),
                    style: GoogleFonts.inter(
                      color: AppColors.textGray,
                      fontSize: 10.sp,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Text(
                  '${draft.imagePaths.length}/${PostDraft.maxImages}',
                  style: GoogleFonts.inter(
                    color: AppColors.textGray,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            // Only said where it means something. A progress post without a
            // photo is missing the point; a tip without one is fine.
            if (draft.label.wantsImages && !draft.hasImages) ...[
              SizedBox(height: 6.h),
              Text(
                'post_photos_suggested'.tr(),
                style: GoogleFonts.inter(
                  color: AppColors.textGray,
                  fontSize: 11.sp,
                ),
              ),
            ],
            SizedBox(height: 10.h),
            SizedBox(
              height: 88.w,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final String path in draft.imagePaths)
                    _Thumbnail(
                      path: path,
                      onRemove: () =>
                          context.read<PostComposerCubit>().removeImage(path),
                    ),
                  if (draft.canAddImage)
                    _AddPhotoButton(onTap: () => _pick(context)),
                ],
              ),
            ),
            SizedBox(height: 18.h),
          ],
        );
      },
    );
  }

  static Future<void> _pick(BuildContext context) async {
    final PostComposerCubit cubit = context.read<PostComposerCubit>();
    final ImageSourceChoice? choice = await ImageSourceSheet.show(context);

    final ImageSource? source = choice?.pluginSource;
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
  /// extension when it does not, so the name is the only thing that knows.
  static String _extensionOf(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'jpg';
    final String extension = path.substring(dot + 1).toLowerCase();
    return extension.length > 5 ? 'jpg' : extension;
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path, required this.onRemove});

  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(right: 8.w),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6.r),
            child: SizedBox(
              width: 88.w,
              height: 88.w,
              // Read off disk, not from the bytes in state: the file is
              // already there, and Image.file lets Flutter cache and downscale
              // it instead of holding a second decoded copy per thumbnail.
              //
              // kIsWeb has no filesystem, and the app targets phones — but the
              // repo builds for web, and Image.file throws there rather than
              // failing to render.
              child: kIsWeb
                  ? ColoredBox(
                      color: const Color(0xFF232323),
                      child: Icon(
                        Icons.image,
                        color: AppColors.textGray,
                        size: 20.sp,
                      ),
                    )
                  : Image.file(File(path), fit: BoxFit.cover),
            ),
          ),
          Positioned(
            top: 4.w,
            right: 4.w,
            child: PressScale(
              child: GestureDetector(
                onTap: onRemove,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: EdgeInsets.all(4.w),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close, color: Colors.white, size: 12.sp),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddPhotoButton extends StatelessWidget {
  const _AddPhotoButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 88.w,
          height: 88.w,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(6.r),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Icon(
            Icons.add_a_photo_outlined,
            color: AppColors.textGray,
            size: 22.sp,
          ),
        ),
      ),
    );
  }
}

/// The meal hanging off the post, if any.
class _MealAttachment extends StatelessWidget {
  const _MealAttachment();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PostComposerCubit, PostComposerState>(
      buildWhen: (previous, current) =>
          previous.draft.attachedMeal != current.draft.attachedMeal,
      builder: (context, state) {
        final Meal? meal = state.draft.attachedMeal;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'post_meal_prompt'.tr().toUpperCase(),
              style: GoogleFonts.inter(
                color: AppColors.textGray,
                fontSize: 10.sp,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            SizedBox(height: 10.h),
            if (meal == null) ...[
              // Two ways in, not one. Picking from the library is the quick
              // path when the meal already exists; writing one is the path
              // that matters for a first-time poster, whose library is empty
              // and who would otherwise hit a dead end being told to go build
              // one somewhere else first.
              _AttachMealButton(
                icon: Icons.restaurant_sharp,
                label: 'post_attach_meal'.tr(),
                onTap: () => _pickMeal(context),
              ),
              SizedBox(height: 8.h),
              _AttachMealButton(
                icon: Icons.add_circle_outline,
                label: 'post_create_meal'.tr(),
                onTap: () => _createMeal(context),
              ),
            ] else ...[
              _AttachedMealRow(
                meal: meal,
                onRemove: () => context.read<PostComposerCubit>().removeMeal(),
              ),
              // Said before posting, not after. Attaching publishes the meal —
              // `PostRepository.createPost` flips `is_public` so readers can
              // actually open the attachment — and a private meal becoming
              // public is not something to discover from the result.
              if (!meal.isPublic) ...[
                SizedBox(height: 8.h),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.public,
                      color: AppColors.textGray,
                      size: 12.sp,
                    ),
                    SizedBox(width: 6.w),
                    Expanded(
                      child: Text(
                        'post_meal_will_publish'.tr(),
                        style: GoogleFonts.inter(
                          color: AppColors.textGray,
                          fontSize: 10.sp,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        );
      },
    );
  }

  /// Offers the user's own meals.
  ///
  /// Their own only. Attaching someone else's would put this author's name over
  /// their work, and the repository refuses it too — the picker is not the only
  /// way into that method.
  static Future<void> _pickMeal(BuildContext context) async {
    final PostComposerCubit cubit = context.read<PostComposerCubit>();
    cubit.loadAttachableMeals();

    final Meal? picked = await showModalBottomSheet<Meal>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => BlocProvider.value(
        value: cubit,
        child: const _MealPickerSheet(),
      ),
    );

    if (picked == null) return;

    // The sheet returns the sentinel rather than closing itself and then asking
    // the caller to guess: "create a new one" is a choice made inside the
    // picker, and it has to run after the sheet is gone so the editor is not
    // pushed underneath it.
    if (picked.id == _MealPickerSheet.createSentinelId) {
      if (!context.mounted) return;
      await _createMeal(context);
      return;
    }

    cubit.attachMeal(picked);
  }

  /// Writes a new meal and attaches it.
  ///
  /// The real editor, not a cut-down version of it: ingredients off Open Food
  /// Facts, the barcode scanner, a photo, the recipe, hand-typed macros. It is
  /// the same screen the Meals tab pushes, so a meal written for a post is a
  /// meal in every sense — it lands in the user's library too, which is where
  /// they will look for it again.
  ///
  /// Opened with the public switch already on, because a meal nobody else can
  /// read renders as no attachment at all.
  static Future<void> _createMeal(BuildContext context) async {
    final PostComposerCubit cubit = context.read<PostComposerCubit>();
    // Read before the await: the library refresh below happens after this
    // route may have been popped, and reading a cubit off a dead context
    // throws.
    final MealsCubit meals = context.read<MealsCubit>();

    final Meal? created = await Navigator.of(context).push<Meal>(
      MaterialPageRoute(
        builder: (_) => const MealEditorScreen(initialIsPublic: true),
      ),
    );

    if (created == null) return;

    cubit.attachMeal(created);

    // The meal is a real row in the user's library, not something that exists
    // only on this post, so the Meals tab has to know about it. Silent, so a
    // library the user is not looking at does not blank itself out behind them.
    meals.refresh();
  }
}

class _AttachMealButton extends StatelessWidget {
  const _AttachMealButton({
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
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primaryNeon, size: 18.sp),
              SizedBox(width: 12.w),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppColors.textGray,
                size: 18.sp,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachedMealRow extends StatelessWidget {
  const _AttachedMealRow({required this.meal, required this.onRemove});

  final Meal meal;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: AppColors.primaryNeon.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.restaurant_sharp,
              color: AppColors.primaryNeon, size: 18.sp),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meal.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 3.h),
                Text(
                  'post_meal_macros'.tr(namedArgs: {
                    'calories': '${meal.totals.caloriesRounded}',
                    'protein': '${meal.totals.proteinRounded}',
                  }),
                  style: GoogleFonts.inter(
                    color: AppColors.textGray,
                    fontSize: 10.sp,
                  ),
                ),
              ],
            ),
          ),
          PressScale(
            child: GestureDetector(
              onTap: onRemove,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: EdgeInsets.all(4.w),
                child: Icon(
                  Icons.close,
                  color: AppColors.textGray,
                  size: 16.sp,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The list of meals a post could carry.
class _MealPickerSheet extends StatelessWidget {
  const _MealPickerSheet();

  /// Id of the meal this sheet returns to mean "none of these — write a new
  /// one".
  ///
  /// A sentinel rather than a second return type, so the sheet stays a
  /// `showModalBottomSheet<Meal>` and the caller keeps one thing to check. The
  /// value cannot collide with a real meal: `meals.id` is a uuid, and this is
  /// not one.
  static const String createSentinelId = 'create-new-meal';

  static Meal get _createSentinel => Meal(
        id: createSentinelId,
        creatorId: '',
        title: '',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PostComposerCubit, PostComposerState>(
      builder: (context, state) {
        return Container(
          constraints: BoxConstraints(maxHeight: 480.h),
          margin: EdgeInsets.all(16.w),
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: const Color(0xFF121212),
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: AppColors.darkBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'post_pick_meal'.tr().toUpperCase(),
                style: GoogleFonts.anton(
                  color: Colors.white,
                  fontSize: 15.sp,
                  letterSpacing: 1.1,
                ),
              ),
              SizedBox(height: 14.h),
              Flexible(child: _buildBody(context, state)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, PostComposerState state) {
    switch (state.mealsStatus) {
      case ComposerMealsStatus.initial:
      case ComposerMealsStatus.loading:
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 30.h),
          child: const Center(
            child: CircularProgressIndicator(color: AppColors.primaryNeon),
          ),
        );

      case ComposerMealsStatus.failure:
        return Padding(
          padding: EdgeInsets.symmetric(vertical: 24.h),
          child: Text(
            'post_meals_failed'.tr(),
            style:
                GoogleFonts.inter(color: AppColors.textGray, fontSize: 12.sp),
          ),
        );

      case ComposerMealsStatus.ready:
        if (state.attachableMeals.isEmpty) {
          // An empty library used to be a dead end that explained itself and
          // offered nothing. The way out is right here.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: 14.h),
                child: Text(
                  'post_no_meals'.tr(),
                  style: GoogleFonts.inter(
                    color: AppColors.textGray,
                    fontSize: 12.sp,
                    height: 1.4,
                  ),
                ),
              ),
              _buildCreateRow(context),
            ],
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          // One extra row at the top for writing a new meal.
          itemCount: state.attachableMeals.length + 1,
          separatorBuilder: (_, __) => SizedBox(height: 8.h),
          itemBuilder: (context, index) {
            if (index == 0) return _buildCreateRow(context);

            final Meal meal = state.attachableMeals[index - 1];

            return SheetActionRow(
              icon: Icons.restaurant_sharp,
              label: meal.title,
              helper: 'post_meal_macros'.tr(namedArgs: {
                'calories': '${meal.totals.caloriesRounded}',
                'protein': '${meal.totals.proteinRounded}',
              }),
              onTap: () => Navigator.of(context).pop(meal),
            );
          },
        );
    }
  }

  Widget _buildCreateRow(BuildContext context) {
    return SheetActionRow(
      icon: Icons.add_circle_outline,
      label: 'post_create_meal'.tr(),
      helper: 'post_create_meal_helper'.tr(),
      // Closes the sheet and lets the caller push the editor, rather than
      // pushing it from under a sheet that is still on screen.
      onTap: () => Navigator.of(context).pop(_createSentinel),
    );
  }
}
