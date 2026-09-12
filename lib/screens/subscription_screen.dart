import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/store_links.dart';
import '../core/plan_limits.dart';
import '../core/telemetry.dart';
import '../cubit/entitlement/entitlement_cubit.dart';
import '../data/purchase_service.dart';
import '../models/entitlement.dart';
import '../styles/app_color.dart';
import '../widgets/sheet_action_row.dart';
import 'upgrade_screen.dart';

/// What this account has, and how to stop having it.
///
/// ## Why this screen exists
///
/// Because until it did, a subscriber could see the charge on their card and
/// find nothing in the app about it — no status, no renewal date, and no route
/// to cancelling. That is a guideline 3.1.2 rejection, and it is also simply
/// the behaviour of an app that has taken somebody's money and stopped being
/// interested.
///
/// ## The rule it is built around
///
/// **Leaving must not be harder than arriving.** Subscribing is: account
/// sheet, Bulkr Premium, pick a plan, Subscribe, confirm at the store.
/// Cancelling is: account sheet, Bulkr Premium, Cancel subscription, confirm
/// at the store. One tap fewer, and no confirmation sheet in front of the
/// cancel button.
///
/// That last part was a decision rather than an omission. Neither store lets
/// an app cancel its own subscription, so "Cancel" can only ever mean "open
/// the page where you cancel" — and a dialog asking "are you sure?" before
/// opening a page the user can back out of anyway is friction that serves us
/// and nobody else. The confirmation happens where the cancellation does.
class SubscriptionScreen extends StatelessWidget {
  const SubscriptionScreen({super.key});

  static Future<void> open(BuildContext context) {
    final EntitlementCubit entitlement = context.read<EntitlementCubit>();
    final PurchaseService purchases = context.read<PurchaseService>();

    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MultiRepositoryProvider(
          providers: <RepositoryProvider<Object>>[
            RepositoryProvider<PurchaseService>.value(value: purchases),
          ],
          child: BlocProvider<EntitlementCubit>.value(
            value: entitlement,
            child: const SubscriptionScreen(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          'sub_title'.tr().toUpperCase(),
          style: GoogleFonts.anton(
            fontSize: 18.sp,
            color: Colors.white,
            letterSpacing: 1,
          ),
        ),
      ),
      body: BlocBuilder<EntitlementCubit, EntitlementState>(
        builder: (BuildContext context, EntitlementState state) {
          return ListView(
            padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 32.h),
            children: <Widget>[
              _StatusCard(state: state),
              SizedBox(height: 20.h),
              if (state.isPremium) ...<Widget>[
                SheetActionRow(
                  icon: Icons.tune,
                  label: 'sub_manage'.tr(),
                  helper: 'sub_manage_helper'.tr(),
                  onTap: () => _openStore(context),
                ),
                SizedBox(height: 10.h),
                SheetActionRow(
                  icon: Icons.cancel_outlined,
                  label: 'sub_cancel'.tr(),
                  helper: Platform.isIOS
                      ? 'sub_cancel_helper_apple'.tr()
                      : 'sub_cancel_helper_google'.tr(),
                  // Straight there. See the note at the top of this class for
                  // why there is no "are you sure?" in the way.
                  onTap: () => _openStore(context),
                ),
                SizedBox(height: 14.h),
                Text(
                  'sub_cancel_note'.tr(),
                  style: GoogleFonts.inter(
                    color: Colors.white38,
                    fontSize: 10.sp,
                    height: 1.5,
                  ),
                ),
              ] else ...<Widget>[
                SheetActionRow(
                  icon: Icons.workspace_premium_outlined,
                  label: 'limit_upgrade'.tr(),
                  helper: 'account_premium_helper'.tr(),
                  onTap: () =>
                      UpgradeScreen.open(context, source: 'subscription'),
                ),
              ],
              SizedBox(height: 10.h),
              // Offered on both tiers, and it has to be: somebody who paid on
              // another phone reads as free here until they tap this, which is
              // exactly the person who most needs to find it.
              SheetActionRow(
                icon: Icons.restore,
                label: 'sub_restore'.tr(),
                helper: 'sub_restore_helper'.tr(),
                onTap: () => _restore(context),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openStore(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final Entitlement entitlement = context
        .read<EntitlementCubit>()
        .state
        .entitlement;

    final Uri url = Uri.parse(
      StoreLinks.subscriptionManagement(productId: entitlement.productId),
    );

    bool opened = false;
    try {
      opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (error, stackTrace) {
      await Telemetry.recordError(
        error,
        stackTrace,
        reason: 'opening the store subscription page',
      );
    }

    if (opened) return;

    // Doing nothing here would be the original bug with extra steps: the user
    // taps Cancel and the app appears to ignore them.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(_notice('sub_store_unavailable'.tr()));
  }

  Future<void> _restore(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final PurchaseService purchases = context.read<PurchaseService>();
    final EntitlementCubit entitlement = context.read<EntitlementCubit>();

    await purchases.restore();

    // The result arrives on the purchase stream, which [EntitlementCubit] is
    // already listening to — so this only has to re-read what that wrote.
    await entitlement.refresh();

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        _notice(
          entitlement.state.isPremium
              ? 'sub_restore_done'.tr()
              : 'premium_nothing_restored'.tr(),
        ),
      );
  }

  static SnackBar _notice(String message) => SnackBar(
    backgroundColor: const Color(0xFF2A2A2A),
    content: Text(
      message,
      style: GoogleFonts.inter(color: Colors.white, fontSize: 12.sp),
    ),
  );
}

/// Status, date, and where it was bought — the three things somebody opens
/// this screen to check.
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});

  final EntitlementState state;

  @override
  Widget build(BuildContext context) {
    final Entitlement entitlement = state.entitlement;
    final bool premium = state.isPremium;

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: premium ? AppColors.primaryNeon : AppColors.darkBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                premium
                    ? Icons.workspace_premium
                    : Icons.workspace_premium_outlined,
                color: premium ? AppColors.primaryNeon : Colors.white38,
                size: 20.sp,
              ),
              SizedBox(width: 10.w),
              Text(
                premium
                    ? 'sub_status_premium'.tr()
                    : (state.hasLapsed
                          ? 'sub_status_lapsed'.tr()
                          : 'sub_status_free'.tr()),
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Text(
            premium || state.hasLapsed
                ? _dateLine(entitlement, premium)
                : 'sub_free_body'.tr(
                    namedArgs: <String, String>{
                      'meals': '${PlanLimits.free.savedMeals}',
                      'days': '${PlanLimits.free.historyDays}',
                    },
                  ),
            style: GoogleFonts.inter(
              color: Colors.white60,
              fontSize: 11.sp,
              height: 1.5,
            ),
          ),
          if (entitlement.source != null) ...<Widget>[
            SizedBox(height: 6.h),
            Text(
              _sourceLine(entitlement.source!),
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 10.sp),
            ),
          ],
        ],
      ),
    );
  }

  /// What the date means depends on which side of it we are on.
  ///
  /// The app cannot tell a subscription that will renew from one that was
  /// cancelled and is running out — the store knows, and until server
  /// notifications are wired up it does not tell us. So the wording hedges
  /// honestly ("renews, unless you cancel") rather than asserting something
  /// that might already be false.
  String _dateLine(Entitlement entitlement, bool premium) {
    final DateTime? expiry = entitlement.expiresAt;
    if (expiry == null) return 'sub_no_end'.tr();

    final String date = DateFormat.yMMMMd().format(expiry);

    if (!premium) {
      return 'sub_ended'.tr(namedArgs: <String, String>{'date': date});
    }

    return (entitlement.source == 'promo' || entitlement.source == 'manual'
            ? 'sub_ends'
            : 'sub_renews')
        .tr(namedArgs: <String, String>{'date': date});
  }

  String _sourceLine(String source) => switch (source) {
    'app_store' => 'sub_source_app_store'.tr(),
    'play' => 'sub_source_play'.tr(),
    'promo' => 'sub_source_promo'.tr(),
    'manual' => 'sub_source_manual'.tr(),
    _ => '',
  };
}
