-- SQL command to add cancellation_confirmed_by_name and cancellation_confirmed_by_role columns to the orders table
-- Run this in the Supabase SQL Editor
-- This adds the columns to track who confirmed the cancellation and their role

-- Full name of the staff/admin who confirmed the cancellation
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS cancellation_confirmed_by_name TEXT;

COMMENT ON COLUMN orders.cancellation_confirmed_by_name IS 'Full name of the staff/admin who confirmed the cancellation';

-- Role/title of the staff/admin who confirmed the cancellation (e.g., Administrator, Staff)
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS cancellation_confirmed_by_role TEXT;

COMMENT ON COLUMN orders.cancellation_confirmed_by_role IS 'Role/title of the staff/admin who confirmed the cancellation';

-- Create index for better query performance
CREATE INDEX IF NOT EXISTS idx_orders_cancellation_confirmed_by ON orders(cancellation_confirmed_by_name);

