-- Create storage policies for featured_display bucket
-- This bucket stores featured images and videos for the customer dashboard carousel
-- Bucket name: featured_display

-- Policy: Allow public (unauthenticated) SELECT (view/download)
CREATE POLICY "Allow public read access to featured_display"
ON storage.objects FOR SELECT
USING (bucket_id = 'featured_display');

-- Policy: Allow public (unauthenticated) INSERT (upload)
CREATE POLICY "Allow public insert access to featured_display"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'featured_display');

-- Policy: Allow public (unauthenticated) UPDATE
CREATE POLICY "Allow public update access to featured_display"
ON storage.objects FOR UPDATE
USING (bucket_id = 'featured_display')
WITH CHECK (bucket_id = 'featured_display');

-- Policy: Allow public (unauthenticated) DELETE
CREATE POLICY "Allow public delete access to featured_display"
ON storage.objects FOR DELETE
USING (bucket_id = 'featured_display');

-- Note: Make sure the bucket is created as PUBLIC in Supabase Dashboard
-- Storage > Buckets > Create new bucket > Name: featured_display > Public bucket: ON

