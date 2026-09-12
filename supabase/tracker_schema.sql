-- The Tracker tab: what `daily_logs` needs before a day can be read back,
-- edited and split into meals.
--
-- `daily_logs` already exists and is already written to — `logMealToday` has
-- been inserting into it since the Meals tab shipped, carrying its own copy of
-- the calories and macros. What has never happened is reading those rows back.
-- Doing that turns up four gaps, and this file closes them:
--
--   1. no stable row identity, so one entry cannot be edited or deleted
--   2. no name on the row, so an entry whose meal was deleted is unreadable
--   3. no link to the food a one-off entry came from
--   4. `meal_type` exists but nothing has ever written it, and its shape is
--      unknown to this repository
--
-- Written to be re-runnable: every statement is guarded, so applying it twice
-- changes nothing the second time. Several sections are `do $$` blocks rather
-- than plain DDL for exactly that reason — `add column if not exists` exists,
-- `add primary key if not exists` does not.
--
-- Run this in the Supabase SQL editor, after `meals_policies.sql`.
--
-- NOTE: the tables this file alters were created outside this repository, so
-- their exact definitions are not checked in. Everything below inspects the
-- catalog before it changes anything, and section 6 has queries to confirm the
-- result.

-- ---------------------------------------------------------------------------
-- 1. A primary key on `daily_logs`
-- ---------------------------------------------------------------------------
-- The tracker lets someone fix a mis-tapped portion or delete one entry. Both
-- need to name a single row, and until now nothing has: every query against
-- this table has addressed rows in bulk, by `(user_id, log_date, meal_id)`.
-- That was sufficient for a toggle whose "off" means "not counted today at
-- all", and it is not sufficient for anything finer.
--
-- Three cases, and this block handles each:
--
--   * an `id` column already exists  -> left alone
--   * it does not, and the table has no primary key -> added and made the key
--   * it does not, and the table HAS some other primary key -> the column is
--     still added and given a unique index, because a second PRIMARY KEY is
--     not allowed and is not needed. A unique non-null column is all the app
--     requires.
--
-- `gen_random_uuid()` backfills every existing row as the column is added, so
-- history written before today gets an identity too and becomes editable
-- rather than being stranded.

do $$
declare
  has_id boolean;
  has_pk boolean;
begin
  select exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'daily_logs'
       and column_name = 'id'
  ) into has_id;

  if not has_id then
    alter table public.daily_logs
      add column id uuid not null default gen_random_uuid();

    select exists (
      select 1 from pg_constraint
       where conrelid = 'public.daily_logs'::regclass and contype = 'p'
    ) into has_pk;

    if has_pk then
      -- Something else is already the key. Settle for uniqueness, which is
      -- what `.eq('id', ...)` actually depends on.
      create unique index if not exists daily_logs_id_key
        on public.daily_logs (id);
      raise notice
        'daily_logs already had a primary key; id added as a unique column.';
    else
      alter table public.daily_logs add primary key (id);
    end if;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. What was eaten, on the row itself
-- ---------------------------------------------------------------------------
-- `item_name` is written for every new entry — library meals included, not
-- just loose foods.
--
-- That looks redundant while the meal still exists, since the title can be
-- joined from `meals`. It stops being redundant the moment the meal is
-- deleted: the foreign key is ON DELETE SET NULL on purpose, so the row
-- survives with its calories intact and nothing left to join to. Without this
-- column that row reads "640 kcal of something", which is a worse record than
-- the schema can support. With it, the log still says "Chicken and rice".
--
-- The live title still wins where both exist, so renaming a meal reads
-- correctly in the log — see `DailyLogEntry.displayName`.
--
-- `cached_food_id` is the other half: for a one-off food it records which
-- `cached_off_foods` row the nutrition came from. It is what makes a logged
-- food re-loggable later and tells a food entry apart from a meal entry whose
-- meal has been deleted. ON DELETE SET NULL for the same reason as `meal_id`
-- — losing the link must never rewrite the macros.

alter table public.daily_logs
  add column if not exists item_name text;

alter table public.daily_logs
  add column if not exists cached_food_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'daily_logs_cached_food_id_fkey'
       and conrelid = 'public.daily_logs'::regclass
  ) then
    alter table public.daily_logs
      add constraint daily_logs_cached_food_id_fkey
      foreign key (cached_food_id)
      references public.cached_off_foods(id) on delete set null;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 3. `meal_type`: breakfast, lunch, dinner, snack
-- ---------------------------------------------------------------------------
-- The column is referenced in `MealRepository.logMealToday` as existing and
-- nullable, and nothing has ever written it. Its type is not recorded anywhere
-- in this repository, so this section establishes what the app needs without
-- assuming what is there.
--
-- The awkward case is a column that already exists as a Postgres ENUM rather
-- than text: adding a CHECK to it would be wrong, and inserting a value the
-- enum lacks would fail at runtime. So the block below only adds a constraint
-- when the column is a plain text type AND has no constraint already, and
-- otherwise says what it found and leaves it alone. Read the notice.
--
-- Existing rows stay null. Null is a real state here — "logged before slots
-- existed" — and the tracker renders those in their own section rather than
-- back-filling a guess about which meal they were.

alter table public.daily_logs
  add column if not exists meal_type text;

do $$
declare
  col_type text;
  constraint_count int;
begin
  select data_type into col_type
    from information_schema.columns
   where table_schema = 'public' and table_name = 'daily_logs'
     and column_name = 'meal_type';

  select count(*) into constraint_count
    from pg_constraint
   where conrelid = 'public.daily_logs'::regclass
     and contype = 'c'
     and pg_get_constraintdef(oid) ilike '%meal_type%';

  if col_type is distinct from 'text' then
    raise notice
      'daily_logs.meal_type is % rather than text — leaving it alone. Confirm it accepts breakfast/lunch/dinner/snack (see section 6).',
      coalesce(col_type, 'missing');
  elsif constraint_count > 0 then
    raise notice
      'daily_logs.meal_type already has a check constraint — leaving it alone. Confirm it allows all four slots (see section 6).';
  else
    alter table public.daily_logs
      add constraint daily_logs_meal_type_check
      check (meal_type is null
             or meal_type in ('breakfast', 'lunch', 'dinner', 'snack'));
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 4. Indexes
-- ---------------------------------------------------------------------------
-- `daily_logs_user_id_log_date_idx (user_id, log_date desc)` already exists
-- from `meals_policies.sql` and is what the tracker's day read uses: one
-- equality on `user_id` and one on `log_date`. Nothing further is needed for
-- it, and the day-browsing strip in the next slice hits the same index.
--
-- What does need one is deleting a food from the cache, which has to find the
-- log rows pointing at it to null them out. Unindexed, that is a sequential
-- scan of every log row in the table.

create index if not exists daily_logs_cached_food_id_idx
  on public.daily_logs (cached_food_id)
  where cached_food_id is not null;

-- ---------------------------------------------------------------------------
-- 5. Row level security: nothing to do
-- ---------------------------------------------------------------------------
-- `meals_policies.sql` section 2 already covers this table:
--
--   create policy "Enable full access for users based on user_id"
--     on public.daily_logs for all to authenticated
--     using (auth.uid() = user_id)
--     with check (auth.uid() = user_id);
--
-- `for all` includes the UPDATE and DELETE the tracker adds, and the
-- `using` clause scopes both to the owner's own rows — so editing an entry
-- and deleting one are already covered, and a request naming somebody else's
-- row id affects nothing rather than being refused.
--
-- No column-level grant is needed either, unlike `posts` in
-- `feed_engagement.sql`. That table has counters a client must never write;
-- every column here is the owner's own record of their own day.

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- 6. Verify
-- ---------------------------------------------------------------------------
-- The whole shape of the table, which is also the answer to "what was already
-- there" — worth keeping the output of:
--   select column_name, data_type, is_nullable, column_default
--     from information_schema.columns
--    where table_schema = 'public' and table_name = 'daily_logs'
--    order by ordinal_position;
--
-- That `id` is unique and not null (either as the primary key or as the index
-- from section 1):
--   select conname, contype, pg_get_constraintdef(oid)
--     from pg_constraint where conrelid = 'public.daily_logs'::regclass;
--   select indexname, indexdef from pg_indexes
--    where schemaname = 'public' and tablename = 'daily_logs';
--
-- **The one that matters most.** If `meal_type` was already an enum or already
-- constrained, section 3 left it alone and this is what tells you whether the
-- app's four values will insert. All four should come back:
--   select unnest(array['breakfast','lunch','dinner','snack']) as slot;
--   -- then, as a real check, inside a transaction you throw away:
--   begin;
--     insert into public.daily_logs
--       (user_id, log_date, meal_type, item_name, quantity_g,
--        calories_logged, protein_logged_g, carbs_logged_g, fat_logged_g)
--     select auth.uid(), current_date, slot, 'constraint probe', 0, 0, 0, 0, 0
--       from unnest(array['breakfast','lunch','dinner','snack']) as slot;
--   rollback;
--
-- If that insert fails, the slot values this app writes are not the ones the
-- column accepts — send the error and the column definition from the first
-- query, and `MealSlot.dbValue` can be changed to match rather than the
-- database being altered.
--
-- That a day reads back with names and slots, once you have logged something
-- from the tracker:
--   select log_date, meal_type, item_name, quantity_g, calories_logged
--     from public.daily_logs
--    where user_id = auth.uid()
--    order by log_date desc, meal_type
--    limit 20;
--
-- And that rows written before this file ran are still counted — they should
-- come back with a null meal_type and a null item_name, which is exactly what
-- the tracker's unsorted section exists to show:
--   select count(*) from public.daily_logs
--    where user_id = auth.uid() and meal_type is null;
