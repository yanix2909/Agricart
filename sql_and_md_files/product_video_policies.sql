-- ============================================================================
-- Supabase Storage Policies for product_video bucket
-- Run this SQL in your Supabase SQL Editor
-- ============================================================================

-- First, ensure the bucket exists (create it in Supabase Dashboard if it doesn't)
-- Storage > Buckets > Create bucket: product_video (make it public)
-- 
-- Steps to create the bucket:
-- 1. Go to Supabase Dashboard > Storage
-- 2. Click "New Bucket"
-- 3. Name: product_video
-- 4. Make it Public (uncheck "Private bucket")
-- 5. Click "Create bucket"

-- Enable RLS (Row Level Security) on the bucket
-- This is done via the Supabase Dashboard: Storage > Policies
-- Or the policies below will work if RLS is enabled

-- Drop existing policies if they exist (to avoid conflicts)
DROP POLICY IF EXISTS "Allow public view of product videos" ON storage.objects;
DROP POLICY IF EXISTS "Allow public insert of product videos" ON storage.objects;
DROP POLICY IF EXISTS "Allow public update of product videos" ON storage.objects;
DROP POLICY IF EXISTS "Allow public delete of product videos" ON storage.objects;

-- Policy: Allow public (unauthenticated) users to view/download videos
-- This allows anyone (even without authentication) to view videos
-- Customers need this to view product videos in the app
CREATE POLICY "Allow public view of product videos"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'product_video');

-- Policy: Allow public (unauthenticated) users to insert/upload videos
-- This allows staff/admin to upload videos from the dashboard
-- Note: In production, you might want to restrict this to authenticated users only
CREATE POLICY "Allow public insert of product videos"
ON storage.objects FOR INSERT
TO public
WITH CHECK (bucket_id = 'product_video');

-- Policy: Allow public (unauthenticated) users to update videos
-- This allows staff/admin to update/replace videos
-- Note: In production, you might want to restrict this to authenticated users only
CREATE POLICY "Allow public update of product videos"
ON storage.objects FOR UPDATE
TO public
USING (bucket_id = 'product_video')
WITH CHECK (bucket_id = 'product_video');

-- Policy: Allow public (unauthenticated) users to delete videos
-- This allows staff/admin to delete videos
-- Note: In production, you might want to restrict this to authenticated users only
CREATE POLICY "Allow public delete of product videos"
ON storage.objects FOR DELETE
TO public
USING (bucket_id = 'product_video');

-- ============================================================================
-- Alternative: More Secure Policies (Authenticated Users Only)
-- ============================================================================
-- If you want to restrict upload/update/delete to authenticated users only,
-- use these policies instead (comment out the public policies above):

/*
-- Policy: Allow public (unauthenticated) users to view/download videos
CREATE POLICY "Allow public view of product videos"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'product_video');

-- Policy: Allow authenticated users to insert/upload videos
CREATE POLICY "Allow authenticated insert of product videos"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (bucket_id = 'product_video');

-- Policy: Allow authenticated users to update videos
CREATE POLICY "Allow authenticated update of product videos"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'product_video')
WITH CHECK (bucket_id = 'product_video');

-- Policy: Allow authenticated users to delete videos
CREATE POLICY "Allow authenticated delete of product videos"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'product_video');
*/

-- ============================================================================
-- Notes:
-- ============================================================================
-- The above policies allow public (not authenticated) access to:
-- - View/Download videos (SELECT) - Required for customers to view product videos
-- - Upload videos (INSERT) - Required for staff to upload videos
-- - Update videos (UPDATE) - Required for staff to update videos
-- - Delete videos (DELETE) - Required for staff to delete videos
--
-- If you want to restrict certain operations, you can:
-- 1. Use the alternative policies above (authenticated users only for write operations)
-- 2. Modify the policies to add additional conditions
-- 3. Remove policies you don't need
--
-- The bucket should be set to "Public" in Supabase Dashboard for public read access
-- Storage > Buckets > product_video > Settings > Make Public
--
-- Video files are stored with the following structure:
-- product_video/{productId}/{productId}_video_{index}_{timestamp}.{ext}
-- Example: product_video/product_1234567890_abc/product_1234567890_abc_video_0_1234567890.mp4

