-- ---------------------------------------------------------------------------
-- Bulkr — push notifications for direct messages
-- ---------------------------------------------------------------------------
-- Run after `chat_schema.sql`, `push_devices.sql` and `social_privacy.sql`,
-- and after the send-push function is deployed. Safe to run more than once.
--
-- `notifications.sql` deliberately leaves direct messages out of the
-- notifications table, and that was right: a message that produced both a
-- thread badge and an inbox row would be one event announced twice.
--
-- What that missed is that push hangs off the notifications table. So a
-- message updated the badge, and the phone in your pocket said nothing —
-- which is the one notification a chat app actually has to get right. This
-- gives messages their own route to the same function, without putting a row
-- in an inbox that already knows about them.

-- ---------------------------------------------------------------------------
-- 1. Who to wake, and what to say
-- ---------------------------------------------------------------------------
-- Service-role only, like `push_payload`: it reads other people's device
-- tokens and message bodies, so it must never be reachable from a client.
create or replace function public.message_push_payload(p_message uuid)
returns table (
  token text,
  platform text,
  title text,
  body text,
  conversation_id uuid
)
language sql
security definer
set search_path = public
as $$
  select
    d.token,
    d.platform,
    -- The sender's name, not 'Bulkr'. A message is from a person, and a
    -- notification that hides who it is from is one the user has to open the
    -- app to understand.
    coalesce(s.display_name, s.username, 'Someone') as title,
    case
      when char_length(m.body) > 140 then left(m.body, 139) || '…'
      else m.body
    end as body,
    m.conversation_id
  from public.messages m
  join public.conversation_members r
    on r.conversation_id = m.conversation_id
   and r.user_id is distinct from m.sender_id
  join public.device_tokens d
    on d.user_id = r.user_id
  left join public.users s
    on s.id = m.sender_id
  where m.id = p_message
    -- A message whose sender's account is gone. `is distinct from` above is
    -- true for everybody once `sender_id` is null, so the "not the sender"
    -- exclusion quietly stops excluding anyone — and there is no longer a
    -- person to announce. Unreachable in practice, because deleting a user
    -- cascades away their membership and their devices before this could run,
    -- but the join should not depend on that to be correct.
    and m.sender_id is not null
    -- Already read it. pg_net is asynchronous, so this runs a moment after the
    -- insert — long enough for somebody with the thread open to have marked it
    -- read over Realtime. That is exactly the case where a buzzing phone is
    -- most annoying, and the same reason `push_payload` checks `read_at`.
    and r.last_read_at < m.created_at
    -- Blocked in either direction. `conversation_is_open` cannot be reused
    -- here because it is written against `auth.uid()`, and there is no session
    -- behind a webhook.
    and not exists (
      select 1
        from public.blocks b
       where (b.blocker_id = r.user_id and b.blocked_id = m.sender_id)
          or (b.blocker_id = m.sender_id and b.blocked_id = r.user_id)
    );
$$;

revoke execute on function public.message_push_payload(uuid) from public;
revoke execute on function public.message_push_payload(uuid) from authenticated;
grant execute on function public.message_push_payload(uuid) to service_role;

comment on function public.message_push_payload(uuid) is
  'Devices to push a direct message to, skipping the sender, blocked pairs '
  'and anyone who has already read it.';

-- ---------------------------------------------------------------------------
-- 2. Firing it
-- ---------------------------------------------------------------------------
-- Two ways, and you only need one.
--
-- The dashboard: Integrations -> Database Webhooks -> Create, on
-- `public.messages`, Insert only, POST to
-- https://<project ref>.supabase.co/functions/v1/send-push with the header
-- `x-push-secret` set to your PUSH_WEBHOOK_SECRET. This is the same setup as
-- the one on `public.notifications`, pointed at a different table — the
-- function tells them apart by the `table` field the webhook sends.
--
-- Or the trigger below, if the dashboard is not cooperating. Replace the two
-- values and run the file. Leaving them as they are is not an error: the
-- function notices and does nothing, so the dashboard route still works.
create extension if not exists pg_net with schema extensions;

create or replace function public.messages_send_push()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  function_url text := 'https://REPLACE_ME.supabase.co/functions/v1/send-push';
  push_secret  text := 'REPLACE_ME';
begin
  if function_url like '%REPLACE_ME%' or push_secret = 'REPLACE_ME' then
    return new;
  end if;

  perform net.http_post(
    url := function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', push_secret
    ),
    -- The shape a dashboard webhook sends, so the function does not care which
    -- route set it up. `table` is what tells it this is a message rather than
    -- a notification.
    body := jsonb_build_object(
      'table', 'messages',
      'record', jsonb_build_object('id', new.id)
    ),
    timeout_milliseconds := 5000
  );

  return new;
exception
  when others then
    -- A message that could not be pushed is still a message. It is committed,
    -- Realtime has already delivered it, and the badge is right; failing the
    -- insert because a queue call errored would trade the part that works for
    -- the part that did not.
    raise notice 'Bulkr: message push not queued — %', sqlerrm;
    return new;
end;
$$;

drop trigger if exists messages_send_push on public.messages;
create trigger messages_send_push
  after insert on public.messages
  for each row execute function public.messages_send_push();

-- ---------------------------------------------------------------------------
-- 3. Verify
-- ---------------------------------------------------------------------------
-- Whether anything is set up to fire at all:
--
--   select tgname from pg_trigger
--    where tgrelid = 'public.messages'::regclass and not tgisinternal;
--
-- A dashboard webhook shows up here too, under a generated name.
--
-- Then send a message from the other device and read what came back:
--
--   select id, created, status_code, content
--     from net._http_response
--    order by created desc
--    limit 5;
--
-- 200 with {"sent":1} is delivery. 403 is the secret not matching. 401 is the
-- function deployed without --no-verify-jwt.
--
-- ---------------------------------------------------------------------------
-- 4. {"sent":0} — which gate closed
-- ---------------------------------------------------------------------------
-- Zero is not a failure on its own: it means the webhook fired, the function
-- ran, and the query above found nobody to wake. Three conditions can do that
-- and the response cannot tell them apart, so ask directly. This reports the
-- most recent message and, for every recipient of it, what each condition
-- says:
--
--   devices = 0            no `device_tokens` row. On iPhone this is usually
--                          no APNs key uploaded to Firebase, so the app never
--                          received a token to register.
--   unread = false         `last_read_at` is already past the message. Either
--                          they really were reading it, or the app marked it
--                          read over Realtime moments after it arrived.
--   blocked = true         a block in one direction or the other.
--
-- All three false-ish and it should have sent — in which case the message id
-- printed here is the one to pass to `message_push_payload` by hand.

with recent as (
  select id, conversation_id, sender_id, created_at, body
    from public.messages
   order by created_at desc
   limit 1
)
select
  m.id            as message_id,
  m.created_at    as sent_at,
  coalesce(su.username, '(deleted)') as from_user,
  coalesce(ru.username, '(unknown)') as to_user,
  (select count(*) from public.device_tokens d where d.user_id = r.user_id)
                  as devices,
  r.last_read_at,
  r.last_read_at < m.created_at as unread,
  exists (
    select 1 from public.blocks b
     where (b.blocker_id = r.user_id and b.blocked_id = m.sender_id)
        or (b.blocker_id = m.sender_id and b.blocked_id = r.user_id)
  )               as blocked
from recent m
join public.conversation_members r
  on r.conversation_id = m.conversation_id
 and r.user_id is distinct from m.sender_id
left join public.users ru on ru.id = r.user_id
left join public.users su on su.id = m.sender_id;
