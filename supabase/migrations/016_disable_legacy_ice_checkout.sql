-- Require explicit paid/unpaid status for new ice deliveries.
revoke execute on function public.ice_checkout_packs(uuid,uuid,integer,integer,bigint,uuid,text) from authenticated;
