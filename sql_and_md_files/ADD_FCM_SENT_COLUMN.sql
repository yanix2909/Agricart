-- ========================================================================
-- Add fcm_sent column to customer_notifications table
-- This tracks whether FCM push notification was already sent
-- ========================================================================
-- NOTE: If the table doesn't exist, run SETUP_NOTIFICATIONS_WITH_FCM.sql first

-- Check if table exists, if not, create it
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.tables 
        WHERE table_name = 'customer_notifications'
    ) THEN
        RAISE EXCEPTION 'Table customer_notifications does not exist. Please run SETUP_NOTIFICATIONS_WITH_FCM.sql first to create the table.';
    END IF;
END $$;

-- Add fcm_sent column (defaults to false for existing notifications)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'customer_notifications' 
        AND column_name = 'fcm_sent'
    ) THEN
        ALTER TABLE customer_notifications 
        ADD COLUMN fcm_sent BOOLEAN DEFAULT FALSE;
        
        RAISE NOTICE 'Added fcm_sent column to customer_notifications table';
    ELSE
        RAISE NOTICE 'fcm_sent column already exists';
    END IF;
END $$;

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_customer_notifications_fcm_sent 
ON customer_notifications(customer_id, fcm_sent) 
WHERE fcm_sent = FALSE;

-- Add comment
COMMENT ON COLUMN customer_notifications.fcm_sent IS 'Whether FCM push notification was already sent. Prevents duplicate notifications.';

