-- SQL command to add ready_for_pickup_at column to orders table
-- This column stores the timestamp when an order was marked as ready for pickup
-- Run this in the Supabase SQL Editor

ALTER TABLE orders ADD COLUMN IF NOT EXISTS ready_for_pickup_at BIGINT;

-- Create index for better query performance
CREATE INDEX IF NOT EXISTS idx_orders_ready_for_pickup_at ON orders(ready_for_pickup_at);

-- Add comment to document the column
COMMENT ON COLUMN orders.ready_for_pickup_at IS 'Timestamp (milliseconds since epoch) when the order was marked as ready for pickup';
