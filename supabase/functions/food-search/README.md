# `food-search` — the FatSecret tier

Tier 2 of the ingredient search. It exists as a function rather than as app code
for one reason: **the FatSecret client secret cannot ship in the app.** An `.apk`
is a zip file, and pulling strings out of one takes about a minute.

## Deploy

This repo has more than one Supabase project reachable from the CLI, and the
Bulkr one is **`hqdfaeiyflbbzkduskaz`** — the same ref as the URL in
`lib/core/config/supabase_config.dart`. Link it once so neither command has to
guess:

```bash
supabase link --project-ref hqdfaeiyflbbzkduskaz
supabase functions deploy food-search
```

Until that link exists the CLI picks a project for you, and deploying to the
wrong one fails with `Cannot retrieve service for project ... status 'INACTIVE'`.
Pass `--project-ref hqdfaeiyflbbzkduskaz` on each command if you would rather not
link.

`WARNING: Docker is not running` is harmless here — deploys upload the source and
build server-side. If the assets are listed as uploading, Docker was not the
problem.

### Secrets

The client secret is the one credential in this project that must not be
published, so keep it out of shell history and out of anywhere it gets pasted.
Easiest safe route is the dashboard:

*Project Settings → Edge Functions → Secrets → Add new secret*

Or from a file the repo already ignores:

```bash
printf 'FATSECRET_CLIENT_ID=...\nFATSECRET_CLIENT_SECRET=...\n' > supabase/.env
supabase secrets set --env-file supabase/.env
```

If you do use the inline form, beware that the shell splits on spaces: a stray
word in the middle of the line silently truncates the value at the first space,
and `secrets set` reports success either way. `diagnose` below catches exactly
that.

`supabase secrets list` shows digests rather than values, so there is no reading
them back.

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected by the platform — do
not set them yourself.

Get the credentials from the FatSecret Platform console under *Manage
Applications → API Credentials*. Note that FatSecret's free tier may also
require IP allow-listing; if so, allow-list the Supabase egress addresses, not a
device.

## Is it actually working?

The failure mode is silent by design — an errored tier is an empty tier, and the
app falls through to Open Food Facts — so tier 2 can be dead and look like
nothing worse than a quiet search. Ask it directly:

```bash
curl -X POST "https://hqdfaeiyflbbzkduskaz.supabase.co/functions/v1/food-search" \
  -H "Authorization: Bearer <your publishable key>" \
  -H "Content-Type: application/json" \
  -d '{"diagnose": true}'
```

```json
{ "configured": true, "clientIdLength": 32, "clientSecretLength": 32,
  "expectedLength": 32, "tokenOk": true }
```

Lengths, never values — enough to spot a truncated or mistyped secret while
being useless to anyone who reads the output. Both should be 32.

`tokenOk: false` comes with FatSecret's own words in `detail`: `invalid_client`
is a wrong secret, anything mentioning the IP is the allow-list.

There is no `supabase functions logs` subcommand in CLI v2 — read logs in the
dashboard under *Edge Functions → food-search → Logs*.

## Test the parser

The awkward part is FatSecret's `food_description`, a human-readable string that
has to become per-100g numbers. It is isolated in `fatsecret.ts` with no Deno
imports so it can be run directly:

```bash
node --experimental-strip-types supabase/functions/food-search/parser.test.ts
```

## What it does

1. Exchanges the client credentials for an access token, and keeps it for the
   life of the isolate — they last 24 hours, so a warm function fetches roughly
   one a day rather than one per search.
2. Calls `foods.search`, and normalises each result to the shape
   `cached_off_foods` stores. Entries whose serving has no weight (`Per 1 cup
   cooked`) are **dropped**: there is no honest way to turn that into grams, and
   a guess would put a wrong number into someone's daily total looking exactly
   like a measured one.
3. Upserts the results into `cached_off_foods` with the service role, and
   returns the stored rows. So every search warms tier 1 for every user, results
   come back already carrying their cache id, and the app needs no write access
   to that shared table for FatSecret foods.

## Failure behaviour

It answers `200` with `{"foods": [], "error": "..."}` on any failure, including a
missing secret. That is deliberate: the app's search is a cascade, and an errored
tier should be an empty tier so the next one is tried. A `500` here would surface
a third party's outage as a broken search.

Check the logs (`supabase functions logs food-search`) if tier 2 is quietly
returning nothing — `not_configured` means the secrets were never set.

## Why Open Food Facts is *not* proxied here

Its rate limit is **per IP**. Behind a function every user in the app would share
one address, and therefore one budget of ten searches a minute between all of
them. Called from the device it is ten a minute *each*. Tier 3 stays on the
client, with `RateLimiter` keeping each device under its own budget.
