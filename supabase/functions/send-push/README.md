# Push notifications

The database half and the sending half are in this repo and finished. The part
that is missing is a **Firebase project**, which only you can create, and the
native app configuration that comes with it.

That is why `firebase_messaging` is deliberately **not** in `pubspec.yaml`.
Adding it without a `google-services.json` does not degrade gracefully — the
Android Gradle plugin fails the build outright with "File google-services.json
is missing". Rather than hand you an app that will not compile, the Dart side
stops at `PushRepository`, which takes a token string and knows nothing about
where it came from. Wiring Firebase to it is the last step below.

Until then nothing is broken: `device_tokens` sits empty, `push_payload`
returns no rows, and the in-app notifications work exactly as they do now.

---

## 1. Firebase

1. Create a project at <https://console.firebase.google.com>.
2. Add an **Android** app with the same application id as
   `android/app/build.gradle`. Download `google-services.json` into
   `android/app/`.
3. Add an **iOS** app if you ship one. Download `GoogleService-Info.plist` into
   `ios/Runner/` and add it to the Runner target in Xcode. iOS also needs an
   APNs key uploaded to Firebase under Project settings → Cloud Messaging.
4. Project settings → Service accounts → **Generate new private key**. This
   downloads a JSON file. Three fields out of it become the secrets below.

## 2. Supabase

Run `supabase/push_devices.sql` first, then:

```bash
supabase functions deploy send-push --no-verify-jwt

supabase secrets set \
  FCM_PROJECT_ID="your-project-id" \
  FCM_CLIENT_EMAIL="firebase-adminsdk-xxxxx@your-project.iam.gserviceaccount.com" \
  FCM_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMII...\n-----END PRIVATE KEY-----\n"

supabase secrets set PUSH_WEBHOOK_SECRET="$(openssl rand -hex 32)"
```

`FCM_PRIVATE_KEY` is the `private_key` field of that JSON, newlines and all —
keep it on one line with the `\n` sequences as they appear in the file. The
function un-escapes them.

`--no-verify-jwt` is there because the caller is Postgres rather than a
signed-in user. `PUSH_WEBHOOK_SECRET` is what replaces that check, and it is
not optional: without it this endpoint would push anything to anyone who could
guess a uuid.

## 3. The webhook

Dashboard → Database → **Webhooks** → Create:

| Field | Value |
| --- | --- |
| Table | `public.notifications` |
| Events | Insert |
| Type | Supabase Edge Functions |
| Function | `send-push` |
| HTTP headers | `x-push-secret: <the value you generated above>` |

A trigger calling out directly would hold a transaction open across the
network, so a slow FCM would make "somebody liked your post" a like that takes
four seconds to record. The webhook fires after commit — the like is saved
whatever happens next.

## 4. The app

Once `google-services.json` is in place:

```bash
flutter pub add firebase_core firebase_messaging
```

Then, in `main()` after `Supabase.initialize`:

```dart
await Firebase.initializeApp();
```

and once the user is signed in — `AuthCubit` is the natural place, next to
where the session is adopted:

```dart
final NotificationSettings settings =
    await FirebaseMessaging.instance.requestPermission();

if (settings.authorizationStatus == AuthorizationStatus.authorized) {
  final String? token = await FirebaseMessaging.instance.getToken();
  if (token != null) {
    await pushRepository.register(token: token, platform: Platform.isIOS ? 'ios' : 'android');
  }

  // FCM rotates tokens. A registration that only happens at sign-in goes
  // stale, and a stale token is a phone that silently stops being notified.
  FirebaseMessaging.instance.onTokenRefresh.listen((token) {
    pushRepository.register(token: token, platform: ...);
  });
}
```

and on sign-out, before the session goes:

```dart
await pushRepository.unregister(token);
```

`PushRepository.unregister` matters more than it looks: the token belongs to
the *device*, not the account, so leaving it behind means the next person to
sign in on that phone receives the last person's notifications.

## What gets sent

`push_payload` builds the sentence in SQL, from the same four kinds the
in-app list uses. It deliberately returns nothing for a notification that has
already been marked read — the webhook fires on insert, so that only happens
when the user was looking at the screen as it arrived, which is exactly when a
buzzing phone is most annoying.

Direct messages are not wired to push. They do not go through `notifications`
at all, by design — see the note at the top of `supabase/notifications.sql`.
Adding them means a second webhook on `public.messages` and a second payload
function; the shape here is meant to be copied for it.

## Checking it works

```sql
-- After the app has signed in on a device:
select user_id, platform, last_seen_at from public.device_tokens;
```

Then have a second account follow the first. `send-push` logs its result in the
dashboard under Edge Functions → send-push → Logs; `{"sent":1}` is what success
looks like.
