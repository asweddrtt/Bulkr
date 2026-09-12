# verify-purchase

Turns a store receipt into a row in `subscriptions`. Called by the app the
moment a purchase completes, and again on "restore purchases".

**The app cannot write `subscriptions`.** There is no insert policy on it — see
`supabase/premium.sql` — so a purchase becomes premium here or it does not
become premium at all.

## What is trusted

Nothing in the request body.

| Platform | What happens |
|---|---|
| iOS | The client's signed transaction is opened only far enough to read a transaction id. Apple is then asked what that transaction actually is, over TLS, authenticated with our own ES256 token. |
| Android | The purchase token is sent straight to Google, which answers with the subscription's real state. |

A forged receipt therefore buys nothing: the worst it can name is a transaction
that does not exist, or one belonging to somebody else — and the second is
closed by `subscriptions.store_id` being unique, so a purchase already attached
to an account cannot be moved to another. That case answers **409
`already_claimed`**, which is nearly always somebody with two accounts on one
phone rather than an attack, and the app says so.

The user id comes from the verified JWT and never from the body, exactly as in
`delete-account`. A body parameter there would make this "make any account you
can name premium".

### Why Apple's signature is not checked locally

It could be. It would mean fetching, caching and rotating Apple's certificate
chain, and it would prove the same thing that asking Apple directly proves. The
client's blob is treated as a hint; every fact written to the database comes
out of Apple's own answer.

## Setup

### Apple — four values

From **App Store Connect → Users and Access → Integrations → In-App Purchase**:

1. Create an in-app purchase key. Download the `.p8` **once** — it cannot be
   downloaded again.
2. `APPLE_KEY_ID` — the key's id, next to it in the list.
3. `APPLE_ISSUER_ID` — at the top of that page, the same for every key.
4. `APPLE_PRIVATE_KEY` — the contents of the `.p8`, `-----BEGIN` line and all.
5. `APPLE_BUNDLE_ID` — `com.alimahmoud.bulkr`.

Both environments are tried, production first. Apple does not say which one a
receipt belongs to, and TestFlight buys in sandbox against the same binary — so
a production-only check works until the first person tests it.

### Google — three values

From **Google Cloud console**, for the project linked to Play:

1. Create a service account, then a JSON key for it.
2. `GOOGLE_SERVICE_ACCOUNT_EMAIL` — `client_email` from that JSON.
3. `GOOGLE_SERVICE_ACCOUNT_KEY` — `private_key` from that JSON.
4. `GOOGLE_PLAY_PACKAGE` — `com.alimahmoud.bulkr`.

Then in **Play Console → Users and permissions**, invite that service account
and grant it **View financial data** — without it the API answers 401 and every
Android purchase fails to verify.

### The secrets

Put them in a file rather than on a command line; a secret in an argument goes
into the shell history on disk.

```sh
supabase link --project-ref hqdfaeiyflbbzkduskaz

cat > .env <<'ENV'
APPLE_KEY_ID=...
APPLE_ISSUER_ID=...
APPLE_BUNDLE_ID=com.alimahmoud.bulkr
APPLE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----
...
-----END PRIVATE KEY-----"
GOOGLE_PLAY_PACKAGE=com.alimahmoud.bulkr
GOOGLE_SERVICE_ACCOUNT_EMAIL=...
GOOGLE_SERVICE_ACCOUNT_KEY="-----BEGIN PRIVATE KEY-----
...
-----END PRIVATE KEY-----"
ENV

supabase secrets set --env-file .env
rm .env
```

The PEM keys keep their line breaks here. If whatever you paste them into turns
those into a literal `\n` instead, that is handled — `jwt.ts` restores them, and
a test covers it, because it is the single most common way this is
misconfigured.

### Deploy

```sh
supabase functions deploy verify-purchase
```

The caller's JWT is verified by the platform, so only signed-in users reach it.

## The tests

```sh
node --experimental-strip-types supabase/functions/verify-purchase/jwt.test.ts
```

They cover the half that can be tested without a store account: base64url,
reading a JWS, and that each signed token verifies against its own key with the
claims the store checks. That last one matters more than it sounds — a
malformed signature makes *every* purchase fail to verify, and both stores
report it as a bare 401, which looks exactly like nobody buying anything.

## What counts as premium

Deliberately more generous than "status is active":

| Store | Also counted |
|---|---|
| Apple | billing retry (3) and grace period (4) |
| Google | `IN_GRACE_PERIOD`, and `CANCELED` while the paid period still runs |

A card declined once should not take the app away mid-retry — that is how a
temporary problem becomes a cancellation. And "cancelled" in Play means "will
not renew", not "has ended": somebody who cancelled on day two of a year has
paid for the year.

## What this does not do yet

**Server notifications.** Apple's App Store Server Notifications V2 and Google's
Real-time Developer Notifications are what tell the backend that a subscription
renewed, lapsed, or was refunded *without the app being opened*. Until they are
wired up, a lapsed subscription is only noticed the next time the app calls
this — which for somebody who has stopped opening it is never, and the row
keeps saying premium until `expires_at` passes.

`expires_at` is why that is survivable rather than a hole: `is_premium()`
checks the clock, so an un-refreshed row degrades on its own. What is genuinely
missed is a **refund**, which revokes access with no date change. Worth adding
before there are enough subscribers for one refund to matter.

## Reading the logs

`supabase functions logs verify-purchase`, while buying in a sandbox account.

| What the log says | What it means |
|---|---|
| `premium: true` | working |
| `APPLE_KEY_ID / ... are not set` | `supabase secrets set` did not take |
| `App Store Server API 401` | the key, key id or issuer id is wrong — or the `.p8` lost a line |
| `transaction not found in either environment` | the receipt is not Apple's, or the bundle id does not match the key |
| `Google OAuth 400` | the service account key is wrong |
| `Play Developer API 401` | the service account was never invited in Play Console |
| `store_id already claimed` | this purchase belongs to another account — a 409, not an error |
