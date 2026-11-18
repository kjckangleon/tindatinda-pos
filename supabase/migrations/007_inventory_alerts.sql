-- Sprint 1: per-product reorder thresholds. Existing inventory is preserved.
alter table public.products add column if not exists reorder_level integer not null default 5;
alter table public.products drop constraint if exists products_reorder_level_valid;
alter table public.products add constraint products_reorder_level_valid check (reorder_level between 0 and 1000000);
create index if not exists inventory_movements_store_recent_idx on public.inventory_movements(store_id,created_at desc);
-- Stock movement read access is restricted to owners/managers/platform admins by existing RLS.
