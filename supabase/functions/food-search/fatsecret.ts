// FatSecret: token handling, search, and the awkward part — turning their
// human-readable nutrition string into per-100g numbers.
//
// Everything here is pure or network-only, with no Deno or Supabase imports, so
// the parser below can be exercised directly:
//
//   node --experimental-strip-types supabase/functions/food-search/parser.test.ts

/** A food normalised to the shape `cached_off_foods` stores. */
export interface NormalisedFood {
  barcode: string;
  product_name: string;
  brand_name: string | null;
  calories_100g: number;
  protein_100g: number;
  carbs_100g: number;
  fat_100g: number;
  serving_size_g: number | null;
}

const TOKEN_URL = "https://oauth.fatsecret.com/connect/token";
const API_URL = "https://platform.fatsecret.com/rest/server.api";

/**
 * FatSecret ids are not barcodes, and `cached_off_foods.barcode` is the key
 * everything is merged on. The prefix keeps them from ever colliding with a
 * real GTIN (digits) or with the curated `bulkr-` rows.
 */
export const BARCODE_PREFIX = "fs-";

/**
 * Access tokens last 24 hours, so one is kept for the life of the isolate.
 * Edge functions stay warm between invocations, which turns the token call
 * from once-per-search into roughly once-per-day.
 */
let cachedToken: { value: string; expiresAt: number } | null = null;

export async function getAccessToken(
  clientId: string,
  clientSecret: string,
  now: number = Date.now(),
): Promise<string> {
  // Sixty seconds of slack, so a token that expires mid-flight is renewed
  // before it is used rather than after it fails.
  if (cachedToken && cachedToken.expiresAt > now + 60_000) {
    return cachedToken.value;
  }

  const credentials = btoa(`${clientId}:${clientSecret}`);

  const response = await fetch(TOKEN_URL, {
    method: "POST",
    headers: {
      Authorization: `Basic ${credentials}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: "grant_type=client_credentials&scope=basic",
  });

  if (!response.ok) {
    throw new Error(
      `FatSecret token request failed: ${response.status} ${await response.text()}`,
    );
  }

  const body = await response.json();
  const token = body.access_token;
  if (typeof token !== "string") throw new Error("FatSecret returned no token");

  const lifetimeMs = (Number(body.expires_in) || 86_400) * 1000;
  cachedToken = { value: token, expiresAt: now + lifetimeMs };

  return token;
}

/** Clears the cached token. Only used by tests. */
export function resetToken(): void {
  cachedToken = null;
}

export async function searchFoods(
  token: string,
  query: string,
  maxResults: number,
): Promise<NormalisedFood[]> {
  const url = new URL(API_URL);
  url.searchParams.set("method", "foods.search");
  url.searchParams.set("search_expression", query);
  url.searchParams.set("max_results", `${maxResults}`);
  url.searchParams.set("format", "json");

  const response = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });

  if (!response.ok) {
    throw new Error(`FatSecret search failed: ${response.status}`);
  }

  return normaliseSearchResponse(await response.json());
}

/**
 * Reads FatSecret's search payload.
 *
 * Two shapes to survive: `foods.food` is an array for several results and a
 * bare object for exactly one, which is a classic way to crash a client on the
 * day a query happens to match a single food.
 */
export function normaliseSearchResponse(body: unknown): NormalisedFood[] {
  const foods = (body as Record<string, any>)?.foods?.food;
  if (!foods) return [];

  const list: any[] = Array.isArray(foods) ? foods : [foods];

  return list
    .map(normaliseFood)
    .filter((food): food is NormalisedFood => food !== null);
}

/** One `food` entry, or null when it cannot be expressed per 100g. */
export function normaliseFood(food: any): NormalisedFood | null {
  const id = `${food?.food_id ?? ""}`.trim();
  const name = `${food?.food_name ?? ""}`.replace(/\s+/g, " ").trim();
  if (!id || !name) return null;

  const nutrition = parseFoodDescription(`${food?.food_description ?? ""}`);
  if (!nutrition) return null;

  const brand = `${food?.brand_name ?? ""}`.trim();

  return {
    barcode: `${BARCODE_PREFIX}${id}`,
    product_name: name,
    brand_name: brand === "" ? null : brand,
    calories_100g: nutrition.calories,
    protein_100g: nutrition.protein,
    carbs_100g: nutrition.carbs,
    fat_100g: nutrition.fat,
    serving_size_g: nutrition.servingSizeG,
  };
}

export interface ParsedNutrition {
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  /** The stated serving in grams, when it was stated in grams. */
  servingSizeG: number | null;
}

/**
 * Turns FatSecret's `food_description` into per-100g figures.
 *
 * The string looks like one of:
 *
 *   Per 100g - Calories: 130kcal | Fat: 0.28g | Carbs: 28.17g | Protein: 2.69g
 *   Per 1 serving (28g) - Calories: 140kcal | Fat: 7.00g | ...
 *   Per 1 cup cooked - Calories: 205kcal | Fat: 0.44g | ...
 *
 * The first two carry a gram basis and can be rescaled. The third cannot: there
 * is no honest way to turn "1 cup cooked" into grams, and guessing would put a
 * wrong number into someone's daily total under the appearance of a measured
 * one. Those entries are dropped.
 *
 * Millilitres are accepted as grams. That is an approximation — milk at 100ml
 * is about 103g — but it is within a few percent for the drinks this affects,
 * and rejecting it would drop every liquid FatSecret knows about.
 */
export function parseFoodDescription(
  description: string,
): ParsedNutrition | null {
  const text = description.replace(/\s+/g, " ").trim();
  if (!text) return null;

  const separator = text.indexOf(" - ");
  if (separator < 0) return null;

  const serving = text.slice(0, separator).replace(/^per\s+/i, "").trim();
  const nutrients = text.slice(separator + 3);

  const grams = servingGrams(serving);
  if (grams === null || grams <= 0) return null;

  const calories = readNutrient(nutrients, "Calories");
  const protein = readNutrient(nutrients, "Protein");
  const carbs = readNutrient(nutrients, "Carbs");
  const fat = readNutrient(nutrients, "Fat");

  // Energy is the one figure a food cannot be logged without.
  if (calories === null) return null;

  const factor = 100 / grams;
  const round = (value: number) => Math.round(value * 100) / 100;

  return {
    calories: round(calories * factor),
    protein: round((protein ?? 0) * factor),
    carbs: round((carbs ?? 0) * factor),
    fat: round((fat ?? 0) * factor),
    servingSizeG: grams,
  };
}

/** Grams described by a serving phrase, or null when it is not weighable. */
export function servingGrams(serving: string): number | null {
  // "100g", "100 g", "250ml"
  const direct = serving.match(/^(\d+(?:\.\d+)?)\s*(g|ml)$/i);
  if (direct) return Number(direct[1]);

  // "1 serving (28g)", "1 cup (158 g)"
  const parenthesised = serving.match(/\((\d+(?:\.\d+)?)\s*(g|ml)\)/i);
  if (parenthesised) return Number(parenthesised[1]);

  return null;
}

/** `Calories: 130kcal`, `Fat: 0.28g` — the unit varies and is not needed. */
export function readNutrient(text: string, label: string): number | null {
  const match = text.match(
    new RegExp(`${label}\\s*:\\s*(\\d+(?:\\.\\d+)?)`, "i"),
  );
  return match ? Number(match[1]) : null;
}
