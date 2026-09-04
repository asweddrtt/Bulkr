-- Profile pictures.
--
-- `users.avatar_url` has existed since onboarding, but nothing has ever
-- written it except the OAuth provider: signing in with Google or Apple hands
-- over whatever picture that account has, and the app stored the URL. Which
-- means the column pointed at somebody else's server, and the user had no way
-- to change it.
--
-- This adds the bucket that lets them. `avatar_url` keeps its type and its
-- meaning — a public URL to an image — and simply starts being able to point
-- somewhere this app controls.
--
-- Written to be re-runnable: every statement is guarded, so applying it twice
-- changes nothing the second time.
--
-- Run this in the Supabase SQL editor, after `feed_profiles.sql`.

-- ---------------------------------------------------------------------------
-- 1. The bucket
-- ---------------------------------------------------------------------------
-- Public-read, like the other three. An avatar appears next to every post its
-- owner has written, in every feed, for every reader — there is no version of
-- this that is private.
--
-- A fourth bucket rather than a folder in an existing one, for the same reason
-- `post-images` is separate from `meal-images`: lifetimes differ. Deleting a
-- post must not be able to take somebody's face off their profile.

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

drop policy if exists "Avatars are publicly readable" on storage.objects;
create policy "Avatars are publicly readable"
  on storage.objects for select
  using (bucket_id = 'avatars');

-- Writes scoped to a folder named after the uploader's id, which is the path
-- the app builds: `<uid>/<timestamp>.jpg`. The timestamp matters — see
-- section 2.
drop policy if exists "Users upload their own avatar" on storage.objects;
create policy "Users upload their own avatar"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users replace their own avatar" on storage.objects;
create policy "Users replace their own avatar"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users delete their own avatar" on storage.objects;
create policy "Users delete their own avatar"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- 2. Why every upload gets a new filename
-- ---------------------------------------------------------------------------
-- The obvious design is one file per user — `<uid>.jpg`, overwritten on each
-- change. It does not work, and the reason is caching rather than storage.
--
-- A public storage URL is served with cache headers, and that URL is embedded
-- in every post card the user has ever appeared on. Overwriting the file
-- leaves the URL unchanged, so every device that has already loaded it keeps
-- showing the old picture until its cache expires — which for the person who
-- just changed theirs looks exactly like the change not having saved.
--
-- So the app writes a new object each time and points `avatar_url` at it. The
-- URL changes, the cache misses, the new picture appears immediately.
--
-- The cost is that old avatars accumulate. That is a real cost and it is
-- deliberately unpaid here: deleting the previous file means reading the old
-- URL, parsing a storage path back out of it, and deleting that — three things
-- that can each go wrong, in service of a few kilobytes per change. When it
-- matters, the tidy-up belongs in a scheduled job that keeps the newest object
-- per folder, not in the upload path where a failure would block someone
-- changing their picture.

-- ---------------------------------------------------------------------------
-- 3. Nothing to do about `avatar_url` itself
-- ---------------------------------------------------------------------------
-- `users` has an UPDATE policy scoped to `auth.uid() = id` and no column-level
-- grant narrowing it, so an owner can already write their own `avatar_url` and
-- nobody else's. Same reasoning as `bio` in `feed_profiles.sql`.
--
-- Worth being clear about what that does not stop: `avatar_url` is free text,
-- so a determined user could point it at any URL on the internet rather than
-- at this bucket, and every reader's device would then fetch that URL. The
-- fix is a CHECK constraint requiring the project's storage prefix — which is
-- not added here because the prefix differs per project and hard-coding it
-- into a file that ships in the repo would break the next person to run it
-- against their own Supabase instance.
--
-- If you want it, this is the shape, with your own project ref:
--
--   alter table public.users
--     add constraint users_avatar_url_check
--     check (
--       avatar_url is null
--       or avatar_url like 'https://<ref>.supabase.co/storage/v1/object/public/avatars/%'
--       or avatar_url like 'https://lh3.googleusercontent.com/%'   -- Google
--       or avatar_url like 'https://appleid.cdn-apple.com/%'       -- Apple
--     );
--
-- Note it has to allow the OAuth providers too, or the constraint would reject
-- the avatar every existing account already has.

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- That the bucket exists and is public:
--   select id, public from storage.buckets where id = 'avatars';
--
-- The four policies on it:
--   select policyname, cmd from pg_policies
--    where tablename = 'objects' and policyname ilike '%avatar%'
--    order by cmd;
--
-- That you can write your own avatar_url and not anyone else's. The first
-- updates one row, the second zero:
--   update public.users set avatar_url = avatar_url where id = auth.uid();
--   update public.users set avatar_url = null where id <> auth.uid();
--
-- After changing a picture in the app, that the URL actually moved — a stored
-- URL identical to the previous one means the upload silently reused a
-- filename, which is the caching problem section 2 exists to avoid:
--   select avatar_url from public.users where id = auth.uid();
