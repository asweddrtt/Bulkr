// Tier 2 of the ingredient search: FatSecret, behind a function.
//
// It runs here rather than on the device for one non-negotiable reason: the
// FatSecret client secret. It is a real credential, and anything shipped in a
// mobile binary is public — an .apk is a zip, and pulling strings out of one
// takes a minute. So the secret stays in the function's environment and the
// device never sees it.
//
// Two things fall out of that which are worth having anyway:
//
//   * The OAuth token is fetched once per warm isolate instead of once per
//     device, so a 24-hour token is actually used for 24 hours.
//   * Results are written to `cached_off_foods` here, with the service role.
//     That means every user's search warms the cache for everyone, and the
//     client needs no insert rights on that shared table for FatSecret foods.
//
// Deploy:
//   supabase functions deploy food-search
//   supabase secrets set FATSECRET_CLIENT_ID=... FATSECRET_CLIENT_SECRET=...
//
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by the platform.
//
// The caller's JWT is verified by default, so only signed-in users reach this.

import {
  getAccessToken,
  type NormalisedFood,
  resetToken,
  searchFoods,
} from "./fatsecret.ts";

const MAX_RESULTS = 20;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const body = await request.json();
    const term = `${body?.query ?? ""}`.trim();

    const clientId = Deno.env.get("FATSECRET_CLIENT_ID");
    const clientSecret = Deno.env.get("FATSECRET_CLIENT_SECRET");

    if (body?.diagnose === true) {
      return json(await diagnose(clientId, clientSecret));
    }

    if (term.length < 2) return json({ foods: [] });

    if (!clientId || !clientSecret) {
      // A missing secret is a deployment mistake, not a user-facing failure.
      // The app treats an errored tier as an empty one and falls through to
      // Open Food Facts, so searching still works while this is sorted out.
      console.error("FATSECRET_CLIENT_ID / _SECRET are not set");
      return json({ foods: [], error: "not_configured" }, 200);
    }

    const token = await getAccessToken(clientId, clientSecret);
    const foods = await searchFoods(token, term, MAX_RESULTS);

    if (foods.length === 0) return json({ foods: [] });

    return json({ foods: await cacheFoods(foods) });
  } catch (error) {
    console.error("food-search failed:", error);
    // Same reasoning: a 200 with nothing in it keeps the client's cascade
    // moving to the next tier instead of surfacing a third party's outage.
    return json({ foods: [], error: `${error}` }, 200);
  }
});

/**
 * Answers "is tier 2 actually working?" without revealing anything.
 *
 * Worth having because the failure mode here is silent by design: a
 * misconfigured function returns an empty list and the app falls through to
 * Open Food Facts, so tier 2 can be dead for weeks and look like nothing more
 * than a quiet search.
 *
 * Lengths, never values. A secret pasted with a typo, or truncated by a shell
 * that split it on a space, is the likeliest thing to be wrong, and a length is
 * enough to see that while being useless to anyone who reads it. A FatSecret
 * client id and secret are both 32 hex characters.
 */
async function diagnose(
  clientId: string | undefined,
  clientSecret: string | undefined,
): Promise<Record<string, unknown>> {
  const result: Record<string, unknown> = {
    configured: Boolean(clientId && clientSecret),
    clientIdLength: clientId?.length ?? 0,
    clientSecretLength: clientSecret?.length ?? 0,
    expectedLength: 32,
  };

  if (!clientId || !clientSecret) {
    result.tokenOk = false;
    result.detail = "FATSECRET_CLIENT_ID / _SECRET are not both set";
    return result;
  }

  try {
    // Forces a real exchange rather than reusing a cached token, so this
    // reports the state of the credentials now.
    resetToken();
    await getAccessToken(clientId, clientSecret);
    result.tokenOk = true;
    return result;
  } catch (error) {
    result.tokenOk = false;
    // FatSecret's own words. `invalid_client` means the pair was rejected;
    // anything mentioning the IP is an allow-list problem, and telling those
    // two apart is most of the point of asking.
    result.detail = `${error}`;
  }

  // Both values are 32 hex characters, so nothing about either one says which
  // is which — and setting them the wrong way round produces exactly the
  // `invalid_client` above. Rather than leave that to guesswork, try the swap
  // and say whether it works. Diagnose only; the search path never does this.
  try {
    resetToken();
    await getAccessToken(clientSecret, clientId);
    result.swappedWorks = true;
    result.detail =
      "The values are the right way round in FatSecret's eyes when swapped — " +
      "set FATSECRET_CLIENT_ID to what is currently the secret, and vice versa.";
  } catch (_) {
    result.swappedWorks = false;
  }

  // Leave no cached token behind from a failed probe.
  resetToken();

  return result;
}

/**
 * Upserts into `cached_off_foods` and returns the stored rows.
 *
 * Returning the rows rather than what we sent means the response carries each
 * food's cache id, so the app can reference it from a meal without a further
 * round trip — and without needing write access to the table.
 *
 * A failed cache write is not a failed search: the foods are still returned,
 * just without ids, and the app falls back to caching them itself.
 */
async function cacheFoods(foods: NormalisedFood[]): Promise<unknown[]> {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return foods;

  const now = new Date().toISOString();
  const rows = foods.map((food) => ({ ...food, last_fetched_at: now }));

  try {
    const response = await fetch(
      `${url}/rest/v1/cached_off_foods?on_conflict=barcode`,
      {
        method: "POST",
        headers: {
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
          "Content-Type": "application/json",
          Prefer: "resolution=merge-duplicates,return=representation",
        },
        body: JSON.stringify(rows),
      },
    );

    if (!response.ok) {
      console.error(`cache upsert failed: ${response.status}`);
      return foods;
    }

    return await response.json();
  } catch (error) {
    console.error("cache upsert failed:", error);
    return foods;
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}
