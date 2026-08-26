# `food-search` — the FatSecret tier

Tier 2 of the ingredient search. It exists as a function rather than as app code
for one reason: **the FatSecret client secret cannot ship in the app.** An `.apk`
is a zip file, and pulling strings out of one takes about a minute.

## Deploy

```bash
supabase functions deploy food-search
supabase secrets set FATSECRET_CLIENT_ID=... FATSECRET_CLIENT_SECRET=...
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected by the platform —
do not set them yourself.

Get the credentials from the FatSecret Platform console under *Manage
Applications → API Credentials*. Note that FatSecret's free tier may also
require IP allow-listing; if so, allow-list the Supabase egress addresses, not a
device.

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
