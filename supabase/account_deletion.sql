-- Making "delete my account" actually delete the account.
--
-- Prerequisites: every other migration, since this repairs foreign keys
-- created by all of them. Re-runnable, and a no-op once the graph is right.
--
-- Run this in the Supabase SQL editor (Dashboard -> SQL Editor -> New query).
--
-- ---------------------------------------------------------------------------
-- The failure this fixes
-- ---------------------------------------------------------------------------
-- `delete-account` calls `auth.admin.deleteUser`, which is one
-- `delete from auth.users`. Postgres will refuse that while any row anywhere
-- still points at it with a foreign key that does not say what to do about a
-- deleted parent — and GoTrue reports the refusal as, in full:
--
--     Database error deleting user
--
-- No constraint, no table, no column. Which is how an account deletion that
-- has never worked can look like a transient server error for months.
--
-- The tables in this repository were written with `on delete cascade`. The
-- ones that came before it — `users`, `meals`, `posts`, `daily_logs`,
-- `weight_logs` — were not necessarily, and `public.users.id` is the one that
-- matters most: every account has that row, so if its foreign key to
-- `auth.users` is the default `no action`, deletion fails for **everybody**,
-- including an account created a minute ago with nothing in it.
--
-- ---------------------------------------------------------------------------
-- Cascade or set null, and why it is decided per column
-- ---------------------------------------------------------------------------
-- Rewriting every such key to `cascade` would be wrong. A nullable column
-- pointing at a user is usually attribution — `notifications.actor_id`,
-- `messages.sender_id`, `posts.source_creator_id` — and cascading those would
-- delete the recipient's notification because the actor left, or a whole
-- conversation because one participant did.
--
-- So the rule is the column's own nullability, which is already the schema's
-- statement about this:
--
--   * `not null` — the row cannot exist without the user, so it is the user's
--     row and goes with them. `cascade`.
--   * nullable — the row can exist without the user, so it survives with the
--     attribution cleared. `set null`.
--
-- Only keys that currently say `no action` or `restrict` are touched. A key
-- that already names an action was a decision somebody made, and this does not
-- overrule it.

-- ---------------------------------------------------------------------------
-- 1. Repair
-- ---------------------------------------------------------------------------
do $$
declare
  fk        record;
  definition text;
  owned     boolean;
  action    text;
begin
  for fk in
    select con.oid          as oid,
           con.conname      as name,
           con.conrelid     as child_oid,
           con.conrelid::regclass::text as child,
           con.conkey       as columns,
           parent.relname   as parent
      from pg_constraint con
      join pg_class  child     on child.oid  = con.conrelid
      join pg_class  parent    on parent.oid = con.confrelid
      join pg_namespace cns    on cns.oid    = child.relnamespace
      join pg_namespace pns    on pns.oid    = parent.relnamespace
     where con.contype = 'f'
       -- No action, or restrict. Both block the delete.
       and con.confdeltype in ('a', 'r')
       -- Only the app's own tables. `storage` and `auth` belong to Supabase
       -- and rewriting their keys would be editing somebody else's schema.
       and cns.nspname = 'public'
       and ((pns.nspname = 'auth'   and parent.relname = 'users')
         or (pns.nspname = 'public' and parent.relname = 'users'))
  loop
    -- Every referencing column `not null`? Then the row is the user's own.
    select bool_and(att.attnotnull)
      into owned
      from unnest(fk.columns) as k(attnum)
      join pg_attribute att
        on att.attrelid = fk.child_oid
       and att.attnum   = k.attnum;

    action := case when owned then 'cascade' else 'set null' end;

    -- Reuse the existing definition rather than rebuilding it from catalogue
    -- columns: it already carries the column list, the referenced columns and
    -- any `match` or `on update` clause, and getting one of those subtly wrong
    -- here would be a silent change to a constraint nobody is looking at.
    definition := regexp_replace(
      pg_get_constraintdef(fk.oid),
      '\s+ON DELETE (NO ACTION|RESTRICT)',
      '',
      'gi'
    );

    execute format(
      'alter table %s drop constraint %I',
      fk.child, fk.name
    );
    execute format(
      'alter table %s add constraint %I %s on delete %s',
      fk.child, fk.name, definition, action
    );

    raise notice 'account_deletion: %.% -> % now on delete %',
      fk.child, fk.name, fk.parent, action;
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. What would still block a deletion
-- ---------------------------------------------------------------------------
-- The repair above covers `public`. Anything left is in a schema this file
-- will not edit — most often `storage.objects.owner`, which on older projects
-- was created with no delete action, so an account that has ever uploaded a
-- file cannot be deleted until its objects are gone.
--
-- `delete-account` calls this when a deletion fails, so the next time it
-- happens the log names the constraint instead of saying "database error".
create or replace function public.account_deletion_blockers()
returns table (schema_name text, table_name text, constraint_name text)
language sql
stable
security definer
set search_path = public, pg_catalog
as $$
  select cns.nspname::text,
         child.relname::text,
         con.conname::text
    from pg_constraint con
    join pg_class  child  on child.oid  = con.conrelid
    join pg_class  parent on parent.oid = con.confrelid
    join pg_namespace cns on cns.oid    = child.relnamespace
    join pg_namespace pns on pns.oid    = parent.relnamespace
   where con.contype = 'f'
     and con.confdeltype in ('a', 'r')
     and ((pns.nspname = 'auth'   and parent.relname = 'users')
       or (pns.nspname = 'public' and parent.relname = 'users'))
   order by 1, 2, 3;
$$;

-- Service role only. This describes the shape of the database, which is not
-- something a signed-in user has any reason to read.
revoke all on function public.account_deletion_blockers() from public;
revoke all on function public.account_deletion_blockers() from anon;
revoke all on function public.account_deletion_blockers() from authenticated;

-- ---------------------------------------------------------------------------
-- 3. Check it worked
-- ---------------------------------------------------------------------------
-- Run this afterwards. Zero rows is the answer you want.
--
--   select * from public.account_deletion_blockers();
--
-- A row naming `storage` means Supabase's own key, and the fix is to clear the
-- account's files before deleting it — which `delete-account` already does,
-- for the buckets Bulkr uses.
