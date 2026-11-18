-- Atomic product editing and auditable stock adjustments.
-- Deploy to Supabase before using Inventory > Edit Product.
create or replace function public.update_inventory_product(
 p_store_id uuid, p_product_id uuid, p_name text, p_barcode text,
 p_price_cents integer, p_stock_delta integer, p_reason text
) returns void language plpgsql security definer set search_path = '' as $$
declare v_product public.products%rowtype;
begin
 if auth.uid() is null or not public.has_store_role(p_store_id,array['owner','manager']) then
  raise exception 'Not authorized';
 end if;
 if not exists(select 1 from public.stores where id=p_store_id and active) then
  raise exception 'Store inactive';
 end if;
 if p_name is null or length(trim(p_name)) not between 1 and 160 or p_price_cents is null or p_price_cents < 0 then
  raise exception 'Invalid product name or price';
 end if;
 if p_stock_delta is null or abs(p_stock_delta::bigint)>1000000 then
  raise exception 'Invalid stock adjustment';
 end if;
 if p_stock_delta<>0 and (p_reason is null or trim(p_reason) not in ('restock','damaged','correction','return')) then
  raise exception 'Choose a valid stock adjustment reason';
 end if;
 select * into v_product from public.products where id=p_product_id and store_id=p_store_id for update;
 if not found then raise exception 'Product not found in store'; end if;
 if v_product.stock::bigint+p_stock_delta<0 or v_product.stock::bigint+p_stock_delta>2147483647 then
  raise exception 'Stock adjustment would exceed valid stock range';
 end if;
 update public.products set name=trim(p_name),barcode=nullif(trim(p_barcode),''),price_cents=p_price_cents,
  stock=stock+p_stock_delta where id=p_product_id and store_id=p_store_id;
 if p_stock_delta<>0 then
  insert into public.inventory_movements(store_id,product_id,delta,reason,actor_id)
  values(p_store_id,p_product_id,p_stock_delta,trim(p_reason),auth.uid());
 end if;
end $$;
revoke all on function public.update_inventory_product(uuid,uuid,text,text,integer,integer,text) from public,anon;
grant execute on function public.update_inventory_product(uuid,uuid,text,text,integer,integer,text) to authenticated;
