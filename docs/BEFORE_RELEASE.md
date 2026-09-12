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

## 4. Mirror the Android nudity model — recommended, not blocking

The check **now runs on Android.** It did not before: the model id is the same
on both platforms, but only iOS bundles it — the plugin's Android descriptor
carries a `downloadUrl`, so the ~11 MB `OpenNSFW2.tflite` has to be fetched
once, and nothing fetched it. Every Android scan threw `ModelNotFound`, scored
nothing, and the fail-open branch allowed the upload.

`ImageSafety.ensureModelReady()` now downloads it once and is awaited before
any image is scored. `ImageSafety.warmUp()` starts the fetch from
`ImageSourceSheet.show` — the one choke point every picker goes through — so it
overlaps with the user choosing a photo instead of being paid when they press
Post.

### What is left to decide

By default the download comes from a **third-party GitHub release**:

    github.com/nexas105/flutter_nsfw_scaner/releases/.../OpenNSFW2.tflite.zip

Two problems with leaning on that for a moderation feature, neither urgent:

1. **It is not ours.** If that repo is renamed, the release deleted, or the
   asset swapped, Android moderation stops working — silently, in the
   fail-open direction.
2. **It is not verified.** The plugin supports pinning a SHA-256 and its own
   source comment says to pin "any URL the integrator does not fully control" —
   but the built-in OpenNSFW2 descriptor leaves it null, so the bytes are
   trusted as they arrive.

Both are fixed the same way. The archive is ~11 MB and never changes, so it is
a one-time upload to a bucket you already have:

```sh
flutter build appbundle \
  --dart-define=NSFW_MODEL_URL=https://<project>.supabase.co/storage/v1/object/public/models/OpenNSFW2.tflite.zip
```

`ModerationConfig` validates it — an https URL with a host, or it is ignored
and the default is used, rather than silently turning the check off.

### What still fails open

A first post on a phone with no connection, or a download past the 45-second
timeout, still ends in an allowed upload. That direction is unchanged and
deliberate: fail-closed would mean one bad network moment turns "post a photo"
into a feature that does not work.

What changed is that it is now rare and loud instead of universal and silent.
Watch two counts on Android:

- `image_check_skipped` with `reason=model_unavailable` — an upload went
  through unchecked
- `moderation_model_failed` — why the model was missing (`timeout` or `error`)

If either is anything but near-zero, Android moderation is not working.
`moderation_model_ready` carries how long the fetch took, which is the number
that says whether the warm-up needs to move earlier than the picker.

## 5. Calibrate the nudity threshold, now that there is data to do it with

`ImageSafety.threshold` is still 0.75, still picked by intuition, and the file
still says so. What has changed is that the numbers now leave the phone:

- `image_refused` — score, threshold, and which channel order produced it
- `image_allowed` — the same, for images that passed

Refusals alone cannot calibrate a threshold: they are the complaints, and the
false negatives are the half that never complains. Both halves are now
recorded.

`channelOrderIsUnverified` is still true, so every image is scored twice — once
RGB, once with red and blue swapped, higher score wins. The `variant` parameter
says which one fired. Once one order is doing the work consistently, drop to a
single scan; that one **is** patchable, since it is a Dart constant with no
asset behind it.

The score is no longer shown to the user. `test/moderation_error_test.dart`
fails if that is turned back on.

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
| `moderation_error_test.dart` | the model score reappearing in a refusal |
| `image_safety_test.dart` | the model id drifting from the one the plugin registers, or the fetch timeout dropping below a usable one |
| `analytics_events_test.dart` | an event name Firebase would silently drop, or a parameter carrying user content |
| `meal_repository_test.dart` | a meal logged against the wrong day in a non-UTC timezone |
| `post_repository_test.dart` | keyset paging turning back into an offset |
