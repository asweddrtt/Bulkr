import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/plan_limit_error.dart';
import '../screens/upgrade_screen.dart';
import '../styles/app_color.dart';

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
class PlanLimitNotice {
  const PlanLimitNotice._();

  /// Shows the notice for [limit].
  static void show(
    BuildContext context,
    PlanLimit limit, {
    String source = 'limit',
  }) {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF2A2A2A),
          duration: const Duration(seconds: 8),
          content: Text(
            planLimitMessage(limit),
            style: GoogleFonts.inter(color: Colors.white, fontSize: 12.sp),
          ),
          action: SnackBarAction(
            label: 'limit_upgrade'.tr(),
            textColor: AppColors.primaryNeon,
            onPressed: () => UpgradeScreen.open(context, source: source),
          ),
        ),
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
