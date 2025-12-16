-- ============================================================================
-- ADD GCASH_RECEIPT_URL TO DELIVERY_ORDERS TABLE
-- ============================================================================
-- This migration adds the gcash_receipt_url field to the delivery_orders table
-- so that delivery riders can view GCash payment receipts uploaded by customers
-- 
-- Date: 2024
-- ============================================================================

-- Add gcash_receipt_url column to delivery_orders table
ALTER TABLE delivery_orders 
ADD COLUMN IF NOT EXISTS gcash_receipt_url TEXT;

COMMENT ON COLUMN delivery_orders.gcash_receipt_url IS 'URL of the GCash payment receipt uploaded by the customer (for GCash payment orders)';

-- Create index for faster queries on payment method (optional)
CREATE INDEX IF NOT EXISTS idx_delivery_orders_payment_method ON delivery_orders(payment_method);

-- ============================================================================
-- UPDATE EXISTING RECORDS
-- ============================================================================
-- Sync gcash_receipt_url from orders table to delivery_orders for existing records
-- This is a one-time sync for orders that were created before this migration

UPDATE delivery_orders
SET gcash_receipt_url = orders.gcash_receipt_url
FROM orders
WHERE delivery_orders.id = orders.id
  AND orders.gcash_receipt_url IS NOT NULL
  AND orders.gcash_receipt_url != ''
  AND orders.gcash_receipt_url != 'pending:gcash_receipt';

-- Log the update
DO $$
DECLARE
    updated_count INTEGER;
BEGIN
    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RAISE NOTICE 'Updated % delivery_orders records with GCash receipt URLs', updated_count;
END $$;

