-- SQL commands to add order rating functionality to the orders table
-- Run this in the Supabase SQL Editor
-- This adds columns for customer feedback on orders and delivery riders

-- ============================================================================
-- 1. ADD ORDER FEEDBACK COLUMNS
-- ============================================================================

-- Order overall rating (1-5 stars)
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS order_rating INTEGER;

-- Order feedback comment
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS order_comment TEXT;

-- Order feedback media (images/videos) - array of URLs
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS order_media JSONB;

-- Timestamp when order was rated
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS order_rated_at BIGINT;

-- ============================================================================
-- 2. ADD DELIVERY RIDER FEEDBACK COLUMNS
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
-- 3. ADD RATING STATUS FLAG
-- ============================================================================

-- Flag to indicate if order has been rated
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS is_rated BOOLEAN DEFAULT FALSE;

-- ============================================================================
-- 4. CREATE INDEXES FOR BETTER QUERY PERFORMANCE
-- ============================================================================

-- Index for querying rated orders
CREATE INDEX IF NOT EXISTS idx_orders_is_rated ON orders(is_rated);

-- Index for querying orders by rating
CREATE INDEX IF NOT EXISTS idx_orders_order_rating ON orders(order_rating);

-- Index for querying orders by rider rating
CREATE INDEX IF NOT EXISTS idx_orders_rider_rating ON orders(rider_rating);

-- Composite index for customer + rated status
CREATE INDEX IF NOT EXISTS idx_orders_customer_rated ON orders(customer_id, is_rated);

-- ============================================================================
-- 5. ADD CONSTRAINTS
-- ============================================================================

-- Ensure ratings are between 1 and 5
ALTER TABLE orders 
ADD CONSTRAINT IF NOT EXISTS check_order_rating 
CHECK (order_rating IS NULL OR (order_rating >= 1 AND order_rating <= 5));

ALTER TABLE orders 
ADD CONSTRAINT IF NOT EXISTS check_rider_rating 
CHECK (rider_rating IS NULL OR (rider_rating >= 1 AND rider_rating <= 5));

-- ============================================================================
-- 6. ADD COMMENTS FOR DOCUMENTATION
-- ============================================================================

COMMENT ON COLUMN orders.order_rating IS 'Customer rating for the order (1-5 stars)';
COMMENT ON COLUMN orders.order_comment IS 'Customer comment/feedback for the order';
COMMENT ON COLUMN orders.order_media IS 'Array of media URLs (images/videos) for order feedback';
COMMENT ON COLUMN orders.order_rated_at IS 'Timestamp (milliseconds) when order was rated';
COMMENT ON COLUMN orders.rider_rating IS 'Customer rating for the delivery rider (1-5 stars)';
COMMENT ON COLUMN orders.rider_comment IS 'Customer comment/feedback for the delivery rider';
COMMENT ON COLUMN orders.rider_rated_at IS 'Timestamp (milliseconds) when rider was rated';
COMMENT ON COLUMN orders.is_rated IS 'Flag indicating if the order has been rated by customer';

