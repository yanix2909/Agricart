-- ========================================================================
-- Add product_id column to customer_notifications table
-- ========================================================================
-- This allows notifications to reference products (for product_restocked and product_added types)

-- Add product_id column if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'customer_notifications' 
        AND column_name = 'product_id'
    ) THEN
        ALTER TABLE customer_notifications 
        ADD COLUMN product_id TEXT;
        
        -- Add index for faster lookups
        CREATE INDEX IF NOT EXISTS idx_customer_notifications_product_id 
        ON customer_notifications(product_id) 
        WHERE product_id IS NOT NULL;
        
        -- Add comment
        COMMENT ON COLUMN customer_notifications.product_id IS 'Optional: related product ID if notification is product-related (e.g., product_restocked, product_added)';
        
        RAISE NOTICE 'Added product_id column to customer_notifications table';
    ELSE
        RAISE NOTICE 'product_id column already exists';
    END IF;
END $$;

-- Verify the column was added
SELECT 
    column_name, 
    data_type, 
    is_nullable
FROM information_schema.columns
WHERE table_name = 'customer_notifications' 
AND column_name = 'product_id';
