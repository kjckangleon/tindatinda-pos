-- Restore authenticated access to Super Admin RPCs.
-- Function bodies still enforce is_platform_admin() for authorization.
grant usage on schema public to authenticated;
grant execute on function public.is_platform_admin() to authenticated;
grant execute on function public.admin_list_store_members() to authenticated;
grant execute on function public.admin_assign_store_member(uuid,text,text) to authenticated;
grant execute on function public.admin_remove_store_member(uuid,uuid) to authenticated;
grant execute on function public.admin_create_store(text,text) to authenticated;
-- Inspect effective function privileges:
select p.proname, has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_can_execute
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in ('is_platform_admin','admin_list_store_members','admin_assign_store_member','admin_remove_store_member','admin_create_store');
