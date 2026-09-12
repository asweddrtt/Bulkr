// Run: node --experimental-strip-types supabase/functions/food-search/parser.test.ts
import assert from "node:assert/strict";
import {
  barcodeFor,
  brandFor,
  energyKcalPer100g,
  normaliseFood,
  normaliseSearchResponse,
  readNutrient,
  servingGrams,
} from "./usda.ts";

let passed = 0;
function check(name: string, run: () => void) {
  try {
    run();
    passed++;
  } catch (error) {
    console.error(`FAIL  ${name}\n      ${error}`);
    process.exitCode = 1;
  }
}

/** The flattened shape the /foods/search endpoint returns. */
const RICE = {
  fdcId: 168878,
  description: "Rice, white, long-grain, regular, cooked, unenriched",
  dataType: "SR Legacy",
  foodNutrients: [
    { nutrientId: 1008, nutrientName: "Energy", unitName: "KCAL", value: 130 },
    { nutrientId: 1003, nutrientName: "Protein", unitName: "G", value: 2.69 },
    { nutrientId: 1005, nutrientName: "Carbohydrate, by difference", unitName: "G", value: 28.17 },
    { nutrientId: 1004, nutrientName: "Total lipid (fat)", unitName: "G", value: 0.28 },
  ],
};

check("a whole food becomes a cache row", () => {
  const food = normaliseFood(RICE);

  assert.equal(food?.product_name, "Rice, white, long-grain, regular, cooked, unenriched");
  assert.equal(food?.calories_100g, 130);
  assert.equal(food?.protein_100g, 2.69);
  assert.equal(food?.carbs_100g, 28.17);
  assert.equal(food?.fat_100g, 0.28);
});

check("a whole food is unbranded, which is what earns its ranking bonus", () => {
  // Must be null, not "" and not invented: the app gives unbranded entries a
  // bonus, and that is how a generic beats a product that merely contains it.
  assert.equal(normaliseFood(RICE)?.brand_name, null);
  assert.equal(brandFor(RICE), null);
  assert.equal(brandFor({ brandName: "  " }), null);
  assert.equal(brandFor({ brandOwner: "Kellogg" }), "Kellogg");
  assert.equal(brandFor({ brandName: "Special K", brandOwner: "Kellogg" }), "Special K");
});

check("a branded product is keyed on its real barcode", () => {
  // So a USDA entry and an Open Food Facts entry for the same tin collapse to
  // one row rather than appearing twice.
  assert.equal(barcodeFor({ fdcId: 1, gtinUpc: "0038000138416" }), "0038000138416");
  assert.equal(barcodeFor({ fdcId: 168878 }), "usda-168878");
  assert.equal(barcodeFor({ fdcId: 1, gtinUpc: "not-a-gtin" }), "usda-1");
  assert.equal(barcodeFor({ fdcId: 1, gtinUpc: "123" }), "usda-1");
  assert.equal(barcodeFor({}), null);
});

check("energy falls back through the Atwater variants and kilojoules", () => {
  assert.equal(energyKcalPer100g([{ nutrientId: 1008, value: 130 }]), 130);
  assert.equal(energyKcalPer100g([{ nutrientId: 2047, value: 128 }]), 128);
  assert.equal(
    energyKcalPer100g([{ nutrientId: 1062, value: 544 }]),
    544 / 4.184,
  );
  // kcal wins when both are present.
  assert.equal(
    energyKcalPer100g([
      { nutrientId: 1062, value: 544 },
      { nutrientId: 1008, value: 130 },
    ]),
    130,
  );
  assert.equal(energyKcalPer100g([]), null);
});

check("a food with no energy is dropped, not logged as zero", () => {
  assert.equal(
    normaliseFood({ fdcId: 1, description: "Water", foodNutrients: [] }),
    null,
  );
  assert.equal(
    normaliseFood({
      fdcId: 1,
      description: "Mystery",
      foodNutrients: [{ nutrientId: 1008, value: 0 }],
    }),
    null,
  );
});

check("a nameless entry is dropped", () => {
  assert.equal(normaliseFood({ fdcId: 1, foodNutrients: [] }), null);
  assert.equal(normaliseFood({ fdcId: 1, description: "   " }), null);
});

check("missing macros read as zero", () => {
  const food = normaliseFood({
    fdcId: 1,
    description: "Olive oil",
    foodNutrients: [
      { nutrientId: 1008, value: 884 },
      { nutrientId: 1004, value: 100 },
    ],
  });

  assert.equal(food?.calories_100g, 884);
  assert.equal(food?.fat_100g, 100);
  assert.equal(food?.protein_100g, 0);
  assert.equal(food?.carbs_100g, 0);
});

check("the nested nutrient shape is read too", () => {
  // The search endpoint flattens to {nutrientId, value}; the detail endpoint
  // nests as {nutrient: {id}, amount}. Both turn up.
  assert.equal(readNutrient([{ nutrient: { id: 1003 }, amount: 31 }], [1003]), 31);
  assert.equal(readNutrient([{ nutrientId: 1003, value: 31 }], [1003]), 31);
  assert.equal(readNutrient([{ nutrientId: 1003, value: 31 }], [1005]), null);
  assert.equal(readNutrient([], [1003]), null);
});

check("serving size is taken only when stated by weight", () => {
  assert.equal(servingGrams({ servingSize: 55, servingSizeUnit: "g" }), 55);
  assert.equal(servingGrams({ servingSize: 240, servingSizeUnit: "ml" }), 240);
  assert.equal(servingGrams({ servingSize: 55, servingSizeUnit: "G" }), 55);
  // "1 cup" cannot honestly become grams.
  assert.equal(servingGrams({ servingSize: 1, servingSizeUnit: "cup" }), null);
  assert.equal(servingGrams({ servingSize: 0, servingSizeUnit: "g" }), null);
  assert.equal(servingGrams({}), null);
});

check("values are rounded to two places", () => {
  const food = normaliseFood({
    fdcId: 1,
    description: "Thing",
    foodNutrients: [
      { nutrientId: 1008, value: 130.456789 },
      { nutrientId: 1003, value: 2.6949 },
    ],
  });

  assert.equal(food?.calories_100g, 130.46);
  assert.equal(food?.protein_100g, 2.69);
});

check("a search payload becomes a list, and junk becomes an empty one", () => {
  assert.equal(normaliseSearchResponse({ foods: [RICE] }).length, 1);
  assert.deepEqual(normaliseSearchResponse({ foods: [] }), []);
  assert.deepEqual(normaliseSearchResponse({}), []);
  assert.deepEqual(normaliseSearchResponse(null), []);
  assert.deepEqual(normaliseSearchResponse({ error: "OVER_RATE_LIMIT" }), []);
});

check("unusable entries are filtered out of an otherwise good payload", () => {
  const foods = normaliseSearchResponse({
    foods: [RICE, { fdcId: 2, description: "No energy", foodNutrients: [] }],
  });

  assert.equal(foods.length, 1);
  assert.equal(foods[0].barcode, "usda-168878");
});

console.log(`${passed} FoodData Central parser checks passed`);
