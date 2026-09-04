-- Feed, slice 3: following people, and a For You that means something.
--
-- Until now `PostRepository._followedAuthorIds` returned the signed-in user and
-- nothing else, so For You was "my own posts" wearing a different name. This
-- file adds the table that makes it real.
--
-- Written to be re-runnable: every statement is guarded, so applying it twice
-- changes nothing the second time.
--
-- Run this in the Supabase SQL editor (Dashboard -> SQL Editor -> New query),
-- after `feed_engagement.sql`.

-- ---------------------------------------------------------------------------
-- 1. Follows
-- ---------------------------------------------------------------------------
-- One row means "follower follows followee". The pair is the primary key,
-- which is what makes following idempotent — a double tap is refused by the
-- key rather than counted twice — and is why the app can treat a follow as an
-- insert and an unfollow as a delete with nothing to reconcile.
--
-- Directional and deliberately not symmetric: following someone does not make
-- them follow you back. A mutual follow is simply two rows, which is also how
-- "follows you" gets answered later without another table.
--
-- The CHECK is not paranoia. A self-follow would put the user in their own For
-- You twice — once through the follow, once through the "and your own posts"
-- clause the feed query adds — and every screen showing a follower count would
-- count them as their own fan.

create table if not exists public.follows (
  follower_id uuid not null,
  followee_id uuid not null,
  created_at timestamp with time zone not null default now(),
  constraint follows_pkey primary key (follower_id, followee_id),
  constraint follows_no_self_follow check (follower_id <> followee_id),
  constraint follows_follower_id_fkey
    foreign key (follower_id) references public.users(id) on delete cascade,
  constraint follows_followee_id_fkey
    foreign key (followee_id) references public.users(id) on delete cascade
);

-- ---------------------------------------------------------------------------
-- 2. Trainers
-- ---------------------------------------------------------------------------
-- For You is "the people you follow, the trainers you follow, and the groups
-- you're in". Trainers are not a separate follow relationship — following a
-- trainer is following a person — but they are a distinct kind of account, and
-- the app surfaces them first when suggesting who to follow.
--
-- IMPORTANT, and worth being blunt about: this is a self-declared claim, not a
-- verified credential. `users` has an UPDATE policy that lets people edit
-- their own row, and this column is inside it, so anyone can mark themselves
-- a trainer. That is fine for now — the flag only affects how prominently an
-- account is suggested — and it is not fine forever.
--
-- Verification, when it matters, goes one of two ways: revoke column-level
-- UPDATE on this column so only the dashboard can set it (see section 6 of
-- `feed_engagement.sql` for the pattern), or add a separate
-- `trainer_verified_at` that only a service-role process can write and show
-- the badge off that instead. Neither belongs in this file, because neither is
-- needed until someone has a reason to lie.

alter table public.users
  add column if not exists is_trainer boolean not null default false;

-- ---------------------------------------------------------------------------
-- 3. No follower counts
-- ---------------------------------------------------------------------------
-- `posts` carries denormalised `likes_count` and friends, and the reasoning
-- there was sound: a feed renders fifteen cards and counting per card turns
-- one query into fifteen.
--
-- Follower counts are deliberately NOT stored the same way, for three reasons:
--
--   1. They are read on one profile at a time, or on a list of twenty people.
--      PostgREST can aggregate that in the same request —
--      `followers:follows!follows_followee_id_fkey(count)` — so the query
--      count does not grow.
--   2. A stored count on `users` would be writable by its owner. The posts
--      UPDATE policy had exactly this hole and section 6 of
--      `feed_engagement.sql` had to close it with column grants; `users` has
--      seventeen columns onboarding writes, and narrowing that grant to
--      protect a vanity number is a good way to break onboarding.
--   3. An aggregate cannot drift. A trigger-maintained counter can, and then
--      needs a repair query.
--
-- The trade this gives up is ordering by follower count in the database — you
-- cannot index an aggregate. "Suggested people" therefore ranks on trainers
-- first and `users.last_active_at` after, which is a better signal anyway:
-- someone who posted this week is a better follow than someone with four
-- thousand followers who left in March. It also cannot be farmed.

-- ---------------------------------------------------------------------------
-- 4. Row level security
-- ---------------------------------------------------------------------------

alter table public.follows enable row level security;

-- Who follows whom is public. It has to be: a follower list is a screen, "you
-- both follow" is a feature, and the aggregate counts in section 3 are only
-- correct if the rows behind them are readable.
--
-- Note the asymmetry with `post_saves`, which is private. What you bookmark is
-- a reading list about you; who you follow is a relationship with someone
-- else, and they can see it from their side no matter what this policy says.
drop policy if exists "Follows are readable by everyone signed in" on public.follows;
create policy "Follows are readable by everyone signed in"
  on public.follows for select to authenticated using (true);

-- You may only follow as yourself. Without this, one user could make another
-- follow accounts on their behalf.
drop policy if exists "Users follow as themselves" on public.follows;
create policy "Users follow as themselves"
  on public.follows for insert to authenticated
  with check (auth.uid() = follower_id);

-- And only unfollow your own follows. Notably this does NOT let someone remove
-- a follower — "block" is the feature that does that, and it is its own slice
-- with its own table, because removing a follower and preventing a re-follow
-- are two different things.
drop policy if exists "Users remove their own follows" on public.follows;
create policy "Users remove their own follows"
  on public.follows for delete to authenticated
  using (auth.uid() = follower_id);

-- No UPDATE policy. There is nothing on a follow to change: the pair is the
-- primary key and the timestamp is a fact.

-- ---------------------------------------------------------------------------
-- 5. Indexes
-- ---------------------------------------------------------------------------
-- The primary key `(follower_id, followee_id)` already serves "does A follow
-- B" and "everyone A follows" — the second is a prefix match on follower_id,
-- and it is the query For You runs on every load, so that direction is covered.
--
-- The other direction is not, and needs its own index: a prefix match cannot
-- start in the middle of a key.

-- "Everyone who follows B" — the follower list, and the count aggregate.
create index if not exists follows_followee_id_created_at_idx
  on public.follows (followee_id, created_at desc);

-- "Everyone A follows", newest first, for the following list. The primary key
-- answers membership but orders by followee_id, which is a uuid and therefore
-- an arbitrary order to show a human.
create index if not exists follows_follower_id_created_at_idx
  on public.follows (follower_id, created_at desc);

-- Suggested people: trainers first, then whoever has been around recently.
-- Partial on `onboarding_completed`, because a half-finished signup has no
-- username to show and should never be suggested to anyone.
create index if not exists users_trainer_last_active_idx
  on public.users (is_trainer desc, last_active_at desc)
  where onboarding_completed;

-- Handle search, which runs `ilike '%term%'` and cannot be served by a btree.
-- pg_trgm is already enabled by `meals_policies.sql`; the guard is here so
-- this file stands on its own.
create extension if not exists pg_trgm;

create index if not exists users_username_trgm_idx
  on public.users using gin (username gin_trgm_ops);

create index if not exists users_display_name_trgm_idx
  on public.users using gin (display_name gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- 6. Reading other people at all
-- ---------------------------------------------------------------------------
-- A problem this slice runs into that the earlier ones did not, and the README
-- already warned about it:
--
--   "depending on the RLS policy on `users`, the client may not be able to see
--    other users' rows, in which case every handle looks free"
--
-- Following people requires finding them, and a profile requires reading their
-- row. If the policy on `users` is `auth.uid() = id`, every screen in this
-- slice returns nothing — no suggestions, no search results, no author name on
-- a post — and it will look like a bug in the app rather than a policy.
--
-- So: a read policy that exposes only what a public profile is. It is additive
-- (policies are OR-ed), so whatever self-access policy already exists keeps
-- working and keeps being the only way to read the private columns.
--
-- What this does NOT do is hide the columns. RLS grants rows, not columns, so
-- a reader who can see the row can see `current_weight_kg` and
-- `date_of_birth` on it. That is the same class of hole section 6 of
-- `feed_engagement.sql` closed on `posts`, and closing it here means either
-- column-level SELECT grants or a view — a real decision that deserves its own
-- change rather than being smuggled in here.
--
-- Until then, be aware: with this policy applied, any signed-in user can read
-- any onboarded user's biometrics through the API. If that is not acceptable
-- for your launch, do not apply this section — instead add a
-- `SECURITY DEFINER` function returning only (id, username, display_name,
-- avatar_url, is_trainer) and point the app's people queries at it.

drop policy if exists "Onboarded profiles are readable by everyone signed in"
  on public.users;
create policy "Onboarded profiles are readable by everyone signed in"
  on public.users for select to authenticated
  using (onboarding_completed);

-- ---------------------------------------------------------------------------
-- 7. Reload the API's schema cache
-- ---------------------------------------------------------------------------
-- A new table and two new foreign keys into `users`. Until PostgREST re-reads
-- them, the aggregate embed `follows!follows_followee_id_fkey(count)` answers
-- PGRST200.
--
-- Note that `users` is now pointed at by `follows` twice, which is one more
-- reason every embed of `users` has to name its foreign key — the app already
-- does this everywhere, for reasons `MealRepository._mealColumns` explains.

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- That a self-follow is refused. This must raise
-- "violates check constraint follows_no_self_follow":
--   insert into public.follows (follower_id, followee_id)
--   values (auth.uid(), auth.uid());
--
-- That following twice is refused rather than duplicated — the second must
-- raise a unique violation (23505):
--   -- insert the same (follower_id, followee_id) pair twice
--
-- That you cannot follow on someone else's behalf. As a signed-in user, with
-- some other id as the follower, this must be refused by RLS (42501):
--   insert into public.follows (follower_id, followee_id)
--   values ('<someone-elses-uuid>', '<a-third-uuid>');
--
-- That RLS is on AND policied — on with no policies reads as an empty table:
--   select c.relname, c.relrowsecurity, count(p.policyname) as policies
--     from pg_class c
--     join pg_namespace n on n.oid = c.relnamespace
--     left join pg_policies p on p.tablename = c.relname
--    where n.nspname = 'public' and c.relname in ('follows', 'users')
--    group by c.relname, c.relrowsecurity;
--
-- That other people are actually readable now, which is what this whole slice
-- depends on. Signed in as a real user, this should return more than one row
-- once you have two onboarded accounts:
--   select id, username, is_trainer from public.users;
--
-- And that the count aggregate resolves. Against the REST API, not SQL:
--   GET /rest/v1/users
--       ?select=id,username,followers:follows!follows_followee_id_fkey(count)
--       &limit=5
--
-- To make an account a trainer while testing:
--   update public.users set is_trainer = true where username = '<handle>';
