-- ============================================================================
-- Rider Conversation Storage Setup
-- ============================================================================
-- This script creates the storage bucket and policies for rider-customer
-- chat images and videos
-- Run this in the Supabase SQL Editor
-- ============================================================================

-- Create the storage bucket for rider conversations (images and videos)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'rider_conversation',
  'rider_conversation',
  true, -- Public bucket (no authentication required)
  52428800, -- 50MB file size limit (adjust as needed)
  ARRAY[
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/gif',
    'image/webp',
    'video/mp4',
    'video/quicktime',
    'video/x-msvideo',
    'video/webm'
  ]
)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- Storage Policies for rider_conversation bucket
-- Public access (no authentication required)
-- ============================================================================

-- Policy: Allow public to view files
CREATE POLICY "Public view rider_conversation"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'rider_conversation');

-- Policy: Allow public to insert/upload files
CREATE POLICY "Public insert rider_conversation"
ON storage.objects
FOR INSERT
TO public
WITH CHECK (bucket_id = 'rider_conversation');

-- Policy: Allow public to update files
CREATE POLICY "Public update rider_conversation"
ON storage.objects
FOR UPDATE
TO public
USING (bucket_id = 'rider_conversation')
WITH CHECK (bucket_id = 'rider_conversation');

-- Policy: Allow public to delete files
CREATE POLICY "Public delete rider_conversation"
ON storage.objects
FOR DELETE
TO public
USING (bucket_id = 'rider_conversation');

-- ============================================================================
-- Add image_url and video_url columns to chat_messages table
-- ============================================================================

-- Add image_url column if it doesn't exist
ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS image_url TEXT;

COMMENT ON COLUMN chat_messages.image_url IS 'URL to image file in rider_conversation bucket';

-- Add video_url column if it doesn't exist
ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS video_url TEXT;

COMMENT ON COLUMN chat_messages.video_url IS 'URL to video file in rider_conversation bucket';

-- Add message_type column to distinguish text, image, video, or mixed messages
ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS message_type TEXT DEFAULT 'text';

COMMENT ON COLUMN chat_messages.message_type IS 'Type of message: text, image, video, or mixed';

-- Create index for better query performance
CREATE INDEX IF NOT EXISTS idx_chat_messages_image_url ON chat_messages(image_url) WHERE image_url IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_chat_messages_video_url ON chat_messages(video_url) WHERE video_url IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_chat_messages_message_type ON chat_messages(message_type);

-- ============================================================================
-- Optional: Add thumbnail_url for videos (for preview)
-- ============================================================================

ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS thumbnail_url TEXT;

COMMENT ON COLUMN chat_messages.thumbnail_url IS 'URL to video thumbnail image in rider_conversation bucket';

-- ============================================================================
-- Optional: Add file metadata columns
-- ============================================================================

ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS file_name TEXT;

COMMENT ON COLUMN chat_messages.file_name IS 'Original filename of uploaded image/video';

ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS file_size BIGINT;

COMMENT ON COLUMN chat_messages.file_size IS 'File size in bytes';

ALTER TABLE chat_messages
ADD COLUMN IF NOT EXISTS mime_type TEXT;

COMMENT ON COLUMN chat_messages.mime_type IS 'MIME type of the file (e.g., image/jpeg, video/mp4)';

