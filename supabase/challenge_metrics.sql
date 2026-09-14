-- What a challenge can measure, and how a standing is computed.
--
-- Prerequisites: `feed_challenges.sql`, `tracker_schema.sql`,
-- `meals_policies.sql` (for the `daily_logs (user_id, log_date)` index this
-- leans on). Re-runnable.
--
-- Run this in the Supabase SQL editor (Dashboard -> SQL Editor -> New query).
--
-- ---------------------------------------------------------------------------
-- Why a second metric, and why this one
-- ---------------------------------------------------------------------------
-- Challenges shipped measuring one thing: kilograms gained. The composer
-- offers 7, 14, 30 and 90 days, and for the first two that metric does not
-- work — a week of scale movement is water, sodium and what time you weighed
-- yourself, and the person who wins a seven-day weight challenge is the person
-- who drank less on the last morning. A challenge nobody can win on purpose is
-- a challenge nobody enters twice.
--
-- `days_logged` counts the days you recorded any food inside the window. It is
-- entirely within the entrant's control, it settles the same way for everyone,
-- it works at seven days, and — the part that matters for this app — the way
-- to win it is to use the app every day. It is the rare leaderboard whose
-- incentive is the behaviour the product is for.
--
-- ---------------------------------------------------------------------------
-- What is deliberately not here yet
-- ---------------------------------------------------------------------------
-- `calories_hit` — days you landed on your calorie target — is the obvious
-- third, and it is not in this file because "your target" is not one number.
-- It is the plan, unless targets are custom, unless there are training and
-- rest day targets, in which case it depends on the weekday. Resolving that
-- per participant per day inside a leaderboard is a real piece of work, and it
-- would buy a metric that is `days_logged` with a stricter door. Worth doing
-- after that resolution exists as a function of its own; not worth inventing
-- it here.

-- ---------------------------------------------------------------------------
-- 1. Let the column hold the new value
-- ---------------------------------------------------------------------------
-- `feed_challenges.sql` creates this constraint inside `create table if not
-- exists`, so a project that has already run it will never see a widened
-- version there. It has to be replaced explicitly, and it has to be replaced
-- rather than added to: two CHECKs both apply, so leaving the old one would
-- keep rejecting exactly the values this is adding.

alter table public.challenges
  drop constraint if exists challenges_metric_check;

alter table public.challenges
  add constraint challenges_metric_check
    check (metric in ('weight_gain', 'days_logged'));

-- ---------------------------------------------------------------------------
-- 2. The scoring, in one place
-- ---------------------------------------------------------------------------
-- Both the leaderboard and the dashboard's standings need "what has everyone
-- in this challenge scored", and a second copy of that arithmetic is a second
-- copy to get wrong — the dashboard telling somebody they are second while the
-- leaderboard shows them third is worse than either screen not existing.
--
-- SECURITY DEFINER because it reads other people's `daily_logs` and `users`
-- rows, which no policy allows and no policy should: what comes back is a
-- count and a delta, never a row. The same argument that made
-- `challenge_leaderboard` definer in the first place.
--
-- `has_data` is the difference between the two metrics and is the whole reason
-- it is a column rather than `score is not null`:
--
--   * weight_gain — null means the participant has never logged a weight.
--     Zero would put them ahead of everyone who has lost and behind everyone
--     who has gained, and they have earned neither position.
--   * days_logged — zero means they logged nothing, which is a real score
--     honestly earned. There is no such thing as no data.

create or replace function public.challenge_scores(challenge uuid)
returns table (user_id uuid, score numeric, has_data boolean, joined_at timestamptz)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    p.user_id,
    case c.metric
      when 'weight_gain' then
        case
          when p.start_weight_kg is null or u.current_weight_kg is null
            then null
          -- Rounded on the way out. A leaderboard reporting 2.3999999 kg is a
          -- leaderboard nobody trusts, and the precision is noise from a scale
          -- that reads to 0.1 at best.
          else round(u.current_weight_kg - p.start_weight_kg, 1)
        end
      when 'days_logged' then (
        select count(distinct d.log_date)::numeric
          from public.daily_logs d
         where d.user_id = p.user_id
           -- From whichever came later, the start or their joining: somebody
           -- who joins on day five has five fewer days available, the same way
           -- their weight snapshot is taken on day five rather than day one.
           and d.log_date >= greatest(c.starts_at, p.joined_at)::date
           and d.log_date <= least(now(), c.ends_at)::date
      )
    end as score,
    case c.metric
      when 'weight_gain' then
        (p.start_weight_kg is not null and u.current_weight_kg is not null)
      else true
    end as has_data,
    p.joined_at
  from public.challenge_participants p
  join public.challenges c on c.id = p.challenge_id
  join public.users u on u.id = p.user_id
 where p.challenge_id = challenge;
$$;

-- A note on the date casts above, because they are the one loose edge here.
-- `daily_logs.log_date` is a calendar date written by the device, from the
-- user's own local day (which starts at 04:00 — see `MealSlot`). `starts_at`
-- and `joined_at` are instants, and casting them to a date uses the server's
-- zone. So somebody who joins just after midnight in a zone ahead of UTC may
-- have their window opened one day early. That is the direction to be wrong
-- in: it can include a day they really did log, and it can never exclude one.

revoke all on function public.challenge_scores(uuid) from public;
grant execute on function public.challenge_scores(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. The leaderboard
-- ---------------------------------------------------------------------------
-- `gained_kg` is now `score`, because it is no longer always kilograms. The
-- unit belongs to the metric, and the client reads it off `challenges.metric`.
--
-- DROP first, not CREATE OR REPLACE: Postgres will not replace a function
-- whose OUT columns have changed, and the failure is a wall of text about
-- return types that reads like a syntax error.

drop function if exists public.challenge_leaderboard(uuid);

create function public.challenge_leaderboard(challenge uuid)
returns table (
  user_id uuid,
  username text,
  display_name text,
  avatar_url text,
  score numeric,
  joined_at timestamptz,
  has_data boolean
)
language sql
security definer
set search_path = public, pg_temp
stable
as $$
  select
    s.user_id,
    u.username::text,
    u.display_name::text,
    u.avatar_url,
    s.score,
    s.joined_at,
    s.has_data
  from public.challenge_scores(challenge) s
  join public.users u on u.id = s.user_id
  -- Most first. NULLS LAST puts the participants with nothing to compute from
  -- at the bottom, which is where "no data" belongs — not at the top, which is
  -- where a descending sort would otherwise put them. Ties break by who
  -- committed first.
 order by s.score desc nulls last, s.joined_at asc;
$$;

revoke all on function public.challenge_leaderboard(uuid) from public;
grant execute on function public.challenge_leaderboard(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. My standings, for the dashboard
-- ---------------------------------------------------------------------------
-- One row per challenge the signed-in user is currently in: their score, their
-- rank, and the person immediately above them.
--
-- That last part is the reason this function exists rather than the dashboard
-- calling `challenge_leaderboard` per challenge. "You are third" is a fact.
-- "Sara is 0.4 ahead of you" is a reason to open the app tomorrow, and it
-- cannot be computed without the row above yours — so the query that knows the
-- ranking is the one that should answer it, rather than shipping a whole
-- leaderboard to a card that draws one line of it.
--
-- Active only: started, not yet ended. A finished challenge belongs on the
-- challenges screen, not on the home screen, and one that has not started has
-- no standings to show.
--
-- SECURITY INVOKER would not work — the ranking is over everybody's scores.
-- It is scoped to `auth.uid()` inside instead, which is the same trade
-- `challenge_leaderboard` makes: definer, but it can only ever be asked about
-- the caller.

create or replace function public.my_challenge_standings()
returns table (
  challenge_id uuid,
  post_id uuid,
  title text,
  metric text,
  goal_amount numeric,
  starts_at timestamptz,
  ends_at timestamptz,
  participant_count integer,
  my_score numeric,
  my_rank integer,
  has_data boolean,
  ahead_score numeric,
  ahead_name text
)
language sql
security definer
set search_path = public, pg_temp
stable
as $$
  with mine as (
    select c.*
      from public.challenges c
      join public.challenge_participants p
        on p.challenge_id = c.id and p.user_id = auth.uid()
     where c.starts_at <= now()
       and c.ends_at > now()
  ),
  ranked as (
    select
      m.id as challenge_id,
      s.user_id,
      s.score,
      s.has_data,
      rank() over (
        partition by m.id
        order by s.score desc nulls last, s.joined_at asc
      ) as position,
      count(*) over (partition by m.id) as participants
    from mine m
    cross join lateral public.challenge_scores(m.id) s
  )
  select
    m.id,
    m.post_id,
    m.title,
    m.metric,
    m.goal_amount,
    m.starts_at,
    m.ends_at,
    me.participants::integer,
    me.score,
    me.position::integer,
    me.has_data,
    ahead.score,
    coalesce(nullif(btrim(au.display_name), ''), au.username)::text
  from mine m
  join ranked me on me.challenge_id = m.id and me.user_id = auth.uid()
  -- The one directly above. Null when they are leading, which the card reads
  -- as "you are top" rather than as missing data.
  left join lateral (
    select r.user_id, r.score
      from ranked r
     where r.challenge_id = m.id
       and r.position < me.position
     order by r.position desc
     limit 1
  ) ahead on true
  left join public.users au on au.id = ahead.user_id
 order by m.ends_at asc;
$$;

revoke all on function public.my_challenge_standings() from public;
grant execute on function public.my_challenge_standings() to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Reload the API's schema cache
-- ---------------------------------------------------------------------------
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
--   select * from public.my_challenge_standings();
--
-- And that both metrics score. As a signed-in user in a challenge:
--
--   select * from public.challenge_leaderboard('<challenge uuid>');
--
-- A `days_logged` challenge must return whole numbers with has_data true for
-- everyone, including participants who have logged nothing — zero is a score.
-- A `weight_gain` one must return null with has_data false for anybody who has
-- never logged a weight, and they must sort last.
