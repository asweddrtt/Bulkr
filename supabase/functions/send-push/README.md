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

## 5. Dashboard — the webhook

Database → **Webhooks** → Create a new hook:

| Field | Value |
| --- | --- |
| Table | `public.notifications` |
| Events | Insert |
| Type | Supabase Edge Functions |
| Edge Function | `send-push` |
| HTTP headers | `x-push-secret` : *the value from step 4* |

A trigger calling out directly would hold a transaction open across the
network, so a slow FCM would turn "somebody liked your post" into a like that
takes four seconds to record. The webhook fires after commit — the like is
saved whatever happens next.

## 6. The app

Only once `google-services.json` is in `android/app/`:

```powershell
flutter pub add firebase_core firebase_messaging
```

In `main()`, after `Supabase.initialize`:

```dart
await Firebase.initializeApp();
```

Once the user is signed in — `AuthCubit`, next to where the session is adopted:

```dart
final NotificationSettings settings =
    await FirebaseMessaging.instance.requestPermission();

if (settings.authorizationStatus == AuthorizationStatus.authorized) {
  final String? token = await FirebaseMessaging.instance.getToken();
  if (token != null) {
    await pushRepository.register(
      token: token,
      platform: Platform.isIOS ? 'ios' : 'android',
    );
  }

  // FCM rotates tokens. Registering only at sign-in goes stale, and a stale
  // token is a phone that silently stops being notified.
  FirebaseMessaging.instance.onTokenRefresh.listen((token) {
    pushRepository.register(token: token, platform: ...);
  });
}
```

And on sign-out, **before** the session goes:

```dart
await pushRepository.unregister(token);
```

That last one matters more than it looks: the token belongs to the *device*,
not the account, so leaving it behind means the next person to sign in on that
phone receives the previous person's notifications.

---

## What gets sent

`push_payload` builds the sentence in SQL from the same four kinds the in-app
list uses. It returns nothing for a notification already marked read — the
webhook fires on insert, so that only happens when the user was looking at the
screen as it arrived, which is when a buzzing phone is most annoying.

Direct messages are not wired to push. They do not go through `notifications`
at all, by design — see the note at the top of `supabase/notifications.sql`.
Adding them means a second webhook on `public.messages` and a second payload
function; the shape here is meant to be copied for it.

## Checking it works

In the SQL editor, after the app has signed in on a real device:

```sql
select user_id, platform, last_seen_at from public.device_tokens;
```

Then have a second account follow the first. Dashboard → Edge Functions →
send-push → Logs. `{"sent":1}` is success. `{"sent":0}` means the row was
found but no device was registered for that user; a 403 means the webhook
header does not match the secret.
