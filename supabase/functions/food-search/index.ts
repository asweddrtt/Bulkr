// Tier 2 of the ingredient search: USDA FoodData Central, behind a function.
//
// It runs here rather than on the device so the API key is not shipped in the
// binary — an .apk is a zip, and pulling strings out of one takes a minute.
// Two things fall out of that which are worth having anyway:
//
//   * Results are written to `cached_off_foods` with the service role, so every
//     user's search warms tier 1 for everyone and the app needs no write access
//     to that shared table.
//   * Results come back already carrying their cache id, so a meal can
//     reference an ingredient without a further round trip.
//
// Deploy:
//   supabase link --project-ref hqdfaeiyflbbzkduskaz
//   supabase functions deploy food-search
//
// The key is free from https://fdc.nal.usda.gov/api-key-signup.html and is set
// as USDA_API_KEY. SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by
// the platform.
//
// The caller's JWT is verified by default, so only signed-in users reach this.

import { type NormalisedFood, searchFoods } from "./usda.ts";

const MAX_RESULTS = 25;

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

    const apiKey = Deno.env.get("USDA_API_KEY");

    if (body?.diagnose === true) return json(await diagnose(apiKey));

    if (term.length < 2) return json({ foods: [] });

    if (!apiKey) {
      // A missing key is a deployment mistake, not a user-facing failure. The
      // app treats an errored tier as an empty one and falls through to Open
      // Food Facts, so searching still works while this is sorted out.
      console.error("USDA_API_KEY is not set");
      return json({ foods: [], error: "not_configured" });
    }

    const foods = await searchFoods(apiKey, term, MAX_RESULTS);
    if (foods.length === 0) return json({ foods: [] });

    return json({ foods: await cacheFoods(foods) });
  } catch (error) {
    console.error("food-search failed:", error);
    // Same reasoning: a 200 with nothing in it keeps the client's cascade
    // moving to the next tier instead of surfacing a third party's outage.
    return json({ foods: [], error: `${error}` });
  }
});

/**
 * Answers "is tier 2 actually working?" without revealing the key.
 *
 * Worth having because the failure mode is silent by design: a misconfigured
 * function returns an empty list and the app falls through to Open Food Facts,
 * so tier 2 can be dead for weeks and look like nothing more than a quiet
 * search.
 */
async function diagnose(apiKey: string | undefined): Promise<
  Record<string, unknown>
> {
  const result: Record<string, unknown> = {
    provider: "usda-fooddata-central",
    configured: Boolean(apiKey),
    // Length, never the value — enough to spot a key truncated by a shell
    // splitting on a space, useless to whoever reads the output.
    apiKeyLength: apiKey?.length ?? 0,
  };

  if (!apiKey) {
    result.searchOk = false;
    result.detail = "USDA_API_KEY is not set";
    return result;
  }

  try {
    // A real search rather than a ping: it exercises the key, the request shape
    // and the parsing in one go, which is what "working" actually means here.
    const foods = await searchFoods(apiKey, "rice", 5);
    result.searchOk = true;
    result.resultCount = foods.length;

    // FoodData Central's own order, NOT the order anyone sees. Ranking against
    // the query happens in the app, after these are merged with the cached and
    // Open Food Facts tiers — so a branded "RICE" sitting at the top here is
    // normal and says nothing about what the search will show. This field is
    // for confirming the tier returns plausible food at all.
    result.unrankedSample = foods.map((food) => food.product_name);
  } catch (error) {
    result.searchOk = false;
    // FoodData Central's own words. An invalid key says so plainly, and
    // OVER_RATE_LIMIT is the hourly cap rather than anything misconfigured.
    result.detail = `${error}`;
  }

  return result;
}

/**
 * Upserts into `cached_off_foods` and returns the stored rows.
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
