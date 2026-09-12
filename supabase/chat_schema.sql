-- Direct messages.
--
-- The first thing in this app that is live. Everything else is read on a pull
-- and refreshed on a gesture; a conversation where the other person's message
-- arrives when you next swipe down is not a conversation.
--
-- Three tables, two of which exist only to make the third one answerable:
-- `messages` is the data, `conversation_members` is who may read it, and
-- `conversations` is the thing they are members of.
--
-- Written to be re-runnable: every statement is guarded, so applying it twice
-- changes nothing the second time.
--
-- Run this in the Supabase SQL editor, after `social_privacy.sql` — the
-- policies below call `public.is_blocked_with`, which that file creates.

-- ---------------------------------------------------------------------------
-- 1. The tables
-- ---------------------------------------------------------------------------
-- `direct_key` is what makes "message this person" idempotent. Two people have
-- exactly one direct conversation, and the obvious way to enforce that — look
-- for one, create it if absent — races: two devices asking at the same moment
-- both find nothing and both create one, and now there are two threads holding
-- half a conversation each.
--
-- The key is the two ids in a fixed order, so both directions produce the same
-- string, and a unique constraint on it makes the race impossible rather than
-- unlikely. It is null for anything that is not a direct thread, which is the
-- room left for group chats: they get a null key, a name, and more than two
-- member rows, and nothing here has to change.

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  direct_key text unique,
  created_at timestamptz not null default now(),
  -- Denormalised so the conversation list can order by it without reading
  -- every message. Maintained by a trigger, never by the client.
  last_message_at timestamptz not null default now()
);

create table if not exists public.conversation_members (
  conversation_id uuid not null
    references public.conversations(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  -- How the unread count is worked out. A timestamp rather than a counter: a
  -- counter has to be incremented for every member on every send and can drift
  -- from the messages it claims to count, while a timestamp is written by the
  -- one person it belongs to and compared against rows that already exist.
  last_read_at timestamptz not null default now(),
  joined_at timestamptz not null default now(),
  constraint conversation_members_pkey primary key (conversation_id, user_id)
);

create index if not exists conversation_members_user_id_idx
  on public.conversation_members (user_id);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null
    references public.conversations(id) on delete cascade,
  -- The sender's account going away does not erase what they said to you; the
  -- name beside it does. SET NULL rather than cascade, for the same reason
  -- `daily_logs.meal_id` is: a conversation is a record of something that
  -- happened.
  sender_id uuid references public.users(id) on delete set null,
  body text not null,
  created_at timestamptz not null default now(),
  constraint messages_body_check
    check (char_length(btrim(body)) between 1 and 4000)
);

-- The one index the whole feature leans on: a thread is read newest-first and
-- paged backwards, which is exactly this.
create index if not exists messages_conversation_id_created_at_idx
  on public.messages (conversation_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 2. Who may read a conversation
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER, and this is the third time in this schema that mattered.
-- A policy on `messages` that reads `conversation_members` runs as the reader,
-- under whatever policy that table has — and if that policy reads back the
-- other way you get `infinite recursion detected in policy` (42P17), which is
-- what `feed_groups.sql` shipped with once already.
--
-- A definer function is read once, by the owner, and answers a boolean.

create or replace function public.is_conversation_member(p_conversation uuid)
returns boolean language sql security definer set search_path = public stable
as $fn$
  select exists (
    select 1 from public.conversation_members
     where conversation_id = p_conversation and user_id = auth.uid()
  );
$fn$;

comment on function public.is_conversation_member(uuid) is
  'Whether the caller is in p_conversation. The read gate for the whole feature.';

-- Whether a conversation is still open to write into.
--
-- Blocking has to reach here or it does not mean anything: someone who cannot
-- see your posts but can still message you has not been blocked in any sense
-- the word is normally used in. Checked against every other member, so it
-- keeps working when a conversation has more than two.
create or replace function public.conversation_is_open(p_conversation uuid)
returns boolean language sql security definer set search_path = public stable
as $fn$
  select not exists (
    select 1
      from public.conversation_members m
     where m.conversation_id = p_conversation
       and m.user_id <> auth.uid()
       and public.is_blocked_with(m.user_id)
  );
$fn$;

comment on function public.conversation_is_open(uuid) is
  'False when the caller has blocked, or been blocked by, anyone else in it.';

revoke all on function public.is_conversation_member(uuid) from public;
revoke all on function public.conversation_is_open(uuid) from public;
grant execute on function public.is_conversation_member(uuid) to authenticated;
grant execute on function public.conversation_is_open(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Row level security
-- ---------------------------------------------------------------------------

alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;

-- Conversations are readable by their members and creatable by nobody.
--
-- No INSERT policy at all, deliberately: starting a thread means writing a
-- membership row for somebody else, which no policy scoped to `auth.uid()`
-- can allow. Section 4 does it with the owner's rights, having checked what
-- needs checking. A client that tries to insert here gets 42501, which is the
-- correct answer.
drop policy if exists "Conversations are readable by their members"
  on public.conversations;
create policy "Conversations are readable by their members"
  on public.conversations for select to authenticated
  using (public.is_conversation_member(id));

drop policy if exists "Membership is readable within a conversation"
  on public.conversation_members;
create policy "Membership is readable within a conversation"
  on public.conversation_members for select to authenticated
  using (
    -- Your own row without consulting anything, which is the common case and
    -- the one that must not depend on a function call.
    auth.uid() = user_id
    or public.is_conversation_member(conversation_id)
  );

-- The only thing a client may write here is its own read marker. Not `for
-- all`: joining and leaving are not things a member decides for themselves in
-- a direct thread, and an UPDATE policy that allowed `conversation_id` to
-- change would let someone move their membership into a thread they were
-- never in.
drop policy if exists "Members mark their own conversations read"
  on public.conversation_members;
create policy "Members mark their own conversations read"
  on public.conversation_members for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

revoke update on public.conversation_members from authenticated;
grant update (last_read_at) on public.conversation_members to authenticated;

drop policy if exists "Messages are readable by members" on public.messages;
create policy "Messages are readable by members"
  on public.messages for select to authenticated
  using (public.is_conversation_member(conversation_id));

-- Sending. As yourself, into a thread you are in, that is not blocked.
drop policy if exists "Members send their own messages" on public.messages;
create policy "Members send their own messages"
  on public.messages for insert to authenticated
  with check (
    auth.uid() = sender_id
    and public.is_conversation_member(conversation_id)
    and public.conversation_is_open(conversation_id)
  );

-- Unsending your own. No UPDATE policy: an edited message in somebody else's
-- thread is a message they read one thing and now shows another, and there is
-- no version of that worth having without showing that it was edited.
drop policy if exists "Senders delete their own messages" on public.messages;
create policy "Senders delete their own messages"
  on public.messages for delete to authenticated
  using (auth.uid() = sender_id);

-- ---------------------------------------------------------------------------
-- 4. Starting a conversation
-- ---------------------------------------------------------------------------
-- Find-or-create, in one call, safe against two devices doing it at once.
--
-- SECURITY DEFINER because it writes the other person's membership row. That
-- is exactly the power that has to be justified, so the guards are first: not
-- yourself, not somebody who does not exist, and not somebody either of you
-- has blocked.

create or replace function public.start_direct_conversation(p_other uuid)
returns uuid language plpgsql security definer set search_path = public
as $fn$
declare
  v_me uuid := auth.uid();
  v_key text;
  v_id uuid;
begin
  if v_me is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  if p_other is null or p_other = v_me then
    raise exception 'cannot message yourself' using errcode = '22023';
  end if;

  if not exists (select 1 from public.users where id = p_other) then
    raise exception 'no such user' using errcode = '23503';
  end if;

  if public.is_blocked_with(p_other) then
    -- Deliberately the same error either way round. Telling somebody they
    -- have been blocked is telling them something the person who blocked them
    -- chose not to say.
    raise exception 'conversation unavailable' using errcode = '42501';
  end if;

  v_key := least(v_me::text, p_other::text) || ':'
        || greatest(v_me::text, p_other::text);

  -- The upsert is what makes this safe under a race: whichever call arrives
  -- second conflicts on `direct_key` and reads the row the first one wrote,
  -- rather than creating a second thread.
  insert into public.conversations (direct_key)
  values (v_key)
  on conflict (direct_key) do update set direct_key = excluded.direct_key
  returning id into v_id;

  insert into public.conversation_members (conversation_id, user_id)
  values (v_id, v_me), (v_id, p_other)
  on conflict (conversation_id, user_id) do nothing;

  return v_id;
end;
$fn$;

comment on function public.start_direct_conversation(uuid) is
  'The id of the direct conversation with p_other, creating it if needed.';

revoke all on function public.start_direct_conversation(uuid) from public;
grant execute on function public.start_direct_conversation(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. The conversation list
-- ---------------------------------------------------------------------------
-- One row per thread, with the other person, the last thing said, and how much
-- of it is unread.
--
-- A function rather than a query the client assembles, because assembling it
-- takes a lateral join per conversation for the last message and an aggregate
-- for the unread count, and PostgREST can express neither. The alternative is
-- one request per thread, which is the shape that makes a chat list slow the
-- moment somebody has twenty of them.
--
-- SECURITY DEFINER, so it must scope itself: every branch below is bounded by
-- `m.user_id = auth.uid()`, and nothing here takes a parameter that could
-- widen it.

create or replace function public.conversation_summaries()
returns table (
  conversation_id uuid,
  other_id uuid,
  other_username text,
  other_display_name text,
  other_avatar_url text,
  last_message_at timestamptz,
  last_body text,
  last_sender_id uuid,
  unread_count integer
)
language sql security definer set search_path = public stable
as $fn$
  select
    c.id,
    o.id,
    o.username,
    o.display_name,
    o.avatar_url,
    c.last_message_at,
    last_message.body,
    last_message.sender_id,
    coalesce(unread.count, 0)::integer
  from public.conversations c
  join public.conversation_members me
    on me.conversation_id = c.id and me.user_id = auth.uid()
  -- The other side of a direct thread. A left join so a conversation whose
  -- other member deleted their account still lists, rather than vanishing and
  -- taking its history with it.
  left join public.conversation_members them
    on them.conversation_id = c.id and them.user_id <> auth.uid()
  left join public.users o on o.id = them.user_id
  left join lateral (
    select m.body, m.sender_id
      from public.messages m
     where m.conversation_id = c.id
     order by m.created_at desc
     limit 1
  ) last_message on true
  left join lateral (
    select count(*) as count
      from public.messages m
     where m.conversation_id = c.id
       and m.created_at > me.last_read_at
       -- Your own messages are never unread to you.
       and m.sender_id is distinct from auth.uid()
  ) unread on true
  -- A thread with nothing in it is one somebody opened and did not write in.
  -- It is not a conversation yet and does not belong in a list of them.
  where last_message.body is not null
  order by c.last_message_at desc;
$fn$;

revoke all on function public.conversation_summaries() from public;
grant execute on function public.conversation_summaries() to authenticated;

-- ---------------------------------------------------------------------------
-- 6. Keeping `last_message_at` true
-- ---------------------------------------------------------------------------
-- A trigger rather than the client, because the client that sends a message is
-- not the only thing that could, and a list ordered by a column the sender
-- forgot to update is a list in the wrong order.

create or replace function public.messages_touch_conversation()
returns trigger language plpgsql security definer set search_path = public
as $fn$
begin
  update public.conversations
     set last_message_at = new.created_at
   where id = new.conversation_id;
  return null;
end;
$fn$;

drop trigger if exists messages_touch_conversation_trigger on public.messages;
create trigger messages_touch_conversation_trigger
  after insert on public.messages
  for each row execute function public.messages_touch_conversation();

-- ---------------------------------------------------------------------------
-- 7. Realtime
-- ---------------------------------------------------------------------------
-- Adds `messages` to the publication the Realtime server reads. Without this
-- the app's subscription connects, stays connected, and never receives
-- anything — which looks exactly like a bug in the client.
--
-- Guarded: adding a table already in a publication is an error, not a no-op.
--
-- RLS still applies. A subscriber receives a change only if the policy above
-- would have let them select the row, so a thread you are not in sends you
-- nothing even though every insert crosses the same publication.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end
$$;

-- Realtime sends the whole old row on a delete only when the table is set to
-- replicate it. Without this, an unsent message arrives as a payload with just
-- its primary key, and the client cannot tell which conversation to remove it
-- from.
alter table public.messages replica identity full;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- 8. Verify
-- ---------------------------------------------------------------------------
-- The tables and their policies. Three tables, and every one with RLS on:
--   select c.relname, c.relrowsecurity, count(p.policyname) as policies
--     from pg_class c
--     join pg_namespace n on n.oid = c.relnamespace
--     left join pg_policies p on p.tablename = c.relname
--    where n.nspname = 'public'
--      and c.relname in ('conversations', 'conversation_members', 'messages')
--    group by c.relname, c.relrowsecurity;
--
-- Starting one. Run twice with the same id — it must return the SAME uuid both
-- times, which is the whole point of `direct_key`:
--   select public.start_direct_conversation('<their user id>');
--   select public.start_direct_conversation('<their user id>');
--
-- And that it refuses the things it should. Each of these must raise:
--   select public.start_direct_conversation(auth.uid());              -- yourself
--   select public.start_direct_conversation(gen_random_uuid());       -- nobody
--
-- Blocking closes it. Block them, then:
--   select public.conversation_is_open('<conversation id>');          -- false
--   insert into public.messages (conversation_id, sender_id, body)
--   values ('<conversation id>', auth.uid(), 'should fail');          -- 42501
--
-- The list, which is what the app actually calls:
--   select * from public.conversation_summaries();
--
-- That you cannot read a thread you are not in. As a third account, with a
-- conversation id from the other two, all of these must return zero rows:
--   select count(*) from public.messages where conversation_id = '<id>';
--   select count(*) from public.conversations where id = '<id>';
--   select public.is_conversation_member('<id>');                     -- false
--
-- And that realtime will actually deliver. This must return one row:
--   select schemaname, tablename from pg_publication_tables
--    where pubname = 'supabase_realtime' and tablename = 'messages';
