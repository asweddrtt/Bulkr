# Bulkr

A bulking companion: set a target, get a calorie and macro plan, and track the climb.

## Getting started

```bash
flutter pub get
flutter run
```

## Onboarding flow

Five steps, in order:

| Step | Route | Collects |
|------|-------|----------|
| 1. Identity | `/` | Supabase Auth session via Google or Apple OAuth |
| 2. Biometrics | `/biometrics` | `username`, `gender`, `date_of_birth`, `height_cm`, `current_weight_kg`, `units` |
| 3. Lifestyle | `/activity-level` | `activity_level` |
| 4. Target & pace | `/target-pace` | `target_weight_kg` + weekly gain pace |
| 5. Reveal & commit | `/plan` | *(nothing)* — calculates, then writes the row |

Nothing is persisted until step 5. Sign-in creates only the auth session; the
public `users` row is written once, at the end, with `onboarding_completed = true`.

### The calorie engine

`lib/core/calorie_engine.dart`. BMR uses Mifflin-St Jeor:

```
male:   10*kg + 6.25*cm - 5*age + 5
female: 10*kg + 6.25*cm - 5*age - 161
other:  10*kg + 6.25*cm - 5*age - 78    // average of the two constants
```

Then `TDEE = BMR * activity multiplier` (1.2 / 1.375 / 1.55 / 1.725 / 1.9), and a
surplus derived from the chosen pace at 7,700 kcal per kg. The target is rounded
to the nearest 10.

Macros: protein at 1.8 g/kg bodyweight, fat at 25% of calories, carbs take the
remainder.

The weekly pace is **not stored** — there's no column for it. It exists only to
derive `daily_calorie_target`.

### Units

`height_cm` and `current_weight_kg` are always stored in metric. The
metric/imperial toggle is a display preference, recorded in `units`, and imperial
values are converted at the edge in `lib/core/unit_converter.dart`.

### Usernames

`users.username` is `NOT NULL UNIQUE`, but no OAuth provider supplies one. The
app derives a handle from the display name or email local-part and pre-fills it
on step 2, where the user can overwrite it.

The inline availability check is a **hint only**: depending on the RLS policy on
`users`, the client may not be able to see other users' rows, in which case every
handle looks free. The authority is the unique constraint —
`UserRepository.completeOnboarding` catches SQLSTATE `23505` and either re-rolls
a generated handle or surfaces "already taken" for one the user typed. Adding a
`SECURITY DEFINER` RPC (`is_username_available(text)`) would make the hint
reliable; the retry path is correct either way.

## Supabase setup

Connection settings live in `lib/core/config/supabase_config.dart`. The
publishable key is the successor to the `anon` key: it is designed to ship inside
the client bundle and is **not a secret** — Row Level Security is what protects
the data. Override per build if needed:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_KEY=sb_publishable_...
```

### OAuth: two different redirect URLs

Sign-in makes two hops, and each needs its own URL configured in a different
place. Conflating them is the usual reason sign-in finishes in the browser and
never returns to the app.

```
app ──▶ Google / Apple ──▶ https://<ref>.supabase.co/auth/v1/callback ──▶ app
        └── hop 1 ──────────────────┘                    └─── hop 2 ───┘
```

**Hop 1 — provider back to Supabase.** Set in the provider's own console:

- Google Cloud → Credentials → your **Web** OAuth client → *Authorized redirect URIs*
- Apple Developer → Identifiers → your **Services ID** → *Return URLs*

Both get:

```
https://<your-project-ref>.supabase.co/auth/v1/callback
```

**Hop 2 — Supabase back to the app.** Set in the Supabase dashboard under
**Authentication → URL Configuration → Redirect URLs**:

```
com.alimahmoud.bulkr://login-callback
```

That second string appears in three places in this repo and all three must
agree:

- `SupabaseConfig.oauthRedirectUrl`
- `android/app/src/main/AndroidManifest.xml` (the `VIEW` intent-filter)
- `ios/Runner/Info.plist` (`CFBundleURLTypes`)

The scheme is the app's bundle ID, per RFC 8252 — an arbitrary short scheme can
be claimed by any other app on the device.

Also enable both providers under **Authentication → Providers**, with the Google
client ID/secret and the Apple Services ID, Team ID, Key ID and `.p8` contents.

### Native sign-in (later)

The current flow is browser-based `signInWithOAuth`, so the app bundle carries
**no provider credentials at all** — everything lives server-side in Supabase.

For App Store submission, Apple expects the native Sign in with Apple sheet
rather than a browser hand-off. That means adding `sign_in_with_apple` and
switching to `signInWithIdToken`. Going native for Google likewise needs
`google_sign_in` plus the Android OAuth client ID (the one tied to your debug
keystore's SHA-1) and an iOS client ID. Client IDs are public identifiers; the
client *secret* stays in Supabase either way.

### Database

The schema is expected to exist already, including RLS policies. Onboarding
writes to two tables:

- `users` — one upsert keyed on `id`
- `weight_logs` — one seed row with the starting weight, so the progress chart
  has a day-one anchor. This insert is deliberately non-fatal: the account is
  already usable if it fails.

## Tests

```bash
flutter test
```

Pure-Dart unit tests over the calorie engine, unit conversions and username
generation. No widget pumping — they're fast and they cover the logic most
likely to be wrong.

## Known placeholder

`/home` is a stub. It confirms the plan was saved and displays the committed
targets; the real dashboard (food logging, progress, feed) is separate work.
