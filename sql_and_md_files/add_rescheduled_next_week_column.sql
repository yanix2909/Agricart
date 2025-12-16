-- SQL command to add rescheduled_next_week column to the orders table in Supabase
-- Run this in the Supabase SQL Editor
-- This adds a flag to indicate if an order was rescheduled to next week

-- Boolean flag to indicate if order was rescheduled to next week
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS rescheduled_next_week BOOLEAN DEFAULT FALSE;
COMMENT ON COLUMN orders.rescheduled_next_week IS 'Flag indicating if the order was rescheduled to next week (cut-off time reschedule)';

-- Create index for better query performance
CREATE INDEX IF NOT EXISTS idx_orders_rescheduled_next_week ON orders(rescheduled_next_week);

