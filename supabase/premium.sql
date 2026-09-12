-- Free and premium accounts: where the answer lives, and who is allowed to
-- write it.
--
-- Prerequisites: none beyond `auth.users`, which Supabase creates. Safe to run
-- before or after everything else in this directory.
--
-- Re-runnable: every statement is guarded, so applying it twice changes
-- nothing the second time.
--
-- Run this in the Supabase SQL editor (Dashboard -> SQL Editor -> New query).
--
-- ---------------------------------------------------------------------------
-- The one thing to understand before changing anything here
-- ---------------------------------------------------------------------------
-- The client is on somebody else's phone. Everything it says about itself is a
-- claim, including "I am premium", and a determined user can patch an app and
-- make it claim whatever they like.
--
-- So this table is the only place the answer is decided, and **the app can
-- only read it.** There is no insert policy, no update policy and no delete
-- policy for `authenticated` below, and that is not an oversight — it is the
-- whole design. Rows are written by the service role: the webhook that
-- receives App Store and Play notifications, or a human in the dashboard.
--
-- What the client caches locally decides *presentation* — whether to draw a
-- banner ad, whether a lock icon appears. Limits that cost money or storage
-- are enforced by policies that call `is_premium()` below, where a patched
-- client cannot reach. See the note at the top of `lib/models/entitlement.dart`.

-- ---------------------------------------------------------------------------
-- 1. The table
-- ---------------------------------------------------------------------------
-- One row per user, or none. No row means free, which is why nothing has to
-- create a row at sign-up: an account that has never paid simply is not in
-- here, and a table of a million free rows saying `tier = 'free'` would be a
-- million rows that mean nothing.

create table if not exists public.subscriptions (
  user_id     uuid primary key references auth.users (id) on delete cascade,

  -- 'free' or 'premium'. Checked rather than an enum type: adding a tier to a
  -- check constraint is one statement, adding a value to an enum used by a
  -- policy is a migration and a lock.
  tier        text        not null default 'free'
                          check (tier in ('free', 'premium')),

  -- When the current period ends. NULL means it does not — a promo, a manual
  -- grant, or a lifetime purchase. A past date means lapsed, and the row is
  -- kept rather than deleted so "they used to pay" is answerable.
  expires_at  timestamptz,

  -- 'app_store' | 'play' | 'promo' | 'manual'. Kept because support questions
  -- are nearly always "I paid, why am I not premium", and that is unanswerable
  -- without knowing which store to go and look in.
  source      text        check (source in ('app_store', 'play', 'promo', 'manual')),

  -- The store's own identifier for the subscription: `original_transaction_id`
  -- on Apple, `purchaseToken` on Google. Needed to tie a later renewal or
  -- cancellation notification back to this row, and unique so the same
  -- purchase cannot be attached to two accounts.
  store_id    text        unique,

  -- Which plan they are on — `bulkr_premium_yearly` and so on. Not used to
  -- decide anything: it labels the membership screen, and it lets Play open
  -- the specific subscription rather than the list of everything the user has
  -- ever subscribed to. Written from the store's own answer, never from the
  -- app's request body.
  product_id  text,

  updated_at  timestamptz not null default now(),
  created_at  timestamptz not null default now()
);

-- The one query that runs often enough to matter: "who is premium and expiring
-- soon", for the job that downgrades them. Partial, because the premium rows
-- are the small half of this table and the free ones never match.
create index if not exists subscriptions_expiring_idx
  on public.subscriptions (expires_at)
  where tier = 'premium';

-- Added after the table shipped, so it is a separate statement rather than
-- part of the `create table` above — a project that already ran this file
-- would otherwise never get the column.
alter table public.subscriptions
  add column if not exists product_id text;

-- ---------------------------------------------------------------------------
-- 2. Row level security
-- ---------------------------------------------------------------------------

alter table public.subscriptions enable row level security;

-- Read your own row. That is the entire grant to `authenticated`.
drop policy if exists "Users read their own subscription" on public.subscriptions;
create policy "Users read their own subscription"
  on public.subscriptions for select to authenticated
  using (auth.uid() = user_id);

-- Deliberately absent: insert, update, delete. The service role bypasses RLS,
-- so the store webhook and the dashboard can still write. Anyone holding only
-- an anon or user JWT cannot, which is the point.
--
-- If a future feature needs the app to write here, it does not get a policy —
-- it gets an edge function that verifies a receipt with the store and writes
-- with the service key. A client that can grant itself premium is a client
-- that will.

-- ---------------------------------------------------------------------------
-- 3. is_premium()
-- ---------------------------------------------------------------------------
-- The function every other policy asks. Written once here so that the rule —
-- premium tier AND not expired — exists in one place, rather than being
-- retyped into each policy that needs it, where one of the copies will
-- eventually forget the date.
--
-- SECURITY DEFINER so it can read `subscriptions` regardless of whose policies
-- are running, with `search_path` pinned: a definer function that resolves
-- `subscriptions` through a caller-controlled search_path is the classic way
-- to hand out the owner's rights by accident.
--
-- STABLE, not VOLATILE, so Postgres may call it once per statement instead of
-- once per row when it appears in a policy.

create or replace function public.is_premium(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from public.subscriptions s
     where s.user_id = uid
       and s.tier = 'premium'
       and (s.expires_at is null or s.expires_at > now())
  );
$$;

revoke all on function public.is_premium(uuid) from public;
grant execute on function public.is_premium(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 4. The free tier's numbers
-- ---------------------------------------------------------------------------
-- These mirror `PlanLimits.free` in `lib/core/plan_limits.dart`, and
-- `test/plan_limits_test.dart` reads this file and fails if the two disagree.
-- Two copies of a pricing number is exactly the kind of thing that drifts —
-- somebody generous raises the client's limit, the database keeps rejecting at
-- the old one, and the app shows a user a library they are not allowed to add
-- to.
--
-- Functions rather than a settings table so a policy can call them inline
-- without a join, and IMMUTABLE so the planner folds them to a constant.

create or replace function public.free_saved_meal_limit()
returns int language sql immutable as $$ select 5 $$;

create or replace function public.free_history_days()
returns int language sql immutable as $$ select 7 $$;

create or replace function public.free_active_challenge_limit()
returns int language sql immutable as $$ select 1 $$;

grant execute on function public.free_saved_meal_limit() to authenticated;
grant execute on function public.free_history_days() to authenticated;
grant execute on function public.free_active_challenge_limit() to authenticated;

-- Nothing enforces these yet. The policies that do — a check on inserting into
-- `meals` and `saved_meals`, a window on reading `daily_logs`, a cap on
-- `challenge_participants` — are the next slice, and each of them is one
-- `and (public.is_premium(auth.uid()) or <count> < public.free_*())` added to
-- a policy that already exists.
--
-- Written in this order on purpose: the table and the helper have to be live
-- before a policy can reference them, and shipping an app that reads a table
-- that does not exist yet is a worse afternoon than shipping a table nothing
-- reads yet.

-- ---------------------------------------------------------------------------
-- 5. updated_at
-- ---------------------------------------------------------------------------
-- So "when did this row last change" is answerable without trusting whoever
-- wrote it to have set the column. Store webhooks retry, and a retry that
-- rewrites the same values should still move this.

create or replace function public.touch_subscriptions_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists subscriptions_touch_updated_at on public.subscriptions;
create trigger subscriptions_touch_updated_at
  before update on public.subscriptions
  for each row execute function public.touch_subscriptions_updated_at();

-- ---------------------------------------------------------------------------
-- 6. Reload the API's schema cache
-- ---------------------------------------------------------------------------
-- PostgREST caches which tables exist. Until it re-reads, the app asking for
-- `subscriptions` gets a 404 from a database that has one.

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Granting somebody premium by hand
-- ---------------------------------------------------------------------------
-- In the SQL editor, which runs as the service role:
--
--   insert into public.subscriptions (user_id, tier, expires_at, source)
--   values ('<uuid>', 'premium', now() + interval '1 year', 'manual')
--   on conflict (user_id) do update
--     set tier = excluded.tier,
--         expires_at = excluded.expires_at,
--         source = excluded.source;
--
-- Taking it away is the same statement with `tier = 'free'`. Do not delete the
-- row: a missing row and a lapsed row both read as free, and only one of them
-- remembers that they paid.
--
-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
--   select policyname, cmd from pg_policies where tablename = 'subscriptions';
--
-- Expect exactly one row, SELECT. More than one, and check that what was added
-- is not a write.
--
--   select public.is_premium(auth.uid());
--
-- And that the app cannot write, which is the assertion this whole file is
-- making. Run as an ordinary signed-in user, not in the SQL editor:
--
--   insert into public.subscriptions (user_id, tier) values (auth.uid(), 'premium');
--
-- must fail with 42501 · new row violates row-level security policy.
