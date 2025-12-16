-- Supabase Storage Policies for customer_profile bucket
-- Run this SQL in your Supabase SQL Editor
--
-- First, ensure the bucket exists (create it in Supabase Dashboard if it doesn't)
-- Storage > Buckets > Create bucket: customer_profile (make it public)
--
-- Enable RLS (Row Level Security) on the bucket
-- This is done via the Supabase Dashboard: Storage > Policies

-- Policy: Allow public (unauthenticated) users to view/download profile pictures
-- This allows anyone (even without authentication) to view profile pictures
CREATE POLICY "Allow public view of customer profile pictures"
ON storage.objects FOR SELECT
TO public
USING (bucket_id = 'customer_profile');

-- Policy: Allow public (unauthenticated) users to insert/upload profile pictures
-- This allows anyone (even without authentication) to upload profile pictures
CREATE POLICY "Allow public insert of customer profile pictures"
ON storage.objects FOR INSERT
TO public
WITH CHECK (bucket_id = 'customer_profile');

-- Policy: Allow public (unauthenticated) users to update profile pictures
-- This allows anyone (even without authentication) to update profile pictures
CREATE POLICY "Allow public update of customer profile pictures"
ON storage.objects FOR UPDATE
TO public
USING (bucket_id = 'customer_profile')
WITH CHECK (bucket_id = 'customer_profile');

-- Policy: Allow public (unauthenticated) users to delete profile pictures
-- This allows anyone (even without authentication) to delete profile pictures
CREATE POLICY "Allow public delete of customer profile pictures"
ON storage.objects FOR DELETE
TO public
USING (bucket_id = 'customer_profile');

-- Note: The above policies allow public (not authenticated) access to:
-- - View/Download profile pictures (SELECT)
-- - Upload profile pictures (INSERT)
-- - Update profile pictures (UPDATE)
-- - Delete profile pictures (DELETE)

-- The profileImageUrl will be stored in Firebase Realtime Database at:
-- customers/{customerId}/profileImageUrl
-- This URL will point to the Supabase Storage location

