-- SQL command to create refund_receipt bucket and policies in Supabase
-- Run this in the Supabase SQL Editor
-- This creates the bucket and sets up public access policies for unauthenticated users

-- Create the refund_receipt bucket if it doesn't exist
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'refund_receipt',
    'refund_receipt',
    true, -- Public bucket
    52428800, -- 50MB file size limit
    ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- Policy: Allow public SELECT (view) access
DROP POLICY IF EXISTS "Public can view refund receipts" ON storage.objects;
CREATE POLICY "Public can view refund receipts"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'refund_receipt');

-- Policy: Allow public INSERT (upload) access
DROP POLICY IF EXISTS "Public can upload refund receipts" ON storage.objects;
CREATE POLICY "Public can upload refund receipts"
ON storage.objects
FOR INSERT
TO public
WITH CHECK (bucket_id = 'refund_receipt');

-- Policy: Allow public UPDATE access
DROP POLICY IF EXISTS "Public can update refund receipts" ON storage.objects;
CREATE POLICY "Public can update refund receipts"
ON storage.objects
FOR UPDATE
TO public
USING (bucket_id = 'refund_receipt')
WITH CHECK (bucket_id = 'refund_receipt');

-- Policy: Allow public DELETE access
DROP POLICY IF EXISTS "Public can delete refund receipts" ON storage.objects;
CREATE POLICY "Public can delete refund receipts"
ON storage.objects
FOR DELETE
TO public
USING (bucket_id = 'refund_receipt');

-- Verify bucket was created
SELECT id, name, public, created_at 
FROM storage.buckets 
WHERE id = 'refund_receipt';

