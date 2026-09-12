-- One day of grace on a broken streak, earned rather than given.
--
-- Prerequisites: `tracker_insights.sql` (this replaces `logging_streak()` from
-- it) and `daily_logs`. Re-runnable.
--
-- Run this in the Supabase SQL editor (Dashboard -> SQL Editor -> New query).
--
-- ---------------------------------------------------------------------------
-- What this is for
-- ---------------------------------------------------------------------------
-- A streak is the one number in Bulkr that hurts to lose, which is exactly why
-- it is the right thing to attach a rewarded ad to: the user wants something
-- specific, the price is thirty seconds of attention, and nobody is worse off.
--
-- It is also the reason to keep it tight. A streak that can be bought back
-- whenever it breaks is not a streak, it is a subscription to a number — so:
--
--   * only a **single** missed day can be restored, and only on the day after
--     it was missed. Miss two and it is gone.
--   * at most one restore per **30 days**.
--   * the restore day must have no log of its own, so this can never be used
--     to invent history that contradicts what was recorded.
--
-- ---------------------------------------------------------------------------
-- On trusting the client
-- ---------------------------------------------------------------------------
-- The app calls `restore_streak()` after AdMob reports the video was watched,
-- and nothing here verifies that. A patched client could call it without
-- watching anything.
--
-- That is deliberate, and it is worth saying why rather than leaving it to be
-- discovered. Closing the gap means AdMob server-side verification: a callback
-- URL, a signature to check, a public key to fetch and cache. What it would
-- protect is a vanity number that no leaderboard reads and nothing is charged
-- for. The rules above are the real defence — they bound the damage to "this
-- person's own streak survived a day it should not have", which is the same
-- harm as them logging a glass of water they did not drink.
--
-- What is *not* trusted to the client: the cooldown, the single-day rule, and
-- the no-overwriting rule. All three are enforced below, in a function the app
-- can only call, against a table the app cannot write.

-- ---------------------------------------------------------------------------
-- 1. The table
-- ---------------------------------------------------------------------------

create table if not exists public.streak_restores (
  user_id     uuid        not null references auth.users (id) on delete cascade,
  -- The day being filled in. A DATE, in the user's own calendar, exactly like
  -- `daily_logs.log_date` — see the note in `tracker_insights.sql` about why
  -- that is not a UTC day.
  log_date    date        not null,
  created_at  timestamptz not null default now(),

  primary key (user_id, log_date)
);

-- The cooldown query: "when did this user last restore".
create index if not exists streak_restores_user_created_idx
  on public.streak_restores (user_id, created_at desc);

alter table public.streak_restores enable row level security;

-- Read your own. That is the whole grant — there is no insert policy, and the
-- function below is `security definer` for exactly that reason.
drop policy if exists "Users read their own streak restores"
  on public.streak_restores;
create policy "Users read their own streak restores"
  on public.streak_restores for select to authenticated
  using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- 2. The streak, now counting restored days
-- ---------------------------------------------------------------------------
-- Identical to `tracker_insights.sql` except for the union in `days`. Replaced
-- wholesale rather than patched, because a streak function that disagreed with
-- itself between two files is the kind of bug that is found months later by
-- somebody whose number went down.
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
       and log_date > current_date - 730
    union
    select log_date
      from public.streak_restores
     where user_id = auth.uid()
       and log_date <= current_date
       and log_date > current_date - 730
  ),
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
  select coalesce(
    (select length from latest where last_day >= current_date - 1),
    0
  );
$$;

-- ---------------------------------------------------------------------------
-- 3. Is there anything to restore?
-- ---------------------------------------------------------------------------
-- Returns the length the streak would come back as, or 0.
--
-- Non-zero only when the most recent run ended the day before yesterday: fill
-- yesterday and the run reaches yesterday, which is where `logging_streak()`
-- still counts it. Any older and one day is not enough, which is the point.
create or replace function public.restorable_streak()
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with days as (
    select distinct log_date
      from public.daily_logs
     where user_id = auth.uid()
       and log_date <= current_date
       and log_date > current_date - 730
    union
    select log_date
      from public.streak_restores
     where user_id = auth.uid()
       and log_date <= current_date
       and log_date > current_date - 730
  ),
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
  select coalesce(
    (
      select l.length + 1
        from latest l
       where l.last_day = current_date - 2
         -- A run of one is a day, not a streak. Nothing to mourn, nothing to
         -- sell.
         and l.length > 1
         -- The cooldown.
         and not exists (
           select 1 from public.streak_restores r
            where r.user_id = auth.uid()
              and r.created_at > now() - interval '30 days'
         )
    ),
    0
  );
$$;

-- ---------------------------------------------------------------------------
-- 4. Do it
-- ---------------------------------------------------------------------------
-- Returns the streak afterwards, which is 0 when nothing was restorable — so
-- the caller never has to ask twice, and a client that calls this without
-- having earned it gets the same answer as one that calls it too often.
--
-- `security definer` because `streak_restores` has no insert policy. The
-- search_path is pinned: a definer function that resolves its own tables
-- through a caller-controlled search_path is the classic way to hand out the
-- owner's rights by accident.
create or replace function public.restore_streak()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  gap date := current_date - 1;
begin
  if uid is null then
    return 0;
  end if;

  -- Re-checked here rather than trusted from whatever the client last read.
  -- Between the app asking and the user finishing a thirty-second video, the
  -- day can turn over and the answer can change.
  if public.restorable_streak() = 0 then
    return 0;
  end if;

  -- `do nothing` rather than an upsert: a day that already has a real log is
  -- not a gap, and this must never be able to rewrite recorded history.
  insert into public.streak_restores (user_id, log_date)
  values (uid, gap)
  on conflict (user_id, log_date) do nothing;

  return public.logging_streak();
end;
$$;

revoke all on function public.restorable_streak() from public;
revoke all on function public.restore_streak() from public;
grant execute on function public.restorable_streak() to authenticated;
grant execute on function public.restore_streak() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Reload the API's schema cache
-- ---------------------------------------------------------------------------
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
--   select public.logging_streak(), public.restorable_streak();
--
-- To try it end to end without waiting two days, as the service role:
--
--   -- pick a user, give them a run ending the day before yesterday
--   insert into public.daily_logs (user_id, log_date, ...) values ...
--   select public.restorable_streak();   -- expect run length + 1
--   select public.restore_streak();      -- expect the same number
--   select public.restorable_streak();   -- expect 0, for the next 30 days
--
--   select policyname, cmd from pg_policies where tablename = 'streak_restores';
--
-- Expect exactly one row, SELECT.
