-- SQL command to add to_receive metadata columns to the orders table in Supabase
-- Run this in the Supabase SQL Editor
-- This adds the columns to track when and who moved an order to "to_receive" status

-- Timestamp (milliseconds) for when the order was moved to "to_receive" status
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS to_receive_at BIGINT;
COMMENT ON COLUMN orders.to_receive_at IS 'Unix timestamp (milliseconds) when the order was moved to "to_receive" status';

-- UID of the staff/admin who moved the order to "to_receive" status
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS to_receive_by TEXT;
COMMENT ON COLUMN orders.to_receive_by IS 'UID of the staff/admin who moved the order to "to_receive" status';

-- Full name of the staff/admin who moved the order to "to_receive" status
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS to_receive_by_name TEXT;
COMMENT ON COLUMN orders.to_receive_by_name IS 'Full name of the staff/admin who moved the order to "to_receive" status';

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_orders_to_receive_at ON orders(to_receive_at);
CREATE INDEX IF NOT EXISTS idx_orders_to_receive_by ON orders(to_receive_by);

