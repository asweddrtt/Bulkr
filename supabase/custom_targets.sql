-- Setting your own calories and macro split, instead of the computed plan.
--
-- Prerequisites: `premium.sql` (for `is_premium()`), and the `users` table.
-- Re-runnable.
--
-- Run this in the Supabase SQL editor (Dashboard -> SQL Editor -> New query).
--
-- ---------------------------------------------------------------------------
-- What this column is for
-- ---------------------------------------------------------------------------
-- `daily_calorie_target` and the three `*_target_g` columns are written by the
-- onboarding plan and overwritten by every recalculation. That is correct for
-- somebody whose target should follow their weight — and wrong for somebody
-- who has decided on their own numbers, because the next recalculation throws
-- them away without asking.
--
-- So the flag does two things: it stops recalculation happening silently, and
-- it is what the app reads to know whose numbers these are.
--
-- ---------------------------------------------------------------------------
-- What is enforced, and what is not
-- ---------------------------------------------------------------------------
-- The trigger stops a free account setting the flag. It does **not** stop a
-- patched client writing whatever it likes into the four target columns — a
-- user may update their own row, and no policy can reasonably say "this
-- number must equal what a Mifflin-St Jeor calculation would produce".
--
-- That is deliberate rather than overlooked. What such a client would gain is
-- a calorie goal of its own invention, shown to nobody but itself, costing
-- nothing and harming no one — the same shape of non-problem as reading your
-- own history past seven days. The things that cost money or storage are the
-- ones enforced properly, in `premium_limits.sql`.

-- ---------------------------------------------------------------------------
-- 1. The column
-- ---------------------------------------------------------------------------

alter table public.users
  add column if not exists targets_are_custom boolean not null default false;

-- ---------------------------------------------------------------------------
-- 2. Premium-only
-- ---------------------------------------------------------------------------
-- Raises the same SQLSTATE as every other plan limit, so the app already knows
-- how to turn it into a sentence with a way out of it rather than a
-- permission error. See `lib/core/plan_limit_error.dart`.

create or replace function public.enforce_custom_targets()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
begin
  -- Only the transition into custom matters. Turning it back off is always
  -- allowed: somebody whose subscription lapsed must be able to return to a
  -- computed plan, and blocking that would strand them on numbers they can no
  -- longer edit.
  if new.targets_are_custom is not true then
    return new;
  end if;

  if old.targets_are_custom is true then
    return new;
  end if;

  -- Not a user action — a service-role import, or a cascade.
  if uid is null or uid is distinct from new.id then
    return new;
  end if;

  if not public.is_premium(uid) then
    raise exception 'Bulkr: custom targets are a Premium feature.'
      using errcode = 'BLKR2', hint = 'custom_targets';
  end if;

  return new;
end;
$$;

drop trigger if exists users_custom_targets_premium on public.users;
create trigger users_custom_targets_premium
  before update on public.users
  for each row execute function public.enforce_custom_targets();

-- ---------------------------------------------------------------------------
-- 3. Reload the API's schema cache
-- ---------------------------------------------------------------------------
notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
--   select targets_are_custom from public.users where id = auth.uid();
--
-- As an ordinary free account, this must fail with SQLSTATE BLKR2 and a hint
-- of `custom_targets`:
--
--   update public.users set targets_are_custom = true where id = auth.uid();
--
-- And must succeed once that account is premium.
