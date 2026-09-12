-- ---------------------------------------------------------------------------
-- Bulkr — one question instead of three
-- ---------------------------------------------------------------------------
-- Run after `feed_engagement.sql` and `image_thumbnails.sql`. Safe to run more
-- than once.
--
-- Every page of every feed asked three separate questions about the twenty
-- posts it had just fetched: which have I liked, which have I saved, and which
-- of the meals attached to them have I already taken a copy of. Three HTTP
-- requests, three connections out of the pool, three sets of policies
-- evaluated, for three sets of ids.
--
-- They run concurrently on the device, so this is not really about how long a
-- page takes. It is about what the server does per page: on a small instance,
-- request count is what decides whether you need a bigger one, and a feed is
-- the thing every user does most.
--
-- This is not `security definer`, deliberately, and that is the whole safety
-- argument. It reads only rows belonging to `auth.uid()` and it runs as the
-- caller, so every policy on `post_likes`, `post_saves` and `meals` applies
-- exactly as it did when the app asked these questions one at a time. There is
-- no new way to see anything; there is one fewer round trip.

create or replace function public.post_engagement(p_post_ids uuid[])
returns table (
  post_id uuid,
  liked boolean,
  saved boolean
)
language sql
stable
set search_path = public
as $$
  select
    p.id as post_id,
    exists (
      select 1 from public.post_likes l
       where l.post_id = p.id and l.user_id = auth.uid()
    ) as liked,
    exists (
      select 1 from public.post_saves s
       where s.post_id = p.id and s.user_id = auth.uid()
    ) as saved
  from unnest(p_post_ids) as p(id);
$$;

-- Which of these meals the caller has already copied.
--
-- Kept separate from the one above rather than folded into it, because the
-- app asks it only for a page that actually carries somebody else's meal.
-- Most pages do not, and a page with no attachments should not spend a round
-- trip discovering that.
--
-- Matched on `source_meal_id`, which is how a copy remembers what it came
-- from. The ids handed in are the roots, so taking the same recipe from two
-- different people's posts is recognised as already taken.
create or replace function public.copied_meals(p_meal_ids uuid[])
returns table (source_meal_id uuid)
language sql
stable
set search_path = public
as $$
  select distinct m.source_meal_id
    from public.meals m
   where m.creator_id = auth.uid()
     and m.source_meal_id = any(p_meal_ids);
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
-- `execute` is granted to public by default on a new function, which is wider
-- than this needs. Revoked and re-granted so an anonymous caller cannot reach
-- them — they would answer with `auth.uid()` null and return nothing useful,
-- but a function that exists for signed-in users should be reachable by
-- signed-in users only.
revoke execute on function public.post_engagement(uuid[]) from public;
revoke execute on function public.copied_meals(uuid[]) from public;

grant execute on function public.post_engagement(uuid[]) to authenticated;
grant execute on function public.copied_meals(uuid[]) to authenticated;

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- As a signed-in user, from the SQL editor these return nothing useful because
-- `auth.uid()` is null there. From the app they answer per reader. To check
-- they exist at all:
--
--   select proname, pronargs
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public'
--      and proname in ('post_engagement', 'copied_meals');
--
-- Two rows.
