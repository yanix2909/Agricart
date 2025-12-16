-- ============================================================================
-- Supabase Storage Policies for gcash_receipt bucket
-- Run this SQL in your Supabase SQL Editor
-- ============================================================================

-- First, ensure the bucket exists (create it in Supabase Dashboard if it doesn't)
-- Storage > Buckets > Create bucket: gcash_receipt (make it public)

-- Enable RLS (Row Level Security) on the bucket
-- This is done via the Supabase Dashboard: Storage > Policies

-- Drop existing policies if they exist (to avoid conflicts)
DROP POLICY IF EXISTS "Allow public view of gcash receipts" ON storage.objects;
DROP POLICY IF EXISTS "Allow public insert of gcash receipts" ON storage.objects;
DROP POLICY IF EXISTS "Allow public update of gcash receipts" ON storage.objects;
DROP POLICY IF EXISTS "Allow public delete of gcash receipts" ON storage.objects;

-- Policy: Allow public (unauthenticated) users to view/download GCash receipts
-- This allows anyone (even without authentication) to view images
CREATE POLICY "Allow public view of gcash receipts"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'gcash_receipt');

-- Policy: Allow public (unauthenticated) users to insert/upload GCash receipts
-- This allows anyone (even without authentication) to upload images
CREATE POLICY "Allow public insert of gcash receipts"
ON storage.objects FOR INSERT
TO public
WITH CHECK (bucket_id = 'gcash_receipt');

-- Policy: Allow public (unauthenticated) users to update GCash receipts
-- This allows anyone (even without authentication) to update images
CREATE POLICY "Allow public update of gcash receipts"
ON storage.objects FOR UPDATE
TO public
USING (bucket_id = 'gcash_receipt')
WITH CHECK (bucket_id = 'gcash_receipt');

-- Policy: Allow public (unauthenticated) users to delete GCash receipts
-- This allows anyone (even without authentication) to delete images
CREATE POLICY "Allow public delete of gcash receipts"
ON storage.objects FOR DELETE
TO public
USING (bucket_id = 'gcash_receipt');

-- Note: The above policies allow public (not authenticated) access to:
-- - View/Download GCash receipts (SELECT)
-- - Upload GCash receipts (INSERT)
-- - Update GCash receipts (UPDATE)
-- - Delete GCash receipts (DELETE)

-- If you want to restrict certain operations, you can modify or remove the respective policies.

