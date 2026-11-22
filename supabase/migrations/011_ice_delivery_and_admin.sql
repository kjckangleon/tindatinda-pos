alter table public.ice_sales add column if not exists person_in_charge text not null default '';
alter table public.ice_sales add column if not exists delivered_by text not null default '';
alter table public.ice_sales add constraint ice_person_in_charge_length check(length(person_in_charge)<=160);
alter table public.ice_sales add constraint ice_delivered_by_length check(length(delivered_by)<=160);
create policy ice_admin_customers_read on public.ice_customers for select to authenticated using(public.is_platform_admin());
create policy ice_admin_customers_write on public.ice_customers for all to authenticated using(public.is_platform_admin()) with check(public.is_platform_admin());
create policy ice_admin_inventory_read on public.ice_inventory for select to authenticated using(public.is_platform_admin());
create policy ice_admin_sales_read on public.ice_sales for select to authenticated using(public.is_platform_admin());
create policy ice_admin_movements_read on public.ice_inventory_movements for select to authenticated using(public.is_platform_admin());
create or replace function public.ice_checkout(p_store_id uuid,p_customer_id uuid,p_qty_centikg integer,p_cash_cents bigint,p_request_id uuid,p_person_in_charge text default '',p_delivered_by text default '')
returns uuid language plpgsql security definer set search_path='' as $$
declare v_customer public.ice_customers%rowtype;v_stock bigint;v_total bigint;v_id uuid;
begin
 if not (public.has_store_role(p_store_id,array['owner','manager','cashier']) or public.is_platform_admin()) then raise exception 'Not authorized';end if;
 if p_store_id <> 'a1a7c4d4-77b9-4173-84f2-98211b9f289a'::uuid then raise exception 'Ice checkout unavailable for this store';end if;
 select id into v_id from public.ice_sales where store_id=p_store_id and request_id=p_request_id;
 if found then return v_id;end if;
 if p_qty_centikg is null or p_qty_centikg<1 or p_qty_centikg>100000000 then raise exception 'Invalid kilograms';end if;
 if length(coalesce(p_person_in_charge,''))>160 or length(coalesce(p_delivered_by,''))>160 then raise exception 'Staff name too long';end if;
 select * into v_customer from public.ice_customers where id=p_customer_id and store_id=p_store_id and active;
 if not found then raise exception 'Customer not found';end if;
 v_total:=(p_qty_centikg::bigint*v_customer.price_per_kg_cents+50)/100;
 if p_cash_cents is null or p_cash_cents<v_total or p_cash_cents>100000000000 then raise exception 'Cash received is insufficient';end if;
 select stock_centikg into v_stock from public.ice_inventory where store_id=p_store_id for update;
 if not found or v_stock<p_qty_centikg then raise exception 'Insufficient ice inventory';end if;
 insert into public.ice_sales(store_id,customer_id,customer_name,qty_centikg,price_per_kg_cents,total_cents,cash_cents,cashier_id,request_id,person_in_charge,delivered_by)
 values(p_store_id,p_customer_id,v_customer.name,p_qty_centikg,v_customer.price_per_kg_cents,v_total,p_cash_cents,auth.uid(),p_request_id,btrim(coalesce(p_person_in_charge,'')),btrim(coalesce(p_delivered_by,''))) returning id into v_id;
 update public.ice_inventory set stock_centikg=stock_centikg-p_qty_centikg,updated_at=now() where store_id=p_store_id;
 insert into public.ice_inventory_movements(store_id,delta_centikg,reason,actor_id) values(p_store_id,-p_qty_centikg,'sale',auth.uid());
 return v_id;
exception when unique_violation then
 select id into v_id from public.ice_sales where store_id=p_store_id and request_id=p_request_id;
 if found then return v_id;end if;
 raise;
end $$;
drop function public.ice_checkout(uuid,uuid,integer,bigint,uuid);
revoke all on function public.ice_checkout(uuid,uuid,integer,bigint,uuid,text,text) from public,anon;
grant execute on function public.ice_checkout(uuid,uuid,integer,bigint,uuid,text,text) to authenticated;
create or replace function public.ice_update_delivery(p_store_id uuid,p_sale_id uuid,p_person_in_charge text,p_delivered_by text)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not (public.has_store_role(p_store_id,array['owner','manager']) or public.is_platform_admin()) then raise exception 'Not authorized';end if;
 if length(coalesce(p_person_in_charge,''))>160 or length(coalesce(p_delivered_by,''))>160 then raise exception 'Staff name too long';end if;
 update public.ice_sales set person_in_charge=btrim(coalesce(p_person_in_charge,'')),delivered_by=btrim(coalesce(p_delivered_by,''))
 where id=p_sale_id and store_id=p_store_id;
 if not found then raise exception 'Sale not found';end if;
end $$;
revoke all on function public.ice_update_delivery(uuid,uuid,text,text) from public,anon;
grant execute on function public.ice_update_delivery(uuid,uuid,text,text) to authenticated;
create or replace function public.ice_restock(p_store_id uuid,p_qty_centikg bigint)
returns bigint language plpgsql security definer set search_path='' as $$
declare v_stock bigint;
begin
 if not (public.has_store_role(p_store_id,array['owner','manager']) or public.is_platform_admin()) then raise exception 'Not authorized';end if;
 if p_store_id <> 'a1a7c4d4-77b9-4173-84f2-98211b9f289a'::uuid then raise exception 'Ice inventory unavailable';end if;
 if p_qty_centikg is null or p_qty_centikg<1 or p_qty_centikg>100000000 then raise exception 'Invalid restock quantity';end if;
 insert into public.ice_inventory(store_id,stock_centikg) values(p_store_id,p_qty_centikg)
 on conflict(store_id) do update set stock_centikg=public.ice_inventory.stock_centikg+excluded.stock_centikg,updated_at=now()
 returning stock_centikg into v_stock;
 insert into public.ice_inventory_movements(store_id,delta_centikg,reason,actor_id) values(p_store_id,p_qty_centikg,'restock',auth.uid());
 return v_stock;
end $$;