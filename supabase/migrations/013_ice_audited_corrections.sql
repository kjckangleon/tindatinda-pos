-- Audited corrections for Ice temples only. Never hard-delete financial transactions.
alter table public.ice_sales add column if not exists voided_at timestamptz;
alter table public.ice_sales add column if not exists voided_by uuid references auth.users(id);
alter table public.ice_sales add column if not exists void_reason text;
alter table public.ice_pack_movements drop constraint if exists ice_pack_movements_reason_check;
alter table public.ice_pack_movements add constraint ice_pack_movements_reason_check check(reason in ('production','sale','adjustment','sale_correction','sale_void'));
create table if not exists public.ice_correction_audit(
 id uuid primary key default gen_random_uuid(),store_id uuid not null references public.stores(id),
 sale_id uuid references public.ice_sales(id),action text not null check(action in ('stock_adjustment','sale_edit','sale_void')),
 old_data jsonb,new_data jsonb,reason text not null check(length(btrim(reason)) between 3 and 500),
 actor_id uuid references auth.users(id),created_at timestamptz not null default now()
);
alter table public.ice_correction_audit enable row level security;
create policy ice_correction_audit_read on public.ice_correction_audit for select to authenticated using(public.has_store_role(store_id,array['owner','manager']) or public.is_platform_admin());
grant select on public.ice_correction_audit to authenticated;
create or replace function public.ice_set_pack_stock(p_store_id uuid,p_pack_kg integer,p_new_packs bigint,p_reason text)
returns void language plpgsql security definer set search_path='' as $$
declare v_old bigint;v_delta bigint;
begin
 if p_store_id<>'a1a7c4d4-77b9-4173-84f2-98211b9f289a'::uuid or not (public.has_store_role(p_store_id,array['owner','manager']) or public.is_platform_admin()) then raise exception 'Not authorized';end if;
 if p_pack_kg not in (1,2,10,15) or p_new_packs is null or p_new_packs<0 or p_new_packs>100000000 then raise exception 'Invalid stock quantity';end if;
 if length(btrim(coalesce(p_reason,''))) not between 3 and 500 then raise exception 'Reason required (3–500 characters)';end if;
 insert into public.ice_pack_stock(store_id,pack_kg,packs) values(p_store_id,p_pack_kg,0) on conflict do nothing;
 select packs into v_old from public.ice_pack_stock where store_id=p_store_id and pack_kg=p_pack_kg for update;
 v_delta:=p_new_packs-v_old;
 if v_delta=0 then return;end if;
 update public.ice_pack_stock set packs=p_new_packs,updated_at=now() where store_id=p_store_id and pack_kg=p_pack_kg;
 insert into public.ice_pack_movements(store_id,pack_kg,delta_packs,reason,actor_id) values(p_store_id,p_pack_kg,v_delta,'adjustment',auth.uid());
 insert into public.ice_correction_audit(store_id,action,old_data,new_data,reason,actor_id) values(p_store_id,'stock_adjustment',jsonb_build_object('pack_kg',p_pack_kg,'packs',v_old),jsonb_build_object('pack_kg',p_pack_kg,'packs',p_new_packs),btrim(p_reason),auth.uid());
end $$;
create or replace function public.ice_correct_sale(p_store_id uuid,p_sale_id uuid,p_pack_kg integer,p_pack_count integer,p_cash_cents bigint,p_delivered_by text,p_reason text)
returns void language plpgsql security definer set search_path='' as $$
declare v_sale public.ice_sales%rowtype;v_stock bigint;v_total bigint;v_qty bigint;v_old jsonb;
begin
 if p_store_id<>'a1a7c4d4-77b9-4173-84f2-98211b9f289a'::uuid or not (public.has_store_role(p_store_id,array['owner','manager']) or public.is_platform_admin()) then raise exception 'Not authorized';end if;
 if length(btrim(coalesce(p_reason,''))) not between 3 and 500 then raise exception 'Reason required (3–500 characters)';end if;
 if p_pack_kg not in (1,2,10,15) or p_pack_count is null or p_pack_count<1 or p_pack_count>1000000 then raise exception 'Invalid pack quantity';end if;
 if length(coalesce(p_delivered_by,''))>160 then raise exception 'Delivery name too long';end if;
 select * into v_sale from public.ice_sales where id=p_sale_id and store_id=p_store_id for update;
 if not found or v_sale.voided_at is not null then raise exception 'Sale missing or voided';end if;
 if v_sale.pack_kg is null then raise exception 'Legacy kg sale cannot be edited with pack quantities';end if;
 v_qty:=p_pack_kg::bigint*p_pack_count;
 if v_qty>100000000 then raise exception 'Too many kilograms';end if;
 v_total:=v_qty*v_sale.price_per_kg_cents;
 if p_cash_cents is null or p_cash_cents<v_total or p_cash_cents>100000000000 then raise exception 'Cash received is insufficient';end if;
 v_old:=to_jsonb(v_sale);
 -- Lock stock rows in consistent size order to prevent concurrent sale/adjustment races.
 insert into public.ice_pack_stock(store_id,pack_kg,packs) values(p_store_id,p_pack_kg,0) on conflict do nothing;
 perform 1 from public.ice_pack_stock where store_id=p_store_id and pack_kg in(v_sale.pack_kg,p_pack_kg) order by pack_kg for update;
 select packs into v_stock from public.ice_pack_stock where store_id=p_store_id and pack_kg=p_pack_kg;
 if v_stock+(case when p_pack_kg=v_sale.pack_kg then v_sale.pack_count else 0 end)<p_pack_count then raise exception 'Insufficient packs for corrected sale';end if;
 update public.ice_pack_stock set packs=packs+v_sale.pack_count,updated_at=now() where store_id=p_store_id and pack_kg=v_sale.pack_kg;
 update public.ice_pack_stock set packs=packs-p_pack_count,updated_at=now() where store_id=p_store_id and pack_kg=p_pack_kg;
 insert into public.ice_pack_movements(store_id,pack_kg,delta_packs,reason,sale_id,actor_id) values(p_store_id,v_sale.pack_kg,v_sale.pack_count,'sale_correction',p_sale_id,auth.uid()),(p_store_id,p_pack_kg,-p_pack_count,'sale_correction',p_sale_id,auth.uid());
 update public.ice_sales set pack_kg=p_pack_kg,pack_count=p_pack_count,qty_centikg=v_qty*100,total_cents=v_total,cash_cents=p_cash_cents,delivered_by=btrim(coalesce(p_delivered_by,'')) where id=p_sale_id;
 insert into public.ice_correction_audit(store_id,sale_id,action,old_data,new_data,reason,actor_id) select p_store_id,p_sale_id,'sale_edit',v_old,to_jsonb(s),btrim(p_reason),auth.uid() from public.ice_sales s where s.id=p_sale_id;
end $$;
create or replace function public.ice_void_sale(p_store_id uuid,p_sale_id uuid,p_reason text)
returns void language plpgsql security definer set search_path='' as $$
declare v_sale public.ice_sales%rowtype;
begin
 if p_store_id<>'a1a7c4d4-77b9-4173-84f2-98211b9f289a'::uuid or not (public.has_store_role(p_store_id,array['owner','manager']) or public.is_platform_admin()) then raise exception 'Not authorized';end if;
 if length(btrim(coalesce(p_reason,''))) not between 3 and 500 then raise exception 'Reason required (3–500 characters)';end if;
 select * into v_sale from public.ice_sales where id=p_sale_id and store_id=p_store_id for update;
 if not found or v_sale.voided_at is not null then raise exception 'Sale missing or already voided';end if;
 if v_sale.pack_kg is not null then
  insert into public.ice_pack_stock(store_id,pack_kg,packs) values(p_store_id,v_sale.pack_kg,0) on conflict do nothing;
  update public.ice_pack_stock set packs=packs+v_sale.pack_count,updated_at=now() where store_id=p_store_id and pack_kg=v_sale.pack_kg;
  insert into public.ice_pack_movements(store_id,pack_kg,delta_packs,reason,sale_id,actor_id) values(p_store_id,v_sale.pack_kg,v_sale.pack_count,'sale_void',p_sale_id,auth.uid());
 end if;
 update public.ice_sales set voided_at=now(),voided_by=auth.uid(),void_reason=btrim(p_reason) where id=p_sale_id;
 insert into public.ice_correction_audit(store_id,sale_id,action,old_data,new_data,reason,actor_id) select p_store_id,p_sale_id,'sale_void',to_jsonb(v_sale),to_jsonb(s),btrim(p_reason),auth.uid() from public.ice_sales s where s.id=p_sale_id;
end $$;
revoke all on function public.ice_set_pack_stock(uuid,integer,bigint,text),public.ice_correct_sale(uuid,uuid,integer,integer,bigint,text,text),public.ice_void_sale(uuid,uuid,text) from public,anon;
grant execute on function public.ice_set_pack_stock(uuid,integer,bigint,text),public.ice_correct_sale(uuid,uuid,integer,integer,bigint,text,text),public.ice_void_sale(uuid,uuid,text) to authenticated;