-- TindaTinda POS schema. Run in Supabase SQL editor.
create extension if not exists pgcrypto;
create table if not exists public.platform_admins(user_id uuid primary key references auth.users(id) on delete cascade);
create table if not exists public.stores(id uuid primary key default gen_random_uuid(),name text not null check(length(trim(name)) between 2 and 120),created_at timestamptz not null default now(),active boolean not null default true);
create table if not exists public.store_members(store_id uuid not null references public.stores(id) on delete cascade,user_id uuid not null references auth.users(id) on delete cascade,role text not null check(role in ('owner','manager','cashier')),primary key(store_id,user_id));
create table if not exists public.products(id uuid primary key default gen_random_uuid(),store_id uuid not null references public.stores(id) on delete cascade,name text not null check(length(trim(name)) between 1 and 160),barcode text,price_cents integer not null check(price_cents>=0),stock integer not null default 0 check(stock>=0),created_at timestamptz not null default now());
create unique index if not exists products_store_barcode_unique on public.products(store_id,barcode) where barcode is not null;
create table if not exists public.sales(id uuid primary key default gen_random_uuid(),store_id uuid not null references public.stores(id),cashier_id uuid not null references auth.users(id),request_id uuid not null,total_cents bigint not null check(total_cents>=0),cash_cents bigint not null check(cash_cents>=total_cents),created_at timestamptz not null default now(),unique(store_id,request_id));
create table if not exists public.sale_lines(id uuid primary key default gen_random_uuid(),sale_id uuid not null references public.sales(id) on delete cascade,product_id uuid not null references public.products(id),qty integer not null check(qty>0),unit_price_cents integer not null check(unit_price_cents>=0));
create table if not exists public.inventory_movements(id uuid primary key default gen_random_uuid(),store_id uuid not null references public.stores(id),product_id uuid not null references public.products(id),delta integer not null,reason text not null,actor_id uuid references auth.users(id),created_at timestamptz not null default now());
create or replace function public.is_platform_admin() returns boolean language sql stable security definer set search_path='' as $$ select exists(select 1 from public.platform_admins where user_id=(select auth.uid())) $$;
create or replace function public.has_store_role(p_store uuid,p_roles text[]) returns boolean language sql stable security definer set search_path='' as $$ select public.is_platform_admin() or exists(select 1 from public.store_members m join public.stores s on s.id=m.store_id where m.store_id=p_store and m.user_id=(select auth.uid()) and m.role=any(p_roles) and s.active) $$;
alter table public.platform_admins enable row level security;
alter table public.stores enable row level security;
alter table public.store_members enable row level security;
alter table public.products enable row level security;
alter table public.sales enable row level security;
alter table public.sale_lines enable row level security;
alter table public.inventory_movements enable row level security;
create policy "admin read own role" on public.platform_admins for select to authenticated using(user_id=(select auth.uid()));
create policy "store read membership" on public.stores for select to authenticated using(public.is_platform_admin() or public.has_store_role(id,array['owner','manager','cashier']));
create policy "member read" on public.store_members for select to authenticated using(public.is_platform_admin() or public.has_store_role(store_id,array['owner','manager','cashier']));
create policy "product read" on public.products for select to authenticated using(public.has_store_role(store_id,array['owner','manager','cashier']));
create policy "product insert" on public.products for insert to authenticated with check(public.has_store_role(store_id,array['owner','manager']));
create policy "product update" on public.products for update to authenticated using(public.has_store_role(store_id,array['owner','manager'])) with check(public.has_store_role(store_id,array['owner','manager']));
create policy "sales read" on public.sales for select to authenticated using(public.has_store_role(store_id,array['owner','manager','cashier']));
create policy "sale lines read" on public.sale_lines for select to authenticated using(exists(select 1 from public.sales s where s.id=sale_id and public.has_store_role(s.store_id,array['owner','manager','cashier'])));
create policy "movements read" on public.inventory_movements for select to authenticated using(public.has_store_role(store_id,array['owner','manager']));
create or replace function public.admin_create_store(p_name text,p_owner_email text default null) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_owner uuid;
begin
 if not public.is_platform_admin() then raise exception 'Not authorized';end if;
 if length(trim(p_name))<2 then raise exception 'Invalid store name';end if;
 if p_owner_email is not null and trim(p_owner_email)<>'' then
  select id into v_owner from auth.users where lower(email)=lower(trim(p_owner_email));
  if v_owner is null then raise exception 'Owner account does not exist';end if;
 end if;
 insert into public.stores(name) values(trim(p_name)) returning id into v_id;
 if v_owner is not null then insert into public.store_members(store_id,user_id,role) values(v_id,v_owner,'owner');end if;
 return v_id;
end $$;
create or replace function public.checkout_cash(p_store_id uuid,p_request_id uuid,p_lines jsonb,p_cash_cents bigint) returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_total bigint:=0;v_line record;v_product record;v_count int;v_distinct int;
begin
 if not public.has_store_role(p_store_id,array['owner','manager','cashier']) then raise exception 'Not authorized';end if;
 if not exists(select 1 from public.stores where id=p_store_id and active) then raise exception 'Store inactive';end if;
 select id into v_id from public.sales where store_id=p_store_id and request_id=p_request_id;
 if v_id is not null then return v_id;end if;
 if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)=0 or jsonb_array_length(p_lines)>100 then raise exception 'Invalid cart';end if;
 select count(*),count(distinct product_id) into v_count,v_distinct from jsonb_to_recordset(p_lines) as x(product_id uuid,qty integer);
 if v_count<>v_distinct then raise exception 'Duplicate product lines';end if;
 -- Lock products in deterministic order to avoid overselling and reduce deadlocks.
 for v_line in select product_id,qty from jsonb_to_recordset(p_lines) as x(product_id uuid,qty integer) order by product_id loop
  if v_line.qty is null or v_line.qty<=0 or v_line.qty>10000 then raise exception 'Invalid quantity';end if;
  select * into v_product from public.products where id=v_line.product_id and store_id=p_store_id for update;
  if not found or v_product.stock<v_line.qty then raise exception 'Insufficient stock or unknown product';end if;
  v_total:=v_total+(v_product.price_cents::bigint*v_line.qty);
 end loop;
 if p_cash_cents is null or p_cash_cents<v_total or p_cash_cents>100000000000 then raise exception 'Invalid cash received';end if;
 insert into public.sales(store_id,cashier_id,request_id,total_cents,cash_cents) values(p_store_id,auth.uid(),p_request_id,v_total,p_cash_cents) returning id into v_id;
 for v_line in select product_id,qty from jsonb_to_recordset(p_lines) as x(product_id uuid,qty integer) order by product_id loop
  select * into v_product from public.products where id=v_line.product_id and store_id=p_store_id;
  update public.products set stock=stock-v_line.qty where id=v_line.product_id;
  insert into public.sale_lines(sale_id,product_id,qty,unit_price_cents) values(v_id,v_line.product_id,v_line.qty,v_product.price_cents);
  insert into public.inventory_movements(store_id,product_id,delta,reason,actor_id) values(p_store_id,v_line.product_id,-v_line.qty,'sale',auth.uid());
 end loop;
 return v_id;
exception when unique_violation then
 select id into v_id from public.sales where store_id=p_store_id and request_id=p_request_id;
 if v_id is not null then return v_id;end if;
 raise;
end $$;
revoke all on function public.admin_create_store(text,text) from public,anon;
revoke all on function public.checkout_cash(uuid,uuid,jsonb,bigint) from public,anon;
grant execute on function public.admin_create_store(text,text) to authenticated;
grant execute on function public.checkout_cash(uuid,uuid,jsonb,bigint) to authenticated;
-- Bootstrap manually: create a user in Authentication > Users, then run:
-- insert into public.platform_admins(user_id) values ('YOUR_AUTH_USER_UUID');
