-- SQL command to add order_notes column to the orders table
-- Run this in the Supabase SQL Editor

-- Add order_notes column if it doesn't exist
ALTER TABLE orders ADD COLUMN IF NOT EXISTS order_notes TEXT;

-- Create index for better query performance (optional, but recommended if you'll query by notes)
-- CREATE INDEX IF NOT EXISTS idx_orders_order_notes ON orders(order_notes) WHERE order_notes IS NOT NULL;
