-- Feed, slice 2: liking, commenting and saving.
--
-- Slice 1 put `likes_count`, `comments_count` and `saves_count` on `posts` and
-- left them at zero, because nothing could move them. This file adds the three
-- tables behind them and the triggers that keep the counters honest.
--
-- Written to be re-runnable: every statement is guarded, so applying it twice
-- changes nothing the second time.
--
-- Run this in the Supabase SQL editor (Dashboard -> SQL Editor -> New query),
-- after `feed_schema.sql`.

-- ---------------------------------------------------------------------------
-- 1. Likes and saves
-- ---------------------------------------------------------------------------
-- Both are the same shape: one row means "this person did this to this post",
-- and the pair is the primary key. That composite key is what makes liking
-- idempotent — a double tap cannot produce two likes, because the second
-- insert violates the key rather than adding a row — and it is why the app can
-- treat a like as an insert and an unlike as a delete with nothing to
-- reconcile.
--
-- A like and a save are kept apart rather than folded into one table with a
-- `kind` column. They mean different things (a like is applause, a save is
-- "come back to this"), they are counted separately on the post row, and one
-- day only one of them will need something the other does not — a save might
-- want a folder, a like never will.

create table if not exists public.post_likes (
  post_id uuid not null,
  user_id uuid not null,
  created_at timestamp with time zone not null default now(),
  constraint post_likes_pkey primary key (post_id, user_id),
  constraint post_likes_post_id_fkey
    foreign key (post_id) references public.posts(id) on delete cascade,
  constraint post_likes_user_id_fkey
    foreign key (user_id) references public.users(id) on delete cascade
);

create table if not exists public.post_saves (
  post_id uuid not null,
  user_id uuid not null,
  created_at timestamp with time zone not null default now(),
  constraint post_saves_pkey primary key (post_id, user_id),
  constraint post_saves_post_id_fkey
    foreign key (post_id) references public.posts(id) on delete cascade,
  constraint post_saves_user_id_fkey
    foreign key (user_id) references public.users(id) on delete cascade
);

-- ---------------------------------------------------------------------------
-- 2. Comments
-- ---------------------------------------------------------------------------
-- `post_comments`, not `comments`. The bare name is the one every future
-- feature wants — comments on a meal, on a workout, on a challenge — and
-- taking it for this one would mean either renaming later or bolting a
-- polymorphic `target_type` onto a table that never needed one.
--
-- Replies go one level deep and no further. `parent_comment_id` points at a
-- top-level comment, and section 3's trigger refuses a reply to a reply.
-- That is a product decision enforced in the database because it is the only
-- place it cannot be forgotten: infinitely nested threads are a UI problem
-- with no good answer on a phone, and once deep rows exist they have to be
-- rendered somehow.

create table if not exists public.post_comments (
  id uuid not null default uuid_generate_v4(),
  post_id uuid not null,
  user_id uuid not null,
  -- Null for a top-level comment; the comment being replied to otherwise.
  parent_comment_id uuid,
  content text not null,
  created_at timestamp with time zone not null default now(),
  constraint post_comments_pkey primary key (id),
  constraint post_comments_post_id_fkey
    foreign key (post_id) references public.posts(id) on delete cascade,
  constraint post_comments_user_id_fkey
    foreign key (user_id) references public.users(id) on delete cascade,
  -- A deleted parent takes its replies with it. The alternative — orphaned
  -- replies promoted to top level — silently reattaches someone's "same here"
  -- to a conversation that is no longer there.
  constraint post_comments_parent_comment_id_fkey
    foreign key (parent_comment_id) references public.post_comments(id)
      on delete cascade,
  -- Empty comments are not a thing, and neither are essays. The upper bound
  -- matches what the composer enforces on a whole post, because a comment
  -- longer than the post it is on is its own post.
  constraint post_comments_content_check
    check (char_length(btrim(content)) between 1 and 2000)
);

-- ---------------------------------------------------------------------------
-- 3. One level of replies
-- ---------------------------------------------------------------------------
-- Refuses a reply whose parent is itself a reply, and refuses one that points
-- at a comment on a different post — which would put a reply in a thread
-- nobody reading it can see.
create or replace function public.post_comments_check_depth()
returns trigger
language plpgsql
as $$
declare
  parent_parent uuid;
  parent_post   uuid;
begin
  if new.parent_comment_id is null then
    return new;
  end if;

  select parent_comment_id, post_id
    into parent_parent, parent_post
    from public.post_comments
   where id = new.parent_comment_id;

  if not found then
    raise exception 'Parent comment % does not exist', new.parent_comment_id;
  end if;

  if parent_parent is not null then
    raise exception 'Replies go one level deep: cannot reply to a reply';
  end if;

  if parent_post <> new.post_id then
    raise exception 'A reply must be on the same post as its parent';
  end if;

  return new;
end;
$$;

drop trigger if exists post_comments_depth_trigger on public.post_comments;
create trigger post_comments_depth_trigger
  before insert or update of parent_comment_id, post_id
  on public.post_comments
  for each row execute function public.post_comments_check_depth();

-- ---------------------------------------------------------------------------
-- 4. The counters
-- ---------------------------------------------------------------------------
-- Three triggers, one per table, each keeping one column on `posts` in step.
--
-- SECURITY DEFINER, and it has to be. The counter lives on somebody else's
-- post row, and the posts UPDATE policy only lets an author touch their own —
-- so a trigger running as the liker would be refused by RLS on every like of
-- anyone else's post. Running as the owner is the point: the only writes it
-- makes are `+1`/`-1` on one column of one row, chosen by the row that fired
-- it, and the caller has no say in which column or which row.
--
-- `search_path` is pinned for the same reason it always is on a definer
-- function: without it the caller's path decides which `posts` this resolves
-- to.
--
-- `greatest(0, ...)` on the way down. A counter that has drifted below what it
-- is counting must not go negative and render as "-1 likes"; clamping hides
-- the drift, which is the right trade when the alternative is showing it to
-- every reader. Section 8 has the query that repairs drift properly.

create or replace function public.post_likes_sync_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.posts
       set likes_count = likes_count + 1
     where id = new.post_id;
  elsif tg_op = 'DELETE' then
    update public.posts
       set likes_count = greatest(0, likes_count - 1)
     where id = old.post_id;
  end if;

  return null;
end;
$$;

drop trigger if exists post_likes_count_trigger on public.post_likes;
create trigger post_likes_count_trigger
  after insert or delete on public.post_likes
  for each row execute function public.post_likes_sync_count();

create or replace function public.post_saves_sync_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.posts
       set saves_count = saves_count + 1
     where id = new.post_id;
  elsif tg_op = 'DELETE' then
    update public.posts
       set saves_count = greatest(0, saves_count - 1)
     where id = old.post_id;
  end if;

  return null;
end;
$$;

drop trigger if exists post_saves_count_trigger on public.post_saves;
create trigger post_saves_count_trigger
  after insert or delete on public.post_saves
  for each row execute function public.post_saves_sync_count();

-- Comments count replies too. The number on the card answers "how much
-- conversation is here", and a thread of one comment and nine replies is not
-- one comment's worth.
create or replace function public.post_comments_sync_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.posts
       set comments_count = comments_count + 1
     where id = new.post_id;
  elsif tg_op = 'DELETE' then
    update public.posts
       set comments_count = greatest(0, comments_count - 1)
     where id = old.post_id;
  end if;

  return null;
end;
$$;

drop trigger if exists post_comments_count_trigger on public.post_comments;
create trigger post_comments_count_trigger
  after insert or delete on public.post_comments
  for each row execute function public.post_comments_sync_count();

-- Each of those updates a counter column, which is exactly what
-- `posts_hot_score_trigger` from `feed_schema.sql` fires on — so a like
-- rescores the post on the way through and Discover reflects it on the next
-- pull. Nothing here has to know that; it falls out of the trigger being on
-- the columns rather than on the tables.

-- Backfill, for a database that already has engagement rows from a previous
-- run of this file. Guarded to rows that disagree, so a re-run is a no-op.
update public.posts p
   set likes_count    = counted.likes,
       comments_count = counted.comments,
       saves_count    = counted.saves
  from (
    select p2.id,
           (select count(*) from public.post_likes    l where l.post_id = p2.id) as likes,
           (select count(*) from public.post_comments c where c.post_id = p2.id) as comments,
           (select count(*) from public.post_saves    s where s.post_id = p2.id) as saves
      from public.posts p2
  ) counted
 where counted.id = p.id
   and (p.likes_count    <> counted.likes
     or p.comments_count <> counted.comments
     or p.saves_count    <> counted.saves);

-- ---------------------------------------------------------------------------
-- 5. Row level security
-- ---------------------------------------------------------------------------

alter table public.post_likes    enable row level security;
alter table public.post_saves    enable row level security;
alter table public.post_comments enable row level security;

-- Likes are public. Who liked a post is not a secret — it is how "liked by
-- someone you follow" becomes possible later — and the count on the card is
-- derived from these rows, so hiding them would make the number unverifiable.
drop policy if exists "Likes are readable by everyone signed in" on public.post_likes;
create policy "Likes are readable by everyone signed in"
  on public.post_likes for select to authenticated using (true);

-- You may only like as yourself, and only unlike your own like.
drop policy if exists "Users like as themselves" on public.post_likes;
create policy "Users like as themselves"
  on public.post_likes for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users remove their own likes" on public.post_likes;
create policy "Users remove their own likes"
  on public.post_likes for delete to authenticated
  using (auth.uid() = user_id);

-- No UPDATE policy, deliberately. There is nothing on a like to change: the
-- pair is the primary key and the timestamp is a fact. Moving a like to
-- another post is a delete and an insert.

-- Saves are private, unlike likes. What someone bookmarks is a reading list,
-- and a reading list is nobody else's business — so the owner sees their own
-- rows and no one else's.
--
-- Which leaves `saves_count` public while the rows behind it are not. That is
-- intended: the number is an engagement signal the ranking already uses, and
-- knowing four people saved a post reveals nothing about which four.
drop policy if exists "Saves are private to their owner" on public.post_saves;
create policy "Saves are private to their owner"
  on public.post_saves for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Comments follow their post: if you can read the post, you can read the
-- conversation on it.
drop policy if exists "Comments follow their post" on public.post_comments;
create policy "Comments follow their post"
  on public.post_comments for select to authenticated
  using (
    exists (
      select 1 from public.posts p
       where p.id = post_id
         and (not p.is_hidden or p.user_id = auth.uid())
    )
  );

-- Commenting requires the post to be readable, and the comment to be yours.
-- Without the first half, a hidden post could still be commented on by anyone
-- who kept its id.
drop policy if exists "Users comment as themselves" on public.post_comments;
create policy "Users comment as themselves"
  on public.post_comments for insert to authenticated
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.posts p
       where p.id = post_id
         and (not p.is_hidden or p.user_id = auth.uid())
    )
  );

-- Editing your own comment. Scoped so it cannot be reassigned to someone else
-- or moved to another post.
drop policy if exists "Users edit their own comments" on public.post_comments;
create policy "Users edit their own comments"
  on public.post_comments for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Two people may delete a comment: whoever wrote it, and whoever owns the post
-- it is on. The second is not a courtesy — it is the only moderation a post's
-- author has over their own thread, and without it "report it and wait" is the
-- whole answer to someone being abusive under your progress photo.
drop policy if exists "Comments are deletable by their author or the post's"
  on public.post_comments;
create policy "Comments are deletable by their author or the post's"
  on public.post_comments for delete to authenticated
  using (
    auth.uid() = user_id
    or exists (
      select 1 from public.posts p
       where p.id = post_id and p.user_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 6. The counters are not the author's to write
-- ---------------------------------------------------------------------------
-- `feed_schema.sql` left a hole and said so: RLS grants a row, not a column,
-- so the posts UPDATE policy — which correctly lets an author edit their own
-- post — also let them set their own `likes_count` to 5000. Nothing in the app
-- does that; anyone with the publishable key and curl could.
--
-- Column privileges are the fix, and they are checked independently of RLS. An
-- author may update the columns a post is made of; the four the server
-- maintains are not among them.
--
-- Revoking column-level UPDATE means naming what *is* updatable, because a
-- bare `revoke update on <table>` removes the lot. The triggers in section 4
-- are unaffected: they run as the table owner, and owners are not subject to
-- these grants.

revoke update on public.posts from authenticated;

grant update (content, label, image_url, attached_meal_id, is_hidden)
  on public.posts to authenticated;

-- `hot_score` is deliberately absent too. It is derived, and a client that
-- could write it could put itself at the top of Discover and stay there.

-- ---------------------------------------------------------------------------
-- 7. Keeping credit on a copied meal
-- ---------------------------------------------------------------------------
-- Saving a meal off a post copies it rather than referencing it: the saver
-- gets their own row, which they can edit, and which cannot be changed or
-- deleted from under them by its original author.
--
-- The cost of copying is that `creator_id` becomes the saver, so the person
-- who actually wrote the recipe disappears from it. These two columns are how
-- the credit survives — and `Meal.creatorUsername` already exists in the app
-- for exactly this, described as being there "so the credit stays visible".
--
-- Both are `on delete set null`: an author deleting their account or their
-- original meal must not take away copies that other people are using, it
-- just stops the credit resolving.

alter table public.meals
  add column if not exists source_meal_id uuid;

alter table public.meals
  add column if not exists source_creator_id uuid;

alter table public.meals
  drop constraint if exists meals_source_meal_id_fkey;
alter table public.meals
  add constraint meals_source_meal_id_fkey
  foreign key (source_meal_id) references public.meals(id) on delete set null;

alter table public.meals
  drop constraint if exists meals_source_creator_id_fkey;
alter table public.meals
  add constraint meals_source_creator_id_fkey
  foreign key (source_creator_id) references public.users(id) on delete set null;

-- Note for whoever reads `meals` embeds later: `meals` now points at `users`
-- twice — `creator_id` and `source_creator_id`. Every embed of `users` from
-- `meals` must name its foreign key or PostgREST answers PGRST201. The app
-- already does this; the comment on `MealRepository._mealColumns` explains
-- why, and this is the second reason.

-- ---------------------------------------------------------------------------
-- 8. Indexes
-- ---------------------------------------------------------------------------
-- The primary keys already serve "did this user like this post" and every
-- lookup by post, because `(post_id, user_id)` is a prefix match on post_id.
-- What they do not serve is the other direction.

-- "Everything I saved" — the saved-posts list, and the reverse lookup the feed
-- does to mark which posts on a page this user has saved.
create index if not exists post_saves_user_id_created_at_idx
  on public.post_saves (user_id, created_at desc);

-- Same, for resolving "which of these did I like" on a page of posts.
create index if not exists post_likes_user_id_created_at_idx
  on public.post_likes (user_id, created_at desc);

-- A post's thread, oldest first, which is the order it is read in.
create index if not exists post_comments_post_id_created_at_idx
  on public.post_comments (post_id, created_at);

-- A top-level comment's replies.
create index if not exists post_comments_parent_id_created_at_idx
  on public.post_comments (parent_comment_id, created_at)
  where parent_comment_id is not null;

-- Copies of a meal, for "N people saved this".
create index if not exists meals_source_meal_id_idx
  on public.meals (source_meal_id) where source_meal_id is not null;

-- ---------------------------------------------------------------------------
-- 9. Reload the API's schema cache
-- ---------------------------------------------------------------------------
-- Three new tables and four new foreign keys. Until PostgREST re-reads them,
-- embedding `post_likes` or `users!meals_source_creator_id_fkey` answers
-- PGRST200 or PGRST201 against a schema that no longer exists.

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- That the counters match what they count — this should return no rows, and
-- is also the query that finds drift later:
--   select p.id, p.likes_count, p.comments_count, p.saves_count
--     from public.posts p
--    where p.likes_count <> (select count(*) from public.post_likes l where l.post_id = p.id)
--       or p.comments_count <> (select count(*) from public.post_comments c where c.post_id = p.id)
--       or p.saves_count <> (select count(*) from public.post_saves s where s.post_id = p.id);
--
-- That an author can no longer write their own counters. As a signed-in user,
-- this must fail with "permission denied for table posts":
--   update public.posts set likes_count = 9999 where user_id = auth.uid();
-- while this must still work:
--   update public.posts set content = content where user_id = auth.uid();
--
-- The column grants, spelled out:
--   select column_name, privilege_type from information_schema.column_privileges
--    where table_name = 'posts' and grantee = 'authenticated'
--      and privilege_type = 'UPDATE' order by column_name;
--
-- That replies cannot nest. The second insert must raise:
--   -- insert a top-level comment, then a reply to it, then a reply to that
--
-- That RLS is on AND policied for all three — on with no policies reads as an
-- empty table:
--   select c.relname, c.relrowsecurity, count(p.policyname) as policies
--     from pg_class c
--     join pg_namespace n on n.oid = c.relnamespace
--     left join pg_policies p on p.tablename = c.relname
--    where n.nspname = 'public'
--      and c.relname in ('post_likes', 'post_saves', 'post_comments')
--    group by c.relname, c.relrowsecurity;
