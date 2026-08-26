// Run: node --experimental-strip-types supabase/functions/food-search/parser.test.ts
import assert from "node:assert/strict";
import {
  normaliseFood,
  normaliseSearchResponse,
  parseFoodDescription,
  readNutrient,
  servingGrams,
} from "./fatsecret.ts";

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

check("per 100g is taken as-is", () => {
  const parsed = parseFoodDescription(
    "Per 100g - Calories: 130kcal | Fat: 0.28g | Carbs: 28.17g | Protein: 2.69g",
  );
  assert.deepEqual(parsed, {
    calories: 130,
    protein: 2.69,
    carbs: 28.17,
    fat: 0.28,
    servingSizeG: 100,
  });
});

check("a gram serving is rescaled to 100g", () => {
  const parsed = parseFoodDescription(
    "Per 1 serving (28g) - Calories: 140kcal | Fat: 7.00g | Carbs: 16.00g | Protein: 2.00g",
  );
  // 140 kcal in 28g is 500 kcal per 100g.
  assert.equal(parsed?.calories, 500);
  assert.equal(parsed?.protein, 7.14);
  assert.equal(parsed?.servingSizeG, 28);
});

check("a serving with no weight is rejected, not guessed", () => {
  assert.equal(
    parseFoodDescription(
      "Per 1 cup cooked - Calories: 205kcal | Fat: 0.44g | Carbs: 44.51g | Protein: 4.25g",
    ),
    null,
  );
});

check("millilitres are accepted as grams", () => {
  const parsed = parseFoodDescription(
    "Per 250ml - Calories: 105kcal | Fat: 4.00g | Carbs: 12.00g | Protein: 8.00g",
  );
  assert.equal(parsed?.calories, 42);
});

check("a missing macro reads as zero, a missing energy rejects the food", () => {
  const noFat = parseFoodDescription("Per 100g - Calories: 90kcal | Protein: 3g");
  assert.equal(noFat?.fat, 0);
  assert.equal(noFat?.protein, 3);

  assert.equal(parseFoodDescription("Per 100g - Fat: 3g | Protein: 3g"), null);
});

check("malformed descriptions do not throw", () => {
  assert.equal(parseFoodDescription(""), null);
  assert.equal(parseFoodDescription("   "), null);
  assert.equal(parseFoodDescription("Calories: 100kcal"), null);
  assert.equal(parseFoodDescription("Per - Calories: 100kcal"), null);
  assert.equal(parseFoodDescription("Per 0g - Calories: 100kcal"), null);
});

check("servingGrams reads the shapes that carry a weight", () => {
  assert.equal(servingGrams("100g"), 100);
  assert.equal(servingGrams("100 g"), 100);
  assert.equal(servingGrams("250ml"), 250);
  assert.equal(servingGrams("1 serving (28g)"), 28);
  assert.equal(servingGrams("1 cup (158 g)"), 158);
  assert.equal(servingGrams("1 cup cooked"), null);
  assert.equal(servingGrams("1 large"), null);
});

check("readNutrient is case insensitive and unit agnostic", () => {
  assert.equal(readNutrient("Calories: 130kcal", "Calories"), 130);
  assert.equal(readNutrient("calories: 130 kcal", "Calories"), 130);
  assert.equal(readNutrient("Fat: 0.28g", "Fat"), 0.28);
  assert.equal(readNutrient("Carbs: 28g", "Protein"), null);
});

check("a food entry becomes a cache row", () => {
  const food = normaliseFood({
    food_id: "35755",
    food_name: "Rice",
    brand_name: "",
    food_description:
      "Per 100g - Calories: 130kcal | Fat: 0.28g | Carbs: 28.17g | Protein: 2.69g",
  });

  assert.equal(food?.barcode, "fs-35755");
  assert.equal(food?.product_name, "Rice");
  assert.equal(food?.brand_name, null);
  assert.equal(food?.calories_100g, 130);
});

check("an entry with no id, name or usable nutrition is dropped", () => {
  assert.equal(normaliseFood({ food_name: "Rice" }), null);
  assert.equal(normaliseFood({ food_id: "1" }), null);
  assert.equal(
    normaliseFood({
      food_id: "1",
      food_name: "Rice",
      food_description: "Per 1 bowl - Calories: 200kcal",
    }),
    null,
  );
});

check("a single result arrives as an object, not an array", () => {
  // FatSecret collapses `foods.food` to a bare object when one food matches,
  // which is a good way to crash on the day a query is specific enough.
  const single = normaliseSearchResponse({
    foods: {
      food: {
        food_id: "1",
        food_name: "Rice",
        food_description: "Per 100g - Calories: 130kcal",
      },
    },
  });
  assert.equal(single.length, 1);

  const many = normaliseSearchResponse({
    foods: {
      food: [
        { food_id: "1", food_name: "Rice", food_description: "Per 100g - Calories: 130kcal" },
        { food_id: "2", food_name: "Brown rice", food_description: "Per 100g - Calories: 123kcal" },
      ],
    },
  });
  assert.equal(many.length, 2);
});

check("an empty or unexpected payload is an empty list", () => {
  assert.deepEqual(normaliseSearchResponse({}), []);
  assert.deepEqual(normaliseSearchResponse(null), []);
  assert.deepEqual(normaliseSearchResponse({ foods: {} }), []);
  assert.deepEqual(normaliseSearchResponse({ error: "rate limited" }), []);
});

console.log(`${passed} FatSecret parser checks passed`);
