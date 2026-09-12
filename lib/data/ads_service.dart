import 'dart:async';
import 'dart:convert';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/ad_policy.dart';
import '../core/analytics_events.dart';
import '../core/config/ads_config.dart';
import '../core/telemetry.dart';
import 'app_preferences.dart';

/// The ad SDK, the consent it needs, and the rules about when it may
/// interrupt.
///
/// One object for the whole app. Everything here is best-effort: an ad that
/// fails to load, a consent form that will not open, an SDK that never
/// initialises — none of it is allowed to break a screen or throw into a
/// widget. The app without ads is the app; the app that crashes because an ad
/// did not load is not.
///
/// The decision about *whether* to interrupt lives in [AdPolicy], which is
/// pure and tested. This class only carries out what that decides, and
/// remembers the result.
class AdsService extends ChangeNotifier {
  AdsService({AppPreferences? preferences})
    : _preferences = preferences ?? AppPreferences();

  final AppPreferences _preferences;

  AdState _state = AdState.fresh;

  /// What the policy is reading. Loaded from the device on [start].
  AdState get state => _state;

  bool _started = false;
  bool _ready = false;

  /// Whether the SDK came up and ads may be requested.
  bool get isReady => _ready;

  InterstitialAd? _interstitial;
  bool _loadingInterstitial = false;

  /// Consent, tracking permission, and the SDK — in that order, which is the
  /// order Google requires.
  ///
  /// Safe to call more than once and safe to call on a platform with no AdMob
  /// app; both return immediately.
  ///
  /// Nothing awaits this before drawing a screen. It is started at launch and
  /// left to finish, because the first banner appearing a second late is
  /// invisible and a launch that waits on a network round trip to Google is
  /// not.
  Future<void> start() async {
    if (_started || !AdsConfig.isSupported) return;
    _started = true;

    await _restoreState();

    // Consent first. On iOS the UMP form is also where Google's own ATT
    // explainer is configured, so asking for tracking before it means the
    // system prompt arrives with no context — which is how you get a denial
    // that iOS will not let you ask about again.
    await _collectConsent();
    await _requestTracking();

    try {
      await MobileAds.instance.initialize();
      _ready = true;
    } catch (error, stackTrace) {
      debugPrint('Bulkr: the ad SDK did not start — $error');
      await Telemetry.recordError(
        error,
        stackTrace,
        reason: 'MobileAds.initialize',
      );
      return;
    }

    unawaited(preloadInterstitial());
  }

  // --- Consent -----------------------------------------------------------

  Future<void> _collectConsent() async {
    final Completer<void> updated = Completer<void>();

    try {
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () {
          if (!updated.isCompleted) updated.complete();
        },
        (FormError error) {
          // Not fatal. Without consent Google serves non-personalised ads,
          // which is less money and not no app.
          debugPrint('Bulkr: consent info failed — ${error.message}');
          if (!updated.isCompleted) updated.complete();
        },
      );

      // Bounded, because the failure callback is not guaranteed to arrive on a
      // connection that is answering slowly rather than not at all, and this
      // sits in front of everything else.
      await updated.future.timeout(const Duration(seconds: 10));

      await ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
        if (error != null) {
          debugPrint('Bulkr: consent form — ${error.message}');
        }
      });

      final ConsentStatus status = await ConsentInformation.instance
          .getConsentStatus();
      await Telemetry.send(AnalyticsEvent.adConsent(status: status.name));
    } catch (error) {
      debugPrint('Bulkr: consent step skipped — $error');
    }
  }

  /// The iOS tracking prompt.
  ///
  /// Serving personalised ads needs the IDFA, and the IDFA needs this — and
  /// shipping ads without asking is an App Store rejection under guideline
  /// 5.1.2. On Android it returns immediately; the plugin answers
  /// `notSupported`.
  ///
  /// Asked once, ever. iOS will not show the prompt a second time, so a denial
  /// here is permanent and the only thing that changes it is the user going to
  /// Settings.
  Future<void> _requestTracking() async {
    try {
      final TrackingStatus current =
          await AppTrackingTransparency.trackingAuthorizationStatus;

      final TrackingStatus status = current == TrackingStatus.notDetermined
          ? await AppTrackingTransparency.requestTrackingAuthorization()
          : current;

      await Telemetry.send(
        AnalyticsEvent.trackingPermission(status: status.name),
      );
    } catch (error) {
      debugPrint('Bulkr: tracking prompt skipped — $error');
    }
  }

  // --- Interstitials ------------------------------------------------------

  /// Fetches one and holds it, so that when the moment comes there is nothing
  /// to wait for.
  ///
  /// This is the difference between an ad at a seam and an ad two seconds
  /// after the seam, by which time the user has started the next thing and the
  /// ad is an interruption rather than a pause.
  Future<void> preloadInterstitial() async {
    if (!_ready || _loadingInterstitial || _interstitial != null) return;
    _loadingInterstitial = true;

    try {
      await InterstitialAd.load(
        adUnitId: AdsConfig.interstitialUnit,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (InterstitialAd ad) {
            _loadingInterstitial = false;
            _interstitial = ad;
          },
          onAdFailedToLoad: (LoadAdError error) {
            _loadingInterstitial = false;
            _interstitial = null;
            debugPrint('Bulkr: interstitial did not load — ${error.message}');
            unawaited(
              Telemetry.send(
                AnalyticsEvent.adFailed(
                  format: 'interstitial',
                  code: error.code,
                ),
              ),
            );
          },
        ),
      );
    } catch (error) {
      _loadingInterstitial = false;
      debugPrint('Bulkr: interstitial request failed — $error');
    }
  }

  /// Shows one if every rule in [AdPolicy] allows it. Returns whether it did.
  ///
  /// The caller does not check anything first and does not need to: a call
  /// site that has to remember the rules is a call site that will get them
  /// wrong, and there are several.
  Future<bool> maybeShowInterstitial({
    required AdTrigger trigger,
    required bool isPremium,
    Duration? awayFor,
    String placement = 'unknown',
  }) async {
    final AdBlock verdict = AdPolicy.evaluate(
      trigger: trigger,
      state: _state,
      isPremium: isPremium,
      awayFor: awayFor,
    );

    if (verdict != AdBlock.none) return false;
    if (!_ready) return false;

    final InterstitialAd? ad = _interstitial;
    if (ad == null) {
      // Nothing loaded. Fetch one for next time rather than making the user
      // wait for this one — an ad the user waits for is the worst version of
      // this.
      unawaited(preloadInterstitial());
      return false;
    }

    _interstitial = null;

    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (InterstitialAd ad) {
        ad.dispose();
        unawaited(preloadInterstitial());
      },
      onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
        ad.dispose();
        debugPrint('Bulkr: interstitial did not show — ${error.message}');
        unawaited(preloadInterstitial());
      },
    );

    try {
      await ad.show();
    } catch (error) {
      debugPrint('Bulkr: interstitial show failed — $error');
      return false;
    }

    // Recorded on shown, never on requested — see AdPolicy.recordShown.
    await _save(AdPolicy.recordShown(_state));
    await Telemetry.send(
      AnalyticsEvent.adShown(format: 'interstitial', placement: placement),
    );

    return true;
  }

  /// The user finished something. Counted whether or not an ad follows.
  Future<void> recordAction() => _save(AdPolicy.recordAction(_state));

  // --- Rewarded -----------------------------------------------------------

  /// Shows a rewarded ad and answers whether the user earned the reward.
  ///
  /// False for every failure — no unit configured, nothing loaded, the user
  /// closed it early. The caller must not pay out on false, and must pay out
  /// on true even if something goes wrong afterwards: an app that takes the
  /// thirty seconds and then does not deliver has taught the user never to
  /// accept an offer again, which costs more than the ad earned.
  Future<bool> showRewarded({required String placement}) async {
    final String? unit = AdsConfig.rewardedUnit;
    if (unit == null || !_ready) return false;

    final Completer<bool> earned = Completer<bool>();

    try {
      await RewardedAd.load(
        adUnitId: unit,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (RewardedAd ad) {
            ad.fullScreenContentCallback =
                FullScreenContentCallback<RewardedAd>(
                  onAdDismissedFullScreenContent: (RewardedAd ad) {
                    ad.dispose();
                    // Dismissed without the reward callback having fired means
                    // they closed it early. Not a failure — a choice.
                    if (!earned.isCompleted) earned.complete(false);
                  },
                  onAdFailedToShowFullScreenContent:
                      (RewardedAd ad, AdError e) {
                        ad.dispose();
                        if (!earned.isCompleted) earned.complete(false);
                      },
                );

            ad.show(
              onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
                if (!earned.isCompleted) earned.complete(true);
              },
            );
          },
          onAdFailedToLoad: (LoadAdError error) {
            debugPrint('Bulkr: rewarded did not load — ${error.message}');
            unawaited(
              Telemetry.send(
                AnalyticsEvent.adFailed(format: 'rewarded', code: error.code),
              ),
            );
            if (!earned.isCompleted) earned.complete(false);
          },
        ),
      );
    } catch (error) {
      debugPrint('Bulkr: rewarded request failed — $error');
      return false;
    }

    // A rewarded ad is 15-30 seconds, and the user is watching it. The bound
    // is here so a callback that never arrives does not leave a spinner up
    // forever.
    final bool result = await earned.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () => false,
    );

    if (result) {
      await Telemetry.send(AnalyticsEvent.rewardEarned(placement: placement));
    }

    return result;
  }

  /// Pays out the ad-free window a rewarded ad bought.
  Future<void> grantAdFree() async {
    await _save(AdPolicy.grantAdFree(_state));
    // Whatever was held is no longer allowed to show. Disposing it now rather
    // than at the next seam means the window starts immediately, which is what
    // the user was promised.
    _interstitial?.dispose();
    _interstitial = null;
  }

  /// How much of an earned ad-free window is left, or null when there is none.
  Duration? get adFreeRemaining => _state.adFreeRemaining();

  // --- State --------------------------------------------------------------

  Future<void> _restoreState() async {
    try {
      final String? raw = await _preferences.adState();
      if (raw != null) {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _state = AdState.fromJson(decoded);
        }
      }
    } catch (error) {
      debugPrint('Bulkr: ad state unreadable, starting fresh — $error');
      _state = AdState.fresh;
    }

    // Stamps the install's first run, which is what the new-user grace is
    // measured from. Done on restore so it exists before the first ad is ever
    // considered — a null there is treated as "too new", so a failure to write
    // it errs towards showing nothing.
    await _save(AdPolicy.seed(_state));
  }

  Future<void> _save(AdState next) async {
    _state = next;
    // Listened to by the banner, which has to disappear the moment a rewarded
    // ad buys an ad-free day. A banner that stayed up until the next scroll
    // would be the app visibly not honouring what it just promised.
    notifyListeners();
    try {
      await _preferences.setAdState(jsonEncode(next.toJson()));
    } catch (error) {
      debugPrint('Bulkr: could not save ad state — $error');
    }
  }

  @override
  void dispose() {
    _interstitial?.dispose();
    _interstitial = null;
    super.dispose();
  }
}
