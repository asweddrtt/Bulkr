-- Curated whole foods for the ingredient search.
--
-- Open Food Facts is three million barcoded *products*, and it is very good at
-- that and very bad at plain food. Searching it for "boiled eggs" leads with
-- Kinder Eggs, because it matches loosely and ranks by how completely a product
-- is documented rather than by how well it answers the question. No amount of
-- client-side ranking invents a good result that is not in the response.
--
-- So the plain foods live here instead. `system_foods` is searched first, is
-- weighted above everything else in the ranking, and is the reason typing "egg"
-- offers an egg.
--
-- Values are per 100g and follow the usual reference figures (USDA and
-- equivalents), rounded to one decimal. Where a food changes substantially with
-- cooking, the state is part of the name — "Chicken breast, cooked, skinless"
-- and "Chicken breast, raw, skinless" are different foods and both are here,
-- because logging one as the other is a 40% error.
--
-- The barcodes are synthetic. `system_foods.barcode` is the primary key and the
-- identity the app merges search results on, and a plain food has no barcode to
-- borrow. The `bulkr-` prefix cannot collide with a real GTIN, which is digits.
--
-- Re-runnable: re-running corrects the numbers in place and leaves anything you
-- have added by hand alone.
--
-- Run this in the Supabase SQL editor, after meals_policies.sql.

insert into public.system_foods
  (barcode, product_name, calories_100g, protein_100g, carbs_100g, fat_100g,
   popularity_score)
values
  ('bulkr-egg-whole-boiled', 'Egg, whole, boiled', 155, 12.6, 1.1, 10.6, 100),
  ('bulkr-egg-whole-raw', 'Egg, whole, raw', 143, 12.6, 0.7, 9.5, 90),
  ('bulkr-egg-fried', 'Egg, fried', 196, 13.6, 0.8, 14.8, 70),
  ('bulkr-egg-white-raw', 'Egg white, raw', 52, 10.9, 0.7, 0.2, 80),
  ('bulkr-chicken-breast-cooked-skinless', 'Chicken breast, cooked, skinless', 165, 31.0, 0.0, 3.6, 100),
  ('bulkr-chicken-breast-raw-skinless', 'Chicken breast, raw, skinless', 120, 22.5, 0.0, 2.6, 95),
  ('bulkr-chicken-thigh-cooked-skinless', 'Chicken thigh, cooked, skinless', 209, 26.0, 0.0, 10.9, 70),
  ('bulkr-turkey-breast-cooked', 'Turkey breast, cooked', 135, 30.1, 0.0, 1.0, 65),
  ('bulkr-beef-mince-5-fat-raw', 'Beef mince, 5% fat, raw', 137, 21.0, 0.0, 5.0, 85),
  ('bulkr-beef-mince-20-fat-raw', 'Beef mince, 20% fat, raw', 254, 17.2, 0.0, 20.0, 75),
  ('bulkr-beef-ribeye-steak-cooked', 'Beef ribeye steak, cooked', 291, 24.0, 0.0, 21.2, 80),
  ('bulkr-beef-sirloin-steak-cooked', 'Beef sirloin steak, cooked', 212, 30.0, 0.0, 9.3, 75),
  ('bulkr-pork-loin-cooked', 'Pork loin, cooked', 209, 28.0, 0.0, 10.0, 60),
  ('bulkr-bacon-cooked', 'Bacon, cooked', 541, 37.0, 1.4, 41.8, 60),
  ('bulkr-lamb-cooked', 'Lamb, cooked', 258, 25.0, 0.0, 17.0, 50),
  ('bulkr-salmon-cooked', 'Salmon, cooked', 208, 22.1, 0.0, 13.4, 85),
  ('bulkr-tuna-canned-in-water-drained', 'Tuna, canned in water, drained', 116, 25.5, 0.0, 0.8, 85),
  ('bulkr-cod-cooked', 'Cod, cooked', 105, 22.8, 0.0, 0.9, 60),
  ('bulkr-prawns-cooked', 'Prawns, cooked', 99, 24.0, 0.2, 0.3, 55),
  ('bulkr-tilapia-cooked', 'Tilapia, cooked', 129, 26.2, 0.0, 2.7, 45),
  ('bulkr-greek-yoghurt-0-fat', 'Greek yoghurt, 0% fat', 59, 10.3, 3.6, 0.4, 95),
  ('bulkr-greek-yoghurt-full-fat', 'Greek yoghurt, full fat', 97, 9.0, 3.9, 5.0, 75),
  ('bulkr-milk-whole', 'Milk, whole', 61, 3.2, 4.8, 3.3, 90),
  ('bulkr-milk-skimmed', 'Milk, skimmed', 34, 3.4, 5.0, 0.1, 80),
  ('bulkr-cottage-cheese-low-fat', 'Cottage cheese, low fat', 81, 11.1, 3.4, 2.3, 75),
  ('bulkr-cheddar-cheese', 'Cheddar cheese', 403, 24.9, 1.3, 33.1, 70),
  ('bulkr-mozzarella', 'Mozzarella', 300, 22.2, 2.2, 22.4, 60),
  ('bulkr-parmesan', 'Parmesan', 392, 35.8, 3.2, 25.0, 55),
  ('bulkr-feta', 'Feta', 264, 14.2, 4.1, 21.3, 45),
  ('bulkr-butter', 'Butter', 717, 0.9, 0.1, 81.1, 65),
  ('bulkr-whey-protein-isolate-powder', 'Whey protein isolate, powder', 373, 88.0, 3.0, 1.0, 100),
  ('bulkr-whey-protein-concentrate-powder', 'Whey protein concentrate, powder', 400, 80.0, 8.0, 5.0, 95),
  ('bulkr-casein-protein-powder', 'Casein protein, powder', 360, 78.0, 8.0, 2.0, 70),
  ('bulkr-mass-gainer-powder', 'Mass gainer, powder', 380, 20.0, 70.0, 3.0, 70),
  ('bulkr-protein-bar', 'Protein bar', 350, 30.0, 35.0, 10.0, 60),
  ('bulkr-rice-white-cooked', 'Rice, white, cooked', 130, 2.7, 28.2, 0.3, 100),
  ('bulkr-rice-white-dry', 'Rice, white, dry', 365, 7.1, 80.0, 0.7, 80),
  ('bulkr-rice-brown-cooked', 'Rice, brown, cooked', 123, 2.7, 25.6, 1.0, 80),
  ('bulkr-oats-rolled-dry', 'Oats, rolled, dry', 379, 13.2, 67.7, 6.9, 100),
  ('bulkr-pasta-cooked', 'Pasta, cooked', 158, 5.8, 30.9, 0.9, 90),
  ('bulkr-pasta-dry', 'Pasta, dry', 371, 13.0, 74.7, 1.5, 75),
  ('bulkr-bread-white', 'Bread, white', 265, 9.0, 49.0, 3.2, 85),
  ('bulkr-bread-wholemeal', 'Bread, wholemeal', 247, 13.0, 41.0, 3.4, 85),
  ('bulkr-potato-boiled', 'Potato, boiled', 87, 1.9, 20.1, 0.1, 90),
  ('bulkr-sweet-potato-baked', 'Sweet potato, baked', 90, 2.0, 20.7, 0.1, 85),
  ('bulkr-quinoa-cooked', 'Quinoa, cooked', 120, 4.4, 21.3, 1.9, 65),
  ('bulkr-couscous-cooked', 'Couscous, cooked', 112, 3.8, 23.2, 0.2, 50),
  ('bulkr-bagel-plain', 'Bagel, plain', 250, 10.0, 48.0, 1.5, 50),
  ('bulkr-tortilla-flour', 'Tortilla, flour', 306, 8.2, 51.4, 7.9, 55),
  ('bulkr-peanut-butter', 'Peanut butter', 588, 25.1, 20.0, 50.4, 95),
  ('bulkr-peanuts', 'Peanuts', 567, 25.8, 16.1, 49.2, 75),
  ('bulkr-almonds', 'Almonds', 579, 21.2, 21.6, 49.9, 85),
  ('bulkr-walnuts', 'Walnuts', 654, 15.2, 13.7, 65.2, 60),
  ('bulkr-cashews', 'Cashews', 553, 18.2, 30.2, 43.9, 60),
  ('bulkr-lentils-cooked', 'Lentils, cooked', 116, 9.0, 20.1, 0.4, 65),
  ('bulkr-chickpeas-cooked', 'Chickpeas, cooked', 164, 8.9, 27.4, 2.6, 65),
  ('bulkr-black-beans-cooked', 'Black beans, cooked', 132, 8.9, 23.7, 0.5, 60),
  ('bulkr-tofu-firm', 'Tofu, firm', 144, 17.3, 2.8, 8.7, 55),
  ('bulkr-hummus', 'Hummus', 166, 7.9, 14.3, 9.6, 55),
  ('bulkr-banana', 'Banana', 89, 1.1, 22.8, 0.3, 100),
  ('bulkr-apple', 'Apple', 52, 0.3, 13.8, 0.2, 85),
  ('bulkr-blueberries', 'Blueberries', 57, 0.7, 14.5, 0.3, 65),
  ('bulkr-strawberries', 'Strawberries', 32, 0.7, 7.7, 0.3, 65),
  ('bulkr-orange', 'Orange', 47, 0.9, 11.8, 0.1, 70),
  ('bulkr-avocado', 'Avocado', 160, 2.0, 8.5, 14.7, 85),
  ('bulkr-broccoli-cooked', 'Broccoli, cooked', 35, 2.4, 7.2, 0.4, 80),
  ('bulkr-spinach-raw', 'Spinach, raw', 23, 2.9, 3.6, 0.4, 75),
  ('bulkr-carrot-raw', 'Carrot, raw', 41, 0.9, 9.6, 0.2, 65),
  ('bulkr-tomato', 'Tomato', 18, 0.9, 3.9, 0.2, 70),
  ('bulkr-onion', 'Onion', 40, 1.1, 9.3, 0.1, 60),
  ('bulkr-mixed-salad-leaves', 'Mixed salad leaves', 15, 1.4, 2.9, 0.2, 50),
  ('bulkr-olive-oil', 'Olive oil', 884, 0.0, 0.0, 100.0, 90),
  ('bulkr-coconut-oil', 'Coconut oil', 862, 0.0, 0.0, 100.0, 55),
  ('bulkr-mayonnaise', 'Mayonnaise', 680, 1.0, 0.6, 75.0, 55),
  ('bulkr-honey', 'Honey', 304, 0.3, 82.1, 0.0, 60),
  ('bulkr-dark-chocolate-70', 'Dark chocolate, 70%', 598, 7.8, 45.9, 42.6, 55)
on conflict (barcode) do update set
  product_name    = excluded.product_name,
  calories_100g   = excluded.calories_100g,
  protein_100g    = excluded.protein_100g,
  carbs_100g      = excluded.carbs_100g,
  fat_100g        = excluded.fat_100g,
  popularity_score = excluded.popularity_score,
  updated_at      = now();

-- Verify: should return 76.
--   select count(*) from public.system_foods where barcode like 'bulkr-%';
--
-- And a spot check of what the search will now lead with:
--   select product_name, calories_100g, protein_100g, popularity_score
--     from public.system_foods
--    where product_name ilike '%egg%'
--    order by popularity_score desc;
