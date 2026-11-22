-- Ice-only checkout is isolated to the Ice temples store; all weights are integer hundredths of kg.
create table if not exists public.ice_customers (
 id uuid primary key default gen_random_uuid(),
 store_id uuid not null references public.stores(id) on delete cascade,
 name text not null check(length(btrim(name)) between 1 and 160),
 price_per_kg_cents integer not null check(price_per_kg_cents>=0),
 active boolean not null default true,
 created_at timestamptz not null default now(),
 unique(store_id,name),
 unique(id,store_id)
);
create table if not exists public.ice_inventory (
 store_id uuid primary key references public.stores(id) on delete cascade,
 stock_centikg bigint not null default 0 check(stock_centikg>=0),
 updated_at timestamptz not null default now()
);
create table if not exists public.ice_sales (
 id uuid primary key default gen_random_uuid(),
 store_id uuid not null references public.stores(id),
 customer_id uuid not null,
 customer_name text not null,
 qty_centikg integer not null check(qty_centikg>0),
 price_per_kg_cents integer not null check(price_per_kg_cents>=0),
 total_cents bigint not null check(total_cents>=0),
 cash_cents bigint not null check(cash_cents>=total_cents),
 cashier_id uuid references auth.users(id),
 request_id uuid not null,
 created_at timestamptz not null default now(),
 foreign key(customer_id,store_id) references public.ice_customers(id,store_id),
 unique(store_id,request_id)
);
create table if not exists public.ice_inventory_movements (
 id uuid primary key default gen_random_uuid(),
 store_id uuid not null references public.stores(id),
 delta_centikg bigint not null check(delta_centikg<>0),
 reason text not null,
 actor_id uuid references auth.users(id),
 created_at timestamptz not null default now()
);
alter table public.ice_customers enable row level security;
alter table public.ice_inventory enable row level security;
alter table public.ice_sales enable row level security;
alter table public.ice_inventory_movements enable row level security;
create policy ice_customers_read on public.ice_customers for select to authenticated using(public.has_store_role(store_id,array['owner','manager','cashier']));
create policy ice_customers_write on public.ice_customers for all to authenticated using(public.has_store_role(store_id,array['owner','manager'])) with check(public.has_store_role(store_id,array['owner','manager']));
create policy ice_inventory_read on public.ice_inventory for select to authenticated using(public.has_store_role(store_id,array['owner','manager','cashier']));
create policy ice_sales_read on public.ice_sales for select to authenticated using(public.has_store_role(store_id,array['owner','manager','cashier']));
create policy ice_movements_read on public.ice_inventory_movements for select to authenticated using(public.has_store_role(store_id,array['owner','manager']));
grant select,insert,update on public.ice_customers to authenticated;
grant select on public.ice_inventory,public.ice_sales,public.ice_inventory_movements to authenticated;
create or replace function public.ice_checkout(p_store_id uuid,p_customer_id uuid,p_qty_centikg integer,p_cash_cents bigint,p_request_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_customer public.ice_customers%rowtype;v_stock bigint;v_total bigint;v_id uuid;
begin
 if not public.has_store_role(p_store_id,array['owner','manager','cashier']) then raise exception 'Not authorized';end if;
 if p_store_id <> 'a1a7c4d4-77b9-4173-84f2-98211b9f289a'::uuid then raise exception 'Ice checkout unavailable for this store';end if;
 select id into v_id from public.ice_sales where store_id=p_store_id and request_id=p_request_id;
 if found then return v_id;end if;
 if p_qty_centikg is null or p_qty_centikg<1 or p_qty_centikg>100000000 then raise exception 'Invalid kilograms';end if;
 select * into v_customer from public.ice_customers where id=p_customer_id and store_id=p_store_id and active;
 if not found then raise exception 'Customer not found';end if;
 v_total:=(p_qty_centikg::bigint*v_customer.price_per_kg_cents+50)/100;
 if p_cash_cents is null or p_cash_cents<v_total or p_cash_cents>100000000000 then raise exception 'Cash received is insufficient';end if;
 select stock_centikg into v_stock from public.ice_inventory where store_id=p_store_id for update;
 if not found or v_stock<p_qty_centikg then raise exception 'Insufficient ice inventory';end if;
 insert into public.ice_sales(store_id,customer_id,customer_name,qty_centikg,price_per_kg_cents,total_cents,cash_cents,cashier_id,request_id)
 values(p_store_id,p_customer_id,v_customer.name,p_qty_centikg,v_customer.price_per_kg_cents,v_total,p_cash_cents,auth.uid(),p_request_id) returning id into v_id;
 update public.ice_inventory set stock_centikg=stock_centikg-p_qty_centikg,updated_at=now() where store_id=p_store_id;
 insert into public.ice_inventory_movements(store_id,delta_centikg,reason,actor_id) values(p_store_id,-p_qty_centikg,'sale',auth.uid());
 return v_id;
exception when unique_violation then
 select id into v_id from public.ice_sales where store_id=p_store_id and request_id=p_request_id;
 if found then return v_id;end if;
 raise;
end $$;
create or replace function public.ice_restock(p_store_id uuid,p_qty_centikg bigint)
returns bigint language plpgsql security definer set search_path='' as $$
declare v_stock bigint;
begin
 if not public.has_store_role(p_store_id,array['owner','manager']) then raise exception 'Not authorized';end if;
 if p_store_id <> 'a1a7c4d4-77b9-4173-84f2-98211b9f289a'::uuid then raise exception 'Ice inventory unavailable';end if;
 if p_qty_centikg is null or p_qty_centikg<1 or p_qty_centikg>100000000 then raise exception 'Invalid restock quantity';end if;
 insert into public.ice_inventory(store_id,stock_centikg) values(p_store_id,p_qty_centikg)
 on conflict(store_id) do update set stock_centikg=public.ice_inventory.stock_centikg+excluded.stock_centikg,updated_at=now()
 returning stock_centikg into v_stock;
 insert into public.ice_inventory_movements(store_id,delta_centikg,reason,actor_id) values(p_store_id,p_qty_centikg,'restock',auth.uid());
 return v_stock;
end $$;
revoke all on function public.ice_checkout(uuid,uuid,integer,bigint,uuid) from public,anon;
revoke all on function public.ice_restock(uuid,bigint) from public,anon;
grant execute on function public.ice_checkout(uuid,uuid,integer,bigint,uuid) to authenticated;
grant execute on function public.ice_restock(uuid,bigint) to authenticated;