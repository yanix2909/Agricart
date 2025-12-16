-- ============================================================================
-- Add Delivery Status Columns to orders Table
-- ============================================================================
-- This script adds columns needed for rider delivery confirmation and failure tracking
-- Run this in the Supabase SQL Editor
-- ============================================================================

-- Delivery completion columns
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS delivered_at BIGINT;

COMMENT ON COLUMN orders.delivered_at IS 'Unix timestamp (milliseconds) when order was delivered by rider';

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS delivered_by TEXT;

COMMENT ON COLUMN orders.delivered_by IS 'UID of the rider who delivered the order';

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS delivered_by_name TEXT;

COMMENT ON COLUMN orders.delivered_by_name IS 'Full name of the rider who delivered the order';

-- Failed delivery columns
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS failed_at BIGINT;

COMMENT ON COLUMN orders.failed_at IS 'Unix timestamp (milliseconds) when order delivery failed';

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS failure_reason TEXT;

COMMENT ON COLUMN orders.failure_reason IS 'Reason for failed delivery (e.g., Customer not available, Wrong address, etc.)';

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS failed_by TEXT;

COMMENT ON COLUMN orders.failed_by IS 'UID of the rider who marked the order as failed';

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS failed_by_name TEXT;

COMMENT ON COLUMN orders.failed_by_name IS 'Full name of the rider who marked the order as failed';

ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS delivery_schedule BIGINT;

COMMENT ON COLUMN orders.delivery_schedule IS 'Unix timestamp (milliseconds) of the scheduled delivery time (from out_for_delivery_at or assigned_at)';

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_orders_delivered_at ON orders(delivered_at);
CREATE INDEX IF NOT EXISTS idx_orders_failed_at ON orders(failed_at);
CREATE INDEX IF NOT EXISTS idx_orders_delivered_by ON orders(delivered_by);
CREATE INDEX IF NOT EXISTS idx_orders_failed_by ON orders(failed_by);

-- Verify columns were added
SELECT 
    column_name, 
    data_type, 
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'orders' 
AND column_name IN (
    'delivered_at', 
    'delivered_by', 
    'delivered_by_name',
    'failed_at',
    'failure_reason',
    'failed_by',
    'failed_by_name',
    'delivery_schedule'
)
ORDER BY column_name;

