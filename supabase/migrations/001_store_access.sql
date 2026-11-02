-- Run this migration once in Supabase SQL Editor after schema.sql.
create or replace function public.admin_assign_store_member(p_store_id uuid,p_user_email text,p_role text)
returns void language plpgsql security definer set search_path='' as $$
declare v_user_id uuid;
begin
 if not public.is_platform_admin() then raise exception 'Not authorized'; end if;
 if p_role not in ('owner','manager','cashier') then raise exception 'Invalid role'; end if;
 if not exists(select 1 from public.stores where id=p_store_id) then raise exception 'Store not found'; end if;
 select id into v_user_id from auth.users where lower(email)=lower(trim(p_user_email));
 if v_user_id is null then raise exception 'User not found. Create the account in Authentication first.'; end if;
 insert into public.store_members(store_id,user_id,role)
 values(p_store_id,v_user_id,p_role)
 on conflict(store_id,user_id) do update set role=excluded.role;
end $$;
create or replace function public.admin_remove_store_member(p_store_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_platform_admin() then raise exception 'Not authorized'; end if;
 delete from public.store_members where store_id=p_store_id and user_id=p_user_id;
end $$;
create or replace function public.admin_list_store_members()
returns table(store_id uuid,user_id uuid,email text,role text)
language plpgsql security definer set search_path='' as $$
begin
 if not public.is_platform_admin() then raise exception 'Not authorized'; end if;
 return query select m.store_id,m.user_id,u.email::text,m.role from public.store_members m join auth.users u on u.id=m.user_id order by u.email,m.store_id;
end $$;
revoke all on function public.admin_assign_store_member(uuid,text,text) from public,anon;
revoke all on function public.admin_remove_store_member(uuid,uuid) from public,anon;
revoke all on function public.admin_list_store_members() from public,anon;
grant execute on function public.admin_assign_store_member(uuid,text,text) to authenticated;
grant execute on function public.admin_remove_store_member(uuid,uuid) to authenticated;
grant execute on function public.admin_list_store_members() to authenticated;