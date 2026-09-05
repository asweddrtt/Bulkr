-- ---------------------------------------------------------------------------
-- Bulkr — fire send-push when a notification is written
-- ---------------------------------------------------------------------------
-- Only needed if the dashboard's Integrations -> Database Webhooks page is not
-- cooperating. It does exactly what that page would have set up, in SQL you
-- can read.
--
-- Run after `notifications.sql` and `push_devices.sql`, and after the
-- send-push function is deployed.
--
-- BEFORE RUNNING: replace the two values in section 1 with your own.

-- ---------------------------------------------------------------------------
-- 1. Your two values
-- ---------------------------------------------------------------------------
-- Replace these, then run the whole file.
--
--   function_url  https://<your project ref>.supabase.co/functions/v1/send-push
--   push_secret   the PUSH_WEBHOOK_SECRET you set with `supabase secrets set`
--
-- A note on the secret living here: it ends up in the function body, which
-- means anyone who can read `pg_proc` can read it. Supabase's own dashboard
-- webhooks have the same property — they store their headers in the trigger
-- definition — so this is not worse than the UI route, but it is worth
-- knowing. What it protects is narrow: `push_payload` is service-role only, so
-- the worst someone could do with the secret is make a push fire for a
-- notification id they already know.

-- ---------------------------------------------------------------------------
-- 2. The extension that lets Postgres make an HTTP request
-- ---------------------------------------------------------------------------
-- pg_net is asynchronous: `net.http_post` puts the request on a queue that a
-- background worker drains, and returns immediately. So this does not hold the
-- transaction open across the network — the notification is committed whether
-- or not FCM is having a good day, which is the property that matters.
create extension if not exists pg_net with schema extensions;

-- ---------------------------------------------------------------------------
-- 3. The trigger
-- ---------------------------------------------------------------------------
create or replace function public.notifications_send_push()
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
    raise notice
      'Bulkr: push webhook not configured — edit the two values in push_webhook.sql and run it again.';
    return new;
  end if;

  perform net.http_post(
    url := function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-push-secret', push_secret
    ),
    -- The same shape a dashboard webhook sends, so the function does not care
    -- which route set it up.
    body := jsonb_build_object('record', jsonb_build_object('id', new.id)),
    timeout_milliseconds := 5000
  );

  return new;
exception
  when others then
    -- A notification that could not be pushed is still a notification. It is
    -- already in the table and the in-app list will show it; failing the
    -- insert because a queue call errored would trade the thing that works for
    -- the thing that did not.
    raise notice 'Bulkr: push not queued — %', sqlerrm;
    return new;
end;
$$;

drop trigger if exists notifications_send_push on public.notifications;
create trigger notifications_send_push
  after insert on public.notifications
  for each row execute function public.notifications_send_push();

-- ---------------------------------------------------------------------------
-- 4. Verify
-- ---------------------------------------------------------------------------
-- The trigger exists:
--
--   select tgname from pg_trigger where tgname = 'notifications_send_push';
--
-- After a follow from a second account, the queue shows what was sent and what
-- came back:
--
--   select id, created, status_code, content
--     from net._http_response
--    order by created desc
--    limit 5;
--
-- 200 with {"sent":1} is delivery. 403 means the secret does not match what
-- `supabase secrets set` stored. 401 means the function was deployed without
-- --no-verify-jwt.
