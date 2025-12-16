-- ============================================================================
-- SQL commands to add video columns to existing products table
-- Run this in the Supabase SQL Editor
-- ============================================================================

-- Add video columns to the existing products table
ALTER TABLE products
ADD COLUMN IF NOT EXISTS video_url TEXT,
ADD COLUMN IF NOT EXISTS video_urls TEXT[] DEFAULT '{}',
ADD COLUMN IF NOT EXISTS videos_stored BOOLEAN DEFAULT FALSE;

-- Add comments for documentation
COMMENT ON COLUMN products.video_url IS 'Primary product video URL';
COMMENT ON COLUMN products.video_urls IS 'Array of all product video URLs (up to 2 videos, max 1 minute each)';
COMMENT ON COLUMN products.videos_stored IS 'Flag indicating if videos have been uploaded';

