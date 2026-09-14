-- Giving somebody premium by hand, and taking it back.
--
-- Prerequisites: `premium.sql`. Re-runnable: it only creates functions.
--
-- Run this in the Supabase SQL editor (Dashboard -> SQL Editor -> New query).
--
-- ---------------------------------------------------------------------------
-- What this is for
-- ---------------------------------------------------------------------------
-- Comping an account: a tester, a friend, somebody whose purchase went wrong
-- and who is owed the thing they paid for while support works out why. The
-- `insert ... on conflict` that does it is already written out at the bottom
-- of `premium.sql`, and it is three lines — but it is three lines that are
-- retyped from memory at the moment somebody is annoyed, and the ways to get
-- it wrong are quiet ones:
--
--   * `insert` without the `on conflict` clause, which fails for anybody who
--     has ever had a row — including everybody whose subscription lapsed,
--     which is most of the people this gets used on.
--   * `delete` instead of setting the tier back to free, which throws away the
--     fact that they ever paid. A missing row and a lapsed row both read as
--     free, and only one of them can answer a support question.
--   * A user id copied out of the wrong column. There is one uuid per user and
--     several places to find it, and `users.id` in this schema is the same
--     value as `auth.users.id` only because it was set up that way.
--
-- So the statement gets a name and the id gets looked up from the email, which
-- is what anybody actually has in front of them.
--
-- ---------------------------------------------------------------------------
-- These run as the service role, and only as the service role
-- ---------------------------------------------------------------------------
-- The SQL editor is the service role, which bypasses RLS — that is why these
-- work there and why `execute` is granted to nobody else. `subscriptions`
-- grants `authenticated` a select and nothing more, and that is the entire
-- security model of the paid tier: a client that can grant itself premium is a
-- client that will. See the header of `premium.sql`.
--
-- SECURITY INVOKER (the default) rather than DEFINER, deliberately. A definer
-- function that writes `subscriptions` is exactly the hole the table's missing
-- write policies exist to close — it would run with the owner's rights
-- whoever called it, and one accidental `grant execute ... to authenticated`
-- away from being a free premium button.

-- ---------------------------------------------------------------------------
-- 1. Grant
-- ---------------------------------------------------------------------------
-- The parameters are named `duration_months` and `grant_source` rather than
-- `months` and `source` because plpgsql resolves a bare identifier as a
-- variable *before* it tries it as a column, so a parameter called `source`
-- makes `insert into subscriptions (..., source) values (..., source)` raise
-- "column reference is ambiguous" — at runtime, on the day somebody needs it.
--
-- `duration_months => null` grants premium with no end date: a comp that does not
-- expire, which is what a tester or a staff account wants. Any number of
-- months sets `expires_at`, and the app downgrades itself when that passes
-- without anything having to run — see `Entitlement.isPremium`.
--
-- `source` is 'promo' rather than 'manual' by default because that is what
-- nearly every use of this is. 'manual' is for putting right a purchase that a
-- store did make.
--
-- Returns the row it wrote, so the result grid is the confirmation.

create or replace function public.grant_premium(
  user_email     text,
  duration_months int  default null,
  grant_source    text default 'promo'
)
returns public.subscriptions
language plpgsql
as $$
declare
  uid uuid;
  granted public.subscriptions;
begin
  select id into uid
    from auth.users
   where lower(email) = lower(trim(user_email));

  if uid is null then
    raise exception 'No account with the email %', user_email
      using hint = 'check auth.users — an OAuth account may be under a '
                   'different address';
  end if;

  insert into public.subscriptions as s (user_id, tier, expires_at, source)
  values (
    uid,
    'premium',
    case
      when duration_months is null then null
      else now() + make_interval(months => duration_months)
    end,
    grant_source
  )
  on conflict (user_id) do update
    set tier       = excluded.tier,
        expires_at = excluded.expires_at,
        source     = excluded.source
  returning s.* into granted;

  return granted;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Revoke
-- ---------------------------------------------------------------------------
-- Sets the tier back to free and keeps the row. Never deletes it: "they used
-- to pay" is a question support gets asked, and a deleted row cannot answer it.
--
-- `store_id` is left alone too. It is the store's own handle for the purchase,
-- and it is unique — clearing it would let the same purchase be attached to a
-- second account, which is the one thing that uniqueness is there to stop.
--
-- Nothing is deleted from the account either. A library of forty meals built
-- on premium stays where it is; the cap in `premium_limits.sql` is on insert
-- only, so it cannot grow until they subscribe again. See the note there.

create or replace function public.revoke_premium(user_email text)
returns public.subscriptions
language plpgsql
as $$
declare
  uid uuid;
  revoked public.subscriptions;
begin
  select id into uid
    from auth.users
   where lower(email) = lower(trim(user_email));

  if uid is null then
    raise exception 'No account with the email %', user_email;
  end if;

  update public.subscriptions as s
     set tier = 'free', expires_at = now()
   where s.user_id = uid
  returning s.* into revoked;

  -- No row means they never had one, which is already free. Not an error:
  -- running this twice should be quiet rather than alarming.
  return revoked;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Who has it
-- ---------------------------------------------------------------------------
-- For the question that follows every grant a week later: is it still on, and
-- when does it stop.

create or replace function public.premium_accounts()
returns table (email text, tier text, expires_at timestamptz, source text)
language sql
stable
as $$
  select u.email::text, s.tier, s.expires_at, s.source
    from public.subscriptions s
    join auth.users u on u.id = s.user_id
   where s.tier = 'premium'
   order by s.expires_at nulls first;
$$;

-- ---------------------------------------------------------------------------
-- 4. Nobody but the service role may call these
-- ---------------------------------------------------------------------------
-- Revoked explicitly rather than relying on the default. Postgres grants
-- `execute` on a new function to `public`, so a function that writes
-- `subscriptions` is callable by every signed-in user until this line runs —
-- and while the function is SECURITY INVOKER and RLS would still refuse the
-- write, "it happens to be refused one layer down" is not where this should
-- rest.

revoke all on function public.grant_premium(text, int, text) from public;
revoke all on function public.revoke_premium(text) from public;
revoke all on function public.premium_accounts() from public;

grant execute on function public.grant_premium(text, int, text) to service_role;
grant execute on function public.revoke_premium(text) to service_role;
grant execute on function public.premium_accounts() to service_role;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Using it
-- ---------------------------------------------------------------------------
-- In the SQL editor:
--
--   select * from public.grant_premium('someone@example.com');            -- forever
--   select * from public.grant_premium('someone@example.com', 12);        -- a year
--   select * from public.grant_premium('someone@example.com', 1, 'manual');
--
-- Named arguments work too, and are clearer for the second one:
--
--   select * from public.grant_premium(
--     user_email => 'someone@example.com', duration_months => 3);
--
--   select * from public.premium_accounts();
--
--   select * from public.revoke_premium('someone@example.com');
--
-- The app picks it up on its next entitlement refresh, which happens at launch
-- and after a purchase. To see it immediately on a device, close and reopen the
-- app — `EntitlementCubit.load` runs on the way in.
