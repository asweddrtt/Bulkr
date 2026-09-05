# Getting Bulkr onto your iPhone, without a Mac

You need a Mac to *build* an iOS app. You do not need to *own* one. Codemagic
rents one per build, and everything below is done from a browser and a
Windows terminal.

Budget: about an hour the first time, ten minutes for every build after.

---

## What was missing, and is now here

These were genuine blockers, not paperwork:

| | |
| --- | --- |
| `ios/Podfile` | Was absent, so a cloud build would generate its own with whatever deployment target Flutter's template defaults to. Committed, pinned to iOS 13, which is what the Firebase pods need. |
| `ios/Runner/Runner.entitlements` | Without `aps-environment`, iOS never hands the app an APNs token — `getToken()` returns null and nothing says why. Added and wired into all three build configurations. |
| Google Sign-In URL scheme | The Google SDK redirects back to the *reversed* client id. Without the scheme the picker opens, you choose an account, and nothing comes back. Added to `Info.plist` — **you must replace the placeholder**, see step 2. |

---

## 1. The two Firebase files - done

`android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`
are committed. A cloud build has no Firebase without them.

They are client configuration rather than credentials - they ship inside every
copy of the app either way, which is why committing them to a private repo is
the normal thing to do rather than plumbing them through CI as secure files.

## 2. Get an iOS OAuth client, and fix the URL scheme

Your `GoogleService-Info.plist` has no `CLIENT_ID` and your
`google-services.json` has `oauth_client: []`. That is not a mistake — Bulkr's
Google sign-in belongs to the **Google Cloud project behind Supabase Auth**,
set up long before the Firebase project you made for push. Two projects, doing
two unrelated jobs. Firebase only sends notifications and needs no OAuth client
at all.

So the value you need does not come from either file.

**Find the iOS client id:**
<https://console.cloud.google.com/apis/credentials> → switch to the project
whose *Web* client id you already use for Supabase Google sign-in → look under
**OAuth 2.0 Client IDs** for one of type **iOS** with bundle id
`com.alimahmoud.bulkr`.

If there is no iOS one, create it: **+ Create credentials → OAuth client ID →
iOS**, bundle id `com.alimahmoud.bulkr`. It needs no review and no secret.

It looks like `123456789012-abcdefg.apps.googleusercontent.com`.

**Then two places:**

1. `ios/Runner/Info.plist` — replace `REPLACE_WITH_REVERSED_CLIENT_ID` with the
   same id *reversed*:
   `com.googleusercontent.apps.123456789012-abcdefg`
2. Codemagic environment variable `GOOGLE_IOS_CLIENT_ID` — the id as-is, not
   reversed (step 5)

Commit the Info.plist change.

Skip this and everything still builds and installs; Google sign-in is the only
thing that breaks, and it breaks by opening the picker and never returning.

## 3. Apple Developer portal

<https://developer.apple.com/account/resources/identifiers/list>

Find or create the App ID `com.alimahmoud.bulkr`, and tick:

- **Push Notifications**
- **Sign In with Apple** — not for the entitlement (Bulkr uses the browser
  flow through Supabase, so it needs none) but because App Store review
  requires it to be *offered* by any app that offers Google sign-in

If Push Notifications is not ticked here, signing fails with a provisioning
profile that does not match the entitlements file.

## 4. App Store Connect

<https://appstoreconnect.apple.com> → Apps → **+** → New App

- Platform: iOS
- Bundle ID: `com.alimahmoud.bulkr`
- SKU: anything, `bulkr` is fine

Note the **Apple ID** number on the app's page — a long number. That is
`APP_STORE_APP_ID` below.

### The API key

Users and Access → **Integrations** → App Store Connect API → **+**

- Access: **App Manager**
- Download the `.p8`. **It downloads once.** Note the Issuer ID and Key ID
  from the same page.

## 5. Codemagic

<https://codemagic.io> — sign in with GitHub, add the `Bulkr` repository.

**Teams → Integrations → Developer Portal → Add key:**

| Field | Value |
| --- | --- |
| Name | `bulkr_asc` *(must match `codemagic.yaml`)* |
| Issuer ID | from step 4 |
| Key ID | from step 4 |
| API key | the `.p8` file |

**App settings → Environment variables**, group `bulkr_secrets`:

| Name | Value | Secure |
| --- | --- | --- |
| `GOOGLE_IOS_CLIENT_ID` | `CLIENT_ID` from `GoogleService-Info.plist` | no |
| `APP_STORE_APP_ID` | the Apple ID number from step 4 | no |

`GOOGLE_IOS_CLIENT_ID` is a `--dart-define` — see
`lib/core/config/supabase_config.dart`. Without it, Google sign-in on iOS
initialises with a null client id and fails at the first tap.

## 6. Build

Codemagic → Bulkr → **Start new build** → workflow `iOS - TestFlight`.

Fifteen to twenty-five minutes. It analyses, runs the tests, builds the ipa,
and uploads.

Then: App Store Connect → your app → TestFlight. The build appears as
"Processing" for a few minutes, then wants an export-compliance answer — Bulkr
uses only HTTPS, so the answer to "does your app use non-exempt encryption" is
**No**.

Install **TestFlight** from the App Store on your phone, sign in with the same
Apple ID, and Bulkr will be there.

---

## Push on iOS needs one more thing

Android works with what you already did. iOS will not send a single
notification without an APNs key:

1. <https://developer.apple.com/account/resources/authkeys/list> → **+**
2. Tick **Apple Push Notifications service (APNs)**, download the `.p8`
3. Firebase Console → Project settings → **Cloud Messaging** → iOS app →
   **APNs Authentication Key** → upload it with its Key ID and your Team ID

Until that is done, `device_tokens` will simply never get an iOS row — the
symptom is silence, not an error.

---

## Every build after the first

```powershell
git push
```

Then Start new build. The build number increments itself from what TestFlight
already has, so you never have to touch `pubspec.yaml`.

## When it fails

| Message | Cause |
| --- | --- |
| `No profiles for 'com.alimahmoud.bulkr' were found` | The App ID or the App Store Connect app record does not exist yet — steps 3 and 4 |
| `Provisioning profile doesn't match the entitlements` | Push Notifications not ticked on the App ID |
| `The bundle version must be higher than the previously uploaded version` | A build with that number already exists; re-run, the counter moves |
| Pod install fails on a deployment target | A new dependency wants more than iOS 13 — raise it in `ios/Podfile` *and* in Xcode's `IPHONEOS_DEPLOYMENT_TARGET` |
| Google sign-in opens and returns nothing | Step 2 was skipped |
