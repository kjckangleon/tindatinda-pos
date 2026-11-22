create table if not exists public.ice_expenses (
 id uuid primary key default gen_random_uuid(),
 store_id uuid not null references public.stores(id),
 expense_date date not null,
 details text not null check (char_length(btrim(details)) between 1 and 500),
 amount_cents bigint not null check (amount_cents > 0 and amount_cents <= 100000000000),
 created_by uuid not null default auth.uid() references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint ice_expenses_store_scope check (store_id = 'a1a7c4d4-77b9-4173-84f2-98211b9f289a'::uuid)
);
create index if not exists ice_expenses_store_date_idx on public.ice_expenses(store_id,expense_date desc);
alter table public.ice_expenses enable row level security;
create policy "ice expenses read members" on public.ice_expenses for select to authenticated using (public.has_store_role(store_id,array['owner','manager','cashier']) or public.is_platform_admin());
create policy "ice expenses insert managers" on public.ice_expenses for insert to authenticated with check ((public.has_store_role(store_id,array['owner','manager']) or public.is_platform_admin()) and created_by=auth.uid());
create policy "ice expenses update managers" on public.ice_expenses for update to authenticated using (public.has_store_role(store_id,array['owner','manager']) or public.is_platform_admin()) with check (public.has_store_role(store_id,array['owner','manager']) or public.is_platform_admin());
create policy "ice expenses delete managers" on public.ice_expenses for delete to authenticated using (public.has_store_role(store_id,array['owner','manager']) or public.is_platform_admin());
grant select,insert,update,delete on public.ice_expenses to authenticated;