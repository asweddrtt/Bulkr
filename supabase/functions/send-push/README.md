# Push notifications

## Where each thing runs

This is what went wrong the first time, so it goes first:

| What | Where it runs |
| --- | --- |
| `supabase/*.sql` | Supabase dashboard → **SQL Editor** |
| `supabase ...` commands | **A terminal on your machine**, in the repo folder |
| The webhook | Supabase dashboard → **Database → Webhooks** |
| Dart changes | Your editor |

The SQL editor only speaks SQL. Pasting `supabase functions deploy` into it
gives you `42601: syntax error at or near "supabase"`, which is the editor
telling you it has been handed a shell command.

Every terminal snippet below is **PowerShell**, since that is what you are on.

---

## The state of this

The database half and the sending half are in this repo and finished. What is
missing is a **Firebase project**, which only you can create.

`firebase_messaging` is deliberately not in `pubspec.yaml`. Without a
`google-services.json` the Android Gradle plugin fails the build outright, so
adding it early would hand you an app that does not compile. The Dart side
stops at `PushRepository`, which takes a token string and knows nothing about
where it came from.

Until you finish this, nothing is broken: `device_tokens` sits empty,
`push_payload` returns no rows, and in-app notifications work as they do now.

---

## 1. SQL editor

Run `supabase/push_devices.sql`. That is the only part of this that belongs in
the SQL editor.

## 2. Firebase console

1. Create a project at <https://console.firebase.google.com>.
2. Add an **Android** app with the same application id as
   `android/app/build.gradle`. Download `google-services.json` into
   `android/app/`.
3. For iOS: add an iOS app, put `GoogleService-Info.plist` in `ios/Runner/` and
   add it to the Runner target in Xcode, then upload an APNs key under Project
   settings → Cloud Messaging.
4. Project settings → **Service accounts** → Generate new private key. Save the
   downloaded JSON somewhere outside the repo — call it
   `firebase-service-account.json` below.

## 3. Terminal — build the secrets file

The private key is multi-line, which is exactly what a shell is worst at.
Do not try to paste it into a command. Let PowerShell read the JSON instead:

```powershell
.\supabase\functions\send-push\make-env.ps1 -ServiceAccount C:\path\to\firebase-service-account.json
```

That writes `supabase\.env` with all four secrets, converting the key's
newlines to the `\n` sequences the function expects and generating the webhook
secret for you. `supabase/.env` is already in `.gitignore`.

### Or skip the terminal entirely

If the script gives you any trouble, the dashboard does the same job and
handles multi-line values properly, which is the only hard part here:

**Edge Functions → send-push → Secrets → Add new secret**, four times:

| Name | Value |
| --- | --- |
| `FCM_PROJECT_ID` | `project_id` from the JSON |
| `FCM_CLIENT_EMAIL` | `client_email` from the JSON |
| `FCM_PRIVATE_KEY` | the key, pasted as-is, line breaks and all |
| `PUSH_WEBHOOK_SECRET` | any long random string you make up |

Paste the private key exactly as it appears — `-----BEGIN PRIVATE KEY-----`,
the body, `-----END PRIVATE KEY-----`. The function accepts real newlines,
Windows line endings and escaped `\n` alike; all three are tested.

### Or write the file by hand

The key must be on **one line**, with literal backslash-n rather than real
line breaks, because a `.env` value cannot span lines:

```
FCM_PROJECT_ID=your-project-id
FCM_CLIENT_EMAIL=firebase-adminsdk-xxxxx@your-project.iam.gserviceaccount.com
FCM_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIIEv...\n-----END PRIVATE KEY-----\n"
PUSH_WEBHOOK_SECRET=any-long-random-string
```

## 4. Terminal — deploy

```powershell
supabase functions deploy send-push --no-verify-jwt
supabase secrets set --env-file supabase\.env
```

`--no-verify-jwt` is there because the caller is Postgres, not a signed-in
user. `PUSH_WEBHOOK_SECRET` is what replaces that check — the webhook sends it
as a header and a request without it is refused.

To read the generated secret back out for the next step:

```powershell
(Get-Content supabase\.env | Select-String '^PUSH_WEBHOOK_SECRET=').Line -replace '^PUSH_WEBHOOK_SECRET=', ''
```

## 5. The webhook

Newer dashboards moved this out of Database. It is under **Integrations ->
Database Webhooks**:

    https://supabase.com/dashboard/project/<your ref>/integrations/webhooks/overview

Enable webhooks if prompted, then create **two** hooks — identical except for
the table:

| Field | Value |
| --- | --- |
| Table | `public.notifications`, and again for `public.messages` |
| Events | Insert |
| Type | Supabase Edge Functions |
| Edge Function | `send-push` |
| HTTP headers | `x-push-secret` : *the value from step 3* |

Two, because a like and a message are announced differently and only one of
them has a row in `notifications`. The function tells them apart by the
`table` field the webhook sends, so nothing else differs.

If that page will not cooperate, the same setup exists as SQL you can read:
`supabase/push_webhook.sql` for notifications, `supabase/chat_push.sql` for
messages. Replace two values at the top of each and run it.

`chat_push.sql` also creates `message_push_payload`, which is needed either
way — run it even if you set the webhook up in the dashboard.

Either route ends up as a trigger calling `net.http_post`, which is
asynchronous — pg_net queues the request and a background worker drains it, so
the insert never waits on the network. The like is recorded whether or not FCM
is reachable.

## 6. The app

**Done.** `firebase_core` and `firebase_messaging` are in `pubspec.yaml`, the
Google Services Gradle plugin is applied, `Firebase.initializeApp()` runs at
startup, and `PushService` registers the device.

For the record, where each piece lives:

| Piece | Where |
| --- | --- |
| Gradle plugin declared | `android/settings.gradle.kts` |
| Gradle plugin applied | `android/app/build.gradle.kts` |
| `Firebase.initializeApp()` | `lib/main.dart` |
| Permission + token registration | `lib/data/push_service.dart` |
| Called on sign-in | `lib/screens/main_screen.dart` |
| Called on sign-out | `lib/screens/profile_screen.dart` |

Two choices in there worth knowing:

**Permission is asked for at the shell, not at launch.** A notification prompt
on first open, before anyone has seen what the app is, is the one most reliably
denied — and on iOS a denial is close to permanent, because the app cannot ask
again.

**Sign-out unregisters before the session goes.** The token belongs to the
phone, not the account. Left behind, the next person to sign in on that device
would receive the previous person's notifications until they registered their
own. Account *deletion* needs no equivalent: `device_tokens.user_id` cascades.

Firebase failing to start is caught and logged rather than thrown. It is only
here to deliver notifications, so a desktop build with no configuration should
run without them rather than not run.

You still need, on the Firebase side:

- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`, added to the Runner target in Xcode
- an **APNs key** uploaded under Project settings → Cloud Messaging, and the
  Push Notifications capability on the Runner target — iOS sends nothing
  without both

---

## What gets sent

`push_payload` builds the sentence in SQL from the same four kinds the in-app
list uses. It returns nothing for a notification already marked read — the
webhook fires on insert, so that only happens when the user was looking at the
screen as it arrived, which is when a buzzing phone is most annoying.

Direct messages take the other route. They still do not go through
`notifications` — a message that produced both a thread badge and an inbox row
would be one event announced twice — so `message_push_payload` in
`supabase/chat_push.sql` reads the message directly. It differs from the
notification path in three ways worth knowing:

- The title is the sender's name rather than `Bulkr`. A message is from a
  person, and hiding who it is from means opening the app to find out.
- The body is the message, trimmed to 140 characters.
- It sends nothing to somebody whose `last_read_at` is already past the
  message. pg_net is asynchronous, so this runs a moment after the insert —
  long enough for whoever had the thread open to have marked it read over
  Realtime.

Blocked pairs are skipped in both directions.

## Checking it works

In the SQL editor, after the app has signed in on a real device:

```sql
select user_id, platform, last_seen_at from public.device_tokens;
```

Then have a second account follow the first. Dashboard → Edge Functions →
send-push → Logs. `{"sent":1}` is success. `{"sent":0}` means the row was
found but no device was registered for that user; a 403 means the webhook
header does not match the secret.

The response also carries `kind`, so a log line says which of the two hooks
fired. If messages push and notifications do not, or the other way round, that
is the field that tells you which webhook is missing.

To see what Postgres actually sent, rather than what the function received:

```sql
select id, created, status_code, content
  from net._http_response
 order by created desc
 limit 5;
```

Empty means nothing fired at all — no webhook, and no trigger either.

### `Invalid APNs credential` / `THIRD_PARTY_AUTH_ERROR`

A 401 with this body means the key is uploaded and **Apple rejected it**.
Firebase mints a JWT from the `.p8` plus the Key ID and Team ID you typed in
beside it, and Apple threw that JWT out. So all three are suspect, and the
same error covers every one of them:

1. **Is it actually an APNs key?** Both an APNs key and an App Store Connect
   API key are `.p8` files downloaded exactly once, and Bulkr needs one of
   each — the API key goes to Codemagic, the APNs key goes to Firebase.
   Uploading the wrong one produces precisely this error. An APNs key comes
   from Certificates, Identifiers & Profiles -> **Keys** with **Apple Push
   Notifications service (APNs)** ticked. If in doubt, make a new one: an
   account can hold two.

2. **Is the Team ID a Team ID?** Ten characters, letters and digits, from
   developer.apple.com -> Membership details. The App Store Connect key has an
   **Issuer ID** instead, which is a dashed UUID. They sit next to each other
   in the same workflow and pasting the UUID here fails exactly like this.

3. **Does the Key ID match the file?** Ten characters, shown against the key
   in the Keys list. It is not interchangeable with the API key's own Key ID,
   which is also ten characters.

Then check it landed on the right app: Cloud Messaging lists Apple app
configuration per iOS app, and a project with more than one has more than one
place to put it. It belongs under the app whose bundle ID is
`com.alimahmoud.bulkr`.

Android is unaffected by all of this — a `{"sent":1}` beside a 401 in the same
minute is one platform working and the other refused, not an intermittent
fault.

#### When the Key ID and Team ID are demonstrably right

Then it is the file, and Firebase cannot tell you so. It stores the `.p8` you
picked and the Key ID you *typed*, and never checks one against the other — so
a screen showing the correct Key ID and Team ID beside the wrong key file
looks exactly like a screen showing a correct setup. Apple is the first thing
in the chain that verifies the signature, and `InvalidProviderToken` is what
that verification failing sounds like.

There is no way to confirm the file from Firebase's side, and Apple only
allows a key to be downloaded once, so an existing key cannot be re-fetched to
compare. The way out is a new key rather than an audit:

- Create a second APNs key and upload that. An account may hold two.
- Do **not** revoke the old one first if it also carries Sign In with Apple —
  Supabase's Apple provider is configured with that same `.p8`, and revoking
  it breaks the browser sign-in flow on Android.
- Prefer a key with APNs and nothing else. One key serving both push and
  sign-in means one revocation breaking both, and it is why the wrong file
  ends up uploaded in the first place: two `.p8` downloads, months apart, for
  two different purposes.

### `{"sent":1}` is FCM accepting, not a phone displaying

Worth being precise about, because it is easy to read as proof and it is not.
FCM validates the token's shape and queues the message; a token belonging to a
phone that has been wiped, or an app uninstalled weeks ago, is accepted just
the same. So `sent:1` against a stale row in `device_tokens` is a success
line for a notification nobody will ever see.

Which devices are actually live:

```sql
select platform, last_seen_at, now() - last_seen_at as idle
  from public.device_tokens
 order by last_seen_at desc;
```

`last_seen_at` is bumped on every app start. A row idle for days is a device
that is not going to show anything, and it will keep inflating `sent` until it
is deleted.

### iOS sends nothing without an APNs key at all

Worth ruling out first on an iPhone, because the symptom is silence rather
than an error: no `.p8` uploaded to Firebase → Cloud Messaging means
`getToken()` returns null, the device never registers, and every push reports
`{"sent":0}` for that user however correct everything else is. See
`ios/TESTFLIGHT.md`.
