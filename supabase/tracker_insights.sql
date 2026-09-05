-- ---------------------------------------------------------------------------
-- Bulkr — streaks and the weekly recap
-- ---------------------------------------------------------------------------
-- Run after `tracker_schema.sql` and `tracker_water.sql`. Safe to run more
-- than once.
--
-- Both of these are answers the app could work out for itself by fetching the
-- rows and doing arithmetic in Dart. Neither should.
--
-- A streak means walking backwards from today until a day has nothing in it.
-- Done on the device, that is "give me every distinct date I have ever
-- logged", which grows without bound and gets slower for exactly the users
-- who have used the app the most. Done here it is one row, computed against an
-- index, and the answer is a single integer on the wire.
--
-- The recap is the same argument with a bigger multiplier: a week of intake is
-- a few dozen `daily_logs` rows, plus water, plus weigh-ins, all of which get
-- collapsed into eight numbers the moment they arrive. Sending the rows to
-- have them added up somewhere else is paying egress to move data to its own
-- summary.
--
-- Both are `security invoker` — the default, stated here because it is the
-- safety argument. They read `auth.uid()`'s rows and run as the caller, so
-- every policy on `daily_logs`, `water_logs` and `weight_logs` applies exactly
-- as it does everywhere else.

-- ---------------------------------------------------------------------------
-- 1. The streak
-- ---------------------------------------------------------------------------
-- Consecutive days ending today, or ending yesterday.
--
-- Yesterday counts as still standing, and that is a deliberate product
-- decision rather than an oversight. Someone who logged every day for three
-- weeks and opens the app at nine in the morning has not broken anything yet;
-- showing them a zero before the day has happened is punishing them for the
-- time of day. The streak breaks when a day passes with nothing in it, which
-- is one day later.
--
-- Days are the user's own dates as `daily_logs.log_date` stored them. That
-- column is written by the app from the device's local calendar — see
-- `MealSlot`, where a day starts at 04:00 — so this counts the days the user
-- lived through, not UTC days.
create or replace function public.logging_streak()
returns integer
language sql
stable
set search_path = public
as $$
  with days as (
    select distinct log_date
      from public.daily_logs
     where user_id = auth.uid()
       and log_date <= current_date
     -- A streak nobody will ever see the end of is not worth scanning for.
     -- Two years bounds the read and is far past where the number stops
     -- meaning anything different.
       and log_date > current_date - 730
  ),
  -- The classic gaps-and-islands trick: consecutive dates all have the same
  -- `date - row_number`, so grouping on that difference groups the runs.
  runs as (
    select log_date,
           log_date - (row_number() over (order by log_date))::integer as run
      from days
  ),
  latest as (
    select max(log_date) as last_day, count(*)::integer as length
      from runs
     group by run
     order by last_day desc
     limit 1
  )
  -- Only the most recent run counts, and only if it reaches yesterday. An
  -- earlier one is a streak that already ended.
  select coalesce(
    (select length from latest where last_day >= current_date - 1),
    0
  );
$$;

-- ---------------------------------------------------------------------------
-- 2. The recap
-- ---------------------------------------------------------------------------
-- The last seven days, as one row.
--
-- `days_logged` is out of seven and is the honest denominator for the rest:
-- an average calorie figure over two logged days is not a week's average, and
-- the screen says so rather than quietly dividing by seven.
--
-- Averages are per *logged day*, not per day. Someone who logged four days
-- wants to know what those four days looked like; dividing their intake by
-- seven would tell them they are eating half of what they are eating.
create or replace function public.weekly_recap()
returns table (
  days_logged integer,
  entries integer,
  avg_calories integer,
  avg_protein_g integer,
  avg_carbs_g integer,
  avg_fat_g integer,
  days_on_target integer,
  calorie_target integer,
  avg_water_ml integer,
  weight_change_kg numeric,
  first_weight_kg numeric,
  last_weight_kg numeric
)
language sql
stable
set search_path = public
as $$
  with window_days as (
    select (current_date - offset_days)::date as day
      from generate_series(0, 6) as offset_days
  ),
  target as (
    select nullif(u.daily_calorie_target, 0) as calories
      from public.users u
     where u.id = auth.uid()
  ),
  per_day as (
    select l.log_date,
           sum(l.calories_logged)::numeric   as calories,
           sum(l.protein_logged_g)::numeric  as protein_g,
           sum(l.carbs_logged_g)::numeric    as carbs_g,
           sum(l.fat_logged_g)::numeric      as fat_g,
           count(*)                          as entries
      from public.daily_logs l
     where l.user_id = auth.uid()
       and l.log_date in (select day from window_days)
     group by l.log_date
  ),
  water as (
    select w.log_date, sum(w.ml)::numeric as ml
      from public.water_logs w
     where w.user_id = auth.uid()
       and w.log_date in (select day from window_days)
     group by w.log_date
  ),
  weights as (
    select wl.weight_kg, wl.logged_at
      from public.weight_logs wl
     where wl.user_id = auth.uid()
       and wl.logged_at >= current_date - interval '6 days'
  )
  select
    (select count(*)::integer from per_day),
    (select coalesce(sum(entries), 0)::integer from per_day),
    (select coalesce(round(avg(calories)), 0)::integer from per_day),
    (select coalesce(round(avg(protein_g)), 0)::integer from per_day),
    (select coalesce(round(avg(carbs_g)), 0)::integer from per_day),
    (select coalesce(round(avg(fat_g)), 0)::integer from per_day),
    -- "On target" is within a tenth of the goal either way. A day is not a
    -- failure for being forty calories over, and a band is what anyone
    -- actually means by hitting it.
    (
      select coalesce(count(*), 0)::integer
        from per_day p, target t
       where t.calories is not null
         and p.calories between t.calories * 0.9 and t.calories * 1.1
    ),
    (select coalesce(t.calories, 0)::integer from target t),
    -- Averaged over days with a drink recorded, for the same reason the
    -- calories are: a day nobody logged is missing, not zero.
    (select coalesce(round(avg(ml)), 0)::integer from water),
    (
      select round(
        coalesce(
          (select weight_kg from weights order by logged_at desc limit 1)
          - (select weight_kg from weights order by logged_at asc limit 1),
          0
        )::numeric,
        1
      )
    ),
    (select round(weight_kg::numeric, 1) from weights order by logged_at asc limit 1),
    (select round(weight_kg::numeric, 1) from weights order by logged_at desc limit 1);
$$;

-- ---------------------------------------------------------------------------
-- 3. Grants
-- ---------------------------------------------------------------------------
revoke execute on function public.logging_streak() from public;
revoke execute on function public.weekly_recap() from public;

grant execute on function public.logging_streak() to authenticated;
grant execute on function public.weekly_recap() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Verify
-- ---------------------------------------------------------------------------
--   select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and proname in ('logging_streak', 'weekly_recap');
--
-- Two rows. Both return zeros from the SQL editor, where `auth.uid()` is null;
-- they answer per reader from the app.
