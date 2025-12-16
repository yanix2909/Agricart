-- SQL commands to create storage bucket for rated order media
-- Run this in the Supabase SQL Editor
-- This creates a bucket for customer rating images/videos with public access

-- ============================================================================
-- 1. CREATE STORAGE BUCKET FOR RATED MEDIA
-- ============================================================================
-- Note: This command needs to be run in Supabase Storage section or via SQL
-- If you run this via SQL and get an error, create the bucket manually in Supabase Dashboard > Storage

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'rated_media',
  'rated_media',
  true, -- public bucket
  52428800, -- 50 MB in bytes (50 * 1024 * 1024)
  ARRAY[
    'image/jpeg',
    'image/jpg', 
    'image/png',
    'image/webp',
    'image/gif',
    'video/mp4',
    'video/quicktime',
    'video/webm',
    'video/x-msvideo'
  ]
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 52428800,
  allowed_mime_types = ARRAY[
    'image/jpeg',
    'image/jpg',
    'image/png', 
    'image/webp',
    'image/gif',
    'video/mp4',
    'video/quicktime',
    'video/webm',
    'video/x-msvideo'
  ];

-- ============================================================================
-- 2. CREATE STORAGE POLICIES FOR RATED_MEDIA BUCKET
-- ============================================================================

-- Policy 1: Allow PUBLIC to VIEW/SELECT files (not authenticated required)
DROP POLICY IF EXISTS "Public can view rated media" ON storage.objects;
CREATE POLICY "Public can view rated media"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'rated_media');

-- Policy 2: Allow PUBLIC to INSERT/UPLOAD files (not authenticated required)
DROP POLICY IF EXISTS "Public can insert rated media" ON storage.objects;
CREATE POLICY "Public can insert rated media"
ON storage.objects FOR INSERT
TO public
WITH CHECK (bucket_id = 'rated_media');

-- Policy 3: Allow PUBLIC to UPDATE files (not authenticated required)
DROP POLICY IF EXISTS "Public can update rated media" ON storage.objects;
CREATE POLICY "Public can update rated media"
ON storage.objects FOR UPDATE
TO public
USING (bucket_id = 'rated_media')
WITH CHECK (bucket_id = 'rated_media');

-- Policy 4: Allow PUBLIC to DELETE files (not authenticated required)
DROP POLICY IF EXISTS "Public can delete rated media" ON storage.objects;
CREATE POLICY "Public can delete rated media"
ON storage.objects FOR DELETE
TO public
USING (bucket_id = 'rated_media');

-- ============================================================================
-- 3. VERIFY BUCKET AND POLICIES
-- ============================================================================

-- Check if bucket was created
SELECT id, name, public, file_size_limit, allowed_mime_types
FROM storage.buckets
WHERE id = 'rated_media';

-- Check if policies were created
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'objects' AND policyname LIKE '%rated media%';

-- ============================================================================
-- NOTES FOR MANUAL BUCKET CREATION (if SQL INSERT fails)
-- ============================================================================
-- If the INSERT INTO storage.buckets fails, create the bucket manually:
-- 1. Go to Supabase Dashboard > Storage
-- 2. Click "Create Bucket" 
-- 3. Set name: rated_media
-- 4. Enable "Public bucket"
-- 5. Set file size limit: 50 MB
-- 6. Add allowed MIME types:
--    - image/jpeg, image/jpg, image/png, image/webp, image/gif
--    - video/mp4, video/quicktime, video/webm, video/x-msvideo
-- 7. Then run the POLICY creation commands above

