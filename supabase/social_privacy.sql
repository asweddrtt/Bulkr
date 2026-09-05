-- Who can see what, who you never want to hear from, and leaving.
--
-- Four things that belong together because they are all answers to the same
-- question — what a reader is allowed to be shown — and because three of them
-- rewrite the same row-level security policies.
--
--   1. per-item visibility: public, followers only, or private
--   2. blocking a user, in both directions
--   3. hiding one post from your own feed
--   4. the table nothing needs, because deletion is an edge function
--
-- Written to be re-runnable: every statement is guarded, so applying it twice
-- changes nothing the second time.
--
-- Run this in the Supabase SQL editor, after `feed_groups.sql`.

-- ---------------------------------------------------------------------------
-- 1. Visibility
-- ---------------------------------------------------------------------------
-- Three levels rather than the boolean `meals.is_public` already has, because
-- the middle one is the one people actually want: something shared with the
-- people who follow you and not with Discover. A boolean cannot express it,
-- and the workaround — posting nothing — is what people do instead.
--
-- Text with a CHECK rather than a Postgres enum, for the reason `feed_schema`
-- gives about `posts.label`: a new label on an enum is not usable until the
-- transaction that added it commits, which turns "add a fourth level" into a
-- deployment order. A CHECK is one ALTER.
--
-- Default 'public'. Every existing post was written when public was the only
-- option, so that is what they already are — a default of anything else would
-- retroactively hide posts their authors chose to share.

alter table public.posts
  add column if not exists visibility text not null default 'public';

alter table public.meals
  add column if not exists visibility text not null default 'public';

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'posts_visibility_check'
       and conrelid = 'public.posts'::regclass
  ) then
    alter table public.posts
      add constraint posts_visibility_check
      check (visibility in ('public', 'followers', 'private'));
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'meals_visibility_check'
       and conrelid = 'public.meals'::regclass
  ) then
    alter table public.meals
      add constraint meals_visibility_check
      check (visibility in ('public', 'followers', 'private'));
  end if;
end
$$;

-- Carry `meals.is_public` across. Guarded on the column still existing so this
-- survives it being dropped later, and on visibility still being at its default
-- so re-running cannot overwrite a level someone has since chosen.
--
-- `is_public` is deliberately NOT dropped here. Dropping a column and losing
-- the data in it is not something to do in the same migration that first reads
-- it — if this file has to be rolled back, the old policies need it back. It
-- can go once the app has shipped and the values have been checked; nothing
-- reads it after this file.

do $$
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'meals'
       and column_name = 'is_public'
  ) then
    update public.meals
       set visibility = case when is_public then 'public' else 'private' end
     where visibility = 'public'
       and is_public is distinct from true;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. Blocking
-- ---------------------------------------------------------------------------
-- Symmetric in effect, one-sided in the record: one row says "A blocked B", and
-- every policy below checks for a row in *either* direction. So blocking
-- someone removes you from their feed as well as them from yours, without B
-- being told, and without needing two rows kept in step.
--
-- No `on delete` worries: both sides cascade with the user, and a block whose
-- other party has deleted their account has nothing left to describe.

create table if not exists public.blocks (
  blocker_id uuid not null references public.users(id) on delete cascade,
  blocked_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint blocks_pkey primary key (blocker_id, blocked_id),
  constraint blocks_no_self_block check (blocker_id <> blocked_id)
);

-- The PK serves lookups by blocker. This serves the other direction, which the
-- policies below need just as often — "is anyone I can see blocking me".
create index if not exists blocks_blocked_id_idx
  on public.blocks (blocked_id);

alter table public.blocks enable row level security;

-- You can read and write your own blocks, and cannot read anyone else's. That
-- second half matters: a list of who has blocked you is exactly the thing a
-- blocked person should not be handed.
drop policy if exists "Blocks are yours alone" on public.blocks;
create policy "Blocks are yours alone"
  on public.blocks for all to authenticated
  using (auth.uid() = blocker_id)
  with check (auth.uid() = blocker_id);

-- ---------------------------------------------------------------------------
-- 3. Hiding one post
-- ---------------------------------------------------------------------------
-- "Not this one" — a preference, not a judgement about the author, and nothing
-- like `posts.is_hidden`, which is the author or the report threshold pulling a
-- post for everybody.

create table if not exists public.hidden_posts (
  user_id uuid not null references public.users(id) on delete cascade,
  post_id uuid not null references public.posts(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint hidden_posts_pkey primary key (user_id, post_id)
);

alter table public.hidden_posts enable row level security;

drop policy if exists "Hidden posts are yours alone" on public.hidden_posts;
create policy "Hidden posts are yours alone"
  on public.hidden_posts for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Note this is NOT enforced in the posts policy below, unlike blocking. Two
-- reasons. It is a preference rather than a permission, so the app filtering it
-- is honest. And a post the reader cannot select is a post that cannot be
-- listed back to them — "here is what you have hidden, tap to unhide" needs to
-- be able to read the thing it is offering to restore.

-- ---------------------------------------------------------------------------
-- 4. The predicates
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER for the same reason `can_read_group` is: a policy on
-- `posts` that reads `follows` runs as the reader, under whatever policy
-- `follows` has, and a chain of policies each consulting the other is how
-- `feed_groups.sql` produced a 42P17 recursion. A definer function is read
-- once, by the owner, and answers a boolean.
--
-- STABLE, not VOLATILE, so the planner may call them once per row rather than
-- once per row per reference.

create or replace function public.follows_me(p_author uuid)
returns boolean language sql security definer set search_path = public stable
as $fn$
  select exists (
    select 1 from public.follows
     where follower_id = auth.uid() and followee_id = p_author
  );
$fn$;

comment on function public.follows_me(uuid) is
  'Whether the caller follows p_author. Drives followers-only visibility.';

create or replace function public.is_blocked_with(p_other uuid)
returns boolean language sql security definer set search_path = public stable
as $fn$
  select exists (
    select 1 from public.blocks
     where (blocker_id = auth.uid() and blocked_id = p_other)
        or (blocker_id = p_other and blocked_id = auth.uid())
  );
$fn$;

comment on function public.is_blocked_with(uuid) is
  'Whether a block exists in either direction between the caller and p_other.';

create or replace function public.can_view(p_author uuid, p_visibility text)
returns boolean language sql security definer set search_path = public stable
as $fn$
  select
    -- Your own is always yours, whatever it says.
    auth.uid() = p_author
    or (
      not public.is_blocked_with(p_author)
      and (
        p_visibility = 'public'
        or (p_visibility = 'followers' and public.follows_me(p_author))
      )
    );
$fn$;

comment on function public.can_view(uuid, text) is
  'Whether the caller may read an item by p_author at p_visibility.';

revoke all on function public.follows_me(uuid) from public;
revoke all on function public.is_blocked_with(uuid) from public;
revoke all on function public.can_view(uuid, text) from public;
grant execute on function public.follows_me(uuid) to authenticated;
grant execute on function public.is_blocked_with(uuid) to authenticated;
grant execute on function public.can_view(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. The policies that use them
-- ---------------------------------------------------------------------------
-- Posts. Replaces the policy `feed_groups.sql` left, keeping both of its
-- clauses and adding visibility:
--
--   * your own, always — including hidden ones, so a pulled post is still on
--     your profile rather than silently gone
--   * a group post: membership decides, and visibility is not consulted. A
--     group is already an audience, and asking someone to pick one twice for
--     the same post is asking them to reason about the schema.
--   * everything else: whatever `visibility` says, and no block either way.

drop policy if exists "Posts are readable when visible to you" on public.posts;
create policy "Posts are readable when visible to you"
  on public.posts for select to authenticated
  using (
    auth.uid() = user_id
    or (
      not is_hidden
      and case
            when group_id is not null then public.can_read_group(group_id)
            else public.can_view(user_id, visibility)
          end
    )
  );

-- Meals. Was `auth.uid() = creator_id or is_public`.
drop policy if exists "Meals are readable when yours or public" on public.meals;
drop policy if exists "Meals are readable when visible to you" on public.meals;
create policy "Meals are readable when visible to you"
  on public.meals for select to authenticated
  using (public.can_view(creator_id, visibility));

-- The column grants are re-issued because they are absolute: each `grant
-- update (...)` names the whole set an author may write, so adding `visibility`
-- means restating the list rather than adding to it.
--
-- `visibility` is a column an author may set, unlike the counters. Deciding who
-- sees your own post is the author's to make and nobody else's.
revoke update on public.posts from authenticated;
grant update (content, label, image_url, attached_meal_id, is_hidden,
              group_id, visibility)
  on public.posts to authenticated;

-- `meals` has a plain `for all` policy and no column grant narrowing it, so
-- there is nothing to re-issue there — an author can already write every column
-- of their own meal, `visibility` included.

-- ---------------------------------------------------------------------------
-- 6. Indexes
-- ---------------------------------------------------------------------------
-- Discover reads public posts by hot score. The existing partial indexes are on
-- `where not is_hidden`; these narrow them to what Discover actually asks for,
-- so a feed of public posts does not walk followers-only and private ones to
-- discard them.

create index if not exists posts_public_hot_idx
  on public.posts (hot_score desc, id desc)
  where not is_hidden and visibility = 'public';

create index if not exists posts_public_created_idx
  on public.posts (created_at desc, id desc)
  where not is_hidden and visibility = 'public';

create index if not exists hidden_posts_user_id_idx
  on public.hidden_posts (user_id);

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- 7. Verify
-- ---------------------------------------------------------------------------
-- The new columns and what constrains them:
--   select table_name, column_name, column_default, is_nullable
--     from information_schema.columns
--    where table_schema = 'public' and column_name = 'visibility';
--
--   select conrelid::regclass, conname, pg_get_constraintdef(oid)
--     from pg_constraint where conname like '%visibility%';
--
-- That the migration from is_public landed. Every private meal should have
-- come across, and this should return zero rows:
--   select count(*) from public.meals
--    where is_public = false and visibility <> 'private';
--
-- That the three levels behave. As yourself, with a second account to follow
-- you, post three things and check each is visible to the right people:
--   select visibility, count(*) from public.posts
--    where user_id = auth.uid() group by visibility;
--
-- The predicates, called directly — much easier to debug than a policy:
--   select public.follows_me('<some author id>');
--   select public.is_blocked_with('<some user id>');
--   select public.can_view('<author id>', 'followers');
--
-- Blocking works both ways. Block someone, then confirm their posts are gone
-- from what you can select AND that yours are gone from what they can:
--   insert into public.blocks (blocker_id, blocked_id)
--   values (auth.uid(), '<their id>');
--   select count(*) from public.posts where user_id = '<their id>';
--   -- then, signed in as them: select count(*) from public.posts
--   --   where user_id = '<your id>';   -- also zero
--
-- And that you cannot read anyone else's block list — this must return only
-- rows where blocker_id is your own id:
--   select blocker_id, blocked_id from public.blocks;
