# AdMob — recorded, not yet integrated

The account exists and the IDs are issued. **No ad code ships today**: there is
no `google_mobile_ads` dependency, nothing reads the IDs below, and no ad is
requested or rendered anywhere in the app.

This file is the record, so the IDs are not sitting in a chat log, and so the
next person to pick this up has the whole checklist rather than half of it.

## The IDs

### Android

| What | Value |
|------|-------|
| App ID | `ca-app-pub-6396760454728825~3257970685` |
| Ad unit — feed banner | `ca-app-pub-6396760454728825/5069745808` |
| Ad unit — interstitial | `ca-app-pub-6396760454728825/1130500796` |

The separator tells them apart: an app ID uses `~`, an ad unit uses `/`.

None of them is a secret. All are designed to ship inside the client binary,
the same way `SupabaseConfig.publishableKey` is — what protects the account is
the AdMob console, not the obscurity of these strings.

### iOS

| What | Value |
|------|-------|
| App ID | `ca-app-pub-6396760454728825~3261840114` |
| Ad unit — feed banner | `ca-app-pub-6396760454728825/2985286754` |
| Ad unit — interstitial | `ca-app-pub-6396760454728825/6249386527` |

### The two sets are not interchangeable

AdMob is per-platform: one AdMob "app" per store listing, each with its own app
ID and its own ad units. The Android IDs do not work on iOS and the iOS IDs do
not work on Android — so every one of them has to be looked up by platform,
never shared, and never defaulted.

Worth being careful about rather than assuming it degrades gracefully. Putting
the wrong app ID in `GADApplicationIdentifier` does not serve no ads — **it
crashes the app on launch**, before Dart runs, which is the same symptom as the
`GoogleService-Info.plist` bug that shipped build 4 as a white screen. Since iOS
is the platform this project actually releases to (see `codemagic.yaml` — both
workflows are iOS), that is the failure most likely to happen here.

So when this is built, the lookup should be exhaustive rather than a ternary
with a fallback:

```dart
// Sketch only — nothing like this exists yet.
static String get bannerUnit {
  if (Platform.isAndroid) return 'ca-app-pub-6396760454728825/5069745808';
  if (Platform.isIOS) return 'ca-app-pub-6396760454728825/2985286754';
  // Desktop builds exist for development and have no AdMob app at all.
  throw UnsupportedError('no ad unit for this platform');
}
```

A `throw` rather than a placeholder string: an unsupported platform should fail
where it is written, not on a tester's phone.

## Intended placement

**A banner in the feed**, and **an interstitial**.

The banner is the settled one. The interstitial still needs a decision about
*when* it fires, and it is the decision that matters most here, because an
interstitial is the format most able to make somebody delete a daily-use app.
Some placements to rule out before picking one:

- **Never on launch.** An ad before the first screen is a guideline 4.2 problem
  and the single most-reported reason for abandoning an app.
- **Never during logging.** The tracker exists to make logging a meal take five
  seconds. An interstitial in that path defeats the feature the app is for.
- **Never between a tap and the thing that was tapped** — opening a post,
  opening a thread. The user asked for something specific; showing an ad
  instead reads as a bug.

The defensible spots are the natural seams, where the user has *finished*
something rather than asked for something: after a meal is saved, after a
weigh-in is logged, or on returning to the app after a long absence. Google's
own frequency-capping (`AdMob console → ad unit → frequency cap`) should be set
regardless — an uncapped interstitial will fire far more often than intended.

## What integrating it actually involves

Listed because four of these are easy to miss and two of them are rejections
rather than bugs.

1. **The plugin.** `google_mobile_ads`. This is native code on both platforms,
   which has a consequence specific to this project: it cannot travel in a
   Shorebird patch. Adding it needs a full `ios-testflight` release, and the
   release it produces becomes the one later patches attach to — see
   `codemagic.yaml`.

2. **The right app ID in each native manifest.** The SDK reads it at startup
   and *crashes the app on launch* if it is missing or belongs to another
   platform — it is not a soft failure.
   - `android/app/src/main/AndroidManifest.xml`: a `<meta-data>` named
     `com.google.android.gms.ads.APPLICATION_ID`, holding the Android app ID
     above.
   - `ios/Runner/Info.plist`: a `GADApplicationIdentifier` key, holding the
     **iOS** app ID. Not the Android one — see above for why that is a crash
     rather than a misconfiguration.

3. **App Tracking Transparency, on iOS.** Serving personalised ads needs the
   IDFA, and the IDFA needs the ATT prompt. That means `NSUserTrackingUsageDescription`
   in `Info.plist` and a call to request authorisation. Shipping ads without it
   is an App Store rejection under guideline 5.1.2.

4. **A consent flow.** Google's UMP SDK, for GDPR/ePrivacy in the EU and the
   equivalent in other regions. AdMob will serve non-personalised ads without
   consent, but the *asking* is not optional where it applies.

5. **`PrivacyInfo.xcprivacy` changes.** The manifest added in this batch
   declares that Bulkr does **not** track and lists no tracking domains, which
   is true today. Ads make it false. At minimum it gains:
   - `NSPrivacyTracking` set to `true`
   - `NSPrivacyTrackingDomains` listing Google's ad domains
   - `Device ID` under collected data types, with `NSPrivacyCollectedDataTypeTracking` true

   The App Store privacy labels in App Store Connect have to change to match,
   and so does whatever the "Policy" link on the welcome screen points at.

6. **Layout.** `BulkrNavBar.contentInset` is what keeps the feed's last post
   clear of the nav bar. A banner anchored above the bar adds to that height,
   and `test/nav_bar_clearance_test.dart` is the test that will catch it if the
   inset is not updated.

7. **Test IDs during development.** Google bans accounts that click their own
   live ads, and during development somebody always does. Use Google's public
   test units for every build that is not a store build:
   - banner: `ca-app-pub-3940256099942544/6300978111`
   - interstitial: `ca-app-pub-3940256099942544/1033173712`

   Switch on `kReleaseMode` rather than by editing the string back and forth —
   the manual version is forgotten exactly once, and the cost is the account.

## Why it is worth thinking about first

Bulkr's feed is the screen people scroll daily, and a banner there is the
placement most likely to be seen — and the one most likely to be the reason
somebody stops opening the app. Worth deciding deliberately whether it appears
for everyone, or only for accounts past some threshold.
