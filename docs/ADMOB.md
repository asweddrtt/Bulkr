# AdMob

Integrated. `google_mobile_ads` is a dependency, both app IDs are in the native
manifests, a banner runs in the feed and interstitials fire at two seams.

**One thing is still missing: the rewarded ad units do not exist.** They have
to be created in the AdMob console — one per platform — and until they do,
`AdsConfig.rewardedUnit` is null and every rewarded offer hides itself rather
than failing in front of the user. See "What is left" at the bottom.

This file is the record of the IDs, so they are not sitting in a chat log, and
of the decisions behind where the ads go.

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

So the lookup in `lib/core/config/ads_config.dart` is exhaustive rather than a
ternary with a fallback: it names each platform and throws on anything else.
An unsupported platform — desktop, where this project is developed — fails
where it is written rather than on a tester's phone, and `AdsConfig.isSupported`
is what every caller checks first so that a development build is simply an app
with no ads.

## Where the ads are, and why

### The banner — inline in the feed, every 5 posts

`lib/widgets/feed_banner_ad.dart`. Not anchored above the navigation bar,
which is the obvious choice and earns more: an anchored banner is fifty pixels
of the phone the user never gets back, on the one screen they open daily, in
an app whose pitch is that checking in takes five seconds. Scrolling past an
ad is a thing people do without resentment; being permanently one banner
shorter is not.

If that trade turns out to be wrong, anchoring it is a small change — and
`BulkrNavBar.contentInset` plus `nav_bar_clearance_test.dart` are already
watching for the layout half of it.

Each slot keeps its ad alive (`AutomaticKeepAliveClientMixin`) so scrolling
back and forth does not request a new one. An impression count inflated by
list recycling is both a lie about how many ads were seen and the sort of
pattern AdMob suspends accounts over.

### The interstitial — two seams, six rules

`lib/core/ad_policy.dart`, which is pure and tested, and `lib/core/ad_moment.dart`,
which is the one line a screen calls.

It fires after a **completed action** — a meal saved, a post published — and on
**returning to the app after four hours or more away**. Both are seams: the
user finished something, or nothing was in progress at all. Never between a
tap and the thing that was tapped.

The rules that decide whether anything actually shows:

| Rule | Value | What it protects |
|---|---|---|
| new-user grace | 24 h from install | the value has to land before the ask does |
| cooldown | 4 min | no two close together, whatever happened between |
| daily cap | 4 | the heavy user, who is also the one worth keeping |
| actions between | 3 | entering a week of meals must not be an ad per meal |
| away threshold | 4 h | a glance at a notification is not "coming back" |
| absolutes | premium, earned ad-free window | no timing makes either acceptable |

The counters are persisted, and are deliberately **not** keyed by account or
cleared on sign-out — a cap you can clear by signing out is not a cap.

### Rewarded — a day without ads

Offered in the account sheet: watch a video, no ads for 24 hours. The window
extends from *now* rather than from any existing expiry, so a second video an
hour in buys 24 hours and not 47.

The reward is granted only when AdMob reports the video was finished, and the
grant happens before anything else can fail. An app that takes thirty seconds
of somebody's attention and then does not deliver has taught them never to
accept an offer again, which is worth more than the ad earned.

Closing the video early says nothing. That was a choice, not an error.

## Placements ruled out

Kept because the reasoning is the part that is easy to lose:

- **Never on launch.** An ad before the first screen is a guideline 4.2 problem
  and the single most-reported reason for abandoning an app.
- **Never during logging.** The tracker exists to make logging a meal take five
  seconds. An interstitial in that path defeats the feature the app is for.
- **Never between a tap and the thing that was tapped** — opening a post,
  opening a thread. The user asked for something specific; showing an ad
  instead reads as a bug.

## What is done

1. **The plugin.** `google_mobile_ads`, plus `app_tracking_transparency` for
   the iOS prompt. Both are native code, which has a consequence specific to
   this project: **this release cannot be a Shorebird patch.** It needs a full
   `ios-testflight` run, and the release that produces becomes the one later
   patches attach to — see `codemagic.yaml`.

2. **The app ID in each native manifest.** Android in
   `AndroidManifest.xml` as `com.google.android.gms.ads.APPLICATION_ID`, iOS in
   `Info.plist` as `GADApplicationIdentifier`. `privacy_manifest_test.dart`
   checks each platform has *its own* and not the other's — that mistake does
   not serve no ads, it crashes the app on launch before Dart runs, which is
   the same symptom that shipped build 4 as a white screen.

3. **App Tracking Transparency.** `NSUserTrackingUsageDescription` is in
   `Info.plist` and the prompt is requested once per install, after the UMP
   consent form so it arrives with context. iOS never shows it twice, so the
   moment it is asked is the only moment there is — which is why it is asked
   from the shell, after onboarding, rather than at launch.

4. **The consent flow.** Google's UMP SDK, before any ad request. A failure
   here is not fatal: without consent Google serves non-personalised ads,
   which is less money and not no app.

5. **`PrivacyInfo.xcprivacy`.** Now declares `NSPrivacyTracking` true, names
   Google's ad domains, marks the device identifier as used for third-party
   advertising, and adds coarse location and advertising data. Guarded by
   `privacy_manifest_test.dart`.

6. **Test units off `kReleaseMode`.** `ad_policy_test.dart` asserts that a
   non-release build can only ever return one of Google's public test units.
   Google bans accounts that click their own live ads, and the manual version
   of this switch is forgotten exactly once.

## What is left

### Create the two rewarded ad units — the only blocker

AdMob console → the Bulkr app (each platform) → Ad units → Add ad unit →
**Rewarded**. Then put each id in `AdsConfig`:

```dart
// lib/core/config/ads_config.dart
static const String _androidRewarded = String.fromEnvironment(
  'REWARDED_AD_UNIT_ANDROID',
);
```

Either replace the `String.fromEnvironment` with the literal id — which is
what the banner and interstitial units do, and what Shorebird prefers, since
it compares dart-defines between a release and its patches — or pass
`--dart-define` consistently in both `codemagic.yaml` workflows.

Until then the offer is simply not shown. Nothing breaks.

### Set the frequency cap in the console as well

`AdMob console → ad unit → frequency cap`. The app's own limits are in
`AdPolicy` and are stricter, but the console cap is the one that still applies
if a future call site forgets to go through `AdMoment`.

### Two things only a person can do

- **App Store privacy labels** in App Store Connect, to match the manifest.
  They are entered separately and nothing checks that they agree.
- **The privacy policy** has to mention advertising, Google as a processor,
  and the identifiers involved. It is the page the welcome screen links to.

## Still worth deciding

Whether the banner should appear for everyone or only past some threshold —
an account's first week, say. Today it appears for every free account from the
first time they scroll five posts. The interstitial already has a 24-hour
grace; the banner deliberately does not, because it is passive.
