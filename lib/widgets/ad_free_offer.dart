import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/config/ads_config.dart';
import '../core/plan_limit_error.dart';
import '../cubit/entitlement/entitlement_cubit.dart';
import '../data/ads_service.dart';
import '../styles/app_color.dart';
import 'animations/press_scale.dart';
import 'bulkr_snack_bar.dart';
import 'premium_sheet.dart';

/// Turning the ads off for a day, offered where the ads are.
///
/// ## Why it belongs on the feed, pinned
///
/// It lived only in the account sheet, three taps behind an avatar, which is
/// the one place somebody annoyed by an ad is not looking. The feed is where
/// the banners are; it is also the only screen in the app where an offer to
/// remove them is obviously an offer rather than an interruption.
///
/// It then spent a version riding above the first post, where it scrolled away
/// after one flick — and the first banner ad is five posts down, so the offer
/// to remove ads was never on screen at the same time as an ad. Pinned to the
/// header it is there when the ad is.
///
/// Which is also why it is a single line. A row that scrolls past can afford
/// two; a row that is always there pays for its height on every screen of
/// every session, so it says one thing and gets out of the way.
///
/// ## Two offers, one row
///
/// The row's action is normally the trade: thirty seconds of video for
/// twenty-four hours without ads. Both platforms have a rewarded-interstitial
/// unit configured (`docs/ADMOB.md`), so that is what nearly every build
/// shows.
///
/// `AdsConfig.hasRewarded` is false on desktop, and would be again if the ids
/// were ever blanked — and there the row is still drawn and is the premium
/// pitch instead. A free account is told what removes the ads either way,
/// which is the whole point of putting it here. Note this is about whether a
/// unit *exists*, not whether an ad *fills*: a unit that cannot fill is
/// handled at the tap, by `AdFreeOffer.watch`, which says so rather than
/// taking thirty seconds and delivering nothing.
///
/// It draws nothing at all for a premium account. There is nothing to sell
/// somebody who already has it, and a row offering to remove ads they are not
/// being shown reads as the app not knowing who it is talking to.
class AdFreeOffer extends StatelessWidget {
  const AdFreeOffer({super.key, this.padding});

  /// Overrides the default gutter. For a caller placing it somewhere with its
  /// own padding already.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final bool premium = context.watch<EntitlementCubit>().state.isPremium;
    if (premium || !AdsConfig.isSupported) return const SizedBox.shrink();

    final AdsService ads = context.read<AdsService>();

    // Rebuilt from the service rather than from a timer: the only things that
    // change this row are a reward landing and the window running out, and the
    // service notifies on the first. The second is a minute or two late, which
    // costs nothing — the banner underneath has already come back, which is
    // the part anybody notices.
    return ListenableBuilder(
      listenable: ads,
      builder: (BuildContext context, Widget? _) {
        final Duration? left = ads.adFreeRemaining;
        final bool active = left != null && left.inSeconds > 0;

        return Padding(
          padding: padding ?? EdgeInsets.fromLTRB(20.w, 0, 20.w, 12.h),
          child: PressScale(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // The row itself always goes to the offer sheet, including while
              // a window is running: "how do I stop doing this every day" is
              // the obvious next question, and the answer is the subscription.
              onTap: () => PremiumSheet.show(
                context,
                limit: PlanLimit.ads,
                source: 'feed_ad_free',
              ),
              child: Container(
                height: 38.h,
                padding: EdgeInsets.symmetric(horizontal: 12.w),
                decoration: BoxDecoration(
                  color: const Color(0xFF16190A),
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(
                    color: AppColors.primaryNeon.withValues(alpha: 0.22),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      active
                          ? Icons.do_not_disturb_on_outlined
                          : Icons.block_flipped,
                      color: AppColors.primaryNeon,
                      size: 15.sp,
                    ),
                    SizedBox(width: 9.w),
                    Expanded(
                      child: Text(
                        active
                            ? 'ads_offer_active'.tr(
                                namedArgs: <String, String>{
                                  'hours': '${_hoursLeft(left)}',
                                },
                              )
                            : 'ads_offer_title'.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    _Action(active: active),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Rounded up, and never to zero: a window with eleven minutes left is still
  /// a window, and "0 hours" reads as it having already gone.
  static int _hoursLeft(Duration left) => (left.inMinutes / 60).ceil();

  /// Watch a video, lose the ads for a day.
  ///
  /// The reward is granted only when AdMob says the video was actually
  /// finished, and it is granted *before* anything else can fail — an app that
  /// takes thirty seconds of somebody's attention and then does not deliver
  /// has taught them never to accept an offer again, which is worth more than
  /// the ad earned.
  ///
  /// Nothing is said when they close it early. That was a choice, not an
  /// error, and a message about it would read as a telling-off.
  ///
  /// Takes the messenger rather than a context because the caller is about to
  /// wait half a minute on a full-screen ad, and the widget that started it
  /// may well be gone by the time this has an answer.
  static Future<void> watch(
    AdsService ads,
    ScaffoldMessengerState messenger, {
    String placement = 'remove_ads_24h',
  }) async {
    final bool earned = await ads.showRewarded(placement: placement);

    if (!earned) {
      // Only when nothing could be shown at all. `showRewarded` cannot tell
      // "closed it early" from "never loaded", so this errs towards the
      // explanation that is actionable.
      BulkrSnackBar.showOn(
        messenger,
        'ads_reward_unavailable'.tr(),
        tone: SnackTone.danger,
      );
      return;
    }

    await ads.grantAdFree();

    BulkrSnackBar.showOn(
      messenger,
      'ads_removed_notice'.tr(),
      tone: SnackTone.success,
    );
  }
}

/// The trailing button: watch, or go premium.
class _Action extends StatelessWidget {
  const _Action({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    // While a window is running there is nothing to watch for — a second video
    // buys nothing, because the grant extends from now rather than from the
    // existing expiry. See `AdPolicy.grantAdFree`.
    final bool canWatch = AdsConfig.hasRewarded && !active;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: canWatch
          ? () => AdFreeOffer.watch(
              context.read<AdsService>(),
              ScaffoldMessenger.of(context),
              placement: 'feed_remove_ads_24h',
            )
          : () => PremiumSheet.show(
              context,
              limit: PlanLimit.ads,
              source: 'feed_ad_free',
            ),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: AppColors.primaryNeon.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(8.r),
        ),
        child: Text(
          (canWatch ? 'ads_offer_watch' : 'limit_upgrade').tr().toUpperCase(),
          style: GoogleFonts.inter(
            color: AppColors.primaryNeon,
            fontSize: 9.sp,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}
