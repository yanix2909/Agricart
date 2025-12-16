-- Supabase Storage Policies for customerconvo_uploads bucket
-- Run this SQL in your Supabase SQL Editor
--
-- First, ensure the bucket exists (create it in Supabase Dashboard if it doesn't)
-- Storage > Buckets > Create bucket: customerconvo_uploads (make it public)
--
-- Enable RLS (Row Level Security) on the bucket
-- This is done via the Supabase Dashboard: Storage > Policies

-- Policy: Allow public (unauthenticated) users to view/download media
-- This allows anyone (even without authentication) to view images and videos
CREATE POLICY "Allow public view of customer conversation uploads"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'customerconvo_uploads');

-- Policy: Allow public (unauthenticated) users to insert/upload media
-- This allows anyone (even without authentication) to upload images and videos
CREATE POLICY "Allow public insert of customer conversation uploads"
ON storage.objects FOR INSERT
TO public
WITH CHECK (bucket_id = 'customerconvo_uploads');

-- Policy: Allow public (unauthenticated) users to update media
-- This allows anyone (even without authentication) to update images and videos
CREATE POLICY "Allow public update of customer conversation uploads"
ON storage.objects FOR UPDATE
TO public
USING (bucket_id = 'customerconvo_uploads')
WITH CHECK (bucket_id = 'customerconvo_uploads');

-- Policy: Allow public (unauthenticated) users to delete media
-- This allows anyone (even without authentication) to delete images and videos
CREATE POLICY "Allow public delete of customer conversation uploads"
ON storage.objects FOR DELETE
TO public
USING (bucket_id = 'customerconvo_uploads');

-- Alternative: If you want to allow all operations without authentication:
-- You can also set the bucket to be public in the Supabase Dashboard
-- Storage > Buckets > customerconvo_uploads > Settings > Make Public

-- Note: The above policies allow public (not authenticated) access to:
-- - View/Download media (SELECT)
-- - Upload media (INSERT)
-- - Update media (UPDATE)
-- - Delete media (DELETE)

-- If you want to restrict certain operations, you can modify or remove the respective policies.

