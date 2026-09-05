-- Water tracking.
--
-- Nothing in the app has ever recorded a drink. The only hydration that exists
-- is advice — `InsightEngine` tells the user how much to drink, from their
-- bodyweight, and then has no idea whether they did.
--
-- This is the table that closes that, plus the one column that lets someone
-- override the figure the advice derives.
--
-- Written to be re-runnable: every statement is guarded, so applying it twice
-- changes nothing the second time.
--
-- Run this in the Supabase SQL editor, after `tracker_schema.sql`.

-- ---------------------------------------------------------------------------
-- 1. The log
-- ---------------------------------------------------------------------------
-- One row per drink, not one row per day.
--
-- A running total on `users` would be a third of the size and is the wrong
-- shape twice over. It cannot be undone — the tap that adds 250 ml by mistake
-- has nothing to take back, only a number to decrement, and decrementing past
-- what was actually drunk is how a counter goes negative. And it cannot be
-- browsed: the tracker shows any day, so yesterday's water has to still exist
-- tomorrow.
--
-- `log_date` alongside `logged_at` looks redundant and is the same decision
-- `daily_logs` already made. The date is the user's local day, decided on the
-- device; the timestamp is the instant. Deriving one from the other server-side
-- would put the day boundary in UTC, which is the wrong midnight for everyone
-- not on it.
--
-- `ml` is an integer and constrained positive. A drink of zero is not a drink,
-- and a negative one is a bug reaching for the undo this table already has.

create table if not exists public.water_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  log_date date not null,
  ml integer not null check (ml > 0),
  logged_at timestamptz not null default now()
);

-- The tracker reads one day for one user, which is exactly this index. Ordered
-- descending on the date for the same reason `daily_logs_user_id_log_date_idx`
-- is: the days people look at are the recent ones.
create index if not exists water_logs_user_id_log_date_idx
  on public.water_logs (user_id, log_date desc);

-- ---------------------------------------------------------------------------
-- 2. Row level security
-- ---------------------------------------------------------------------------
-- Same shape as `weight_logs` and `daily_logs`: full access to your own rows,
-- no reads of anyone else's. Nothing in the feed shows what somebody drank, so
-- unlike `meals` there is no widened read here — and adding one later would be
-- a deliberate decision rather than an oversight.
--
-- RLS is enabled explicitly. A new table has it off by default, which would
-- make this table world-readable to every signed-in user through PostgREST.

alter table public.water_logs enable row level security;

drop policy if exists "Enable full access for users based on user_id"
  on public.water_logs;
create policy "Enable full access for users based on user_id"
  on public.water_logs for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 3. The goal
-- ---------------------------------------------------------------------------
-- Derived from bodyweight — 35 ml per kg, the figure `InsightEngine` has been
-- quoting all along — so it needs no column at all in the ordinary case, and
-- moves on its own as the user bulks.
--
-- This column is the override, and it is nullable *meaning* "derive it". Null
-- is not a missing value here: it is the normal state, and the only way to
-- distinguish "I never set one" from "I set one that happens to equal the
-- derived figure". Someone who overrides and then wants the automatic number
-- back sets it to null again.
--
-- No default, for the same reason. A default of 3000 would be an override
-- nobody chose, applied to every existing account, permanently detaching the
-- goal from the weight it is supposed to follow.

alter table public.users
  add column if not exists water_target_ml integer;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'users_water_target_ml_check'
       and conrelid = 'public.users'::regclass
  ) then
    -- An upper bound as well as a lower one. 20 litres is far past any real
    -- intake and well into the range where drinking to a goal is dangerous,
    -- so the column refuses to store it — a fat-fingered 30000 should not
    -- become a target the app then nags someone towards.
    alter table public.users
      add constraint users_water_target_ml_check
      check (water_target_ml is null
             or (water_target_ml > 0 and water_target_ml <= 20000));
  end if;
end
$$;

-- `users` already has an UPDATE policy scoped to `auth.uid() = id` and no
-- column-level grant narrowing it, so an owner can write their own
-- `water_target_ml` and nobody else's. Same reasoning as `bio` in
-- `feed_profiles.sql` and `avatar_url` in `feed_avatars.sql`.

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- 4. Verify
-- ---------------------------------------------------------------------------
-- The table and its column types:
--   select column_name, data_type, is_nullable, column_default
--     from information_schema.columns
--    where table_schema = 'public' and table_name = 'water_logs'
--    order by ordinal_position;
--
-- That RLS is on AND has a policy — enabled with no policy denies everything,
-- which is the state weight_logs was in and reported as 42501:
--   select c.relname, c.relrowsecurity as rls_enabled,
--          count(p.policyname) as policies
--     from pg_class c
--     join pg_namespace n on n.oid = c.relnamespace
--     left join pg_policies p on p.tablename = c.relname
--    where n.nspname = 'public' and c.relname in ('water_logs', 'users')
--    group by c.relname, c.relrowsecurity;
--
-- That the constraints bite. The first succeeds, the next two must fail:
--   insert into public.water_logs (user_id, log_date, ml)
--   values (auth.uid(), current_date, 250);
--   insert into public.water_logs (user_id, log_date, ml)
--   values (auth.uid(), current_date, 0);            -- violates ml > 0
--   update public.users set water_target_ml = 30000
--    where id = auth.uid();                          -- violates the range
--
-- Today's total, which is what the tracker shows:
--   select coalesce(sum(ml), 0) as ml
--     from public.water_logs
--    where user_id = auth.uid() and log_date = current_date;
--
-- And that null is a storable, settable state — this must report null, not 0:
--   update public.users set water_target_ml = null where id = auth.uid();
--   select water_target_ml from public.users where id = auth.uid();
