-- ============================================================================
-- COMPLETE ORDER RATING SYSTEM SETUP FOR SUPABASE
-- ============================================================================
-- This script sets up the complete order rating system including:
-- 1. Order feedback columns (rating, comment, media)
-- 2. Delivery rider feedback columns (rating, comment)
-- 3. Storage bucket for rated media
-- 4. Public policies for rated_media bucket
-- 
-- Run this entire script in the Supabase SQL Editor
-- ============================================================================

-- ============================================================================
-- PART 1: ADD ORDER RATING COLUMNS TO orders TABLE
-- ============================================================================

-- Order overall rating (1-5 stars)
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS order_rating INTEGER;

-- Order feedback comment
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS order_comment TEXT;

-- Order feedback media (images/videos) - array of URLs stored as JSONB
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS order_media JSONB;

-- Timestamp when order was rated
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS order_rated_at BIGINT;

-- ============================================================================
-- PART 2: ADD DELIVERY RIDER FEEDBACK COLUMNS
-- ============================================================================

-- Rider overall rating (1-5 stars)
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS rider_rating INTEGER;

-- Rider feedback comment
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS rider_comment TEXT;

-- Timestamp when rider was rated
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS rider_rated_at BIGINT;

-- ============================================================================
-- PART 2B: ADD PICKUP EXPERIENCE FEEDBACK COLUMNS
-- ============================================================================

-- Pickup experience comment (for pickup orders only)
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS pickup_experience_comment TEXT;

-- Timestamp when pickup experience was rated
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS pickup_experience_rated_at BIGINT;

-- ============================================================================
-- PART 3: ADD RATING STATUS FLAG
-- ============================================================================

-- Flag to indicate if order has been rated by customer
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS is_rated BOOLEAN DEFAULT FALSE;

-- ============================================================================
-- PART 4: CREATE INDEXES FOR BETTER QUERY PERFORMANCE
-- ============================================================================

-- Index for querying rated orders
CREATE INDEX IF NOT EXISTS idx_orders_is_rated ON orders(is_rated);

-- Index for querying orders by rating
CREATE INDEX IF NOT EXISTS idx_orders_order_rating ON orders(order_rating);

-- Index for querying orders by rider rating
CREATE INDEX IF NOT EXISTS idx_orders_rider_rating ON orders(rider_rating);

-- Composite index for customer + rated status
CREATE INDEX IF NOT EXISTS idx_orders_customer_rated ON orders(customer_id, is_rated);

-- Composite index for rider + rating (to see rider performance)
CREATE INDEX IF NOT EXISTS idx_orders_rider_rating_performance ON orders(rider_id, rider_rating) WHERE rider_rating IS NOT NULL;

-- ============================================================================
-- PART 5: ADD CONSTRAINTS
-- ============================================================================

-- Ensure ratings are between 1 and 5
ALTER TABLE orders 
DROP CONSTRAINT IF EXISTS check_order_rating;

ALTER TABLE orders 
ADD CONSTRAINT check_order_rating 
CHECK (order_rating IS NULL OR (order_rating >= 1 AND order_rating <= 5));

ALTER TABLE orders 
DROP CONSTRAINT IF EXISTS check_rider_rating;

ALTER TABLE orders 
ADD CONSTRAINT check_rider_rating 
CHECK (rider_rating IS NULL OR (rider_rating >= 1 AND rider_rating <= 5));

-- ============================================================================
-- PART 6: ADD COMMENTS FOR DOCUMENTATION
-- ============================================================================

COMMENT ON COLUMN orders.order_rating IS 'Customer rating for the order (1-5 stars)';
COMMENT ON COLUMN orders.order_comment IS 'Customer comment/feedback for the order';
COMMENT ON COLUMN orders.order_media IS 'JSONB array of media URLs (images/videos) for order feedback, max 5 files, 50MB total';
COMMENT ON COLUMN orders.order_rated_at IS 'Unix timestamp (milliseconds) when order was rated by customer';
COMMENT ON COLUMN orders.rider_rating IS 'Customer rating for the delivery rider (1-5 stars) - for delivery orders';
COMMENT ON COLUMN orders.rider_comment IS 'Customer comment/feedback for the delivery rider - for delivery orders';
COMMENT ON COLUMN orders.rider_rated_at IS 'Unix timestamp (milliseconds) when rider was rated by customer';
COMMENT ON COLUMN orders.pickup_experience_comment IS 'Customer comment about pickup experience - for pickup orders';
COMMENT ON COLUMN orders.pickup_experience_rated_at IS 'Unix timestamp (milliseconds) when pickup experience was rated';
COMMENT ON COLUMN orders.is_rated IS 'Boolean flag indicating if the order has been rated by customer';

-- ============================================================================
-- PART 7: CREATE STORAGE BUCKET FOR RATED MEDIA
-- ============================================================================

-- Create the rated_media bucket if it doesn't exist
-- This bucket will store images and videos uploaded by customers when rating orders
-- Note: Run this in SQL editor or use Supabase Storage UI to create bucket with these settings:
--   - Name: rated_media
--   - Public: true
--   - File size limit: 52428800 (50 MB)
--   - Allowed MIME types: image/*, video/*

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'rated_media',
  'rated_media',
  true,
  52428800, -- 50 MB in bytes
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp', 'video/mp4', 'video/quicktime', 'video/webm', 'video/x-msvideo']
)
ON CONFLICT (id) DO UPDATE SET
  public = true,
  file_size_limit = 52428800,
  allowed_mime_types = ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/gif', 'image/webp', 'video/mp4', 'video/quicktime', 'video/webm', 'video/x-msvideo'];

-- ============================================================================
-- PART 8: CREATE STORAGE POLICIES FOR rated_media BUCKET
-- ============================================================================

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Public can view rated media" ON storage.objects;
DROP POLICY IF EXISTS "Public can insert rated media" ON storage.objects;
DROP POLICY IF EXISTS "Public can update rated media" ON storage.objects;
DROP POLICY IF EXISTS "Public can delete rated media" ON storage.objects;

-- Policy 1: Allow public/unauthenticated users to VIEW (SELECT) files in rated_media bucket
CREATE POLICY "Public can view rated media"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'rated_media');

-- Policy 2: Allow public/unauthenticated users to INSERT (upload) files to rated_media bucket
CREATE POLICY "Public can insert rated media"
ON storage.objects
FOR INSERT
TO public
WITH CHECK (bucket_id = 'rated_media');

-- Policy 3: Allow public/unauthenticated users to UPDATE files in rated_media bucket
CREATE POLICY "Public can update rated media"
ON storage.objects
FOR UPDATE
TO public
USING (bucket_id = 'rated_media')
WITH CHECK (bucket_id = 'rated_media');

-- Policy 4: Allow public/unauthenticated users to DELETE files from rated_media bucket
CREATE POLICY "Public can delete rated media"
ON storage.objects
FOR DELETE
TO public
USING (bucket_id = 'rated_media');

-- ============================================================================
-- PART 9: VERIFICATION QUERIES (OPTIONAL - FOR TESTING)
-- ============================================================================

-- Verify columns were added
-- SELECT column_name, data_type, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_name = 'orders' AND column_name IN (
--   'order_rating', 'order_comment', 'order_media', 'order_rated_at',
--   'rider_rating', 'rider_comment', 'rider_rated_at', 'is_rated'
-- );

-- Verify bucket was created
-- SELECT * FROM storage.buckets WHERE id = 'rated_media';

-- Verify policies were created
-- SELECT * FROM pg_policies WHERE tablename = 'objects' AND policyname LIKE '%rated media%';

-- Sample query to get orders with ratings
-- SELECT 
--   id, 
--   customer_name, 
--   status,
--   order_rating,
--   order_comment,
--   order_media,
--   rider_rating,
--   rider_comment,
--   is_rated,
--   order_rated_at
-- FROM orders 
-- WHERE is_rated = true
-- ORDER BY order_rated_at DESC
-- LIMIT 10;

-- ============================================================================
-- SETUP COMPLETE!
-- ============================================================================
-- Next steps:
-- 1. Customer app will automatically upload media to rated_media bucket
-- 2. Update web dashboard to display ratings
-- 3. Test the rating system end-to-end
-- ============================================================================

