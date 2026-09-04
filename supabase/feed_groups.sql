-- Feed, slice 4a: groups.
--
-- The third source For You draws on. Slices 1-3 built "the people you follow";
-- this is "the groups you're in", and it is the first thing in the feed whose
-- visibility depends on something other than whether a post is hidden.
--
-- Written to be re-runnable: every statement is guarded, so applying it twice
-- changes nothing the second time.
--
-- Run this in the Supabase SQL editor (Dashboard -> SQL Editor -> New query),
-- after `feed_follows.sql`. Then `feed_reports.sql`, then
-- `feed_challenges.sql`.

-- ---------------------------------------------------------------------------
-- 1. Groups
-- ---------------------------------------------------------------------------

create table if not exists public.groups (
  id uuid not null default uuid_generate_v4(),
  name text not null,
  description text,
  image_url text,
  owner_id uuid not null,
  -- A private group is invisible to non-members, and so are its posts. A
  -- public one can be read by anyone signed in but still only posted to by
  -- members — "open to read, closed to write" is what most fitness groups
  -- actually want, and it is the default here.
  is_private boolean not null default false,
  created_at timestamp with time zone not null default now(),
  constraint groups_pkey primary key (id),
  -- Deleting the owner's account deletes the group. The alternative is a
  -- group with no owner, which nobody can administer and nobody can delete.
  constraint groups_owner_id_fkey
    foreign key (owner_id) references public.users(id) on delete cascade,
  constraint groups_name_check
    check (char_length(btrim(name)) between 2 and 60),
  constraint groups_description_check
    check (description is null or char_length(description) <= 500)
);

-- ---------------------------------------------------------------------------
-- 2. Membership
-- ---------------------------------------------------------------------------
-- The pair is the primary key, so joining twice is refused by the key rather
-- than counted twice.
--
-- `role` is deliberately two values, not four. An owner can delete the group
-- and remove members; a member can post and leave. "Admin" and "moderator"
-- are real needs at a scale this app is nowhere near, and inventing them now
-- means writing policies for powers nobody has asked for.

create table if not exists public.group_members (
  group_id uuid not null,
  user_id uuid not null,
  role text not null default 'member',
  joined_at timestamp with time zone not null default now(),
  constraint group_members_pkey primary key (group_id, user_id),
  constraint group_members_group_id_fkey
    foreign key (group_id) references public.groups(id) on delete cascade,
  constraint group_members_user_id_fkey
    foreign key (user_id) references public.users(id) on delete cascade,
  constraint group_members_role_check check (role in ('owner', 'member'))
);

-- The owner is a member. Without this the owner is not in their own group's
-- feed, is not counted in its size, and every query has to special-case them.
--
-- Guarded on "not already there", so re-running adds nothing.
insert into public.group_members (group_id, user_id, role)
select g.id, g.owner_id, 'owner'
  from public.groups g
 where not exists (
   select 1 from public.group_members m
    where m.group_id = g.id and m.user_id = g.owner_id
 );

-- And keeps it true for groups created from now on.
create or replace function public.groups_add_owner_as_member()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.group_members (group_id, user_id, role)
  values (new.id, new.owner_id, 'owner')
  on conflict (group_id, user_id) do nothing;

  return null;
end;
$$;

drop trigger if exists groups_owner_member_trigger on public.groups;
create trigger groups_owner_member_trigger
  after insert on public.groups
  for each row execute function public.groups_add_owner_as_member();

-- ---------------------------------------------------------------------------
-- 3. Posts belong to a group, or to nobody
-- ---------------------------------------------------------------------------
-- Null means "posted to the feed", which is every post written so far and most
-- posts written from now on. A group post is scoped to that group: it appears
-- in the group, and in the For You of its members, and nowhere else.

alter table public.posts
  add column if not exists group_id uuid;

alter table public.posts
  drop constraint if exists posts_group_id_fkey;
alter table public.posts
  add constraint posts_group_id_fkey
  foreign key (group_id) references public.groups(id) on delete set null;

-- SET NULL rather than CASCADE, and the difference matters. Deleting a group
-- must not delete what people wrote in it — that is somebody's progress log —
-- so the posts survive and become ordinary feed posts. Losing the group is
-- losing the room, not the conversation.

-- ---------------------------------------------------------------------------
-- 4. The posts read policy, revisited
-- ---------------------------------------------------------------------------
-- This is the substantive change in this file, and the riskiest.
--
-- `feed_schema.sql` set the rule to "readable unless hidden, and your own
-- either way". That was right when every post was public. It is now wrong in
-- two directions:
--
--   * A post in a PRIVATE group would be readable by anyone, which defeats
--     the point of a private group.
--   * A post in a group should not appear in Discover at all — even a public
--     group's posts are for that group, not for the front page. That part is
--     enforced by the queries (`group_id is null` on Discover) rather than by
--     the policy, because "can read" and "belongs in this list" are different
--     questions and only the first belongs in RLS.
--
-- So the policy gains a group clause. Reading it in order: your own posts
-- always; hidden posts never (except your own); a group post only if the group
-- is public or you are in it; everything else as before.
--
-- The subquery on `group_members` runs per row, which is why section 6 indexes
-- `(user_id, group_id)` — the reverse of the primary key — so the membership
-- check is an index lookup rather than a scan.

drop policy if exists "Posts are readable unless hidden" on public.posts;
drop policy if exists "Posts are readable when visible to you" on public.posts;
create policy "Posts are readable when visible to you"
  on public.posts for select to authenticated
  using (
    auth.uid() = user_id
    or (
      not is_hidden
      and (
        group_id is null
        or exists (
          select 1 from public.groups g
           where g.id = group_id
             and (
               not g.is_private
               or exists (
                 select 1 from public.group_members m
                  where m.group_id = g.id and m.user_id = auth.uid()
               )
             )
        )
      )
    )
  );

-- Posting into a group requires being in it. Checked here and not only in the
-- UI: the composer is not the only way to reach an insert.
drop policy if exists "Posts are insertable by their author" on public.posts;
create policy "Posts are insertable by their author"
  on public.posts for insert to authenticated
  with check (
    auth.uid() = user_id
    and (
      group_id is null
      or exists (
        select 1 from public.group_members m
         where m.group_id = group_id and m.user_id = auth.uid()
      )
    )
  );

-- `group_id` joins the columns an author may update. Without it, the composer
-- can create a group post but nothing can ever move or unscope one — and
-- `feed_engagement.sql` revoked table-level UPDATE, so an ungranted column is
-- a permission error rather than a policy failure.
--
-- Restated in full rather than added to, because `grant` is additive and the
-- full list is the documentation.
revoke update on public.posts from authenticated;

grant update (content, label, image_url, attached_meal_id, is_hidden, group_id)
  on public.posts to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Row level security on the group tables
-- ---------------------------------------------------------------------------

alter table public.groups        enable row level security;
alter table public.group_members enable row level security;

-- A public group is discoverable by anyone signed in; a private one only by
-- its members. This is what makes a private group private — everything else
-- follows from not being able to see the row.
drop policy if exists "Groups are readable when public or joined" on public.groups;
create policy "Groups are readable when public or joined"
  on public.groups for select to authenticated
  using (
    not is_private
    or exists (
      select 1 from public.group_members m
       where m.group_id = id and m.user_id = auth.uid()
    )
  );

-- Anyone can start a group, and only as themselves.
drop policy if exists "Groups are creatable by their owner" on public.groups;
create policy "Groups are creatable by their owner"
  on public.groups for insert to authenticated
  with check (auth.uid() = owner_id);

drop policy if exists "Groups are editable by their owner" on public.groups;
create policy "Groups are editable by their owner"
  on public.groups for update to authenticated
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

drop policy if exists "Groups are deletable by their owner" on public.groups;
create policy "Groups are deletable by their owner"
  on public.groups for delete to authenticated
  using (auth.uid() = owner_id);

-- Membership of a group you can see is visible. A member list is a screen, and
-- hiding it from members would make a group a room where you cannot tell who
-- else is in it.
--
-- Note this leans on the `groups` policy above: you can only read membership
-- of a group you can read, so a private group's member list is members-only
-- without saying so twice.
drop policy if exists "Membership is readable with the group" on public.group_members;
create policy "Membership is readable with the group"
  on public.group_members for select to authenticated
  using (
    exists (
      select 1 from public.groups g
       where g.id = group_id
         and (
           not g.is_private
           or exists (
             select 1 from public.group_members m
              where m.group_id = g.id and m.user_id = auth.uid()
           )
         )
    )
  );

-- Joining. Only as yourself, only a group you can see, and only as a plain
-- member — the `role = 'member'` check is what stops someone joining a group
-- as its owner and inheriting the power to delete it.
--
-- A private group is joinable by anyone who can see it, which today means its
-- members — so in practice a private group can only grow by someone being
-- added, and there is no invite flow yet. That is a gap, not a bug: private
-- groups work for a group that forms and then closes, and invites are their
-- own slice.
drop policy if exists "Users join groups as themselves" on public.group_members;
create policy "Users join groups as themselves"
  on public.group_members for insert to authenticated
  with check (
    auth.uid() = user_id
    and role = 'member'
    and exists (
      select 1 from public.groups g
       where g.id = group_id
         and (
           not g.is_private
           or exists (
             select 1 from public.group_members m
              where m.group_id = g.id and m.user_id = auth.uid()
           )
         )
    )
  );

-- Leaving, or being removed by the owner.
--
-- The owner cannot leave their own group — `role <> 'owner'` covers both the
-- owner removing themselves and anyone else trying to. A group whose owner has
-- left has nobody who can delete it, and "delete the group" is the operation
-- an owner who wants out actually wants.
drop policy if exists "Users leave groups, owners remove members"
  on public.group_members;
create policy "Users leave groups, owners remove members"
  on public.group_members for delete to authenticated
  using (
    role <> 'owner'
    and (
      auth.uid() = user_id
      or exists (
        select 1 from public.groups g
         where g.id = group_id and g.owner_id = auth.uid()
      )
    )
  );

-- No UPDATE policy on membership. Promoting someone is the feature that would
-- need one, and there is nothing to promote them to.

-- ---------------------------------------------------------------------------
-- 6. Indexes
-- ---------------------------------------------------------------------------

-- "Which groups is this user in" — read on every For You load, and by the
-- membership subquery in every policy above. The primary key is
-- `(group_id, user_id)`, which cannot serve a lookup that starts with the
-- user, so this is not optional.
create index if not exists group_members_user_id_joined_at_idx
  on public.group_members (user_id, joined_at desc);

-- A group's own feed, newest first.
create index if not exists posts_group_id_created_at_id_idx
  on public.posts (group_id, created_at desc, id desc)
  where group_id is not null;

-- Discover excludes group posts, so its index should too. The unqualified
-- version from `feed_schema.sql` still exists and still works; this one is
-- narrower and is what the query will actually use.
create index if not exists posts_feed_hot_score_id_idx
  on public.posts (hot_score desc, id desc)
  where not is_hidden and group_id is null;

create index if not exists posts_feed_label_hot_score_id_idx
  on public.posts (label, hot_score desc, id desc)
  where not is_hidden and group_id is null;

-- Browsing groups: public ones, biggest first is tempting but member count is
-- an aggregate here for the same reasons follower count is (see section 3 of
-- `feed_follows.sql`), so newest first it is.
create index if not exists groups_public_created_at_idx
  on public.groups (created_at desc) where not is_private;

-- Group name search runs `ilike '%term%'`, which no btree can serve. pg_trgm
-- is already enabled by `meals_policies.sql`; the guard is here so this file
-- stands on its own, the same way `feed_follows.sql` does.
create extension if not exists pg_trgm;

create index if not exists groups_name_trgm_idx
  on public.groups using gin (name gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- 7. Group images
-- ---------------------------------------------------------------------------
-- Public-read, like the other two buckets. A private group's picture being
-- readable is a deliberate non-problem: it is a name and an image, the posts
-- are what the policy protects, and scoping bucket reads to membership is not
-- something storage policies express cheaply.

insert into storage.buckets (id, name, public)
values ('group-images', 'group-images', true)
on conflict (id) do update set public = true;

drop policy if exists "Group images are publicly readable" on storage.objects;
create policy "Group images are publicly readable"
  on storage.objects for select
  using (bucket_id = 'group-images');

drop policy if exists "Users upload group images to their own folder"
  on storage.objects;
create policy "Users upload group images to their own folder"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'group-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users manage their own group images" on storage.objects;
create policy "Users manage their own group images"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'group-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users delete their own group images" on storage.objects;
create policy "Users delete their own group images"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'group-images'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- 8. Reload the API's schema cache
-- ---------------------------------------------------------------------------

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- That creating a group makes you a member of it. After inserting a group as
-- yourself, this must return one row with role 'owner':
--   select * from public.group_members
--    where group_id = '<new-group-id>' and user_id = auth.uid();
--
-- That you cannot join as an owner. This must be refused by RLS (42501):
--   insert into public.group_members (group_id, user_id, role)
--   values ('<some-group>', auth.uid(), 'owner');
--
-- That an owner cannot leave. This must delete zero rows:
--   delete from public.group_members
--    where group_id = '<your-group>' and user_id = auth.uid();
--
-- That a private group's posts are invisible to non-members. As a user who is
-- NOT in the group, this must return nothing:
--   select id from public.posts where group_id = '<private-group-id>';
--
-- That `group_id` is updatable and the counters still are not:
--   select column_name from information_schema.column_privileges
--    where table_name = 'posts' and grantee = 'authenticated'
--      and privilege_type = 'UPDATE' order by column_name;
--   -- expect exactly: attached_meal_id, content, group_id, image_url,
--   --                 is_hidden, label
--
-- And that the policy count on posts is still one per command:
--   select policyname, cmd from pg_policies
--    where tablename = 'posts' order by cmd, policyname;
