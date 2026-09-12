import 'dart:io' show Platform;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/config/premium_products.dart';
import '../core/plan_limits.dart';
import '../core/trial_offer.dart';
import '../cubit/entitlement/entitlement_cubit.dart';
import '../cubit/purchase/purchase_cubit.dart';
import '../data/purchase_service.dart';
import '../models/premium_plan.dart';
import '../styles/app_color.dart';
import '../widgets/animations/press_scale.dart';

/// Where somebody buys premium.
///
/// ## What this screen is careful about
///
/// **Every price comes from the store.** Nothing here writes "$39.99".
/// `ProductDetails.price` is already formatted in the user's own currency, and
/// a hardcoded price is wrong in every country but one, wrong again after any
/// change, and wrong in the way that gets noticed at the moment somebody is
/// charged.
///
/// **The trial is only promised when the store is offering it.** Somebody who
/// has already used it is not offered it again, and that is the store's answer
/// rather than ours — see [TrialOffer].
///
/// **The terms are on the screen, not behind a link.** Length, price, that it
/// renews, and where to cancel. Both stores require it, and it is also the
/// sentence that stops the refund request.
class UpgradeScreen extends StatelessWidget {
  const UpgradeScreen({super.key, this.source = 'unknown'});

  /// What led here — `limit`, `settings`, `ad`. Recorded with
  /// `paywall_shown`, which is the top of the only funnel that matters.
  final String source;

  static Future<void> open(BuildContext context, {String source = 'unknown'}) {
    final PurchaseService purchases = context.read<PurchaseService>();
    final EntitlementCubit entitlement = context.read<EntitlementCubit>();

    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => MultiBlocProvider(
          providers: <BlocProvider<StateStreamableSource<Object?>>>[
            BlocProvider<PurchaseCubit>(
              create: (_) => PurchaseCubit(service: purchases)..load(),
            ),
          ],
          child: BlocProvider<EntitlementCubit>.value(
            value: entitlement,
            child: UpgradeScreen(source: source),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<PurchaseCubit, PurchaseState>(
      listenWhen: (PurchaseState previous, PurchaseState current) =>
          previous.succeeded != current.succeeded && current.succeeded,
      listener: (BuildContext context, PurchaseState state) async {
        // The server has already written the row; this is the app catching up
        // with it. Awaited before closing so the screen behind is premium the
        // moment it is visible rather than a frame later.
        await context.read<EntitlementCubit>().refresh();
        if (!context.mounted) return;

        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(_notice('premium_welcome'.tr()));

        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: BlocBuilder<PurchaseCubit, PurchaseState>(
            builder: (BuildContext context, PurchaseState state) {
              return Column(
                children: <Widget>[
                  _Header(),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 20.h),
                      children: <Widget>[
                        _Pitch(),
                        SizedBox(height: 22.h),
                        const _Benefits(),
                        SizedBox(height: 24.h),
                        if (state.status == PaywallStatus.unavailable)
                          const _Unavailable()
                        else
                          const _Plans(),
                      ],
                    ),
                  ),
                  if (state.status != PaywallStatus.unavailable)
                    const _Footer(),
                ],
              );
            },
          ),
        ),
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

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(8.w, 4.h, 12.w, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Semantics(
            button: true,
            label: 'a11y_close'.tr(),
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white70),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          TextButton(
            onPressed: () => context.read<PurchaseCubit>().restore(),
            child: Text(
              'premium_restore'.tr(),
              style: GoogleFonts.inter(
                color: Colors.white54,
                fontSize: 11.sp,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pitch extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'premium_title'.tr(),
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 26.sp,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          'premium_subtitle'.tr(),
          style: GoogleFonts.inter(
            color: Colors.white60,
            fontSize: 13.sp,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

/// What the money buys, in the order somebody runs into it.
///
/// The last row is the important one and is deliberately not a benefit of
/// paying: logging is free and stays free. A paywall that implies otherwise
/// loses the person who was going to subscribe in month three.
class _Benefits extends StatelessWidget {
  const _Benefits();

  @override
  Widget build(BuildContext context) {
    final PlanLimits free = PlanLimits.free;

    return Column(
      children: <Widget>[
        _BenefitRow(
          icon: Icons.restaurant_menu,
          title: 'premium_benefit_meals'.tr(),
          subtitle: 'premium_benefit_meals_sub'.tr(
            namedArgs: <String, String>{'count': '${free.savedMeals}'},
          ),
        ),
        _BenefitRow(
          icon: Icons.history,
          title: 'premium_benefit_history'.tr(),
          subtitle: 'premium_benefit_history_sub'.tr(
            namedArgs: <String, String>{'days': '${free.historyDays}'},
          ),
        ),
        _BenefitRow(
          icon: Icons.emoji_events_outlined,
          title: 'premium_benefit_challenges'.tr(),
          subtitle: 'premium_benefit_challenges_sub'.tr(),
        ),
        _BenefitRow(
          icon: Icons.block_flipped,
          title: 'premium_benefit_ads'.tr(),
          subtitle: 'premium_benefit_ads_sub'.tr(),
        ),
        _BenefitRow(
          icon: Icons.check_circle_outline,
          title: 'premium_benefit_logging'.tr(),
          subtitle: 'premium_benefit_logging_sub'.tr(),
        ),
      ],
    );
  }
}

class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 14.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: AppColors.primaryNeon, size: 18.sp),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  subtitle,
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

class _Plans extends StatelessWidget {
  const _Plans();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PurchaseCubit, PurchaseState>(
      builder: (BuildContext context, PurchaseState state) {
        if (state.status == PaywallStatus.loading ||
            state.status == PaywallStatus.initial) {
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 24.h),
            child: const Center(
              child: CircularProgressIndicator(
                color: AppColors.primaryNeon,
                strokeWidth: 2,
              ),
            ),
          );
        }

        return Column(
          children: <Widget>[
            for (final PremiumPlan plan in state.plans)
              _PlanCard(
                plan: plan,
                selected: plan.id == state.selectedId,
                onTap: () => context.read<PurchaseCubit>().select(plan.id),
              ),
          ],
        );
      },
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final PremiumPlan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool yearly = PremiumProducts.isYearly(plan.id);

    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: GestureDetector(
        onTap: onTap,
        child: PressScale(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
            decoration: BoxDecoration(
              color: const Color(0xFF141414),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(
                color: selected ? AppColors.primaryNeon : AppColors.darkBorder,
                width: selected ? 1.6 : 1,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? AppColors.primaryNeon : Colors.white24,
                  size: 18.sp,
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            yearly
                                ? 'premium_plan_yearly'.tr()
                                : 'premium_plan_monthly'.tr(),
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (yearly) ...<Widget>[
                            SizedBox(width: 8.w),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 6.w,
                                vertical: 2.h,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryNeon.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(4.r),
                              ),
                              child: Text(
                                'premium_best_value'.tr().toUpperCase(),
                                style: GoogleFonts.inter(
                                  color: AppColors.primaryNeon,
                                  fontSize: 8.sp,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        // The store's own formatting, in the user's own
                        // currency. Never anything written down in this app.
                        (yearly ? 'premium_per_year' : 'premium_per_month').tr(
                          namedArgs: <String, String>{'price': plan.priceLabel},
                        ),
                        style: GoogleFonts.inter(
                          color: Colors.white54,
                          fontSize: 11.sp,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'premium_unavailable'.tr(),
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            'premium_unavailable_body'.tr(),
            style: GoogleFonts.inter(color: Colors.white54, fontSize: 11.sp),
          ),
        ],
      ),
    );
  }
}

/// The button, and the sentence the stores require next to it.
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PurchaseCubit, PurchaseState>(
      listenWhen: (PurchaseState previous, PurchaseState current) =>
          current.failure != null && previous.failure != current.failure,
      listener: (BuildContext context, PurchaseState state) {
        final PurchaseFailure failure = state.failure!;
        context.read<PurchaseCubit>().clearFailure();

        // Backing out is a choice, not an error. A message about it reads as a
        // telling-off for not spending money.
        if (failure == PurchaseFailure.cancelled) return;

        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            UpgradeScreen._notice(switch (failure) {
              PurchaseFailure.storeRefused => 'premium_failed_refused'.tr(),
              PurchaseFailure.notVerified => 'premium_failed_unverified'.tr(),
              PurchaseFailure.alreadyClaimed => 'premium_failed_claimed'.tr(),
              PurchaseFailure.nothingToRestore =>
                'premium_nothing_restored'.tr(),
              PurchaseFailure.cancelled => '',
            }),
          );
      },
      builder: (BuildContext context, PurchaseState state) {
        final TrialOffer? trial = state.trial;
        final PremiumPlan? plan = state.selected;

        return Container(
          padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 16.h),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.darkBorder)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (state.pending) ...<Widget>[
                Text(
                  'premium_pending'.tr(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: Colors.white70,
                    fontSize: 11.sp,
                  ),
                ),
                SizedBox(height: 10.h),
              ],
              SizedBox(
                width: double.infinity,
                height: 48.h,
                child: ElevatedButton(
                  onPressed: state.canBuy
                      ? () => context.read<PurchaseCubit>().buy()
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryNeon,
                    disabledBackgroundColor: const Color(0xFF2A2A2A),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                  child: state.busy
                      ? SizedBox(
                          width: 18.w,
                          height: 18.w,
                          child: const CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          trial == null
                              ? 'premium_cta'.tr()
                              : 'premium_cta_trial'.tr(
                                  namedArgs: <String, String>{
                                    'days': '${trial.days}',
                                  },
                                ),
                          style: GoogleFonts.inter(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                          ),
                        ),
                ),
              ),
              SizedBox(height: 10.h),
              Text(
                _terms(state, trial, plan),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: 9.sp,
                  height: 1.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Length, price, that it renews, and where to cancel.
  ///
  /// Both stores require these next to the button rather than behind a link,
  /// and it is also the sentence that prevents most refund requests — a charge
  /// nobody was expecting is the one that gets disputed.
  String _terms(PurchaseState state, TrialOffer? trial, PremiumPlan? plan) {
    if (plan == null) return '';

    final String store = Platform.isIOS
        ? 'premium_store_apple'.tr()
        : 'premium_store_google'.tr();

    // The recurring price, not the trial's. What the terms have to quote is
    // what will be charged on day eight.
    final String price = PremiumProducts.isYearly(plan.id)
        ? 'premium_per_year'.tr(
            namedArgs: <String, String>{'price': plan.priceLabel},
          )
        : 'premium_per_month'.tr(
            namedArgs: <String, String>{'price': plan.priceLabel},
          );

    if (trial == null) {
      return 'premium_terms'.tr(
        namedArgs: <String, String>{'price': price, 'store': store},
      );
    }

    return 'premium_terms_trial'.tr(
      namedArgs: <String, String>{
        'days': '${trial.days}',
        'price': price,
        'store': store,
      },
    );
  }
}
