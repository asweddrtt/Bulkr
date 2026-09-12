-- Where the free tier's numbers are actually enforced.
--
-- Prerequisites: `premium.sql` (the `free_*()` functions and `is_premium()`),
-- `meals_policies.sql`, `feed_challenges.sql`. Re-runnable.
--
-- Run this in the Supabase SQL editor (Dashboard -> SQL Editor -> New query).
--
-- ---------------------------------------------------------------------------
-- Triggers rather than policies, and why
-- ---------------------------------------------------------------------------
-- A `with check` on the existing insert policy would do the job and would fail
-- as SQLSTATE 42501: "new row violates row-level security policy". The app
-- already maps 42501 to "you don't have permission to do that", which is both
-- wrong and unhelpful — hitting a plan limit is not a permission problem, and
-- the person seeing it can do something about it.
--
-- So each limit is a trigger raising its own SQLSTATE, `BLKR2`, with the name
-- of the limit in the hint. That is the same shape `moderation_terms.sql`
-- already uses for blocked terms (`BLKR1`), and it lets the app say "you have
-- reached the 20 meals a free account keeps" and offer the upgrade, which is
-- the only version of this that is any use to anybody.
--
-- ---------------------------------------------------------------------------
-- What is enforced here, and what deliberately is not
-- ---------------------------------------------------------------------------
-- Enforced: the size of the meal library, and how many challenges can be run
-- at once. Both cost storage or rows, both are checked on the way in, and
-- neither can be worked around by a patched client.
--
-- **Not enforced: how far back the tracker can be read.** That one is gated in
-- the app and nowhere else, on purpose. Restricting `select` on `daily_logs`
-- to seven days would also restrict it for `logging_streak()` and
-- `weekly_recap()`, which run as the caller — so every free account's streak
-- would silently cap at seven days, which is a worse bug than the thing being
-- prevented. And what is being prevented is somebody reading their own data,
-- which costs nothing and harms nobody. A display gate is the honest name for
-- it, and calling it anything else in the documentation would be worse than
-- the gap.

-- ---------------------------------------------------------------------------
-- 1. How big is the library?
-- ---------------------------------------------------------------------------
-- "My Meals" is meals you created plus meals you saved, shown as one list — so
-- the limit counts them as one list too. Distinct ids, because saving a meal
-- you also created must not cost two of the twenty.
create or replace function public.meal_library_size(uid uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select count(*)::integer from (
    select id as meal_id from public.meals where creator_id = uid
    union
    select meal_id from public.saved_meals where user_id = uid
  ) as library;
$$;

revoke all on function public.meal_library_size(uuid) from public;
grant execute on function public.meal_library_size(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 2. The meal library cap
-- ---------------------------------------------------------------------------
create or replace function public.enforce_meal_limit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
begin
  -- No caller (a service-role import, a trigger cascade): not a user action,
  -- so not the user's limit to hit.
  if uid is null then
    return new;
  end if;

  if public.is_premium(uid) then
    return new;
  end if;

  if public.meal_library_size(uid) >= public.free_saved_meal_limit() then
    raise exception 'Bulkr: free accounts keep % meals.',
      public.free_saved_meal_limit()
      using errcode = 'BLKR2', hint = 'saved_meals';
  end if;

  return new;
end;
$$;

drop trigger if exists meals_free_limit on public.meals;
create trigger meals_free_limit
  before insert on public.meals
  for each row execute function public.enforce_meal_limit();

drop trigger if exists saved_meals_free_limit on public.saved_meals;
create trigger saved_meals_free_limit
  before insert on public.saved_meals
  for each row execute function public.enforce_meal_limit();

-- Only inserts. An update to a meal that is already in the library is not
-- growth, and blocking it would mean somebody over the limit — because they
-- subscribed, filled it, and then lapsed — could not fix a typo in a meal they
-- already own. Nothing is deleted when a subscription ends.

-- ---------------------------------------------------------------------------
-- 3. The challenge cap
-- ---------------------------------------------------------------------------
-- "Active" means still running. A challenge that ended last month is not
-- occupying anything, and counting it would mean the cap tightens over time
-- until a free account can never join another one — which is a limit that
-- turns into a ban.
create or replace function public.active_challenge_count(uid uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select count(*)::integer
    from public.challenge_participants p
    join public.challenges c on c.id = p.challenge_id
   where p.user_id = uid
     and c.ends_at > now();
$$;

revoke all on function public.active_challenge_count(uuid) from public;
grant execute on function public.active_challenge_count(uuid) to authenticated;

create or replace function public.enforce_challenge_limit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null or new.user_id is distinct from uid then
    return new;
  end if;

  if public.is_premium(uid) then
    return new;
  end if;

  if public.active_challenge_count(uid) >= public.free_active_challenge_limit()
  then
    raise exception 'Bulkr: free accounts run % challenge at a time.',
      public.free_active_challenge_limit()
      using errcode = 'BLKR2', hint = 'active_challenges';
  end if;

  return new;
end;
$$;

drop trigger if exists challenge_participants_free_limit
  on public.challenge_participants;
create trigger challenge_participants_free_limit
  before insert on public.challenge_participants
  for each row execute function public.enforce_challenge_limit();

-- ---------------------------------------------------------------------------
-- 4. Indexes the counts need
-- ---------------------------------------------------------------------------
-- Both counts run on every insert into the tables they guard, so they are the
-- one place in this schema where an index is not optional.
--
-- `meals (creator_id, created_at desc)` and `saved_meals (user_id, saved_at
-- desc)` already exist from `meals_policies.sql` and serve the library count.

create index if not exists challenge_participants_user_id_idx
  on public.challenge_participants (user_id);

-- ---------------------------------------------------------------------------
-- 5. Reload the API's schema cache
-- ---------------------------------------------------------------------------
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
--   select public.meal_library_size(auth.uid()),
--          public.free_saved_meal_limit(),
--          public.active_challenge_count(auth.uid());
--
-- And that the limit actually bites. As an ordinary signed-in user with a full
-- library:
--
--   insert into public.meals (creator_id, title) values (auth.uid(), 'x');
--
-- must fail with SQLSTATE BLKR2 and a hint of `saved_meals`. Granting that
-- account premium and running it again must succeed:
--
--   insert into public.subscriptions (user_id, tier, source)
--   values ('<uuid>', 'premium', 'manual')
--   on conflict (user_id) do update set tier = 'premium';
