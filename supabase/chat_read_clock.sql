-- ---------------------------------------------------------------------------
-- Bulkr — one clock, and it is the server's
-- ---------------------------------------------------------------------------
-- Run after `chat_schema.sql` and `push_devices.sql`. Safe to run more than
-- once.
--
-- `conversation_members.last_read_at` is compared against
-- `messages.created_at` in two places that matter: the unread badge, and the
-- decision in `chat_push.sql` about whether a message is worth waking a phone
-- for. `created_at` defaults to the server's `now()`.
--
-- The app was writing `last_read_at` from the device: `DateTime.now()`, sent
-- as a literal. So the comparison was between two clocks that have no reason
-- to agree. A phone running a minute fast writes a read time in the future,
-- and every message sent in the following minute reads as already seen — no
-- push, no badge, and nothing anywhere that says why.
--
-- PostgREST cannot put `now()` in an update payload, so this is a function.

create or replace function public.mark_conversation_read(p_conversation uuid)
returns timestamptz
language sql
-- Invoker, deliberately. The existing UPDATE policy on
-- `conversation_members` and the column grant that limits writes to
-- `last_read_at` are exactly the right rules; a definer function would be
-- taking that authority away from the policy in order to re-implement it.
security invoker
set search_path = public
as $$
  update public.conversation_members
     set last_read_at = now()
   where conversation_id = p_conversation
     and user_id = auth.uid()
  returning last_read_at;
$$;

grant execute on function public.mark_conversation_read(uuid) to authenticated;

comment on function public.mark_conversation_read(uuid) is
  'Marks a thread read as of the server clock, so last_read_at and '
  'messages.created_at are comparable.';

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- Any read time in the future is a device that was writing its own clock:
--
--   select conversation_id, user_id, last_read_at, last_read_at - now() as ahead
--     from public.conversation_members
--    where last_read_at > now();
--
-- Those rows suppress pushes until the clock they came from catches up. Once
-- the app is updated they stop appearing, and existing ones can be pulled back
-- to the present:
--
--   update public.conversation_members set last_read_at = now()
--    where last_read_at > now();

-- ---------------------------------------------------------------------------
-- 2. device_tokens.last_seen_at, for the same reason
-- ---------------------------------------------------------------------------
-- The app was sending this one from the device too. It shows: a real row has
--
--   created_at   2026-09-08 07:52:14.777275+00   -- server
--   last_seen_at 2026-09-08 07:52:14.359154+00   -- phone, 0.4s behind
--
-- Nothing is broken by that. `last_seen_at` only separates a live device from
-- one uninstalled a year ago, and 0.4 seconds does not change the answer. It
-- is here because it is the same mistake, it is eight lines, and it was the
-- evidence that the two clocks on that phone genuinely disagree — which is
-- what made the read timestamp worth fixing before it bit.
--
-- A trigger rather than a default: an upsert on conflict has to *move* this
-- forward, and a default only applies to an insert.
--
-- It fires on every update, so the column cannot be set to anything else by
-- anyone, including deliberately. Backdating a row to test staleness means
-- disabling the trigger for the statement:
--
--   alter table public.device_tokens disable trigger device_tokens_touch;
--   -- ... backdate ...
--   alter table public.device_tokens enable trigger device_tokens_touch;
create or replace function public.device_tokens_touch()
returns trigger
language plpgsql
as $$
begin
  new.last_seen_at := now();
  return new;
end;
$$;

drop trigger if exists device_tokens_touch on public.device_tokens;
create trigger device_tokens_touch
  before insert or update on public.device_tokens
  for each row execute function public.device_tokens_touch();
