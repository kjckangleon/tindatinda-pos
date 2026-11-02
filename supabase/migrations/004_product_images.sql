-- Run once in Supabase SQL Editor to enable compressed product photos.
alter table public.products add column if not exists image_path text;
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('product-images','product-images',true,262144,array['image/webp'])
on conflict (id) do update set public=true,file_size_limit=262144,allowed_mime_types=array['image/webp'];
-- Path convention: <store UUID>/<random UUID>.webp.
create policy "Read product photos" on storage.objects for select to public
using (bucket_id='product-images');
create policy "Store managers upload product photos" on storage.objects for insert to authenticated
with check (
 bucket_id='product-images'
 and (storage.foldername(name))[1] is not null
 and (public.is_platform_admin() or public.has_store_role(((storage.foldername(name))[1])::uuid,array['owner','manager']))
);
create policy "Store managers remove product photos" on storage.objects for delete to authenticated
using (
 bucket_id='product-images'
 and (storage.foldername(name))[1] is not null
 and public.has_store_role(((storage.foldername(name))[1])::uuid,array['owner','manager'])
);
