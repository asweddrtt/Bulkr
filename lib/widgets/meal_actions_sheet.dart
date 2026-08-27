import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/meal.dart';
import '../styles/app_color.dart';
import 'sheet_action_row.dart';

/// What the user chose to do with a meal from its overflow menu.
enum MealAction {
  /// Open the meal in the editor. Offered for every meal — someone else's can
  /// be edited into a copy of your own, never overwritten.
  edit,

  /// Delete a meal the user wrote. Irreversible, and visible to anyone who
  /// saved it.
  delete,

  /// Drop someone else's meal out of this user's library, leaving the meal
  /// itself alone.
  removeFromLibrary,
}

/// The overflow menu on a meal card.
///
/// Editing is offered for every meal; what the editor will let you save differs,
/// and that decision belongs there rather than here. The destructive option is
/// the one that changes with ownership: you delete what you wrote and you let go
/// of what you saved. Presenting both would imply a user can delete a meal out
/// of someone else's account.
class MealActionsSheet extends StatelessWidget {
  const MealActionsSheet({super.key, required this.meal});

  final Meal meal;

  /// Resolves to the chosen action, or null when dismissed.
  static Future<MealAction?> show(BuildContext context, Meal meal) {
    return showModalBottomSheet<MealAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => MealActionsSheet(meal: meal),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SheetShell(
      title: meal.title,
      children: [
        SheetActionRow(
          icon: Icons.edit_outlined,
          label: 'meal_edit'.tr(),
          helper: meal.isMine
              ? 'meal_edit_helper'.tr()
              : 'meal_edit_copy_helper'.tr(),
          onTap: () => Navigator.of(context).pop(MealAction.edit),
        ),
        SizedBox(height: 10.h),
        if (meal.isMine)
          SheetActionRow(
            icon: Icons.delete_outline_rounded,
            label: 'meal_delete'.tr(),
            helper: meal.isPublic
                ? 'meal_delete_public_helper'.tr()
                : 'meal_delete_helper'.tr(),
            isDestructive: true,
            onTap: () => Navigator.of(context).pop(MealAction.delete),
          )
        else
          SheetActionRow(
            icon: Icons.bookmark_remove_outlined,
            label: 'meal_remove'.tr(),
            helper: 'meal_remove_helper'.tr(),
            isDestructive: true,
            onTap: () =>
                Navigator.of(context).pop(MealAction.removeFromLibrary),
          ),
      ],
    );
  }
}

/// Last check before a meal the user wrote is gone for good.
///
/// Shown only for deletion, never for removing a saved meal: that one is a
/// single tap to undo — find the meal in the feed and save it again — and a
/// confirmation for a reversible action just trains people to tap through
/// confirmations.
class DeleteMealDialog extends StatelessWidget {
  const DeleteMealDialog({super.key, required this.meal});

  final Meal meal;

  static Future<bool> show(BuildContext context, Meal meal) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => DeleteMealDialog(meal: meal),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8.r),
        side: const BorderSide(color: AppColors.darkBorder),
      ),
      title: Text(
        'meal_delete_confirm_title'.tr().toUpperCase(),
        style: GoogleFonts.anton(
          fontSize: 16.sp,
          color: Colors.white,
          letterSpacing: 1,
        ),
      ),
      content: Text(
        meal.isPublic
            ? 'meal_delete_confirm_public_body'.tr(namedArgs: {'meal': meal.title})
            : 'meal_delete_confirm_body'.tr(namedArgs: {'meal': meal.title}),
        style: GoogleFonts.inter(
          fontSize: 13.sp,
          color: AppColors.offWhiteMuted,
          height: 1.5,
        ),
      ),
      actionsPadding: EdgeInsets.fromLTRB(12.w, 0, 12.w, 12.h),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'meal_delete_cancel'.tr().toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 12.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.offWhiteMuted,
              letterSpacing: 1,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            'meal_delete_confirm'.tr().toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 12.sp,
              fontWeight: FontWeight.w700,
              color: SheetActionRow.destructive,
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    );
  }
}
