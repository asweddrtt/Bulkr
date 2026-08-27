// USDA FoodData Central: search, and the mapping from their nutrient arrays to
// per-100g numbers.
//
// Chosen over FatSecret because FatSecret refuses OAuth 2.0 until an IP is
// whitelisted, and a Supabase edge function's egress address changes call to
// call — four consecutive probes came back 16.63.101.218, 16.18.174.25,
// 51.96.17.101, 16.18.17.167. There is no whitelist entry that can cover that.
// FoodData Central authenticates with a plain key and restricts nothing by
// address. Its Foundation and SR Legacy datasets are also better at plain food
// than a barcode catalogue is, which is the gap that made "boiled eggs" return
// a chocolate one.
//
// Nothing here imports Deno, so the parsing can be exercised directly:
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

const SEARCH_URL = "https://api.nal.usda.gov/fdc/v1/foods/search";

/**
 * Foundation and SR Legacy are the curated whole foods — the reason this tier
 * is worth having. Branded is included for everything else, and Survey is left
 * out: it is dietary-recall data, full of composite entries like "Chicken,
 * coated, fried, from restaurant" that are not things anyone puts in a recipe.
 */
const DATA_TYPES = ["Foundation", "SR Legacy", "Branded"];

/** Used when a food has no GTIN of its own — see [barcodeFor]. */
export const BARCODE_PREFIX = "usda-";

/**
 * FoodData Central nutrient ids. Stable across datasets, unlike the names,
 * which vary ("Carbohydrate, by difference" against "Carbohydrates").
 */
const NUTRIENT = {
  protein: [1003],
  fat: [1004],
  carbs: [1005],
  /** Preferred first: kcal, then the Atwater variants, then kJ. */
  energyKcal: [1008, 2047, 2048],
  energyKj: [1062],
};

export async function searchFoods(
  apiKey: string,
  query: string,
  maxResults: number,
): Promise<NormalisedFood[]> {
  const url = new URL(SEARCH_URL);
  url.searchParams.set("api_key", apiKey);

  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      query,
      dataType: DATA_TYPES,
      pageSize: maxResults,
      // Their own relevance, which is decent. The app re-ranks everything
      // against the query afterwards regardless.
      sortBy: "dataType.keyword",
      sortOrder: "asc",
    }),
  });

  if (!response.ok) {
    throw new Error(
      `FoodData Central search failed: ${response.status} ${await response.text()}`,
    );
  }

  return normaliseSearchResponse(await response.json());
}

export function normaliseSearchResponse(body: unknown): NormalisedFood[] {
  const foods = (body as Record<string, any>)?.foods;
  if (!Array.isArray(foods)) return [];

  return foods
    .map(normaliseFood)
    .filter((food): food is NormalisedFood => food !== null);
}

/** One `foods` entry, or null when it cannot be expressed per 100g. */
export function normaliseFood(food: any): NormalisedFood | null {
  const description = `${food?.description ?? ""}`.replace(/\s+/g, " ").trim();
  if (!description) return null;

  const nutrients = Array.isArray(food?.foodNutrients) ? food.foodNutrients : [];

  const calories = energyKcalPer100g(nutrients);
  // Energy is the one figure a food cannot be logged without.
  if (calories === null || calories <= 0) return null;

  const barcode = barcodeFor(food);
  if (!barcode) return null;

  return {
    barcode,
    product_name: description,
    brand_name: brandFor(food),
    calories_100g: round(calories),
    protein_100g: round(readNutrient(nutrients, NUTRIENT.protein) ?? 0),
    carbs_100g: round(readNutrient(nutrients, NUTRIENT.carbs) ?? 0),
    fat_100g: round(readNutrient(nutrients, NUTRIENT.fat) ?? 0),
    serving_size_g: servingGrams(food),
  };
}

/**
 * The identity this food is merged on.
 *
 * A branded product's real GTIN is used when it has one, so a USDA entry and an
 * Open Food Facts entry for the same tin of beans collapse to one row instead
 * of appearing twice. Whole foods have no barcode to borrow and fall back to
 * the FoodData Central id, prefixed so it cannot collide with a real GTIN.
 */
export function barcodeFor(food: any): string | null {
  const gtin = `${food?.gtinUpc ?? ""}`.trim();
  if (/^\d{8,14}$/.test(gtin)) return gtin;

  const id = `${food?.fdcId ?? ""}`.trim();
  return id ? `${BARCODE_PREFIX}${id}` : null;
}

/**
 * Null for Foundation and SR Legacy entries, which are generic foods with no
 * brand — and being unbranded is what earns them their ranking bonus in the
 * app, so this must not invent one.
 */
export function brandFor(food: any): string | null {
  const brand = `${food?.brandName ?? food?.brandOwner ?? ""}`.trim();
  return brand === "" ? null : brand;
}

/** The stated serving, but only when it is stated in grams. */
export function servingGrams(food: any): number | null {
  const unit = `${food?.servingSizeUnit ?? ""}`.trim().toLowerCase();
  // Millilitres are taken as grams: a few percent out for drinks, and better
  // than dropping the serving for every liquid.
  if (unit !== "g" && unit !== "ml") return null;

  const size = Number(food?.servingSize);
  return Number.isFinite(size) && size > 0 ? size : null;
}

/**
 * A nutrient's per-100g value.
 *
 * Two response shapes to survive: the search endpoint flattens each entry to
 * `{nutrientId, value}`, while the detail endpoint nests it as
 * `{nutrient: {id}, amount}`. Both turn up in the wild.
 */
export function readNutrient(nutrients: any[], ids: number[]): number | null {
  for (const id of ids) {
    for (const entry of nutrients) {
      const entryId = Number(entry?.nutrientId ?? entry?.nutrient?.id);
      if (entryId !== id) continue;

      const value = Number(entry?.value ?? entry?.amount);
      if (Number.isFinite(value)) return value;
    }
  }
  return null;
}

/**
 * Energy in kcal, from whichever field the food carries.
 *
 * Some entries declare only kilojoules, which are converted at 4.184 rather
 * than dropped.
 */
export function energyKcalPer100g(nutrients: any[]): number | null {
  const kcal = readNutrient(nutrients, NUTRIENT.energyKcal);
  if (kcal !== null && kcal > 0) return kcal;

  const kj = readNutrient(nutrients, NUTRIENT.energyKj);
  return kj !== null && kj > 0 ? kj / 4.184 : null;
}

function round(value: number): number {
  return Math.round(value * 100) / 100;
}
