-- ---------------------------------------------------------------------------
-- Bulkr — scheduled maintenance
-- ---------------------------------------------------------------------------
-- Run after `feed_schema.sql`. Safe to run more than once.
--
-- There is exactly one thing in this app that has to happen on a clock, and it
-- is `public.refresh_post_hot_scores()`.
--
-- Why it is needed at all: a post's `hot_score` is written by a trigger when
-- something happens to it — a like, a comment, a save. A trigger cannot see
-- time pass. So a post that stops getting engagement keeps the score it had
-- when it was last touched, forever, and sits above newer posts it should have
-- aged out under. Discover is ordered by that stored column (every index on
-- it is, which is the point — a score computed at query time could not be
-- indexed and every pull would scan every public post ever written).
--
-- Without this schedule Discover still works; it just slowly stops being a
-- ranking and starts being a museum.
--
-- Why pg_cron and not a scheduled edge function: this runs inside the
-- database, on the database's own scheduler. It costs no function invocations,
-- no egress, and no network round trip — it is one UPDATE against a bounded
-- set of rows. A scheduled function doing the same work would be billed for
-- every firing, forever, to accomplish less.
--
-- Cost: the sweep touches only posts from the last seven days. Older ones have
-- decayed to a score no realistic engagement lifts back onto a front page, so
-- rewriting them hourly would be churn for nothing.

-- ---------------------------------------------------------------------------
-- 1. The extension
-- ---------------------------------------------------------------------------
-- Supabase ships pg_cron; it just is not enabled by default. Creating it in
-- the `extensions` schema is where Supabase's own dashboard puts it, so this
-- and the dashboard toggle end up in the same place rather than two.
create extension if not exists pg_cron with schema extensions;

-- ---------------------------------------------------------------------------
-- 2. The schedule
-- ---------------------------------------------------------------------------
-- Hourly, on the hour. The decay curve is measured in hours, so anything
-- faster rewrites rows to the same value and anything slower shows visibly.
--
-- Unscheduled first: `cron.schedule` on an existing name updates it, but only
-- on newer pg_cron. Removing and re-adding works on every version, and this
-- file has to be safe to run twice.
do $$
begin
  if not exists (
    select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'refresh_post_hot_scores'
  ) then
    raise notice
      'Bulkr: public.refresh_post_hot_scores() not found — run feed_schema.sql first. Nothing scheduled.';
    return;
  end if;

  perform cron.unschedule('refresh-post-hot-scores')
    where exists (
      select 1 from cron.job where jobname = 'refresh-post-hot-scores'
    );

  perform cron.schedule(
    'refresh-post-hot-scores',
    '0 * * * *',
    $cron$ select public.refresh_post_hot_scores() $cron$
  );

  raise notice 'Bulkr: hot-score sweep scheduled hourly.';
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Verify
-- ---------------------------------------------------------------------------
-- What is scheduled:
--
--   select jobid, schedule, jobname, active from cron.job;
--
-- Whether it has been running, and what it did:
--
--   select jobid, status, return_message, start_time
--     from cron.job_run_details
--    order by start_time desc
--    limit 10;
--
-- To stop it:
--
--   select cron.unschedule('refresh-post-hot-scores');
