-- SQL command to add reschedule metadata columns to the orders table in Supabase
-- Run this in the Supabase SQL Editor
-- This adds the columns to track when and who rescheduled an order

-- Timestamp (milliseconds) for when the order was rescheduled
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS rescheduled_at BIGINT;
COMMENT ON COLUMN orders.rescheduled_at IS 'Unix timestamp (milliseconds) when the order was rescheduled';

-- UID of the staff/admin who rescheduled the order
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS rescheduled_by TEXT;
COMMENT ON COLUMN orders.rescheduled_by IS 'UID of the staff/admin who rescheduled the order';

-- Full name of the staff/admin who rescheduled the order
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS rescheduled_by_name TEXT;
COMMENT ON COLUMN orders.rescheduled_by_name IS 'Full name of the staff/admin who rescheduled the order (e.g., "John Doe")';

-- Role/title of the staff/admin who rescheduled the order (e.g., Administrator, Staff)
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS rescheduled_by_role TEXT;
COMMENT ON COLUMN orders.rescheduled_by_role IS 'Role/title of the staff/admin who rescheduled the order (e.g., "System Administrator", "Staff Member")';

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_orders_rescheduled_at ON orders(rescheduled_at);
CREATE INDEX IF NOT EXISTS idx_orders_rescheduled_by ON orders(rescheduled_by);

-- Note: This file should be run along with:
-- 1. add_to_receive_metadata.sql (for to_receive_at, to_receive_by, to_receive_by_name)
-- 2. add_estimated_delivery_columns.sql (for estimated_delivery_start, estimated_delivery_end)

