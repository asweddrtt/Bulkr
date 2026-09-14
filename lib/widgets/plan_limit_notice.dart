import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../core/plan_limit_error.dart';
import 'bulkr_snack_bar.dart';
import 'premium_sheet.dart';

/// The message somebody sees when the free tier runs out, with the way out of
/// it attached.
///
/// A limit without a next step is just a refusal. This exists so that every
/// wall in the app reads the same way — what the limit is, what removes it,
/// and a button rather than an instruction to go and find the settings.
///
/// The action is not a nag: it appears only when a limit was actually hit, and
/// it is a snackbar rather than a dialog, so somebody who wants to carry on
/// doing what they were doing can ignore it entirely.
///
/// ## This one, or the sheet
///
/// Use this when the limit arrives as a *failure* — the database refused a
/// write that was already in flight, and the user is owed an explanation for
/// something that has already happened. Use [PremiumSheet] directly when the
/// app can see the wall coming and stops at the button, where a snackbar would
/// be a strange answer to a tap that appeared to do nothing.
///
/// Either way the upgrade goes through the same sheet, so "how do I subscribe"
/// has one answer wherever it is asked.
class PlanLimitNotice {
  const PlanLimitNotice._();

  /// Shows the notice for [limit].
  static void show(
    BuildContext context,
    PlanLimit limit, {
    String source = 'limit',
  }) {
    BulkrSnackBar.show(
      context,
      planLimitMessage(limit),
      tone: SnackTone.premium,
      duration: const Duration(seconds: 8),
      actionLabel: 'limit_upgrade'.tr(),
      // The snackbar outlives the widget that showed it — it belongs to the
      // app's messenger, not to the route. A screen that has since been popped
      // must not be asked to push a sheet.
      onAction: () {
        if (!context.mounted) return;
        PremiumSheet.show(context, limit: limit, source: source);
      },
    );
  }

  /// Shows the notice if [error] was a plan limit, and answers whether it was.
  ///
  /// Lets a failure handler stay one line: try this first, and fall through to
  /// the ordinary error message when it returns false.
  static bool maybeShow(
    BuildContext context,
    Object error, {
    String source = 'limit',
  }) {
    final PlanLimit? limit = planLimitReached(error);
    if (limit == null) return false;

    show(context, limit, source: source);
    return true;
  }
}
