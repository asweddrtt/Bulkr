# Before the next release

Things this change left deliberately unfinished, because finishing them needs a
decision, an account, or a machine this work did not have. Each one is written
so it can be done without re-deriving why.

Ordered by what blocks a store submission first.

---

## 1. Confirm the privacy policy is public — blocks App Store review

`LegalConfig.privacyPolicyUrl` is set to

    https://sites.google.com/view/bulkr-privacy-policy/home

so the welcome screen now renders "Policy" as a real link that opens in the
browser. Two things still need a human.

### It must be published and visible to anyone

Google Sites keeps a site restricted until it is both **published** and set to
**Anyone** under Share. A policy that asks for a Google sign-in is a failed
review under guideline 5.1.1, and it fails in a way that is invisible to you —
your browser is already signed in.

**Check it in a private window.** That is the whole test.

### `?authuser=2` was removed, deliberately

The URL first supplied carried `?authuser=2`. Google Sites adds that to the
address bar to record which of the accounts signed into *that browser* is being
used. It is session state, not part of the address: shipped, it sends every
user a parameter that means nothing to them and can land them on an account
chooser instead of the policy.

`legal_config_test.dart` fails if it — or `usp`, or `pli` — comes back.

### What the policy has to mention now that it did not before

- Firebase Analytics and Crashlytics
- **Images sent to AWS Rekognition for moderation**, and which region processes
  them — this is new as of the moderation change and is a third-party
  processor handling user photos
- **Google AdMob**, that ads may be personalised, that the advertising
  identifier is used when the user allows it, and how to opt out. This is new
  as of the ads change and it is the part most likely to be checked
- Everything in the `ios/Runner/PrivacyInfo.xcprivacy` categories
- That the identifier tying analytics to an account is the Supabase user id

## 2. Enter the App Store privacy labels to match the manifest

`PrivacyInfo.xcprivacy` and the nutrition labels in App Store Connect are
entered separately and **nothing checks that they agree**. The manifest now
declares twelve collected data types, and this release changes the answer to
the question review cares about most:

- **"Used for tracking" is now yes.** `NSPrivacyTracking` is true, Google's ad
  domains are listed, and Device ID is marked as used for third-party
  advertising. The labels have to say the same.
- Coarse Location and Advertising Data are new, and both are tracking.
- Product Interaction — analytics, from the previous release.
- Crash Data — Crashlytics, from the previous release.

`test/privacy_manifest_test.dart` guards the manifest. Only a person can guard
App Store Connect.

## 2b. Set a frequency cap on the interstitial unit

All six ad units now exist and are in `AdsConfig`. One thing is still worth
doing in the AdMob console: a frequency cap on each interstitial unit. The
app's own limits in `AdPolicy` are stricter, but the console cap is the one
that still applies if a future call site forgets to go through `AdMoment`.

Note that the rewarded units are **rewarded interstitial**, a different format
from plain rewarded. The code matches them. If either is ever recreated as the
other format, the ad stops filling and the error says only "no fill" — see
`docs/ADMOB.md`.

## 3. This release cannot be a Shorebird patch

`google_mobile_ads`, `app_tracking_transparency`, `firebase_crashlytics`,
`firebase_analytics`, `url_launcher` and `app_links` are native dependencies. Native code cannot travel in a patch — see the note in
`codemagic.yaml`, which is right about this and worth re-reading. Run
`ios-testflight`, not `ios-patch`. The release it produces becomes the one
later patches attach to.

---

## 4. Deploy `moderate-image`, or nothing is checked

Image moderation now runs server-side through AWS Rekognition. **Until the
function is deployed and its secrets are set, every upload passes unchecked** —
the client fails open on purpose, and says so.

Setup is in `supabase/functions/moderate-image/README.md`: an IAM user with one
permission, three secrets, one deploy command.

Then watch `image_check_skipped` in analytics. It should be near zero. Anything
else means the function is down, undeployed, or the key is wrong.

### The on-device check is gone

`lib/core/image_safety.dart` has been deleted rather than kept as a fallback.
It worked on neither platform — iOS scored a full nude below a topless photo,
Android's model 404s — and a broken fallback is worse than none, because it
restores exactly the false confidence this replaced.

### Still advisory

The function is called *by the client*, so a patched client can skip it. The
AWS key is safe and the model is good, but the decision is not yet enforced.

Closing that is the next slice: move the upload into the function and lock the
buckets to service-role writes, so a client that skips moderation cannot write
anything at all.

## 4b. Apply `premium.sql` and `streak_restore.sql`

Two new files in `supabase/`, and the apply order in `supabase/README.md` now
has them at 28 and 29.

`streak_restore.sql` **replaces `logging_streak()`** from
`tracker_insights.sql` with a version that also counts restored days. Applying
it before that file leaves the old definition in place, and the restore then
appears to work and changes nothing.

A third, `premium_limits.sql`, is where the free tier's caps are enforced. It
needs `premium.sql` first, and without it free and premium differ only in ads.

Once they are applied, prove the cap actually bites — the verify block at the
bottom of `premium_limits.sql` is two statements — and then prove that
granting premium lifts it. A limit that does not bite and a limit that cannot
be lifted are both silent, and they look identical from the app.

Without `premium.sql` nobody is premium — which the app treats as an answer
rather than an error, so it will not complain. The symptom is that no
subscription ever takes effect.

## 4c. Watch the ads on a real device before trusting any of it

None of the ad code has run on a phone. It cannot be run from where this was
written: there is no Android SDK on that machine and both `codemagic.yaml`
workflows are iOS releases.

What to check on the first TestFlight build, in this order:

1. **The app launches at all.** A wrong or missing `GADApplicationIdentifier`
   crashes before Dart runs, and the symptom is the white screen that shipped
   build 4. `privacy_manifest_test.dart` checks the value is the iOS one, but
   only a device proves the SDK accepts it.
2. **The consent form and the tracking prompt appear**, in that order, after
   onboarding rather than at launch. iOS shows the tracking prompt once per
   install, ever — so if it arrives at the wrong moment, the only way to see it
   again is to delete the app.
3. **A banner appears in the feed** after five posts, and it is a Google test
   ad. A release build serves real ads; anything before that must not.
4. **An interstitial does not appear on the first day.** That is the grace
   period doing its job, and it means the interstitial cannot be tested
   properly on a fresh install — reinstall or wait a day rather than assuming
   it is broken.

Then watch `ad_failed` in analytics. Code 3 is "no fill" and is normal for a
new unit; anything else in volume is a misconfigured unit.

## 5. Calibrate against your own photos

The policy in `supabase/functions/moderate-image/policy.ts` is written from
Rekognition's documented taxonomy, not from your feed. The labels it allows —
`Male Swimwear Or Underwear`, `Barechested Male`, `Emaciated Bodies` — are the
ones a bulking app must never reject, but that list is reasoned, not measured.

Worth doing once with real images: post a shirtless progress photo, a lean
cutting photo, a gym selfie, a meal — and confirm each is allowed. Then confirm
an explicit image is refused. `image_allowed` carries the labels each one
produced, so the dashboard tells you what the model actually saw.

If a physique photo is ever refused, the fix is one line in `NEVER_REFUSE` and
a redeploy — no app release, which is most of why the policy lives server-side.

---

## 6. Optional: the Crashlytics Gradle plugin on Android

Not added, deliberately. It was not possible to verify an Android Gradle
configuration from where this work was done — there is no Android SDK on that
machine and `codemagic.yaml` has no Android workflow to catch a break — and an
unverifiable build-file change is a poor trade for what it buys.

**Dart errors report without it.** Bulkr is almost entirely Dart, and Dart stack
traces arrive already symbolicated. The plugin adds R8 mapping-file upload and
NDK symbols, which matter for native Android crashes.

To add it when there is a machine that can build Android:

```kotlin
// android/settings.gradle.kts
id("com.google.firebase.crashlytics") version "3.0.2" apply false

// android/app/build.gradle.kts — after com.google.gms.google-services
id("com.google.firebase.crashlytics")
```

## 7. Optional: an Android CI workflow

Both `codemagic.yaml` workflows are iOS. `flutter analyze` and `flutter test`
only run as a step inside a release or a patch, so a broken commit sits on
`main` until a build is cut, and Android is never built at all — which is how
the `app_links` / AGP breakage that still needs a version pin reached the repo.

A Linux job running `flutter analyze && flutter test` costs about two minutes
and would have caught it.

---

## What is already guarded by a test

No action needed; listed so nobody re-checks them by hand.

| Guarded by | What breaks the build |
|---|---|
| `privacy_manifest_test.dart` | the manifest missing, an undeclared required-reason API, or the file not being in the Xcode Resources phase |
| `deep_link_test.dart` | the Android intent-filter for `post` going missing, or the parser answering the OAuth callback |
| `translation_keys_test.dart` | a `.tr()` key with no entry, or an entry nothing uses |
| `accessibility_test.dart` | a new icon-only control with no label |
| `moderation_error_test.dart` | a model score or label reappearing in a user-facing refusal |
| `policy.test.ts` | the moderation policy starting to reject shirtless or lean physique photos |
| `analytics_events_test.dart` | an event name Firebase would silently drop, a parameter carrying user content, or a new event nobody added to the list those rules are checked against |
| `ad_policy_test.dart` | an interstitial becoming reachable on day one, twice in four minutes, five times a day, or inside an earned ad-free window — and a non-release build ever requesting a real ad unit |
| `privacy_manifest_test.dart` | the manifest claiming not to track while the ad SDK is a dependency, or either platform carrying the other's AdMob app ID |
| `streak_state_test.dart` | the restore offer appearing next to a running streak, or for a one-day run |
| `plan_limit_error_test.dart` | a full free tier being reported as a permission error, or a limit with no sentence and no way out of it |
| `trial_offer_test.dart` | a store period the parser does not understand being shown as "0 days free" |
| `meal_repository_test.dart` | a meal logged against the wrong day in a non-UTC timezone |
| `post_repository_test.dart` | keyset paging turning back into an offset |
| `plan_limits_test.dart` | the free tier's numbers in the app and in `premium.sql` drifting apart, or a write policy appearing on `subscriptions` |
| `entitlement_test.dart` | an unknown tier, a corrupt cache or a failed refresh resolving to premium instead of free |
| `analytics_events_test.dart` | a new event that nobody added to the list the name rules are checked against |
