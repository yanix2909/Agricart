-- ============================================================================
-- SQL Commands for Delivery Proof Storage Bucket
-- ============================================================================
-- This script creates the delivery_proof storage bucket and policies
-- Run this in the Supabase SQL Editor
-- ============================================================================

-- ============================================================================
-- 1. CREATE STORAGE BUCKET
-- ============================================================================
-- Create the delivery_proof bucket if it doesn't exist
-- Note: Bucket creation must be done via Supabase Dashboard or Storage API
-- This SQL will check if bucket exists and provide instructions

-- Check if bucket exists (this is informational - actual creation is via Dashboard)
-- To create the bucket manually:
-- 1. Go to Supabase Dashboard > Storage
-- 2. Click "New bucket"
-- 3. Name: delivery_proof
-- 4. Public bucket: Yes (checked)
-- 5. File size limit: 50MB (or as needed)
-- 6. Allowed MIME types: image/jpeg, image/png, image/webp

-- ============================================================================
-- 2. CREATE STORAGE POLICIES
-- ============================================================================
-- Policies for public access (not authenticated) - view, insert, update, delete

-- Drop existing policies if they exist (to avoid conflicts)
DROP POLICY IF EXISTS "Allow public view of delivery proof images" ON storage.objects;
DROP POLICY IF EXISTS "Allow public insert of delivery proof images" ON storage.objects;
DROP POLICY IF EXISTS "Allow public update of delivery proof images" ON storage.objects;
DROP POLICY IF EXISTS "Allow public delete of delivery proof images" ON storage.objects;

-- Policy 1: Allow public SELECT (view/download) access
CREATE POLICY "Allow public view of delivery proof images"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'delivery_proof');

-- Policy 2: Allow public INSERT (upload) access
CREATE POLICY "Allow public insert of delivery proof images"
ON storage.objects FOR INSERT
TO public
WITH CHECK (bucket_id = 'delivery_proof');

-- Policy 3: Allow public UPDATE access
CREATE POLICY "Allow public update of delivery proof images"
ON storage.objects FOR UPDATE
TO public
USING (bucket_id = 'delivery_proof')
WITH CHECK (bucket_id = 'delivery_proof');

-- Policy 4: Allow public DELETE access
CREATE POLICY "Allow public delete of delivery proof images"
ON storage.objects FOR DELETE
TO public
USING (bucket_id = 'delivery_proof');

-- ============================================================================
-- 3. VERIFY POLICIES
-- ============================================================================
-- Check if policies were created successfully
SELECT 
    policyname,
    cmd,
    roles,
    qual,
    with_check
FROM pg_policies
WHERE schemaname = 'storage' 
AND tablename = 'objects'
AND policyname LIKE '%delivery_proof%'
ORDER BY policyname;

-- ============================================================================
-- NOTES
-- ============================================================================
-- 1. The bucket must be created manually via Supabase Dashboard first
-- 2. After creating the bucket, run this SQL to create the policies
-- 3. These policies allow public (unauthenticated) access to the bucket
-- 4. File naming convention: {orderId}_{timestamp}_{index}.{ext}
--    Example: order123_1234567890_0.jpg
-- 5. Make sure the bucket is set to "Public" in the Dashboard settings

