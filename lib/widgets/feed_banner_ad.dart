import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/analytics_events.dart';
import '../core/config/ads_config.dart';
import '../core/telemetry.dart';
import '../cubit/entitlement/entitlement_cubit.dart';
import '../data/ads_service.dart';

/// A banner between two posts.
///
/// ## Why inline rather than anchored
///
/// The obvious place for a banner is pinned above the navigation bar, where it
/// is always on screen and therefore always earning. It is also, for the same
/// reason, fifty pixels of the phone that the user never gets back — on the
/// one screen they open every day, in an app whose whole pitch is that
/// checking in takes five seconds.
///
/// Inline costs impressions and keeps the screen. Scrolling past an ad is a
/// thing people do without resentment; being permanently one banner shorter is
/// not. If the revenue turns out to matter more than this argument, the change
/// is anchoring this widget and adding its height to
/// `BulkrNavBar.contentInset` — which `nav_bar_clearance_test.dart` is already
/// watching.
///
/// ## Why it is kept alive
///
/// A `ListView` disposes what scrolls off. Without [wantKeepAlive] this widget
/// would request a fresh ad every time it came back into view — which is
/// wasted requests, an impression count that says something untrue about how
/// many ads were seen, and the sort of pattern AdMob suspends accounts over.
/// Loaded once per slot, per feed.
class FeedBannerAd extends StatefulWidget {
  const FeedBannerAd({super.key});

  /// One banner per this many posts.
  ///
  /// Five is roughly a screen and a half of scrolling on a phone, so two ads
  /// are never in view at once and the feed still reads as a feed. It is also
  /// the number to change first if the ads feel heavy — which is why it is a
  /// constant with a name rather than a literal in the list builder.
  static const int everyNPosts = 5;

  /// Whether a banner belongs after the post at [index].
  ///
  /// Zero-based, so this puts the first one after the fifth post — far enough
  /// in that somebody opening the app to check one thing never reaches it.
  static bool followsPost(int index) => (index + 1) % everyNPosts == 0;

  @override
  State<FeedBannerAd> createState() => _FeedBannerAdState();
}

class _FeedBannerAdState extends State<FeedBannerAd>
    with AutomaticKeepAliveClientMixin {
  BannerAd? _ad;
  bool _loaded = false;
  bool _requested = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  void _request() {
    if (_requested || !AdsConfig.isSupported) return;
    _requested = true;

    final BannerAd ad = BannerAd(
      size: AdSize.banner,
      adUnitId: AdsConfig.bannerUnit,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _loaded = true);
          Telemetry.send(
            AnalyticsEvent.adShown(format: 'banner', placement: 'feed'),
          );
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          ad.dispose();
          debugPrint('Bulkr: banner did not load — ${error.message}');
          Telemetry.send(
            AnalyticsEvent.adFailed(format: 'banner', code: error.code),
          );
          // Deliberately not retried. A feed that keeps asking for an ad it
          // cannot get spends battery and data to show nothing; the next slot
          // down the list will ask again anyway.
          if (mounted) setState(() => _ad = null);
        },
      ),
    );

    _ad = ad;
    ad.load();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final AdsService ads = context.read<AdsService>();

    return ListenableBuilder(
      listenable: ads,
      builder: (BuildContext context, Widget? _) {
        final bool premium = context.watch<EntitlementCubit>().state.isPremium;

        // Two ways to have no ads, and both are checked on every rebuild so
        // that buying either one takes effect immediately rather than at the
        // next scroll.
        if (premium || ads.state.isAdFree || !AdsConfig.isSupported) {
          return const SizedBox.shrink();
        }

        _request();

        // Nothing until it has actually loaded. A reserved 50px box that may
        // never fill is a hole in the feed, and a feed that shifts under the
        // reader's thumb when it does fill is worse than either.
        final BannerAd? ad = _ad;
        if (ad == null || !_loaded) return const SizedBox.shrink();

        return Padding(
          padding: EdgeInsets.only(bottom: 16.h),
          child: Center(
            child: SizedBox(
              width: ad.size.width.toDouble(),
              height: ad.size.height.toDouble(),
              child: AdWidget(ad: ad),
            ),
          ),
        );
      },
    );
  }
}
