-- SQL command to add refund cancellation columns to the orders table in Supabase
-- Run this in the Supabase SQL Editor
-- This adds ALL columns needed for staff refund processing functionality

-- Add cancellation_confirmed column (boolean, default FALSE)
-- This indicates whether the cancellation has been confirmed by staff (refund processed)
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS cancellation_confirmed BOOLEAN DEFAULT FALSE;

-- Add cancellation_confirmed_at column (timestamp in milliseconds, nullable)
-- This is the timestamp when the cancellation was confirmed by staff
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS cancellation_confirmed_at BIGINT;

-- Add refund_confirmed_at column (timestamp in milliseconds, nullable)
-- This is the timestamp when the refund was confirmed
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS refund_confirmed_at BIGINT;

-- Add refund_confirmed_by column (text, nullable)
-- Staff UID who confirmed the refund
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS refund_confirmed_by TEXT;

-- Add refund_confirmed_by_name column (text, nullable)
-- Staff name who confirmed the refund
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS refund_confirmed_by_name TEXT;

-- Add refund_receipt_url column (text, nullable)
-- URL or path to the refund receipt image
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS refund_receipt_url TEXT;

-- Add refund_denied column (boolean, nullable)
-- Whether refund was denied
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS refund_denied BOOLEAN;

-- Add refund_denied_reason column (text, nullable)
-- Reason why refund was denied
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS refund_denied_reason TEXT;

-- Add refund_denied_at column (timestamp in milliseconds, nullable)
-- Timestamp when refund was denied
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS refund_denied_at BIGINT;

-- Add refund_denied_by column (text, nullable)
-- Staff UID who denied the refund
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS refund_denied_by TEXT;

-- Add refund_denied_by_name column (text, nullable)
-- Staff name who denied the refund
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS refund_denied_by_name TEXT;

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_orders_cancellation_confirmed ON orders(cancellation_confirmed);
CREATE INDEX IF NOT EXISTS idx_orders_refund_confirmed_at ON orders(refund_confirmed_at);
CREATE INDEX IF NOT EXISTS idx_orders_refund_denied ON orders(refund_denied);

-- Add comments for documentation
COMMENT ON COLUMN orders.cancellation_confirmed IS 'Whether the cancellation has been confirmed by staff (refund processed)';
COMMENT ON COLUMN orders.cancellation_confirmed_at IS 'Unix timestamp in milliseconds when cancellation was confirmed by staff';
COMMENT ON COLUMN orders.refund_confirmed_at IS 'Unix timestamp in milliseconds when refund was confirmed';
COMMENT ON COLUMN orders.refund_confirmed_by IS 'Staff UID who confirmed the refund';
COMMENT ON COLUMN orders.refund_confirmed_by_name IS 'Staff name who confirmed the refund';
COMMENT ON COLUMN orders.refund_receipt_url IS 'URL or path to the refund receipt image';
COMMENT ON COLUMN orders.refund_denied IS 'Whether refund was denied';
COMMENT ON COLUMN orders.refund_denied_reason IS 'Reason why refund was denied';
COMMENT ON COLUMN orders.refund_denied_at IS 'Unix timestamp in milliseconds when refund was denied';
COMMENT ON COLUMN orders.refund_denied_by IS 'Staff UID who denied the refund';
COMMENT ON COLUMN orders.refund_denied_by_name IS 'Staff name who denied the refund';
