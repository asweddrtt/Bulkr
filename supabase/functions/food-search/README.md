# `food-search` — the hosted food database tier

Tier 2 of the ingredient search, backed by **USDA FoodData Central**.

It exists as a function rather than as app code so the API key is not shipped in
the binary — an `.apk` is a zip file, and pulling strings out of one takes about
a minute.

## Why not FatSecret

FatSecret was the first choice and does not work here. Its OAuth 2.0 endpoint
refuses every request until at least one IP address is whitelisted, and a
Supabase edge function's egress address changes from call to call — four
consecutive probes returned `16.63.101.218`, `16.18.174.25`, `51.96.17.101`,
`16.18.17.167`, not even in the same prefix. There is no whitelist entry that
covers that, and Supabase does not pin egress for functions.

It also cost a long debugging detour, because an un-whitelisted caller is
refused as `invalid_client` — indistinguishable from a wrong secret.

FoodData Central authenticates with a plain key and restricts nothing by
address. Its Foundation and SR Legacy datasets are also better at plain food
than a barcode catalogue is, which is the gap that made "boiled eggs" return a
chocolate one.

## Deploy

```bash
supabase link --project-ref hqdfaeiyflbbzkduskaz
supabase functions deploy food-search
```

Without the link the CLI picks a project for you, and deploying to the wrong one
fails with `Cannot retrieve service for project ... status 'INACTIVE'`.

`WARNING: Docker is not running` is harmless — deploys upload the source and
build server-side. If the assets are listed as uploading, Docker was not the
problem.

### The key

Free, instant, no card: <https://fdc.nal.usda.gov/api-key-signup.html>. The
default `api.data.gov` allowance is 1,000 requests an hour, shared across
everyone using the app — which is ample, because tier 1 answers most repeat
queries without reaching this function at all.

Set it from the dashboard (*Project Settings → Edge Functions → Secrets*), or
from a file the repo already ignores:

```bash
printf 'USDA_API_KEY=...\n' > supabase/.env
supabase secrets set --env-file supabase/.env
```

If you use the inline form, beware that the shell splits on spaces: a stray word
mid-line truncates the value at the first space, and `secrets set` reports
success either way. `apiKeyLength` below catches exactly that.

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected by the platform — do
not set them yourself.

## Is it actually working?

The failure mode is silent by design — an errored tier is an empty tier, and the
app falls through to Open Food Facts — so tier 2 can be dead and look like
nothing worse than a quiet search. Ask it directly.

**PowerShell** (`curl` there is an alias for `Invoke-WebRequest`, which takes
neither `-X` nor `-H`):

```powershell
Invoke-RestMethod `
  -Uri "https://hqdfaeiyflbbzkduskaz.supabase.co/functions/v1/food-search" `
  -Method Post `
  -Headers @{ Authorization = "Bearer <your publishable key>" } `
  -ContentType "application/json" `
  -Body (@{ diagnose = $true } | ConvertTo-Json)
```

**bash / zsh**:

```bash
curl -X POST "https://hqdfaeiyflbbzkduskaz.supabase.co/functions/v1/food-search" \
  -H "Authorization: Bearer <your publishable key>" \
  -H "Content-Type: application/json" \
  -d '{"diagnose": true}'
```

Working looks like:

```json
{ "provider": "usda-fooddata-central", "configured": true, "apiKeyLength": 40,
  "searchOk": true, "sampleCount": 5,
  "sample": "Rice, white, long-grain, regular, cooked, unenriched" }
```

It runs a real search for "rice" rather than a ping, so it exercises the key,
the request shape and the parsing together — which is what "working" means here.
The key's length is reported, never its value.

`searchOk: false` carries FoodData Central's own words in `detail`. An invalid
key says so plainly; `OVER_RATE_LIMIT` is the hourly cap rather than anything
misconfigured.

There is no `supabase functions logs` subcommand in CLI v2 — read logs in the
dashboard under *Edge Functions → food-search → Logs*.

## Test the parser

The mapping from FoodData Central's nutrient arrays to per-100g numbers is
isolated in `usda.ts` with no Deno imports, so it can be run directly:

```bash
node --experimental-strip-types supabase/functions/food-search/parser.test.ts
```

## What it does

1. Searches Foundation, SR Legacy and Branded. Survey is excluded: it is
   dietary-recall data, full of composite entries like "Chicken, coated, fried,
   from restaurant" that nobody puts in a recipe.
2. Normalises each result to the shape `cached_off_foods` stores. Entries
   without an energy value are **dropped** rather than stored as zero calories,
   and a branded product is keyed on its real GTIN so it collapses together with
   the same product from Open Food Facts instead of appearing twice.
3. Upserts the results into `cached_off_foods` with the service role, and
   returns the stored rows. So every search warms tier 1 for every user, results
   arrive already carrying their cache id, and the app needs no write access to
   that shared table.

## Failure behaviour

It answers `200` with `{"foods": [], "error": "..."}` on any failure, including a
missing key. That is deliberate: the app's search is a cascade, and an errored
tier should be an empty tier so the next one is tried. A `500` here would surface
a third party's outage as a broken search.

## Why Open Food Facts is *not* proxied here

Its rate limit is **per IP**. Behind a function every user in the app would share
one address, and therefore one budget of ten searches a minute between all of
them. Called from the device it is ten a minute *each*. Tier 3 stays on the
client, with `RateLimiter` keeping each device under its own budget.
