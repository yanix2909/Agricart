-- SQL commands to add cancellation_requested_at and refund_denied_reason columns to the orders table in Supabase
-- Run this in the Supabase SQL Editor

-- 1. Add cancellation_requested_at column (bigint, nullable)
-- This stores the timestamp when the customer requested cancellation
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS cancellation_requested_at BIGINT;
COMMENT ON COLUMN orders.cancellation_requested_at IS 'Timestamp (milliseconds) when the customer requested cancellation of the order';

-- 2. Add refund_denied_reason column (text, nullable)
-- This stores the reason provided by staff/admin when confirming cancellation without refund
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS refund_denied_reason TEXT;
COMMENT ON COLUMN orders.refund_denied_reason IS 'Reason provided by staff/admin when confirming cancellation without refund (no-refund cancellations)';

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_orders_cancellation_requested_at ON orders(cancellation_requested_at);
CREATE INDEX IF NOT EXISTS idx_orders_refund_denied_reason ON orders(refund_denied_reason);

