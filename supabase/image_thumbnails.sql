-- ---------------------------------------------------------------------------
-- Bulkr — small copies of pictures
-- ---------------------------------------------------------------------------
-- Run after every other migration. Safe to run more than once.
--
-- The app shows the same photo at four sizes: full width in a post, half width
-- in the meals grid, a third of the width in saved posts, and 44 points in a
-- thumbnail on a post card. Until now it downloaded the full-size file for all
-- four, because that was the only file there was.
--
-- Disk caching fixed the second look at a picture. It cannot fix the first,
-- and the first is what is billed. So the app now uploads a second, ~640px
-- copy alongside the original and every small rendering points at that one.
--
-- These columns are all nullable and stay nullable. Everything uploaded before
-- this migration has no thumbnail and never will — going back to generate them
-- would mean downloading every picture in the bucket to re-upload a smaller
-- one, which costs more egress than it could ever save. The app falls back to
-- the full size when the column is null, which is exactly the behaviour it had
-- before, so old rows simply keep working.

-- ---------------------------------------------------------------------------
-- 1. The columns
-- ---------------------------------------------------------------------------
alter table public.post_images
  add column if not exists thumb_url text;

alter table public.meals
  add column if not exists thumb_url text;

alter table public.groups
  add column if not exists image_thumb_url text;

-- ---------------------------------------------------------------------------
-- 2. Why avatars are not in this list
-- ---------------------------------------------------------------------------
-- Avatars are already uploaded at 512px and drawn at 30 to 44, so on the face
-- of it they are the worst offender here — twenty of them on a feed page.
--
-- They are also the one picture that repeats. The same twenty authors write
-- most of what any one reader sees, so after the disk cache landed an avatar
-- is fetched once per author and then never again. A meal photo and a post
-- photo are unique to the row they belong to: every one is a first look, and a
-- first look is the only thing a thumbnail can help with.
--
-- So the three tables above are the ones where a second copy pays for itself,
-- and `users` is left alone rather than given a column nothing would write.

-- ---------------------------------------------------------------------------
-- 3. Verify
-- ---------------------------------------------------------------------------
--   select table_name, column_name
--     from information_schema.columns
--    where table_schema = 'public'
--      and column_name in ('thumb_url', 'image_thumb_url')
--    order by table_name;
--
-- Three rows: groups, meals, post_images.
