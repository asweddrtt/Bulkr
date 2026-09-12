-- Feed, slice 1: what a post is.
--
-- `public.posts` already existed before the feed did — `meals_policies.sql`
-- reaches into it to set the `attached_meal_id` delete rule — but it was built
-- for a simpler idea of a post: one image, a like counter, a comment counter,
-- and no way to say what kind of post it is. This file brings it up to what the
-- Feed tab needs.
--
-- What it does NOT do, on purpose: no `post_likes`, no `comments`, no
-- `follows`, no `groups`. Those are later slices. The two counter columns that
-- already exist (`likes_count`, `comments_count`) stay untouched and stay zero
-- until the slice that earns them — the ranking below reads them, so it starts
-- correct and simply has nothing to rank on yet.
--
-- Written to be re-runnable: every statement is guarded, so applying it twice
-- changes nothing the second time.
--
-- Run this in the Supabase SQL editor (Dashboard -> SQL Editor -> New query),
-- after `meals_policies.sql`.

-- ---------------------------------------------------------------------------
-- 1. What kind of post it is
-- ---------------------------------------------------------------------------
-- A `text` column with a CHECK rather than a Postgres enum. Enums cannot be
-- extended inside a transaction and the new value is not usable until the
-- transaction that added it commits, which makes "add a seventh label" a
-- migration with a deployment order. A CHECK constraint is one DDL statement
-- and can be replaced in place.
--
-- The default is deliberately the vaguest label. A post that arrives without
-- one — an old row, or a client that predates this column — is a thought
-- someone shared, and `tip` is the honest bucket for that. It is never used for
-- a post created through the composer, which always sends a label.
--
-- `challenge` is in the set and is only a label today. The participant list,
-- the end date and the leaderboard are a later slice; until then it tags a post
-- about a challenge rather than driving one.

alter table public.posts
  add column if not exists label text not null default 'tip';

alter table public.posts drop constraint if exists posts_label_check;
alter table public.posts
  add constraint posts_label_check
  check (label in ('meal', 'workout', 'progress', 'tip', 'question', 'challenge'));

-- ---------------------------------------------------------------------------
-- 2. Counters the feed reads
-- ---------------------------------------------------------------------------
-- `likes_count` and `comments_count` are already on the table. Saves need the
-- same treatment for the same reason the meal rows carry `total_calories`: a
-- count(*) per card turns one query into one query per row on screen.
--
-- Denormalised counters are only ever as right as whatever maintains them, so
-- the triggers that own them land in the slice that adds the tables they count.
-- Until then these are zero, which is the truth.

alter table public.posts
  add column if not exists saves_count integer not null default 0;

-- ---------------------------------------------------------------------------
-- 3. Ranking
-- ---------------------------------------------------------------------------
-- Discover is "public and engaging", which needs an ORDER BY. Computing a
-- score at query time means no index can serve it and every pull is a full
-- scan over every public post that ever existed, so it is a stored column.
--
-- The shape is the usual time-decayed one: engagement over age, with age
-- winning eventually. A post cannot stay on the front page for a month because
-- it did well on a Tuesday.
--
--   score = (weighted engagement + 1) / (hours_old + 2) ^ 1.5
--
-- The weights say what the app values. A save is worth more than a like
-- because it costs the reader something — it puts the thing in their library —
-- and a comment is worth more than a like because writing one is work. The +1
-- keeps a brand-new post with no engagement above zero so it can be seen at
-- all; the +2 and the exponent are Hacker News' gravity, which is well-tested
-- at keeping a front page moving.
--
-- IMMUTABLE and not reading now(): the age is passed in, so the function can
-- be called from a trigger and from a refresh sweep with the same result. A
-- function that read the clock could not be used in an index and would make
-- every row's score depend on when it happened to be written.

create or replace function public.post_hot_score(
  likes integer,
  comments integer,
  saves integer,
  age_hours double precision
) returns double precision
language sql
immutable
as $$
  select (
    coalesce(likes, 0)
    + coalesce(comments, 0) * 2
    + coalesce(saves, 0) * 3
    + 1
  )::double precision / power(greatest(age_hours, 0) + 2, 1.5);
$$;

alter table public.posts
  add column if not exists hot_score double precision not null default 0;

-- Keeps the score in step with the counters it is made of.
--
-- Recomputed on insert and whenever a counter moves, which is the only time it
-- can change other than by the clock. Age is the part this cannot keep current
-- — nothing writes to a post as it gets older — so the score decays only when
-- something touches the row. That is what section 7's sweep is for.
create or replace function public.posts_refresh_hot_score()
returns trigger
language plpgsql
as $$
begin
  new.hot_score := public.post_hot_score(
    new.likes_count,
    new.comments_count,
    new.saves_count,
    extract(epoch from (now() - coalesce(new.created_at, now()))) / 3600.0
  );
  return new;
end;
$$;

drop trigger if exists posts_hot_score_trigger on public.posts;
create trigger posts_hot_score_trigger
  before insert or update of likes_count, comments_count, saves_count
  on public.posts
  for each row execute function public.posts_refresh_hot_score();

-- Backfill: existing rows have never been through the trigger.
update public.posts
   set hot_score = public.post_hot_score(
         likes_count,
         comments_count,
         saves_count,
         extract(epoch from (now() - created_at)) / 3600.0
       )
 where hot_score = 0;

-- ---------------------------------------------------------------------------
-- 4. Visibility and moderation
-- ---------------------------------------------------------------------------
-- `is_public` is not on posts the way it is on meals, and the two are not the
-- same question. A meal is a private thing that can be shared; a post is a
-- published thing by definition. What a post needs instead is a way to stop
-- being published — because its author changed their mind, or because enough
-- people reported it.
--
-- `report_count` lives here rather than being counted from the reports table so
-- the feed query can filter on it without a join. The reports table itself is a
-- later slice; this is the column it will maintain.
--
-- Auto-hiding at a threshold matters because there is no admin panel. A report
-- that only ever lands in a table nobody reads does nothing, and "we will
-- review it" is not true if no one can.

alter table public.posts
  add column if not exists report_count integer not null default 0;

alter table public.posts
  add column if not exists is_hidden boolean not null default false;

-- ---------------------------------------------------------------------------
-- 5. Images
-- ---------------------------------------------------------------------------
-- `posts.image_url` holds one image. The `progress` label is before-and-after
-- by nature, so one is the wrong number, and widening a column to an array
-- later means a migration with a backfill against live rows.
--
-- So: a child table, ordered, and `posts.image_url` is backfilled into it and
-- then left alone. It is not dropped — dropping a populated column in someone
-- else's production database is not this file's decision to make — but nothing
-- reads it after this runs. New posts write here only.

create table if not exists public.post_images (
  id uuid not null default uuid_generate_v4(),
  post_id uuid not null,
  url text not null,
  -- Where it sits in the post. Zero-based, and unique per post, so the order
  -- the author chose is the order every reader gets.
  position integer not null default 0,
  created_at timestamp with time zone not null default now(),
  constraint post_images_pkey primary key (id),
  constraint post_images_post_id_fkey
    foreign key (post_id) references public.posts(id) on delete cascade,
  constraint post_images_post_id_position_key unique (post_id, position)
);

-- One-time move of the single-image rows into the table. Guarded on "this post
-- has no images yet", so re-running cannot duplicate them.
insert into public.post_images (post_id, url, position)
select p.id, p.image_url, 0
  from public.posts p
 where p.image_url is not null
   and p.image_url <> ''
   and not exists (
     select 1 from public.post_images i where i.post_id = p.id
   );

-- ---------------------------------------------------------------------------
-- 6. Row level security
-- ---------------------------------------------------------------------------
-- `posts` had RLS neither enabled nor policied. Enabling it without policies
-- would take the table to "nobody can read anything", so both happen here,
-- in one file, and the order within a transaction does not matter to the app —
-- what matters is that this file is never applied half-way.

alter table public.posts        enable row level security;
alter table public.post_images  enable row level security;

-- Reads: every signed-in user sees every post that has not been hidden. The
-- feed is public by design — Discover is the whole point — and For You narrows
-- it by who you follow in the client and, from slice 3, in the query.
--
-- Authors keep seeing their own hidden posts. Someone whose post was pulled
-- should find it still on their profile rather than silently gone, and hiding
-- is not deletion.
drop policy if exists "Posts are readable unless hidden" on public.posts;
create policy "Posts are readable unless hidden"
  on public.posts for select to authenticated
  using (not is_hidden or auth.uid() = user_id);

-- Writes: split per command rather than one `for all`, because the columns an
-- author may set are not the columns an author may change.
drop policy if exists "Posts are insertable by their author" on public.posts;
create policy "Posts are insertable by their author"
  on public.posts for insert to authenticated
  with check (auth.uid() = user_id);

-- An author edits their own text. The WITH CHECK repeats the USING clause so a
-- post cannot be handed to someone else by updating `user_id`.
--
-- Note what this does not stop: an author can write to their own row's
-- `likes_count` or `report_count`, because RLS grants a row, not a column.
-- Column-level grants are the fix and they belong with the tables those
-- counters count — a like counter is only worth defending once liking exists.
drop policy if exists "Posts are updatable by their author" on public.posts;
create policy "Posts are updatable by their author"
  on public.posts for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Posts are deletable by their author" on public.posts;
create policy "Posts are deletable by their author"
  on public.posts for delete to authenticated
  using (auth.uid() = user_id);

-- post_images: inherits the post's visibility, exactly as meal_ingredients
-- inherits its meal's. Someone who can see the post can see its pictures; only
-- its author can change them.
drop policy if exists "Post images follow their post" on public.post_images;
create policy "Post images follow their post"
  on public.post_images for select to authenticated
  using (
    exists (
      select 1 from public.posts p
       where p.id = post_id
         and (not p.is_hidden or p.user_id = auth.uid())
    )
  );

drop policy if exists "Post images are writable by the post's author"
  on public.post_images;
create policy "Post images are writable by the post's author"
  on public.post_images for all to authenticated
  using (
    exists (
      select 1 from public.posts p
       where p.id = post_id and p.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.posts p
       where p.id = post_id and p.user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 7. Indexes
-- ---------------------------------------------------------------------------
-- One per access path the feed actually uses. Every one of them is a composite
-- ending in `id`, because the feed pages by keyset — `(sort_key, id) < (?, ?)`
-- — and not by OFFSET.
--
-- That is not a micro-optimisation. A feed gets new rows at the top while
-- someone is reading it, and under OFFSET every insert above the cursor shifts
-- the window: page 2 re-serves a row from page 1 and skips one of its own. The
-- duplicate is what users notice. Keyset asks "what comes after this exact
-- row", which no insert can change the answer to.

-- Discover: hottest first, hidden rows excluded from the index entirely.
create index if not exists posts_hot_score_id_idx
  on public.posts (hot_score desc, id desc) where not is_hidden;

-- Discover, filtered to one label.
create index if not exists posts_label_hot_score_id_idx
  on public.posts (label, hot_score desc, id desc) where not is_hidden;

-- For You: newest first. A followed author's post is interesting because it is
-- theirs and it is new, not because it went viral.
create index if not exists posts_created_at_id_idx
  on public.posts (created_at desc, id desc) where not is_hidden;

create index if not exists posts_label_created_at_id_idx
  on public.posts (label, created_at desc, id desc) where not is_hidden;

-- A single author's posts: their profile, and the For You query before follows
-- exist.
create index if not exists posts_user_id_created_at_id_idx
  on public.posts (user_id, created_at desc, id desc);

create index if not exists post_images_post_id_position_idx
  on public.post_images (post_id, position);

-- Posts carrying a meal, for "who else cooked this".
create index if not exists posts_attached_meal_id_idx
  on public.posts (attached_meal_id) where attached_meal_id is not null;

-- ---------------------------------------------------------------------------
-- 8. Keeping the decay honest
-- ---------------------------------------------------------------------------
-- The trigger in section 3 cannot see time pass. A post that stops getting
-- engagement stops being rescored, so its stored score is the one it had when
-- it was last touched — and it keeps that score forever, sitting above newer
-- posts it should have aged out under.
--
-- Something has to walk the recent rows and re-decay them. This is that
-- function; what calls it is a schedule, not this file.
--
-- Bounded to the last week and to rows whose score is still worth moving.
-- Older posts have decayed to a score no realistic engagement can lift back
-- into a front page, so rewriting them every hour is churn for nothing.
create or replace function public.refresh_post_hot_scores()
returns integer
language plpgsql
as $$
declare
  touched integer;
begin
  update public.posts
     set hot_score = public.post_hot_score(
           likes_count,
           comments_count,
           saves_count,
           extract(epoch from (now() - created_at)) / 3600.0
         )
   where created_at > now() - interval '7 days';

  get diagnostics touched = row_count;
  return touched;
end;
$$;

-- Scheduling this is `maintenance_cron.sql`, which enables pg_cron and sets it
-- to run hourly. Kept in its own file because enabling an extension is a
-- project-level decision, and Discover is correct without it — just
-- increasingly stale at the top. Every posts_* index above is on the stored
-- column, so the sweep is what keeps them meaningful.
--
--   select cron.schedule(
--     'refresh-post-hot-scores',
--     '0 * * * *',
--     $cron$ select public.refresh_post_hot_scores() $cron$
--   );

-- ---------------------------------------------------------------------------
-- 9. Post images bucket
-- ---------------------------------------------------------------------------
-- Public-read, same as `meal-images` and for the same reason: a post has to
-- render for everyone who can see it. Writes are scoped to a folder named after
-- the uploader's id, which is the path the app builds:
-- `<uid>/<timestamp>-<n>.jpg`.
--
-- A separate bucket from `meal-images` rather than a shared one, because the
-- two have different lifetimes — deleting a post must not be able to take the
-- photo off a meal that is still in someone's library.

insert into storage.buckets (id, name, public)
values ('post-images', 'post-images', true)
on conflict (id) do update set public = true;

drop policy if exists "Post images are publicly readable" on storage.objects;
create policy "Post images are publicly readable"
  on storage.objects for select
  using (bucket_id = 'post-images');

drop policy if exists "Users upload post images to their own folder"
  on storage.objects;
create policy "Users upload post images to their own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'post-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users manage their own post images" on storage.objects;
create policy "Users manage their own post images"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'post-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users delete their own post images" on storage.objects;
create policy "Users delete their own post images"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'post-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- 10. Reload the API's schema cache
-- ---------------------------------------------------------------------------
-- PostgREST caches the schema, including which tables are related and how. A
-- new table and a new foreign key change that, and until it re-reads them the
-- API answers from a picture of the database that no longer exists — the
-- symptom is PGRST200 on the `post_images` embed.

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- The label column and its constraint:
--   select column_name, data_type, column_default
--     from information_schema.columns
--    where table_name = 'posts' order by ordinal_position;
--
--   select conname, pg_get_constraintdef(oid) from pg_constraint
--    where conrelid = 'public.posts'::regclass and contype = 'c';
--
-- That RLS is on AND policied — on with no policies reads as an empty table:
--   select c.relname, c.relrowsecurity, count(p.policyname) as policies
--     from pg_class c
--     join pg_namespace n on n.oid = c.relnamespace
--     left join pg_policies p on p.tablename = c.relname
--    where n.nspname = 'public' and c.relname in ('posts', 'post_images')
--    group by c.relname, c.relrowsecurity;
--
-- That the ranking is sane — newer beats older at equal engagement, and a
-- save outweighs a like:
--   select public.post_hot_score(0, 0, 0, 1)   as fresh_empty,
--          public.post_hot_score(0, 0, 0, 100) as old_empty,
--          public.post_hot_score(3, 0, 0, 10)  as three_likes,
--          public.post_hot_score(0, 0, 1, 10)  as one_save;
--
-- That the single-image backfill landed:
--   select count(*) filter (where image_url is not null and image_url <> '')
--            as legacy_images,
--          (select count(*) from public.post_images) as rows_in_table
--     from public.posts;
--
-- And that Discover's index is actually used, rather than a scan and a sort:
--   explain analyze
--   select id from public.posts
--    where not is_hidden order by hot_score desc, id desc limit 20;
