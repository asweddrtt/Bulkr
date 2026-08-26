-- weight_logs has no RLS policies, so with RLS enabled Postgres denies every
-- read and write on it. That is why the day-one seed row never landed, why the
-- progress chart is empty, and why logging a weight reports 42501.
--
-- Same shape as the existing `users` policy ("Enable full access for users
-- based on id"), keyed on user_id instead of id.

alter table public.weight_logs enable row level security;

create policy "Enable full access for users based on user_id"
  on public.weight_logs
  for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Verify: this should now return one row for weight_logs.
--   select tablename, policyname, cmd from pg_policies
--   where tablename in ('users', 'weight_logs');
--
-- And to confirm which tables have RLS on but no policy at all:
--   select c.relname,
--          c.relrowsecurity as rls_enabled,
--          count(p.policyname) as policies
--     from pg_class c
--     join pg_namespace n on n.oid = c.relnamespace
--     left join pg_policies p on p.tablename = c.relname
--    where n.nspname = 'public' and c.relkind = 'r'
--    group by c.relname, c.relrowsecurity
--    order by policies, c.relname;
