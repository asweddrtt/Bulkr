import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Which AdMob identifiers this build uses.
///
/// Two rules, and both exist because getting either wrong is expensive:
///
/// **Every lookup is exhaustive.** AdMob is per-platform — one AdMob "app" per
/// store listing, with its own app ID and its own ad units — and the Android
/// IDs do not work on iOS or the reverse. A ternary with a fallback would
/// quietly serve nothing, or worse: the wrong `GADApplicationIdentifier`
/// *crashes the app on launch*, before Dart runs, which is the same symptom as
/// the `GoogleService-Info.plist` bug that shipped build 4 as a white screen.
/// So an unsupported platform throws where it is written rather than on a
/// tester's phone.
///
/// **Release builds get the real units, everything else gets Google's test
/// units.** Google bans accounts that click their own live ads, and during
/// development somebody always does. Switching on [kReleaseMode] rather than
/// by editing the strings back and forth: the manual version is forgotten
/// exactly once, and the cost is the account.
///
/// None of these strings is a secret. They are designed to ship inside the
/// client binary, the same way `SupabaseConfig.publishableKey` is — what
/// protects the account is the AdMob console, not the obscurity of an ID.
///
/// See `docs/ADMOB.md` for where they came from and the native-side setup that
/// has to match.
class AdsConfig {
  const AdsConfig._();

  /// Whether this platform has an AdMob app at all.
  ///
  /// False on desktop, which is where this project is developed. Everything
  /// ad-shaped checks this first, so a development build is simply an app with
  /// no ads rather than an app that throws on its first frame.
  static bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  // --- Real units --------------------------------------------------------

  static const String _androidBanner = 'ca-app-pub-6396760454728825/5069745808';
  static const String _androidInterstitial =
      'ca-app-pub-6396760454728825/1130500796';

  static const String _iosBanner = 'ca-app-pub-6396760454728825/2985286754';
  static const String _iosInterstitial =
      'ca-app-pub-6396760454728825/6249386527';

  /// Rewarded units do not exist yet — they have to be created in the AdMob
  /// console, one per platform, before anything can serve.
  ///
  /// Empty rather than absent so the app compiles and every rewarded offer
  /// hides itself ([hasRewarded]) instead of requesting an ad against an ID
  /// that is not there. A `--dart-define` is accepted so a staging build can
  /// point somewhere else without a code change; the default is what ships,
  /// deliberately, because Shorebird compares dart-defines between a release
  /// and its patches and a flag present on one build and missing on another
  /// reads as a diff and the patch is refused.
  static const String _androidRewarded = String.fromEnvironment(
    'REWARDED_AD_UNIT_ANDROID',
  );
  static const String _iosRewarded = String.fromEnvironment(
    'REWARDED_AD_UNIT_IOS',
  );

  // --- Google's public test units ----------------------------------------
  //
  // The same on both platforms, from
  // https://developers.google.com/admob/android/test-ads — safe to click, and
  // the only units any non-release build ever requests.

  static const String testBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const String testInterstitial =
      'ca-app-pub-3940256099942544/1033173712';
  static const String testRewarded = 'ca-app-pub-3940256099942544/5224354917';

  static String get bannerUnit =>
      kReleaseMode ? _perPlatform(_androidBanner, _iosBanner) : testBanner;

  static String get interstitialUnit => kReleaseMode
      ? _perPlatform(_androidInterstitial, _iosInterstitial)
      : testInterstitial;

  /// The rewarded unit, or null when this build has none.
  ///
  /// Null is a real answer rather than an error: the units are not created
  /// yet, and a rewarded *offer* — "watch an ad to restore your streak" — that
  /// cannot be filled must not be on screen at all. Offering something and
  /// then failing to deliver it is worse than never offering it.
  static String? get rewardedUnit {
    if (!isSupported) return null;
    if (!kReleaseMode) return testRewarded;

    final String unit = _perPlatform(_androidRewarded, _iosRewarded);
    return unit.isEmpty ? null : unit;
  }

  static bool get hasRewarded => rewardedUnit != null;

  /// Exhaustive on purpose. See the note at the top of this class.
  static String _perPlatform(String android, String ios) {
    if (Platform.isAndroid) return android;
    if (Platform.isIOS) return ios;

    throw UnsupportedError(
      'No AdMob unit for ${Platform.operatingSystem}. Check AdsConfig.isSupported '
      'before asking for one — desktop builds have no AdMob app.',
    );
  }
}
