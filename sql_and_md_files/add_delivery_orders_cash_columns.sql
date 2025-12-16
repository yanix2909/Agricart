-- ============================================================================
-- Add Cash on Delivery Columns to delivery_orders Table
-- ============================================================================
-- This script adds cash_received and change columns for COD orders
-- Run this in the Supabase SQL Editor
-- ============================================================================

-- Add cash_received column (amount of cash received from customer)
ALTER TABLE delivery_orders 
ADD COLUMN IF NOT EXISTS cash_received NUMERIC(10, 2);

COMMENT ON COLUMN delivery_orders.cash_received IS 'Amount of cash received from customer for cash on delivery orders';

-- Add change column (change given to customer)
ALTER TABLE delivery_orders 
ADD COLUMN IF NOT EXISTS change NUMERIC(10, 2);

COMMENT ON COLUMN delivery_orders.change IS 'Change given to customer (cash_received - total_amount)';

-- Verify columns were added
SELECT 
    column_name, 
    data_type, 
    is_nullable
FROM information_schema.columns 
WHERE table_name = 'delivery_orders' 
AND column_name IN ('cash_received', 'change')
ORDER BY column_name;

