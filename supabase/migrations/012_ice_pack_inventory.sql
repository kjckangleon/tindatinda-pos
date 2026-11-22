-- Separate physical pack inventory. Legacy kilogram inventory is preserved, not converted automatically.
create table if not exists public.ice_pack_stock(
 store_id uuid not null references public.stores(id) on delete cascade,
 pack_kg integer not null check(pack_kg in (1,2,10,15)),
 packs bigint not null default 0 check(packs>=0),
 updated_at timestamptz not null default now(),
 primary key(store_id,pack_kg)
);
create table if not exists public.ice_pack_movements(
 id uuid primary key default gen_random_uuid(),
 store_id uuid not null references public.stores(id),
 pack_kg integer not null check(pack_kg in (1,2,10,15)),
 delta_packs bigint not null check(delta_packs<>0),
 reason text not null check(reason in ('production','sale')),
 sale_id uuid references public.ice_sales(id),
 actor_id uuid references auth.users(id),
 created_at timestamptz not null default now()
);
alter table public.ice_sales add column if not exists pack_kg integer check(pack_kg in (1,2,10,15));
alter table public.ice_sales add column if not exists pack_count integer check(pack_count>0);
alter table public.ice_sales add constraint ice_pack_pair check ((pack_kg is null)=(pack_count is null));
alter table public.ice_pack_stock enable row level security;
alter table public.ice_pack_movements enable row level security;
create policy ice_pack_stock_select on public.ice_pack_stock for select to authenticated using(public.has_store_role(store_id,array['owner','manager','cashier']) or public.is_platform_admin());
create policy ice_pack_movements_select on public.ice_pack_movements for select to authenticated using(public.has_store_role(store_id,array['owner','manager','cashier']) or public.is_platform_admin());
grant select on public.ice_pack_stock,public.ice_pack_movements to authenticated;
create or replace function public.ice_add_packs(p_store_id uuid,p_pack_kg integer,p_packs integer)
returns bigint language plpgsql security definer set search_path='' as $$
declare v_remaining bigint;
begin
 if p_store_id <> 'a1a7c4d4-77b9-4173-84f2-98211b9f289a'::uuid then raise exception 'Ice pack inventory unavailable';end if;
 if not (public.has_store_role(p_store_id,array['owner','manager']) or public.is_platform_admin()) then raise exception 'Not authorized';end if;
 if p_pack_kg is null or p_pack_kg not in(1,2,10,15) or p_packs is null or p_packs<1 or p_packs>1000000 then raise exception 'Invalid pack size or quantity';end if;
 insert into public.ice_pack_stock(store_id,pack_kg,packs) values(p_store_id,p_pack_kg,p_packs)
 on conflict(store_id,pack_kg) do update set packs=public.ice_pack_stock.packs+excluded.packs,updated_at=now()
 returning packs into v_remaining;
 insert into public.ice_pack_movements(store_id,pack_kg,delta_packs,reason,actor_id) values(p_store_id,p_pack_kg,p_packs,'production',auth.uid());
 return v_remaining;
end $$;
create or replace function public.ice_checkout_packs(p_store_id uuid,p_customer_id uuid,p_pack_kg integer,p_packs integer,p_cash_cents bigint,p_request_id uuid,p_delivered_by text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare v_customer public.ice_customers%rowtype;v_remaining bigint;v_total bigint;v_id uuid;v_qty bigint;
begin
 if p_store_id <> 'a1a7c4d4-77b9-4173-84f2-98211b9f289a'::uuid then raise exception 'Ice checkout unavailable';end if;
 if not (public.has_store_role(p_store_id,array['owner','manager','cashier']) or public.is_platform_admin()) then raise exception 'Not authorized';end if;
 select id into v_id from public.ice_sales where store_id=p_store_id and request_id=p_request_id;
 if found then return v_id;end if;
 if p_pack_kg is null or p_pack_kg not in(1,2,10,15) or p_packs is null or p_packs<1 or p_packs>1000000 then raise exception 'Invalid pack size or quantity';end if;
 if length(coalesce(p_delivered_by,''))>160 then raise exception 'Delivery name too long';end if;
 select * into v_customer from public.ice_customers where id=p_customer_id and store_id=p_store_id and active;
 if not found then raise exception 'Customer not found';end if;
 v_qty:=p_pack_kg::bigint*p_packs;
 if v_qty>100000000 then raise exception 'Too many kilograms';end if;
 v_total:=v_qty*v_customer.price_per_kg_cents;
 if p_cash_cents is null or p_cash_cents<v_total or p_cash_cents>100000000000 then raise exception 'Cash received is insufficient';end if;
 select packs into v_remaining from public.ice_pack_stock where store_id=p_store_id and pack_kg=p_pack_kg for update;
 if not found or v_remaining<p_packs then raise exception 'Insufficient packs for selected size';end if;
 insert into public.ice_sales(store_id,customer_id,customer_name,qty_centikg,price_per_kg_cents,total_cents,cash_cents,cashier_id,request_id,person_in_charge,delivered_by,pack_kg,pack_count)
 values(p_store_id,p_customer_id,v_customer.name,v_qty*100,v_customer.price_per_kg_cents,v_total,p_cash_cents,auth.uid(),p_request_id,'',btrim(coalesce(p_delivered_by,'')),p_pack_kg,p_packs) returning id into v_id;
 update public.ice_pack_stock set packs=packs-p_packs,updated_at=now() where store_id=p_store_id and pack_kg=p_pack_kg;
 insert into public.ice_pack_movements(store_id,pack_kg,delta_packs,reason,sale_id,actor_id) values(p_store_id,p_pack_kg,-p_packs,'sale',v_id,auth.uid());
 return v_id;
exception when unique_violation then
 select id into v_id from public.ice_sales where store_id=p_store_id and request_id=p_request_id;
 if found then return v_id;end if;
 raise;
end $$;
-- Delivery editing needs only the delivered-by field, and remains scoped to the sale's store.
create or replace function public.ice_update_delivery(p_store_id uuid,p_sale_id uuid,p_delivered_by text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not (public.has_store_role(p_store_id,array['owner','manager']) or public.is_platform_admin()) then raise exception 'Not authorized';end if;
 if length(coalesce(p_delivered_by,''))>160 then raise exception 'Delivery name too long';end if;
 update public.ice_sales set delivered_by=btrim(coalesce(p_delivered_by,'')) where id=p_sale_id and store_id=p_store_id;
 if not found then raise exception 'Sale not found';end if;
end $$;
drop function if exists public.ice_update_delivery(uuid,uuid,text,text);
revoke all on function public.ice_add_packs(uuid,integer,integer) from public,anon;
revoke all on function public.ice_checkout_packs(uuid,uuid,integer,integer,bigint,uuid,text) from public,anon;
revoke all on function public.ice_update_delivery(uuid,uuid,text) from public,anon;
grant execute on function public.ice_add_packs(uuid,integer,integer),public.ice_checkout_packs(uuid,uuid,integer,integer,bigint,uuid,text),public.ice_update_delivery(uuid,uuid,text) to authenticated;
-- Block old kg-based writes after migration to avoid two independent stock balances.
revoke execute on function public.ice_checkout(uuid,uuid,integer,bigint,uuid,text,text),public.ice_restock(uuid,bigint) from authenticated;