-- Supabase Storage Policies for customerid_image bucket
-- Run this SQL in your Supabase SQL Editor

-- First, ensure the bucket exists (create it in Supabase Dashboard if it doesn't)
-- Storage > Buckets > Create bucket: customerid_image (make it public)

-- Enable RLS (Row Level Security) on the bucket
-- This is done via the Supabase Dashboard: Storage > Policies

-- Policy: Allow public (unauthenticated) users to view/download images
-- This allows anyone (even without authentication) to view images
CREATE POLICY "Allow public view of customer ID images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'customerid_image');

-- Policy: Allow public (unauthenticated) users to insert/upload images
-- This allows anyone (even without authentication) to upload images
CREATE POLICY "Allow public insert of customer ID images"
ON storage.objects FOR INSERT
TO public
WITH CHECK (bucket_id = 'customerid_image');

-- Policy: Allow public (unauthenticated) users to update images
-- This allows anyone (even without authentication) to update images
CREATE POLICY "Allow public update of customer ID images"
ON storage.objects FOR UPDATE
TO public
USING (bucket_id = 'customerid_image')
WITH CHECK (bucket_id = 'customerid_image');

-- Policy: Allow public (unauthenticated) users to delete images
-- This allows anyone (even without authentication) to delete images
CREATE POLICY "Allow public delete of customer ID images"
ON storage.objects FOR DELETE
TO public
USING (bucket_id = 'customerid_image');

-- Alternative: If you want to allow all operations without authentication:
-- You can also set the bucket to be public in the Supabase Dashboard
-- Storage > Buckets > customerid_image > Settings > Make Public

-- Note: The above policies allow public (not authenticated) access to:
-- - View/Download images (SELECT)
-- - Upload images (INSERT)
-- - Update images (UPDATE)
-- - Delete images (DELETE)

-- If you want to restrict certain operations, you can modify or remove the respective policies.

-- ============================================================================
-- NOTE: GCash Receipt Policies
-- ============================================================================
-- The policies for the gcash_receipt bucket are in a separate file:
-- See: gcash_receipt_policies.sql
-- Run that file separately to avoid conflicts with existing policies.

