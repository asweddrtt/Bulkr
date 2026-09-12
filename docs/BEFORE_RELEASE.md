# Before the next release

Things this change left deliberately unfinished, because finishing them needs a
decision, an account, or a machine this work did not have. Each one is written
so it can be done without re-deriving why.

Ordered by what blocks a store submission first.

---

## 1. Set the privacy policy URL — blocks App Store review

`LegalConfig.privacyPolicyUrl` is empty. While it is, the welcome screen
renders "BY CONTINUING YOU AGREE TO THE Policy" as **plain text**, with no
underline and no tap — honest, and better than the underlined non-link it
replaced, but not sufficient for review.

Guideline 5.1.1 requires a reachable privacy policy, and the sign-up screen is
where review looks. An app collecting an email address, body measurements,
photos, messages and — as of this release — analytics will not pass without
one.

Two ways to set it:

```sh
flutter build ipa --dart-define=PRIVACY_POLICY_URL=https://…
```

or edit the default in `lib/core/config/legal_config.dart`. If you use the
`--dart-define`, add it to **both** workflows in `codemagic.yaml`: Shorebird
compares dart-defines between a release and its patches, so a define present on
one and missing on the other reads as a diff and the patch is refused.

The URL is validated at runtime — https, with a host — so a typo on the build
machine turns the link off rather than shipping a dead one.

**What the policy has to mention now that it did not before:** Firebase
Analytics and Crashlytics, the categories in `ios/Runner/PrivacyInfo.xcprivacy`,
and that the identifier tying them to an account is the Supabase user id.

## 2. Enter the App Store privacy labels to match the manifest

`PrivacyInfo.xcprivacy` and the nutrition labels in App Store Connect are
entered separately and **nothing checks that they agree**. The manifest now
declares ten collected data types, two of which are new this release:

- Product Interaction — analytics
- Crash Data — Crashlytics

`test/privacy_manifest_test.dart` guards the manifest. Only a person can guard
App Store Connect.

## 3. This release cannot be a Shorebird patch

`firebase_crashlytics`, `firebase_analytics`, `url_launcher` and `app_links`
are native dependencies. Native code cannot travel in a patch — see the note in
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
| `analytics_events_test.dart` | an event name Firebase would silently drop, or a parameter carrying user content |
| `meal_repository_test.dart` | a meal logged against the wrong day in a non-UTC timezone |
| `post_repository_test.dart` | keyset paging turning back into an offset |
