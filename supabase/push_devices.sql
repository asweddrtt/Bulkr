-- ---------------------------------------------------------------------------
-- Bulkr — where to send a push
-- ---------------------------------------------------------------------------
-- Run after `notifications.sql`. Safe to run more than once.
--
-- This is the database half of push notifications. The other two halves are
-- the `send-push` edge function in this repo and a Firebase project, which
-- only you can create — see `supabase/functions/send-push/README.md`.
--
-- Nothing here breaks if push is never finished. The table sits empty, the
-- trigger finds no tokens, and the in-app notifications built in
-- `notifications.sql` carry on exactly as they do now.

-- ---------------------------------------------------------------------------
-- 1. Devices
-- ---------------------------------------------------------------------------
-- One row per device per user, not one per user. People have a phone and a
-- tablet, and a notification that reached one of them is not a notification
-- delivered.
--
-- The token is the primary key rather than `(user_id, token)`, and that is
-- load-bearing: FCM hands the *same* token to whoever installs the app on that
-- device, so when two people share a phone the second sign-in has to take the
-- token over rather than sit beside the first. A primary key on the token plus
-- the upsert below is what makes that happen — otherwise the first user keeps
-- receiving the second user's notifications, which is a privacy bug, not a
-- delivery bug.
create table if not exists public.device_tokens (
  token text not null,
  user_id uuid not null,
  -- 'android', 'ios'. Not constrained to a list: a platform this build has
  -- never heard of is a client older or newer than this schema, and refusing
  -- its token would be refusing to notify it.
  platform text,
  created_at timestamptz not null default now(),
  -- Bumped every time the app starts and confirms the token. What tells a live
  -- device from one that was uninstalled a year ago.
  last_seen_at timestamptz not null default now(),
  constraint device_tokens_pkey primary key (token),
  constraint device_tokens_user_id_fkey
    foreign key (user_id) references public.users(id) on delete cascade
);

create index if not exists device_tokens_user_id_idx
  on public.device_tokens (user_id);

-- ---------------------------------------------------------------------------
-- 2. Row-level security
-- ---------------------------------------------------------------------------
alter table public.device_tokens enable row level security;

drop policy if exists "Devices are readable by their owner" on public.device_tokens;
create policy "Devices are readable by their owner"
  on public.device_tokens for select to authenticated
  using (auth.uid() = user_id);

-- Insert and update are how the app registers a token, and the upsert needs
-- both — including the case where the row exists and belongs to somebody else,
-- which is the shared-phone case above. `using` deliberately does not check
-- ownership for that reason; `with check` does, so the row can only ever end
-- up pointing at the caller.
drop policy if exists "Devices are registered by their owner" on public.device_tokens;
create policy "Devices are registered by their owner"
  on public.device_tokens for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Devices are claimed by whoever is signed in"
  on public.device_tokens;
create policy "Devices are claimed by whoever is signed in"
  on public.device_tokens for update to authenticated
  using (true)
  with check (auth.uid() = user_id);

drop policy if exists "Devices are removable by their owner" on public.device_tokens;
create policy "Devices are removable by their owner"
  on public.device_tokens for delete to authenticated
  using (auth.uid() = user_id);

grant select, insert, update, delete on public.device_tokens to authenticated;

-- ---------------------------------------------------------------------------
-- 3. What a push says
-- ---------------------------------------------------------------------------
-- Called by the `send-push` edge function with the service role, which is why
-- it is not readable by anyone else: it answers "where do I send this and what
-- does it say" for a notification belonging to somebody the caller is not.
--
-- SECURITY DEFINER with execute granted to `service_role` only. The app never
-- calls it and could not — `authenticated` has no privilege on it at all.
create or replace function public.push_payload(p_notification uuid)
returns table (
  token text,
  platform text,
  title text,
  body text
)
language sql
security definer
set search_path = public
as $$
  select
    d.token,
    d.platform,
    'Bulkr' as title,
    case n.kind
      when 'follow'  then coalesce(a.display_name, a.username, 'Someone')
                          || ' followed you'
      when 'like'    then coalesce(a.display_name, a.username, 'Someone')
                          || ' liked your post'
      when 'comment' then coalesce(a.display_name, a.username, 'Someone')
                          || ' commented on your post'
      when 'reply'   then coalesce(a.display_name, a.username, 'Someone')
                          || ' replied to you'
      else 'New activity'
    end as body
  from public.notifications n
  join public.device_tokens d on d.user_id = n.user_id
  left join public.users a on a.id = n.actor_id
  where n.id = p_notification
    -- Not if they have already seen it in the app. The webhook fires on
    -- insert, so this is only ever true when somebody was looking at the
    -- screen as it arrived — but that is exactly the case where a buzzing
    -- phone is most annoying.
    and n.read_at is null;
$$;

revoke execute on function public.push_payload(uuid) from public;
revoke execute on function public.push_payload(uuid) from authenticated;
grant execute on function public.push_payload(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 4. Verify
-- ---------------------------------------------------------------------------
--   select count(*) from public.device_tokens;
--
-- Zero until the app registers one, which needs the Firebase half. Then, from
-- a device that has signed in:
--
--   select user_id, platform, last_seen_at from public.device_tokens;
