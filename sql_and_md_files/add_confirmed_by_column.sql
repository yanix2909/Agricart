-- SQL command to add confirmed_by and confirmed_by_name columns to the orders table in Supabase
-- Run this in the Supabase SQL Editor
-- This adds the columns to track who confirmed the order

-- Add confirmed_by column (text, nullable)
-- This is the UID of the staff/admin who confirmed the order
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS confirmed_by TEXT;

-- Add confirmed_by_name column (text, nullable)
-- This is the full name of the staff/admin who confirmed the order
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS confirmed_by_name TEXT;

-- Create index for better query performance
CREATE INDEX IF NOT EXISTS idx_orders_confirmed_by ON orders(confirmed_by);

-- Add comments for documentation
COMMENT ON COLUMN orders.confirmed_by IS 'UID of the staff/admin who confirmed the order';
COMMENT ON COLUMN orders.confirmed_by_name IS 'Full name of the staff/admin who confirmed the order';

