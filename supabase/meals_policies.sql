-- RUN THIS FIRST. Without it the app reports
--   42501 · new row violates row-level security policy for table "..."
-- on the first meal you try to save, because RLS is on and the tables have no
-- policies at all — the same state weight_logs was in.
--
-- Meals tab: the one additive column it needs, row-level security for every
-- table it touches, the storage bucket for meal photos, and the indexes the
-- queries assume.
--
-- Written to be re-runnable: every statement is guarded, so applying it twice
-- changes nothing the second time.
--
-- Run this in the Supabase SQL editor (Dashboard -> SQL Editor -> New query).

-- ---------------------------------------------------------------------------
-- 1. Favourites
-- ---------------------------------------------------------------------------
-- The Meals screen has two tabs over one library. "My Meals" is meals the user
-- created plus meals they saved; "Favorites" is the subset they starred, and
-- there was nowhere to record the star. It goes on `saved_meals` rather than in
-- a table of its own, which is what makes favouriting a meal also save it —
-- deliberate, since a favourite that is not in your library has nowhere to
-- appear.

alter table public.saved_meals
  add column if not exists is_favorite boolean not null default false;

-- ---------------------------------------------------------------------------
-- 2. Row level security
-- ---------------------------------------------------------------------------
-- Same shape as the existing `users` and `weight_logs` policies: full access
-- keyed on the owning column, with reads widened where the feed needs them.

alter table public.meals             enable row level security;
alter table public.meal_ingredients  enable row level security;
alter table public.saved_meals       enable row level security;
alter table public.daily_logs        enable row level security;
alter table public.cached_off_foods  enable row level security;
alter table public.system_foods      enable row level security;

-- meals: your own are yours; public ones are readable by anyone signed in, so
-- a meal attached to a feed post can be viewed and saved.
drop policy if exists "Meals are readable when yours or public" on public.meals;
create policy "Meals are readable when yours or public"
  on public.meals for select to authenticated
  using (auth.uid() = creator_id or is_public);

drop policy if exists "Meals are writable by their creator" on public.meals;
create policy "Meals are writable by their creator"
  on public.meals for all to authenticated
  using (auth.uid() = creator_id)
  with check (auth.uid() = creator_id);

-- meal_ingredients: inherits the parent meal's visibility. Someone who can see
-- a public meal can see what is in it; only its creator can change it.
drop policy if exists "Ingredients follow their meal" on public.meal_ingredients;
create policy "Ingredients follow their meal"
  on public.meal_ingredients for select to authenticated
  using (
    exists (
      select 1 from public.meals m
       where m.id = meal_id
         and (m.creator_id = auth.uid() or m.is_public)
    )
  );

drop policy if exists "Ingredients are writable by the meal's creator"
  on public.meal_ingredients;
create policy "Ingredients are writable by the meal's creator"
  on public.meal_ingredients for all to authenticated
  using (
    exists (
      select 1 from public.meals m
       where m.id = meal_id and m.creator_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.meals m
       where m.id = meal_id and m.creator_id = auth.uid()
    )
  );

-- saved_meals and daily_logs: private to their owner, no exceptions.
drop policy if exists "Enable full access for users based on user_id"
  on public.saved_meals;
create policy "Enable full access for users based on user_id"
  on public.saved_meals for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Enable full access for users based on user_id"
  on public.daily_logs;
create policy "Enable full access for users based on user_id"
  on public.daily_logs for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- cached_off_foods: a shared cache of third-party nutrition data, not user
-- data. Everyone signed in reads it, and everyone contributes to it — the app
-- upserts a row the first time anyone puts that food in a meal.
--
-- Deletes are deliberately not granted: `meal_ingredients.cached_food_id`
-- points here, so removing a row would strip the nutrition out of other
-- people's saved meals.
drop policy if exists "Cached foods are readable by everyone signed in"
  on public.cached_off_foods;
create policy "Cached foods are readable by everyone signed in"
  on public.cached_off_foods for select to authenticated using (true);

drop policy if exists "Cached foods can be added by anyone signed in"
  on public.cached_off_foods;
create policy "Cached foods can be added by anyone signed in"
  on public.cached_off_foods for insert to authenticated with check (true);

drop policy if exists "Cached foods can be refreshed by anyone signed in"
  on public.cached_off_foods;
create policy "Cached foods can be refreshed by anyone signed in"
  on public.cached_off_foods for update to authenticated
  using (true) with check (true);

-- system_foods: curated by us, read-only to the app.
drop policy if exists "System foods are readable by everyone signed in"
  on public.system_foods;
create policy "System foods are readable by everyone signed in"
  on public.system_foods for select to authenticated using (true);

-- ---------------------------------------------------------------------------
-- 3. Meal photos
-- ---------------------------------------------------------------------------
-- Public-read because a meal on a feed post has to render for everyone who
-- sees it. Writes are scoped to a folder named after the uploader's id, which
-- is the path the app builds: `<uid>/<timestamp>.jpg`.

insert into storage.buckets (id, name, public)
values ('meal-images', 'meal-images', true)
on conflict (id) do update set public = true;

drop policy if exists "Meal images are publicly readable" on storage.objects;
create policy "Meal images are publicly readable"
  on storage.objects for select
  using (bucket_id = 'meal-images');

drop policy if exists "Users upload meal images to their own folder"
  on storage.objects;
create policy "Users upload meal images to their own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'meal-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users manage their own meal images" on storage.objects;
create policy "Users manage their own meal images"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'meal-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users delete their own meal images" on storage.objects;
create policy "Users delete their own meal images"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'meal-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- 4. Indexes
-- ---------------------------------------------------------------------------
-- One per access path the app actually uses.

create index if not exists meals_creator_id_created_at_idx
  on public.meals (creator_id, created_at desc);

create index if not exists meals_public_created_at_idx
  on public.meals (created_at desc) where is_public;

create index if not exists saved_meals_user_id_saved_at_idx
  on public.saved_meals (user_id, saved_at desc);

create index if not exists meal_ingredients_meal_id_idx
  on public.meal_ingredients (meal_id);

create index if not exists daily_logs_user_id_log_date_idx
  on public.daily_logs (user_id, log_date desc);

-- Food search runs `ilike '%term%'`, which no btree index can serve. Trigram
-- indexes can, and the extension ships with Supabase.
create extension if not exists pg_trgm;

create index if not exists cached_off_foods_product_name_trgm_idx
  on public.cached_off_foods using gin (product_name gin_trgm_ops);

create index if not exists system_foods_product_name_trgm_idx
  on public.system_foods using gin (product_name gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- 5. What happens to everything else when a meal is deleted
-- ---------------------------------------------------------------------------
-- Four tables point at `meals`, and the default (NO ACTION) means deleting a
-- meal that has ever been used simply fails. Each one wants a different answer,
-- and the difference matters:
--
--   meal_ingredients  cascade   the ingredients ARE the meal; nothing survives it
--   saved_meals       cascade   a library entry for a meal that no longer exists
--                               is a blank card, so the row goes with it
--   daily_logs        set null  NEVER cascade. A log row records what someone ate
--                               on a day that has already happened, and it carries
--                               its own copy of the calories and macros precisely
--                               so deleting the meal cannot rewrite history. It
--                               loses the link, not the meal.
--   posts             set null  the post is the author's writing and stays; only
--                               the attachment goes
--
-- Cascades run as the table owner, so they reach other users' saved_meals rows
-- that RLS would never let the deleting user touch directly. That is intended:
-- deleting a public meal has to be able to clean up after itself.
--
-- Drop-then-add rather than a bare add, so this section is re-runnable like the
-- rest of the file.

alter table public.meal_ingredients
  drop constraint if exists meal_ingredients_meal_id_fkey;
alter table public.meal_ingredients
  add constraint meal_ingredients_meal_id_fkey
  foreign key (meal_id) references public.meals(id) on delete cascade;

alter table public.saved_meals
  drop constraint if exists saved_meals_meal_id_fkey;
alter table public.saved_meals
  add constraint saved_meals_meal_id_fkey
  foreign key (meal_id) references public.meals(id) on delete cascade;

alter table public.daily_logs
  drop constraint if exists daily_logs_meal_id_fkey;
alter table public.daily_logs
  add constraint daily_logs_meal_id_fkey
  foreign key (meal_id) references public.meals(id) on delete set null;

alter table public.posts
  drop constraint if exists posts_attached_meal_id_fkey;
alter table public.posts
  add constraint posts_attached_meal_id_fkey
  foreign key (attached_meal_id) references public.meals(id) on delete set null;

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
--   select tablename, policyname, cmd from pg_policies
--    where tablename in ('meals', 'meal_ingredients', 'saved_meals',
--                        'daily_logs', 'cached_off_foods', 'system_foods')
--    order by tablename, cmd;
--
--   select id, public from storage.buckets where id = 'meal-images';
--
-- And that a deleted meal takes the right things with it:
--   select tc.table_name, tc.constraint_name, rc.delete_rule
--     from information_schema.referential_constraints rc
--     join information_schema.table_constraints tc
--       on tc.constraint_name = rc.constraint_name
--    where rc.unique_constraint_name = 'meals_pkey';
--
-- And to confirm no table has RLS on with no policy at all:
--   select c.relname,
--          c.relrowsecurity as rls_enabled,
--          count(p.policyname) as policies
--     from pg_class c
--     join pg_namespace n on n.oid = c.relnamespace
--     left join pg_policies p on p.tablename = c.relname
--    where n.nspname = 'public' and c.relkind = 'r'
--    group by c.relname, c.relrowsecurity
--    order by policies, c.relname;
