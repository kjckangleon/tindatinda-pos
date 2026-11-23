-- A removed sale is a returned/cancelled sale; preserve its audit trail and record an assumed refund.
create table public.ice_sale_refunds (
 id uuid primary key default gen_random_uuid(),
 store_id uuid not null references public.stores(id),
 sale_id uuid not null unique references public.ice_sales(id),
 amount_cents bigint not null check(amount_cents>0),
 actor_id uuid references auth.users(id),
 reason text not null,
 created_at timestamptz not null default now()
);
alter table public.ice_sale_refunds enable row level security;
create policy ice_sale_refunds_read on public.ice_sale_refunds for select to authenticated using(public.has_store_role(store_id,array['owner','manager']) or public.is_platform_admin());
grant select on public.ice_sale_refunds to authenticated;
create or replace function public.ice_guard_receivable_changes() returns trigger language plpgsql set search_path='' as $$
begin
 if old.paid_cents>0 and new.total_cents is distinct from old.total_cents then
  raise exception 'Cannot change amount of a sale with payments';
 end if;
 if old.paid_cents>0 and new.voided_at is distinct from old.voided_at then
  if new.voided_at is null or new.voided_by is null or not exists
   (select 1 from public.ice_sale_refunds r where r.sale_id=old.id and r.store_id=old.store_id and r.amount_cents=old.paid_cents)
  then raise exception 'Paid sale removal requires a matching refund audit';end if;
 end if;
 return new;
end $$;
create or replace function public.ice_void_sale(p_store_id uuid,p_sale_id uuid,p_reason text)
returns void language plpgsql security definer set search_path='' as $$
declare v_sale public.ice_sales%rowtype;
begin
 if p_store_id<>'a1a7c4d4-77b9-4173-84f2-98211b9f289a'::uuid or not (public.has_store_role(p_store_id,array['owner','manager']) or public.is_platform_admin()) then raise exception 'Not authorized';end if;
 if length(btrim(coalesce(p_reason,''))) not between 3 and 500 then raise exception 'Reason required (3–500 characters)';end if;
 select * into v_sale from public.ice_sales where id=p_sale_id and store_id=p_store_id for update;
 if not found or v_sale.voided_at is not null then raise exception 'Sale missing or already voided';end if;
 if v_sale.paid_cents>0 then
  insert into public.ice_sale_refunds(store_id,sale_id,amount_cents,actor_id,reason) values(p_store_id,p_sale_id,v_sale.paid_cents,auth.uid(),btrim(p_reason));
 end if;
 if v_sale.pack_kg is not null then
  insert into public.ice_pack_stock(store_id,pack_kg,packs) values(p_store_id,v_sale.pack_kg,0) on conflict do nothing;
  update public.ice_pack_stock set packs=packs+v_sale.pack_count,updated_at=now() where store_id=p_store_id and pack_kg=v_sale.pack_kg;
  insert into public.ice_pack_movements(store_id,pack_kg,delta_packs,reason,sale_id,actor_id) values(p_store_id,v_sale.pack_kg,v_sale.pack_count,'sale_void',p_sale_id,auth.uid());
 end if;
 update public.ice_sales set voided_at=now(),voided_by=auth.uid(),void_reason=btrim(p_reason) where id=p_sale_id;
 insert into public.ice_correction_audit(store_id,sale_id,action,old_data,new_data,reason,actor_id) select p_store_id,p_sale_id,'sale_void',to_jsonb(v_sale),to_jsonb(s),btrim(p_reason),auth.uid() from public.ice_sales s where s.id=p_sale_id;
end $$;

revoke all on function public.ice_void_sale(uuid,uuid,text) from public,anon;
grant execute on function public.ice_void_sale(uuid,uuid,text) to authenticated;
