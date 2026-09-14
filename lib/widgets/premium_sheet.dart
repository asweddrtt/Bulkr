import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/plan_limit_error.dart';
import '../core/plan_limits.dart';
import '../cubit/entitlement/entitlement_cubit.dart';
import '../screens/upgrade_screen.dart';
import '../styles/app_color.dart';
import 'animations/press_scale.dart';

/// The wall, with the way through it attached.
///
/// ## Why a sheet and not just the paywall
///
/// Sending somebody straight to a full-screen paywall the moment they tap a
/// locked button is a bait-and-switch: they asked to scan a barcode and got a
/// price list. This sheet is the half-step between — it names the thing they
/// just tried to do, says what free gets, and *then* offers the paywall as a
/// button they choose to press. Dismissing it puts them back exactly where
/// they were, which the paywall's full-screen route does not.
///
/// It is also the answer to "where do I subscribe" being different on every
/// screen. There is one sheet, every gate in the app opens it, and it always
/// ends in the same button.
///
/// ## It records the wall, not the sale
///
/// Every [show] fires `plan_limit_reached` through [EntitlementCubit]. Which
/// limits people actually hit is the single most useful number this feature
/// produces: a cap nobody reaches is selling nothing, and a cap everybody
/// reaches in week one is costing users rather than converting them. The sale
/// itself is counted by the paywall.
class PremiumSheet extends StatelessWidget {
  const PremiumSheet({super.key, required this.limit, required this.source});

  /// Which wall they hit. Decides the sentence at the top; everything below it
  /// is the same whichever wall it was.
  final PlanLimit limit;

  /// What led here — `meals_create`, `scan`, `history`. Carried into
  /// `paywall_shown` so the funnel can be read per gate rather than in total.
  final String source;

  /// Shows the sheet, and resolves when it closes — or when the paywall it
  /// led to closes, for a caller that wants to retry the thing that was
  /// blocked once the user is back.
  ///
  /// The paywall is pushed from *this* context rather than from the sheet's,
  /// after the sheet has gone. A sheet that pops itself and then uses its own
  /// context to push is reading providers off a deactivated element, which is
  /// the classic way to throw inside a button nobody is watching.
  static Future<void> show(
    BuildContext context, {
    required PlanLimit limit,
    required String source,
  }) async {
    _record(context, limit);

    final bool? wantsUpgrade = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PremiumSheet(limit: limit, source: source),
    );

    if (wantsUpgrade != true || !context.mounted) return;

    await UpgradeScreen.open(context, source: source);
  }

  /// Fire-and-forget, and deliberately swallowing a missing provider: a
  /// telemetry call is never a reason for a wall not to explain itself.
  static void _record(BuildContext context, PlanLimit limit) {
    try {
      context.read<EntitlementCubit>().recordLimitReached(limit.key);
    } catch (_) {
      // No cubit above this context — a widget test, or a sheet shown from a
      // route outside the app shell.
    }
  }

  @override
  Widget build(BuildContext context) {
    final PlanLimits free = PlanLimits.free;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
          border: Border(
            top: BorderSide(color: AppColors.primaryNeon.withValues(alpha: 0.35)),
          ),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 20.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: AppColors.darkBorder,
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                ),
              ),
              SizedBox(height: 20.h),
              Row(
                children: <Widget>[
                  Container(
                    padding: EdgeInsets.all(9.w),
                    decoration: BoxDecoration(
                      color: AppColors.primaryNeon.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11.r),
                    ),
                    child: Icon(
                      Icons.workspace_premium_rounded,
                      color: AppColors.primaryNeon,
                      size: 20.sp,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      'premium_sheet_title'.tr(),
                      style: GoogleFonts.anton(
                        fontSize: 20.sp,
                        color: Colors.white,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 14.h),

              // The sentence for the wall they actually hit, in a box of its
              // own. Everything under it is the general pitch, and somebody
              // who taps a locked scanner should not have to find the scanning
              // line in a list of five.
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                decoration: BoxDecoration(
                  color: const Color(0xFF16190A),
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(
                    color: AppColors.primaryNeon.withValues(alpha: 0.25),
                  ),
                ),
                child: Text(
                  planLimitMessage(limit),
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12.sp,
                    height: 1.45,
                  ),
                ),
              ),
              SizedBox(height: 20.h),

              Text(
                'premium_sheet_includes'.tr().toUpperCase(),
                style: GoogleFonts.inter(
                  color: AppColors.textGray,
                  fontSize: 9.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
              SizedBox(height: 12.h),

              _Perk(
                icon: Icons.restaurant_menu,
                label: 'premium_benefit_meals'.tr(),
                sub: 'premium_benefit_meals_sub'.tr(
                  namedArgs: <String, String>{'count': '${free.savedMeals}'},
                ),
              ),
              _Perk(
                icon: Icons.qr_code_scanner,
                label: 'premium_benefit_scan'.tr(),
                sub: 'premium_benefit_scan_sub'.tr(),
              ),
              _Perk(
                icon: Icons.history,
                label: 'premium_benefit_history'.tr(),
                sub: 'premium_benefit_history_sub'.tr(
                  namedArgs: <String, String>{'days': '${free.historyDays}'},
                ),
              ),
              _Perk(
                icon: Icons.emoji_events_outlined,
                label: 'premium_benefit_challenges'.tr(),
                sub: 'premium_benefit_challenges_sub'.tr(),
              ),
              _Perk(
                icon: Icons.block_flipped,
                label: 'premium_benefit_ads'.tr(),
                sub: 'premium_benefit_ads_sub'.tr(),
              ),

              SizedBox(height: 18.h),
              PressScale(
                child: SizedBox(
                  height: 48.h,
                  child: ElevatedButton(
                    // Pops with the answer rather than pushing the paywall
                    // itself, so backing out of the paywall lands on the
                    // screen they started from rather than on a sheet they
                    // have already read. See [show].
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryNeon,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    child: Text(
                      'premium_sheet_cta'.tr(),
                      style: GoogleFonts.inter(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 4.h),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  'premium_sheet_dismiss'.tr(),
                  style: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w500,
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

class _Perk extends StatelessWidget {
  const _Perk({required this.icon, required this.label, required this.sub});

  final IconData icon;
  final String label;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: AppColors.primaryNeon, size: 17.sp),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  sub,
                  style: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 10.sp,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
