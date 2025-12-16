-- ============================================================================
-- Add Payment Proof Column to delivery_orders Table
-- ============================================================================
-- This script adds payment_proof column for GCash payment proof images
-- Run this in the Supabase SQL Editor
-- ============================================================================

-- Add payment_proof column (URL of payment proof image for GCash payments)
ALTER TABLE delivery_orders 
ADD COLUMN IF NOT EXISTS payment_proof TEXT;

COMMENT ON COLUMN delivery_orders.payment_proof IS 'URL of payment proof image uploaded by rider (for GCash payment orders)';

-- Verify column was added
SELECT 
    column_name, 
    data_type, 
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'delivery_orders' 
AND column_name = 'payment_proof';

-- ============================================================================
-- Optional: Add payment_proof to orders table as well (for consistency)
-- ============================================================================
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS payment_proof TEXT;

COMMENT ON COLUMN orders.payment_proof IS 'URL of payment proof image uploaded by rider (for GCash payment orders)';

-- Verify column was added
SELECT 
    column_name, 
    data_type, 
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'orders' 
AND column_name = 'payment_proof';

