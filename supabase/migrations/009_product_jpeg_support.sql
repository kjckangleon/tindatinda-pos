-- Preserve existing WebP photos while allowing iOS-compatible compressed JPEG uploads.
update storage.buckets
set allowed_mime_types = array['image/jpeg','image/webp'], file_size_limit = 262144
where id = 'product-images';
