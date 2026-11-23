-- Business sale date is separate from immutable entry timestamp.
alter table public.ice_sales add column if not exists sale_date date;
update public.ice_sales set sale_date=(created_at at time zone 'Asia/Manila')::date where sale_date is null;
alter table public.ice_sales alter column sale_date set default ((now() at time zone 'Asia/Manila')::date);
alter table public.ice_sales alter column sale_date set not null;
alter table public.ice_sales add constraint ice_sale_date_range check(sale_date between '2020-01-01'::date and '2100-12-31'::date);
create or replace function public.ice_checkout_packs_receivable(p_store_id uuid,p_customer_id uuid,p_pack_kg integer,p_packs integer,p_cash_cents bigint,p_request_id uuid,p_delivered_by text,p_paid boolean,p_sale_date date)
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
 if p_sale_date is null or p_sale_date<'2020-01-01'::date or p_sale_date>(now() at time zone 'Asia/Manila')::date then raise exception 'Invalid sale date';end if;
 if p_paid is null then raise exception 'Payment status required';end if;
 if p_paid and (p_cash_cents is null or p_cash_cents<v_total or p_cash_cents>100000000000) then raise exception 'Cash received is insufficient';end if;
 if not p_paid and coalesce(p_cash_cents,0)<>0 then raise exception 'Unpaid sale cannot receive cash at checkout';end if;
 select packs into v_remaining from public.ice_pack_stock where store_id=p_store_id and pack_kg=p_pack_kg for update;
 if not found or v_remaining<p_packs then raise exception 'Insufficient packs for selected size';end if;
 insert into public.ice_sales(store_id,customer_id,customer_name,qty_centikg,price_per_kg_cents,total_cents,cash_cents,cashier_id,request_id,person_in_charge,delivered_by,pack_kg,pack_count,paid_cents,sale_date)
 values(p_store_id,p_customer_id,v_customer.name,v_qty*100,v_customer.price_per_kg_cents,v_total,p_cash_cents,auth.uid(),p_request_id,'',btrim(coalesce(p_delivered_by,'')),p_pack_kg,p_packs,case when p_paid then v_total else 0 end,p_sale_date) returning id into v_id;
 update public.ice_pack_stock set packs=packs-p_packs,updated_at=now() where store_id=p_store_id and pack_kg=p_pack_kg;
 insert into public.ice_pack_movements(store_id,pack_kg,delta_packs,reason,sale_id,actor_id) values(p_store_id,p_pack_kg,-p_packs,'sale',v_id,auth.uid());
 return v_id;
exception when unique_violation then
 select id into v_id from public.ice_sales where store_id=p_store_id and request_id=p_request_id;
 if found then return v_id;end if;
 raise;
end $$;


revoke all on function public.ice_checkout_packs_receivable(uuid,uuid,integer,integer,bigint,uuid,text,boolean) from authenticated;
revoke all on function public.ice_checkout_packs_receivable(uuid,uuid,integer,integer,bigint,uuid,text,boolean,date) from public,anon;
grant execute on function public.ice_checkout_packs_receivable(uuid,uuid,integer,integer,bigint,uuid,text,boolean,date) to authenticated;

create or replace function public.ice_change_sale_date(p_store_id uuid,p_sale_id uuid,p_sale_date date,p_reason text)
returns void language plpgsql security definer set search_path='' as $$
declare v_sale public.ice_sales%rowtype;
begin
 if p_store_id<>'a1a7c4d4-77b9-4173-84f2-98211b9f289a'::uuid or not (public.has_store_role(p_store_id,array['owner','manager']) or public.is_platform_admin()) then raise exception 'Not authorized';end if;
 if p_sale_date is null or p_sale_date<'2020-01-01'::date or p_sale_date>(now() at time zone 'Asia/Manila')::date then raise exception 'Sale date must be between 2020 and today (Philippines)';end if;
 if length(btrim(coalesce(p_reason,''))) not between 3 and 500 then raise exception 'Reason required (3–500 characters)';end if;
 select * into v_sale from public.ice_sales where id=p_sale_id and store_id=p_store_id for update;
 if not found or v_sale.voided_at is not null then raise exception 'Sale missing or removed';end if;
 if v_sale.sale_date=p_sale_date then return;end if;
 update public.ice_sales set sale_date=p_sale_date where id=p_sale_id;
 insert into public.ice_correction_audit(store_id,sale_id,action,old_data,new_data,reason,actor_id)
 select p_store_id,p_sale_id,'sale_edit',to_jsonb(v_sale),to_jsonb(s),btrim(p_reason),auth.uid() from public.ice_sales s where s.id=p_sale_id;
end $$;
revoke all on function public.ice_change_sale_date(uuid,uuid,date,text) from public,anon;
grant execute on function public.ice_change_sale_date(uuid,uuid,date,text) to authenticated;
