-- SQL command to add estimated delivery columns to the orders table in Supabase
-- Run this in the Supabase SQL Editor
-- This adds the columns to track estimated delivery/pickup time ranges for rescheduled orders

-- Estimated delivery start timestamp (milliseconds)
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS estimated_delivery_start BIGINT;
COMMENT ON COLUMN orders.estimated_delivery_start IS 'Unix timestamp (milliseconds) for estimated delivery/pickup start time';

-- Estimated delivery end timestamp (milliseconds)
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS estimated_delivery_end BIGINT;
COMMENT ON COLUMN orders.estimated_delivery_end IS 'Unix timestamp (milliseconds) for estimated delivery/pickup end time';

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_orders_estimated_delivery_start ON orders(estimated_delivery_start);
CREATE INDEX IF NOT EXISTS idx_orders_estimated_delivery_end ON orders(estimated_delivery_end);

