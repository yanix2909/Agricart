-- ============================================================================
-- SQL Commands for Delivery Proof Storage Bucket Policies
-- ============================================================================
-- Run this SQL in Supabase SQL Editor
-- Make sure the 'delivery_proof' bucket exists first (create via Dashboard)
-- ============================================================================

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

-- Verify policies were created
SELECT 
    policyname,
    cmd,
    roles
FROM pg_policies
WHERE schemaname = 'storage' 
AND tablename = 'objects'
AND policyname LIKE '%delivery_proof%'
ORDER BY policyname;

