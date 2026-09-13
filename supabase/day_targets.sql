-- Training days and rest days, with their own targets.
--
-- Prerequisites: `custom_targets.sql` (this is the same feature family and the
-- same premium gate) and the `users` table. Re-runnable.
--
-- Run this in the Supabase SQL editor (Dashboard -> SQL Editor -> New query).
--
-- ---------------------------------------------------------------------------
-- Why this shape
-- ---------------------------------------------------------------------------
-- Eating the same every day is not what anybody bulking actually does. More on
-- the days you lift, less on the days you do not — carb cycling, refeeds, call
-- it what you like — and every app at this price makes you either average it
-- out or edit your goal twice a week by hand.
--
-- The four columns that already exist stay put and become the **training day**
-- targets. That is deliberate: it means an account that never turns this on is
-- untouched, and one that turns it off again falls back to exactly what it had.
-- The rest-day numbers are a second, nullable set, and `training_days` says
-- which weekdays use the first.
--
-- `training_days` holds ISO weekday numbers — Monday 1 through Sunday 7, which
-- is what Dart's `DateTime.weekday` returns, so nothing has to convert. Null or
-- empty means the feature is off and every day uses the original four columns.

-- ---------------------------------------------------------------------------
-- 1. The columns
-- ---------------------------------------------------------------------------

alter table public.users
  add column if not exists rest_day_calorie_target int,
  add column if not exists rest_day_protein_g      int,
  add column if not exists rest_day_carbs_g        int,
  add column if not exists rest_day_fat_g          int,
  add column if not exists training_days           int[];

-- Nothing outside 1-7 is a weekday, and a stray 0 or 8 would silently mean
-- "never a training day" rather than failing where it was written.
alter table public.users
  drop constraint if exists users_training_days_check;
alter table public.users
  add constraint users_training_days_check check (
    training_days is null
    or (
      array_length(training_days, 1) between 1 and 7
      and training_days <@ array[1, 2, 3, 4, 5, 6, 7]
    )
  );

-- ---------------------------------------------------------------------------
-- 2. Premium only
-- ---------------------------------------------------------------------------
-- Its own trigger rather than an edit to `enforce_custom_targets`, so the two
-- files never hold two versions of one function. Both raise the same SQLSTATE,
-- which the app already turns into a sentence with a way out of it.

create or replace function public.enforce_day_targets()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
begin
  -- Only switching the feature on matters. Turning it off must always work:
  -- an account whose subscription lapsed has to be able to get back to one set
  -- of numbers, and blocking that would strand them on a split they can no
  -- longer edit.
  if new.training_days is null or array_length(new.training_days, 1) is null then
    return new;
  end if;

  if old.training_days is not null
     and array_length(old.training_days, 1) is not null then
    return new;
  end if;

  if uid is null or uid is distinct from new.id then
    return new;
  end if;

  if not public.is_premium(uid) then
    raise exception 'Bulkr: training and rest day targets are a Premium feature.'
      using errcode = 'BLKR2', hint = 'day_targets';
  end if;

  return new;
end;
$$;

drop trigger if exists users_day_targets_premium on public.users;
create trigger users_day_targets_premium
  before update on public.users
  for each row execute function public.enforce_day_targets();

-- ---------------------------------------------------------------------------
-- 3. Reload the API's schema cache
-- ---------------------------------------------------------------------------
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
--   select training_days, rest_day_calorie_target from public.users
--    where id = auth.uid();
--
-- As a free account this must fail with SQLSTATE BLKR2, hint `day_targets`:
--
--   update public.users set training_days = array[1,3,5] where id = auth.uid();
--
-- And the constraint must reject a day that is not a day:
--
--   update public.users set training_days = array[0] where id = auth.uid();
