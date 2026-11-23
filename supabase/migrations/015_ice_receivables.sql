-- Ice temples receivables: old sales are treated as settled; no historical amounts changed.
alter table public.ice_sales add column if not exists paid_cents bigint;
update public.ice_sales set paid_cents=total_cents where paid_cents is null;
alter table public.ice_sales alter column paid_cents set default 0;
alter table public.ice_sales alter column paid_cents set not null;
alter table public.ice_sales add constraint ice_paid_bounds check(paid_cents>=0 and paid_cents<=total_cents);
alter table public.ice_sales drop constraint if exists ice_sales_cash_cents_check;
-- Existing cash constraint name can vary: drop every check involving cash_cents and total_cents.
do $$declare c record;begin for c in select conname from pg_constraint where conrelid='public.ice_sales'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%cash_cents%' loop execute format('alter table public.ice_sales drop constraint %I',c.conname);end loop;end $$;
alter table public.ice_sales add constraint ice_cash_nonnegative check(cash_cents>=0);

create table public.ice_sale_payments(
 id uuid primary key default gen_random_uuid(),
 store_id uuid not null references public.stores(id),
 sale_id uuid not null references public.ice_sales(id),
 amount_cents bigint not null check(amount_cents>0),
 recorded_by uuid references auth.users(id),
 paid_at timestamptz not null default now(),
 note text not null default '' check(length(note)<=500)
);
create index ice_sale_payments_sale_idx on public.ice_sale_payments(sale_id,paid_at);
alter table public.ice_sale_payments enable row level security;
create policy ice_sale_payments_read on public.ice_sale_payments for select to authenticated using (
 store_id='a1a7c4d4-77b9-4173-84f2-98211b9f289a'::uuid and
 (public.has_store_role(store_id,array['owner','manager','cashier']) or public.is_platform_admin()));
grant select on public.ice_sale_payments to authenticated;

create or replace function public.ice_checkout_packs_receivable(p_store_id uuid,p_customer_id uuid,p_pack_kg integer,p_packs integer,p_cash_cents bigint,p_request_id uuid,p_delivered_by text,p_paid boolean)
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
 if p_paid is null then raise exception 'Payment status required';end if;
 if p_paid and (p_cash_cents is null or p_cash_cents<v_total or p_cash_cents>100000000000) then raise exception 'Cash received is insufficient';end if;
 if not p_paid and coalesce(p_cash_cents,0)<>0 then raise exception 'Unpaid sale cannot receive cash at checkout';end if;
 select packs into v_remaining from public.ice_pack_stock where store_id=p_store_id and pack_kg=p_pack_kg for update;
 if not found or v_remaining<p_packs then raise exception 'Insufficient packs for selected size';end if;
 insert into public.ice_sales(store_id,customer_id,customer_name,qty_centikg,price_per_kg_cents,total_cents,cash_cents,cashier_id,request_id,person_in_charge,delivered_by,pack_kg,pack_count,paid_cents)
 values(p_store_id,p_customer_id,v_customer.name,v_qty*100,v_customer.price_per_kg_cents,v_total,p_cash_cents,auth.uid(),p_request_id,'',btrim(coalesce(p_delivered_by,'')),p_pack_kg,p_packs,case when p_paid then v_total else 0 end) returning id into v_id;
 update public.ice_pack_stock set packs=packs-p_packs,updated_at=now() where store_id=p_store_id and pack_kg=p_pack_kg;
 insert into public.ice_pack_movements(store_id,pack_kg,delta_packs,reason,sale_id,actor_id) values(p_store_id,p_pack_kg,-p_packs,'sale',v_id,auth.uid());
 return v_id;
exception when unique_violation then
 select id into v_id from public.ice_sales where store_id=p_store_id and request_id=p_request_id;
 if found then return v_id;end if;
 raise;
end $$;

revoke all on function public.ice_checkout_packs_receivable(uuid,uuid,integer,integer,bigint,uuid,text,boolean) from public,anon;
grant execute on function public.ice_checkout_packs_receivable(uuid,uuid,integer,integer,bigint,uuid,text,boolean) to authenticated;

create or replace function public.ice_record_payment(p_store_id uuid,p_sale_id uuid,p_amount_cents bigint,p_note text default '')
returns bigint language plpgsql security definer set search_path='' as $$
declare v_sale public.ice_sales%rowtype;v_remaining bigint;
begin
 if p_store_id<>'a1a7c4d4-77b9-4173-84f2-98211b9f289a'::uuid or not (public.has_store_role(p_store_id,array['owner','manager']) or public.is_platform_admin()) then raise exception 'Not authorized';end if;
 if p_amount_cents is null or p_amount_cents<=0 or p_amount_cents>100000000000 then raise exception 'Invalid payment amount';end if;
 if length(coalesce(p_note,''))>500 then raise exception 'Note too long';end if;
 select * into v_sale from public.ice_sales where id=p_sale_id and store_id=p_store_id for update;
 if not found or v_sale.voided_at is not null then raise exception 'Sale missing or voided';end if;
 v_remaining:=v_sale.total_cents-v_sale.paid_cents;
 if p_amount_cents>v_remaining then raise exception 'Payment exceeds outstanding balance';end if;
 update public.ice_sales set paid_cents=paid_cents+p_amount_cents where id=p_sale_id;
 insert into public.ice_sale_payments(store_id,sale_id,amount_cents,recorded_by,note) values(p_store_id,p_sale_id,p_amount_cents,auth.uid(),btrim(coalesce(p_note,'')));
 return v_remaining-p_amount_cents;
end $$;
revoke all on function public.ice_record_payment(uuid,uuid,bigint,text) from public,anon;
grant execute on function public.ice_record_payment(uuid,uuid,bigint,text) to authenticated;

-- Prevent changing already-paid financial records without a dedicated refund/reconciliation workflow.
create or replace function public.ice_guard_receivable_changes() returns trigger language plpgsql set search_path='' as $$
begin
 if old.paid_cents>0 and (new.total_cents is distinct from old.total_cents or new.voided_at is distinct from old.voided_at) then
 raise exception 'Cannot change amount or void a sale with payments; reconcile payments first';
 end if;
 return new;
end $$;
create trigger ice_guard_receivable_changes before update on public.ice_sales
for each row execute function public.ice_guard_receivable_changes();
