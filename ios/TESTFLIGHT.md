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
| ~~`ios/Podfile`~~ | Added, then removed. Flutter now resolves every iOS plugin through Swift Package Manager, and a hand-written Podfile is what stops it finishing that migration — it reports "your project uses a non-standard Podfile" and then archives against a Pods sandbox that no longer matches. There is no Podfile now, on purpose. |
| `ios/Runner/Runner.entitlements` | Without `aps-environment`, iOS never hands the app an APNs token — `getToken()` returns null and nothing says why. Added and wired into all three build configurations. |
| Google Sign-In URL scheme | The Google SDK redirects back to the *reversed* client id. Without the scheme the picker opens, you choose an account, and nothing comes back. Added to `Info.plist` — **you must replace the placeholder**, see step 2. |

---

## 1. The two Firebase files - done

`android/app/google-services.json` and `ios/Runner/GoogleService-Info.plist`
are committed. A cloud build has no Firebase without them.

They are client configuration rather than credentials - they ship inside every
copy of the app either way, which is why committing them to a private repo is
the normal thing to do rather than plumbing them through CI as secure files.

## 2. The iOS OAuth client - done

Created in the `Bulkr` Google Cloud project (the one behind Supabase Auth, not
the Firebase one), and `ios/Runner/Info.plist` carries its reversed form as a
URL scheme.

One value still has to go into Codemagic in step 5, **un-reversed**:

    GOOGLE_IOS_CLIENT_ID = 482455223938-d4m26ijhdn9uoued3dvlu7hd9r10fhc5.apps.googleusercontent.com

Two forms of one id, and they are not interchangeable. The URL scheme is
written host-first — `com.googleusercontent.apps.482455223938-...` — because
that is what a scheme is. The build define wants the id as Google prints it.
Getting either one wrong fails the same way: the account picker opens, you
choose, and nothing comes back.

Nothing changes on the Supabase side. `signInWithGoogle` passes
`serverClientId: googleWebClientId`, so the ID token's audience is the **web**
client on every platform, and the web client is the only one Supabase has ever
been configured with. The iOS client exists purely so the native picker can
run.

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

**The API key must be a Team Key**, created under Users and Access →
Integrations → **Team Keys**, with **App Manager** or **Admin** access. A key
made under *Individual Keys* is scoped to one app and cannot manage
certificates or profiles at all — and it does not say so when you create it. It
says so here, as "No matching profiles found", which reads like the profile is
missing rather than like the key cannot make one.

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
| `GOOGLE_IOS_CLIENT_ID` | the iOS OAuth client id from step 2, un-reversed | no |
| `APP_STORE_APP_ID` | the Apple ID number from step 4 | no |
| `CERTIFICATE_PRIVATE_KEY` | see just below | **yes** |

### The certificate private key

Apple issues a signing certificate against a private key that never leaves the
machine that asked for it. So the distribution certificate already in your
account — made on a Mac, for your other app — cannot be used here at all. That
is what

    Cannot save Signing Certificates without certificate private key

means: the certificate was found, the key to use it was not.

Give Codemagic a key of its own and Apple issues a **second** certificate
against it, leaving the first one alone. (Revoking the old one would also work,
and would break whatever still signs with it. Apple allows two.)

Generate it once, in PowerShell:

```powershell
ssh-keygen -t rsa -b 2048 -m PEM -f cert_key -q -N '""'
```

`ssh-keygen` ships with Windows 10 and 11 — no OpenSSL needed. That writes
`cert_key` (the private key) and `cert_key.pub` (ignore it).

```powershell
Get-Content cert_key | Set-Clipboard
```

Paste into a Codemagic variable named `CERTIFICATE_PRIVATE_KEY` in group
`bulkr_secrets`, and **tick Secure**. Include the
`-----BEGIN RSA PRIVATE KEY-----` and `-----END RSA PRIVATE KEY-----` lines.

Then delete the local copy — Codemagic has it now, and it is the one file here
that genuinely is a credential:

```powershell
Remove-Item cert_key, cert_key.pub
```

Generated once and stored, not per build: a fresh key every run would issue a
new certificate every run, and Apple's limit of two would be gone by the second
build.

Not from `GoogleService-Info.plist`, which has no `CLIENT_ID` in it — the two
are different Google Cloud projects, and the plist even says so: its
`GCM_SENDER_ID` is 848696099138 while the OAuth client is 482455223938.
Firebase sends pushes; the other project owns sign-in.

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
| `No matching profiles found for bundle identifier ... app_store` | There is no App Store profile yet, which is normal before the first build. The workflow creates one with `--create`; if it still fails, the App Store Connect key is the cause — see below |
| `No profiles for 'com.alimahmoud.bulkr' were found` | The App ID or the App Store Connect app record does not exist yet — steps 3 and 4 |
| `Cannot save Signing Certificates without certificate private key` | `CERTIFICATE_PRIVATE_KEY` is missing or truncated — step 5 |
| `App Store Connect integration "bulkr_asc" does not exist` | The API key is not registered in Codemagic under that exact name |
| `Provisioning profile doesn't match the entitlements` | Push Notifications not ticked on the App ID |
| `The bundle version must be higher than the previously uploaded version` | A build with that number already exists; re-run, the counter moves |
| `The sandbox is not in sync with the Podfile.lock` | Something reintroduced a Podfile. All plugins are Swift Packages; there should not be one |
| A pod wants a higher deployment target | Raise `IPHONEOS_DEPLOYMENT_TARGET` in `project.pbxproj` and `MinimumOSVersion` in `ios/Flutter/AppFrameworkInfo.plist` — both, or Flutter rewrites them mid-build |
| Google sign-in opens and returns nothing | Step 2 was skipped |
| Crash at launch in `MLKAnalyticsLogger` / `unrecognized selector ... synchronize` | ML Kit and Firebase disagreeing about GoogleUtilities. Fixed by mobile_scanner 7 plus static linkage in the Podfile; if it comes back, a new pod has brought an old GoogleUtilities with it |
