-- Safe to run more than once. Allow signed-in users to verify only their own platform admin status.
grant usage on schema public to authenticated;
grant select on table public.platform_admins to authenticated;
alter table public.platform_admins enable row level security;
drop policy if exists "admin read own role" on public.platform_admins;
create policy "admin read own role"
on public.platform_admins for select to authenticated
using (user_id = (select auth.uid()));
grant execute on function public.is_platform_admin() to authenticated;
-- Verify the SQL privileges (RLS still restricts which rows users can see).
select
 has_table_privilege('authenticated','public.platform_admins','SELECT') as authenticated_can_select,
 has_function_privilege('authenticated','public.is_platform_admin()','EXECUTE') as authenticated_can_check_role;
