-- Fixes: creating a *private* group fails with
--   new row violates row-level security policy for table "groups"  (42501)
-- while creating a public one works.
--
-- ## What is actually wrong
--
-- `GroupRepository.createGroup` does `insert(...).select(...).single()`, which
-- PostgREST sends as `INSERT ... RETURNING`. Postgres applies the SELECT
-- policy to a row it returns, so creating a group requires being allowed to
-- read it — in the same statement that creates it.
--
-- The SELECT policy was:
--
--   using (not is_private or public.is_group_member(id))
--
-- For a public group `not is_private` is true and it returns. For a private
-- one it falls through to membership, and the owner is made a member by
-- `groups_add_owner_as_member`, which is an **AFTER INSERT** trigger — it has
-- not run when RETURNING is evaluated. So the creator of a private group could
-- not read back the row they were in the middle of writing.
--
-- Which means the row does land. A private group created before this file was
-- run exists, owned by whoever made it, and becomes visible to them as soon as
-- this policy is in place — nothing needs cleaning up.
--
-- ## The fix
--
-- Say the thing the policy left out: an owner can always read their own group.
--
-- That is not redundant with membership even though the trigger makes every
-- owner a member. It is what holds *during* the insert, before any trigger has
-- fired — and it is what holds if that trigger is ever missing. A group whose
-- own creator cannot see it is not a state worth being one trigger away from.
--
-- Nothing else is touched. The insert, update and delete policies are correct
-- and are doing their job — a public group creates fine, which is the proof.
--
-- Safe to run more than once.
--
-- Run this in the Supabase SQL editor.

drop policy if exists "Groups are readable when public or joined" on public.groups;
create policy "Groups are readable when public or joined"
  on public.groups for select to authenticated
  using (
    not is_private
    or auth.uid() = owner_id
    or public.is_group_member(id)
  );

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------
-- Verify
-- ---------------------------------------------------------------------------
-- The policy now has three clauses:
--   select policyname, cmd, qual from pg_policies
--    where tablename = 'groups' and cmd = 'SELECT';
--
-- Creating a private group returns its row, which is the thing that failed.
-- Both of these should come back with an id:
--   insert into public.groups (name, owner_id, is_private)
--   values ('policy probe public', auth.uid(), false) returning id, name;
--   insert into public.groups (name, owner_id, is_private)
--   values ('policy probe private', auth.uid(), true) returning id, name;
--
-- The trigger still ran, so the owner is a member of both:
--   select g.name, m.role from public.groups g
--     join public.group_members m on m.group_id = g.id and m.user_id = auth.uid()
--    where g.name like 'policy probe%';
--
--   delete from public.groups where name like 'policy probe%';
--
-- Any private group made before this file was run is now visible again. If
-- this returns rows, those are they — they were never lost:
--   select id, name, created_at from public.groups
--    where owner_id = auth.uid() and is_private
--    order by created_at desc;
--
-- And somebody else's private group is still invisible. Signed in as another
-- account, this must return zero:
--   select count(*) from public.groups where is_private and owner_id <> auth.uid();
