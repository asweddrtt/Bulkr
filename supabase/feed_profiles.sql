-- Profiles: the one thing a profile screen needs that the schema did not have.
--
-- `users` was built by onboarding, so every column on it is a number the
-- calorie engine needs. None of it is anything a person would write about
-- themselves — which is fine for a dashboard and not enough for a profile.
--
-- Written to be re-runnable: every statement is guarded, so applying it twice
-- changes nothing the second time.
--
-- Run this in the Supabase SQL editor, after `feed_challenges.sql`.

-- ---------------------------------------------------------------------------
-- 1. About
-- ---------------------------------------------------------------------------
-- Free text, and bounded. The ceiling is a paragraph rather than an essay: a
-- bio is read at a glance above someone's posts, and a profile whose about
-- section fills the screen pushes the posts — the actual content — below the
-- fold on every visit.
--
-- Nullable, and stays null for everyone who signed up before this existed.
-- The UI treats null and empty the same way, which is by showing nothing
-- rather than a placeholder: an empty bio is a fact about the person, not a
-- gap to apologise for.

alter table public.users
  add column if not exists bio text;

alter table public.users drop constraint if exists users_bio_check;
alter table public.users
  add constraint users_bio_check
  check (bio is null or char_length(bio) <= 300);

-- ---------------------------------------------------------------------------
-- 2. Who can write it, and who can read it
-- ---------------------------------------------------------------------------
-- Nothing to do, and worth saying why rather than leaving the absence to be
-- puzzled over.
--
-- Writing: `users` has an UPDATE policy scoped to `auth.uid() = id`, and
-- unlike `posts` it has no column-level grant narrowing it — see section 3 of
-- `feed_follows.sql` for why narrowing it was deliberately not attempted. So
-- an owner can already write their own bio and nobody else's.
--
-- Reading: `feed_follows.sql` section 6 added a read policy for onboarded
-- profiles, which is what lets one user see another's name at all. A bio is
-- less sensitive than the biometrics that policy already exposes, and that
-- file names the exposure and the two ways to close it. A bio is the one
-- column on `users` that is *meant* to be public, so it is the one that makes
-- the closed-off version — a SECURITY DEFINER function returning only the
-- public fields — easier to write rather than harder: `bio` simply joins
-- `username`, `display_name`, `avatar_url` and `is_trainer` in its return
-- type.

-- ---------------------------------------------------------------------------
-- 3. Reload the API's schema cache
-- ---------------------------------------------------------------------------
-- A new column. Until PostgREST re-reads the schema, selecting `bio` answers
-- PGRST204 ("column not found"), which in the app looks like the profile
-- failing to load rather than like a migration not having run.

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- That the column and its bound exist:
--   select column_name, data_type from information_schema.columns
--    where table_name = 'users' and column_name = 'bio';
--
--   select conname, pg_get_constraintdef(oid) from pg_constraint
--    where conrelid = 'public.users'::regclass and conname = 'users_bio_check';
--
-- That you can write your own and the bound holds. The first succeeds, the
-- second must fail with "violates check constraint":
--   update public.users set bio = 'Bulking since March.' where id = auth.uid();
--   update public.users set bio = repeat('x', 301) where id = auth.uid();
--
-- And that you cannot write anyone else's — this must update zero rows:
--   update public.users set bio = 'nope' where id <> auth.uid();
