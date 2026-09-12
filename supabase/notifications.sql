-- ---------------------------------------------------------------------------
-- Bulkr — notifications
-- ---------------------------------------------------------------------------
-- Run after `feed_engagement.sql`, `feed_follows.sql` and `social_privacy.sql`.
-- Safe to run more than once.
--
-- Everything social in this app is currently invisible unless you go looking
-- for it. Somebody follows you, likes your post, answers your comment — and
-- the only way to find out is to happen to open the right screen. That is the
-- gap this closes.
--
-- Direct messages are deliberately *not* in here. They already have an inbox
-- with its own unread counts, and a message that produced both a thread badge
-- and a notification row would be one event announced twice.

-- ---------------------------------------------------------------------------
-- 1. The table
-- ---------------------------------------------------------------------------
create table if not exists public.notifications (
  id uuid not null default uuid_generate_v4(),
  -- Who is being told.
  user_id uuid not null,
  -- Who did the thing. Nullable, and on delete set null rather than cascade:
  -- an account going away should not silently rewrite the history of what
  -- happened to everyone else. The row survives and reads as "someone".
  actor_id uuid,
  kind text not null,
  -- What it is about. Both nullable — a follow is about a person, not a post.
  post_id uuid,
  comment_id uuid,
  created_at timestamptz not null default now(),
  -- When it was seen. Null is unread; a timestamp rather than a boolean for
  -- the same reason `conversation_members.last_read_at` is one — "unread" is
  -- derived from a fact about time, not stored as an opinion that can drift.
  read_at timestamptz,
  constraint notifications_pkey primary key (id),
  constraint notifications_kind_check
    check (kind in ('follow', 'like', 'comment', 'reply')),
  -- Nobody is notified about their own doing.
  constraint notifications_no_self check (user_id is distinct from actor_id),
  constraint notifications_user_id_fkey
    foreign key (user_id) references public.users(id) on delete cascade,
  constraint notifications_actor_id_fkey
    foreign key (actor_id) references public.users(id) on delete set null,
  constraint notifications_post_id_fkey
    foreign key (post_id) references public.posts(id) on delete cascade,
  constraint notifications_comment_id_fkey
    foreign key (comment_id) references public.post_comments(id)
      on delete cascade
);

-- The list: one user's notifications, newest first.
create index if not exists notifications_user_id_created_at_idx
  on public.notifications (user_id, created_at desc);

-- The badge: how many are unread. Partial, so it indexes only the rows the
-- count is over rather than every notification anyone has ever received.
create index if not exists notifications_unread_idx
  on public.notifications (user_id) where read_at is null;

-- One notification per thing, not one per time it happened.
--
-- Liking, unliking and liking again is one person being interested once. The
-- triggers below insert with `on conflict do nothing`, which turns the second
-- and third into no-ops rather than into a pile of identical rows.
--
-- `coalesce` on the two nullable columns because null is never equal to null
-- in a unique index, so without it every follow notification would be distinct
-- from every other and the deduplication would silently do nothing.
create unique index if not exists notifications_unique_event_idx
  on public.notifications (
    user_id,
    actor_id,
    kind,
    coalesce(post_id, '00000000-0000-0000-0000-000000000000'::uuid),
    coalesce(comment_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

-- ---------------------------------------------------------------------------
-- 2. Row-level security
-- ---------------------------------------------------------------------------
alter table public.notifications enable row level security;

drop policy if exists "Notifications are readable by their recipient"
  on public.notifications;
create policy "Notifications are readable by their recipient"
  on public.notifications for select to authenticated
  using (auth.uid() = user_id);

-- Marking as read is the only edit anyone makes. The column grant below is
-- what stops it being used to rewrite what a notification says: RLS grants a
-- row, never a column.
drop policy if exists "Notifications are markable by their recipient"
  on public.notifications;
create policy "Notifications are markable by their recipient"
  on public.notifications for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Notifications are deletable by their recipient"
  on public.notifications;
create policy "Notifications are deletable by their recipient"
  on public.notifications for delete to authenticated
  using (auth.uid() = user_id);

-- There is deliberately no INSERT policy. Notifications are written by the
-- triggers below and by nothing else — a client that could insert them could
-- tell any user that anyone had done anything.
grant select, delete on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Writing one
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER because the whole point is writing a row that belongs to
-- somebody else, which no policy scoped to `auth.uid()` can allow — the same
-- reason `start_direct_conversation` is.
--
-- Every guard is in here rather than repeated in three triggers: no self
-- notification, nothing to a null recipient, and nothing in either direction
-- across a block. That last one matters — blocking somebody has to stop their
-- likes arriving as notifications, or the block is not a block.
create or replace function public.notify(
  p_user uuid,
  p_actor uuid,
  p_kind text,
  p_post uuid default null,
  p_comment uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_user is null or p_actor is null or p_user = p_actor then
    return;
  end if;

  if exists (
    select 1 from public.blocks b
     where (b.blocker_id = p_user and b.blocked_id = p_actor)
        or (b.blocker_id = p_actor and b.blocked_id = p_user)
  ) then
    return;
  end if;

  insert into public.notifications (user_id, actor_id, kind, post_id, comment_id)
  values (p_user, p_actor, p_kind, p_post, p_comment)
  on conflict do nothing;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. The three things worth being told about
-- ---------------------------------------------------------------------------
create or replace function public.follows_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.notify(new.followee_id, new.follower_id, 'follow');
  return new;
end;
$$;

drop trigger if exists follows_notify on public.follows;
create trigger follows_notify
  after insert on public.follows
  for each row execute function public.follows_notify();

create or replace function public.post_likes_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  author uuid;
begin
  select p.user_id into author from public.posts p where p.id = new.post_id;
  perform public.notify(author, new.user_id, 'like', new.post_id);
  return new;
end;
$$;

drop trigger if exists post_likes_notify on public.post_likes;
create trigger post_likes_notify
  after insert on public.post_likes
  for each row execute function public.post_likes_notify();

-- A comment tells the post's author. A reply tells the post's author *and*
-- the person being replied to, unless they are the same person — in which case
-- `notify`'s deduplication is not what saves us, the two calls carry different
-- kinds, so the branch does.
create or replace function public.post_comments_notify()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  post_author uuid;
  parent_author uuid;
begin
  select p.user_id into post_author from public.posts p where p.id = new.post_id;

  if new.parent_comment_id is null then
    perform public.notify(post_author, new.user_id, 'comment', new.post_id, new.id);
    return new;
  end if;

  select c.user_id into parent_author
    from public.post_comments c
   where c.id = new.parent_comment_id;

  perform public.notify(parent_author, new.user_id, 'reply', new.post_id, new.id);

  -- The post's author hears about a reply on their post too, but only when it
  -- is not already their own reply notification.
  if post_author is distinct from parent_author then
    perform public.notify(post_author, new.user_id, 'comment', new.post_id, new.id);
  end if;

  return new;
end;
$$;

drop trigger if exists post_comments_notify on public.post_comments;
create trigger post_comments_notify
  after insert on public.post_comments
  for each row execute function public.post_comments_notify();

-- ---------------------------------------------------------------------------
-- 5. Reading them
-- ---------------------------------------------------------------------------
-- The list, with the actor and enough of the post to show what it is about.
--
-- A function rather than a PostgREST select with embeds, for one reason:
-- `notifications` points at `users` once and at `posts` once, and `posts`
-- points at `users` as well — so the embed the app would need is three levels
-- deep and re-derives the same joins on every read. One function, one shape,
-- one place to change it.
--
-- `security invoker`, so the SELECT policy above is what decides which rows
-- come back. There is no way to ask this for somebody else's notifications.
create or replace function public.notification_feed(p_limit integer default 50)
returns table (
  id uuid,
  kind text,
  created_at timestamptz,
  read_at timestamptz,
  actor_id uuid,
  actor_username text,
  actor_display_name text,
  actor_avatar_url text,
  post_id uuid,
  post_excerpt text,
  comment_id uuid,
  comment_excerpt text
)
language sql
stable
set search_path = public
as $$
  select
    n.id,
    n.kind,
    n.created_at,
    n.read_at,
    n.actor_id,
    a.username,
    a.display_name,
    a.avatar_url,
    n.post_id,
    -- Enough to recognise which post, not the post. A notification list that
    -- carried whole post bodies would be a feed's worth of egress for a
    -- screen that shows one line each.
    left(p.content, 80),
    n.comment_id,
    left(c.content, 80)
  from public.notifications n
  left join public.users a on a.id = n.actor_id
  left join public.posts p on p.id = n.post_id
  left join public.post_comments c on c.id = n.comment_id
  where n.user_id = auth.uid()
  order by n.created_at desc
  limit least(coalesce(p_limit, 50), 100);
$$;

revoke execute on function public.notification_feed(integer) from public;
grant execute on function public.notification_feed(integer) to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Verify
-- ---------------------------------------------------------------------------
--   select count(*) from public.notifications;
--
--   select tgname from pg_trigger
--    where tgname in ('follows_notify', 'post_likes_notify',
--                     'post_comments_notify');
--
-- Three rows. Then follow somebody from a second account and check that one
-- notification appears for the first.
