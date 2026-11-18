-- Atomic edit of product fields, reorder threshold and stock movement.
create or replace function public.update_inventory_product_with_reorder(
 p_store_id uuid,p_product_id uuid,p_name text,p_barcode text,p_price_cents integer,
 p_stock_delta integer,p_reason text,p_reorder_level integer
) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or not public.has_store_role(p_store_id,array['owner','manager']) then raise exception 'Not authorized'; end if;
 if p_reorder_level is null or p_reorder_level not between 0 and 1000000 then raise exception 'Invalid reorder level'; end if;
 perform public.update_inventory_product(p_store_id,p_product_id,p_name,p_barcode,p_price_cents,p_stock_delta,p_reason);
 update public.products set reorder_level=p_reorder_level where id=p_product_id and store_id=p_store_id;
 if not found then raise exception 'Product not found'; end if;
end $$;
revoke all on function public.update_inventory_product_with_reorder(uuid,uuid,text,text,integer,integer,text,integer) from public,anon;
grant execute on function public.update_inventory_product_with_reorder(uuid,uuid,text,text,integer,integer,text,integer) to authenticated;
