-- SQL command to add confirmed_at column to the orders table in Supabase
-- Run this in the Supabase SQL Editor
-- This adds the column to track when an order was confirmed

-- Add confirmed_at column (timestamp in milliseconds, nullable)
-- This is the timestamp when the order was confirmed by staff
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS confirmed_at BIGINT;

-- Create index for better query performance
CREATE INDEX IF NOT EXISTS idx_orders_confirmed_at ON orders(confirmed_at);

-- Add comment for documentation
COMMENT ON COLUMN orders.confirmed_at IS 'Unix timestamp in milliseconds when order was confirmed by staff';

