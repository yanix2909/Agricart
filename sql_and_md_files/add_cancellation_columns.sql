-- SQL command to add cancellation columns to the orders table in Supabase
-- Run this in the Supabase SQL Editor
-- This adds the columns needed for order cancellation functionality

-- Add cancellation_requested column (boolean, default FALSE)
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS cancellation_requested BOOLEAN DEFAULT FALSE;

-- Add cancellation_requested_at column (timestamp in milliseconds, nullable)
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS cancellation_requested_at BIGINT;

-- Add cancellation_initiated_by column (text, nullable - 'customer' or 'staff')
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS cancellation_initiated_by TEXT;

-- Add cancellation_reason column (text, nullable)
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS cancellation_reason TEXT;

-- Create index on cancellation_requested for faster queries
CREATE INDEX IF NOT EXISTS idx_orders_cancellation_requested ON orders(cancellation_requested);

-- Create index on cancellation_initiated_by for filtering
CREATE INDEX IF NOT EXISTS idx_orders_cancellation_initiated_by ON orders(cancellation_initiated_by);

-- Add comments for documentation
COMMENT ON COLUMN orders.cancellation_requested IS 'Whether the order has been requested for cancellation';
COMMENT ON COLUMN orders.cancellation_requested_at IS 'Unix timestamp in milliseconds when cancellation was requested';
COMMENT ON COLUMN orders.cancellation_initiated_by IS 'Who initiated the cancellation: "customer" or "staff"';
COMMENT ON COLUMN orders.cancellation_reason IS 'Reason provided for the cancellation request';

