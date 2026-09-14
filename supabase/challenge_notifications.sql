-- Telling people what is happening in their challenges.
--
-- Prerequisites: `notifications.sql`, `feed_challenges.sql`,
-- `challenge_metrics.sql`, `maintenance_cron.sql` (for pg_cron). Re-runnable.
--
-- Run this in the Supabase SQL editor (Dashboard -> SQL Editor -> New query).
--
-- ---------------------------------------------------------------------------
-- The problem this fixes
-- ---------------------------------------------------------------------------
-- A challenge never said anything. Not when somebody joined the one you set
-- up, not when yours was about to start, not when it had a day left, not when
-- it finished. You found out by opening a screen three taps inside the account
-- sheet and reading it.
--
-- So a challenge was a thing you entered and then forgot, which is the same as
-- a thing you did not enter. Every notification below exists to put it back in
-- front of somebody at a moment when there is still something they can do
-- about it — which is why "one day left" is a notification and "seven days
-- left" is not.
--
-- ---------------------------------------------------------------------------
-- Everything points at the announcement post
-- ---------------------------------------------------------------------------
-- `notifications` has `post_id` and no `challenge_id`, and it stays that way.
-- A challenge exists only as its post's challenge — `challenges.post_id` is
-- UNIQUE and the row CASCADEs from the post — so the post *is* the challenge's
-- address, it is already how you reach a leaderboard, and it is already what
-- the notification list knows how to open. A parallel column would be a second
-- way to say the same thing and a second thing to keep pointing at the right
-- row when a post is deleted.
--
-- It also gives deduplication for free. The unique index on
-- (user_id, actor_id, kind, post_id, comment_id) means "this challenge is
-- ending" can only ever be written once per person per challenge, which is
-- what makes it safe for the sweep below to run every day and simply re-offer
-- the same rows.

-- ---------------------------------------------------------------------------
-- 1. The new kinds
-- ---------------------------------------------------------------------------
-- Replaced rather than added to, for the same reason as the metric CHECK in
-- `challenge_metrics.sql`: `notifications.sql` writes this inside a
-- `create table if not exists`, so an existing project would never pick up a
-- widened version, and two CHECKs both apply.

alter table public.notifications
  drop constraint if exists notifications_kind_check;

alter table public.notifications
  add constraint notifications_kind_check
    check (kind in (
      'follow', 'like', 'comment', 'reply',
      -- Somebody joined a challenge you created.
      'challenge_joined',
      -- One you are in starts within the day.
      'challenge_starting',
      -- One you are in has a day left.
      'challenge_ending',
      -- One you were in has finished.
      'challenge_ended',
      -- Somebody went past you on a leaderboard.
      'challenge_passed'
    ));

-- ---------------------------------------------------------------------------
-- 2. Notifications with nobody behind them
-- ---------------------------------------------------------------------------
-- `notify()` refuses a null actor, and it is right to: every kind it was
-- written for is one person doing something to another, and a like from
-- nobody is a bug. Three of the kinds above have no actor at all — a deadline
-- is not a person — so they need their own door rather than a weakened one.
--
-- No block check here, deliberately. There is nobody to have blocked: the
-- sender is the clock. The recipient is always a participant of the challenge
-- being reported on, so the only way to stop receiving these is to leave it,
-- which is the correct control.
--
-- The table's own `notifications_no_self` CHECK still holds, and passes: a
-- null actor is DISTINCT FROM any user id.

create or replace function public.notify_system(
  p_user uuid,
  p_kind text,
  p_post uuid default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_user is null then
    return;
  end if;

  insert into public.notifications (user_id, actor_id, kind, post_id)
  values (p_user, null, p_kind, p_post)
  on conflict do nothing;
end;
$$;

revoke all on function public.notify_system(uuid, text, uuid) from public;
-- Service role only. Nothing a signed-in client does should be able to write a
-- notification that claims to come from the system.
grant execute on function public.notify_system(uuid, text, uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 3. Somebody joined yours
-- ---------------------------------------------------------------------------
-- The one notification here with a real actor, and the most useful of the
-- five: setting up a challenge and hearing nothing is how somebody concludes
-- the feature does not work. Goes through `notify()` rather than
-- `notify_system()`, so a block still stops it.

create or replace function public.challenge_participants_notify()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  owner uuid;
  announcement uuid;
begin
  select c.created_by, c.post_id
    into owner, announcement
    from public.challenges c
   where c.id = new.challenge_id;

  -- `notify` drops it when the joiner is the creator, which is every
  -- challenge's first participant.
  perform public.notify(
    owner, new.user_id, 'challenge_joined', announcement
  );

  return new;
end;
$$;

drop trigger if exists challenge_participants_notify
  on public.challenge_participants;
create trigger challenge_participants_notify
  after insert on public.challenge_participants
  for each row execute function public.challenge_participants_notify();

-- ---------------------------------------------------------------------------
-- 4. Somebody went past you
-- ---------------------------------------------------------------------------
-- The one that makes a leaderboard a leaderboard. Being third is a fact;
-- being told that you *were* second is an event.
--
-- Fired from the weight write rather than from a sweep, because the before and
-- after are both right there. `old` and `new` give this user's score before
-- and after the weigh-in, and anybody whose score sits between the two has
-- just been overtaken by it — no stored ranks, no recomputation of anybody
-- else's history, and no possibility of announcing a pass that did not happen.
--
-- **`weight_gain` challenges only.** The same idea applies to `days_logged`,
-- and it would have to hang off `daily_logs`, which is written several times a
-- day per user — so it would mean a leaderboard scan per meal, to announce a
-- pass that is usually a tie being broken by who logged first. A day's
-- logging is not a race in the way a weigh-in is. If it is added later it
-- belongs on the first entry of a day, not on every entry.

create or replace function public.challenge_weight_passes()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  passed record;
begin
  -- Nothing moved, or there is nothing to compare against.
  if new.current_weight_kg is null
     or old.current_weight_kg is null
     or new.current_weight_kg <= old.current_weight_kg then
    return new;
  end if;

  -- Scored inline rather than through `challenge_scores`, which is the one
  -- place that arithmetic otherwise lives. The reason is cost: that function
  -- returns a whole challenge, so asking it per rival would be a scan of every
  -- participant for every participant — quadratic, on a write that happens
  -- every time anybody steps on a scale. For `weight_gain`, and only for
  -- `weight_gain`, the score is two columns subtracted, and doing it here
  -- keeps this linear. The `c.metric = 'weight_gain'` join condition below is
  -- what makes that safe; a metric added later cannot silently fall through
  -- to the wrong formula, it simply will not match.
  for passed in
    select
      c.post_id,
      rival.user_id,
      round(old.current_weight_kg - mine.start_weight_kg, 1) as was,
      round(new.current_weight_kg - mine.start_weight_kg, 1) as now_is,
      round(ru.current_weight_kg - rival.start_weight_kg, 1) as theirs
    from public.challenge_participants mine
    join public.challenges c
      on c.id = mine.challenge_id
     and c.metric = 'weight_gain'
     and c.starts_at <= now()
     and c.ends_at > now()
    join public.challenge_participants rival
      on rival.challenge_id = mine.challenge_id
     and rival.user_id <> new.id
     and rival.start_weight_kg is not null
    join public.users ru
      on ru.id = rival.user_id
     and ru.current_weight_kg is not null
   where mine.user_id = new.id
     and mine.start_weight_kg is not null
  loop
    -- Overtaken: they were ahead of where this user was, and are no longer
    -- ahead of where this user now is. `>=` on the lower bound so drawing
    -- level counts as a pass — a tie breaks on who joined first, and on a
    -- leaderboard the person who just moved is the one who did something.
    if passed.theirs >= passed.was and passed.theirs <= passed.now_is then
      perform public.notify(
        passed.user_id, new.id, 'challenge_passed', passed.post_id
      );
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists challenge_weight_passes on public.users;
create trigger challenge_weight_passes
  after update of current_weight_kg on public.users
  for each row execute function public.challenge_weight_passes();

-- ---------------------------------------------------------------------------
-- 5. The clock
-- ---------------------------------------------------------------------------
-- Starting, ending, ended. All three are "a date arrived", which no row being
-- written can notice, so they are swept.
--
-- The windows are wider than the schedule (a day for the two deadlines, two
-- days for the finish) so that a run the scheduler missed is still caught by
-- the next one. That only works because the unique index makes a second
-- delivery of the same thing a no-op — without it, a wide window would mean
-- telling everybody their challenge was ending once per sweep.

create or replace function public.challenge_clock_sweep()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  sent integer := 0;
  due record;
begin
  for due in
    select p.user_id, c.post_id,
      case
        when c.starts_at > now() then 'challenge_starting'
        when c.ends_at   > now() then 'challenge_ending'
        else 'challenge_ended'
      end as kind
      from public.challenges c
      join public.challenge_participants p on p.challenge_id = c.id
     where (c.starts_at > now() and c.starts_at <= now() + interval '1 day')
        or (c.ends_at   > now() and c.ends_at   <= now() + interval '1 day')
        or (c.ends_at  <= now() and c.ends_at    > now() - interval '2 days')
  loop
    perform public.notify_system(due.user_id, due.kind, due.post_id);
    sent := sent + 1;
  end loop;

  return sent;
end;
$$;

revoke all on function public.challenge_clock_sweep() from public;
grant execute on function public.challenge_clock_sweep() to service_role;

-- ---------------------------------------------------------------------------
-- 6. The schedule
-- ---------------------------------------------------------------------------
-- Daily rather than hourly. Every one of these is about a day boundary, so an
-- hourly sweep would do twenty-four times the work to deliver the same rows at
-- the same resolution.
--
-- 09:00 UTC: late morning in Europe, early morning in the Gulf where most of
-- this app's users are, and not the middle of anybody's night. A notification
-- about a deadline is only useful during a day somebody can act in.
--
-- Unscheduled and re-added rather than updated in place — `cron.schedule` on
-- an existing name only updates on newer pg_cron, and this works on every
-- version. Same pattern as `maintenance_cron.sql`.

do $$
begin
  if to_regprocedure('public.challenge_clock_sweep()') is null then
    raise notice
      'Bulkr: public.challenge_clock_sweep() not found. Nothing scheduled.';
    return;
  end if;

  perform cron.unschedule('challenge-clock-sweep')
    where exists (
      select 1 from cron.job where jobname = 'challenge-clock-sweep'
    );

  perform cron.schedule(
    'challenge-clock-sweep',
    '0 9 * * *',
    $cron$ select public.challenge_clock_sweep() $cron$
  );

  raise notice 'Bulkr: challenge clock sweep scheduled daily at 09:00 UTC.';
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. The notification list has to be able to name the challenge
-- ---------------------------------------------------------------------------
-- `notification_feed` returns the first 80 characters of the post as the thing
-- that identifies it. For a challenge that is the announcement's prose, which
-- is whatever the creator felt like writing — "right, who's in" — and not the
-- challenge's title, which is the only part anybody would recognise.
--
-- So the excerpt prefers the challenge title when the post has one. Everything
-- else about the function is unchanged; it is replaced whole because that is
-- how `create or replace` works and because a copy that drifts from
-- `notifications.sql` is worse than one that is obviously the same query.

create or replace function public.notification_feed(p_limit integer default 50)
returns table (
  id uuid,
  kind text,
  created_at timestamptz,
  read_at timestamptz,
  actor_id uuid,
  actor_username text,
  actor_display_name text,
  actor_avatar_url text,
  post_id uuid,
  post_excerpt text,
  comment_id uuid,
  comment_excerpt text
)
language sql
stable
set search_path = public
as $$
  select
    n.id,
    n.kind,
    n.created_at,
    n.read_at,
    n.actor_id,
    a.username,
    a.display_name,
    a.avatar_url,
    n.post_id,
    -- The challenge's title when there is one, the post's opening otherwise.
    -- Enough to recognise which, never the thing itself: a notification list
    -- carrying whole post bodies would be a feed's worth of egress for a
    -- screen that shows one line each.
    coalesce(ch.title, left(p.content, 80)),
    n.comment_id,
    left(c.content, 80)
  from public.notifications n
  left join public.users a on a.id = n.actor_id
  left join public.posts p on p.id = n.post_id
  left join public.challenges ch on ch.post_id = n.post_id
  left join public.post_comments c on c.id = n.comment_id
  where n.user_id = auth.uid()
  order by n.created_at desc
  limit least(coalesce(p_limit, 50), 100);
$$;

revoke execute on function public.notification_feed(integer) from public;
grant execute on function public.notification_feed(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 8. Reload the API's schema cache
-- ---------------------------------------------------------------------------
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
--   select jobid, schedule, jobname, active from cron.job
--    where jobname = 'challenge-clock-sweep';
--
-- Run the sweep by hand — it is idempotent, so this is safe at any time and
-- the second run should report the same number having written nothing new:
--
--   select public.challenge_clock_sweep();
--   select kind, count(*) from public.notifications group by kind;
--
-- And that joining tells the creator. As a second account, join a challenge
-- somebody else made, then as its creator:
--
--   select kind, actor_id, post_id from public.notifications
--    where user_id = auth.uid() and kind = 'challenge_joined';
