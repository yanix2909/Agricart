-- ========================================================================
-- Complete Setup: customer_notifications table with fcm_sent column
-- ========================================================================
-- Run this file to create the table (if it doesn't exist) and add fcm_sent column
-- This is a safe script that can be run multiple times

-- ========================================================================
-- 1. Create customer_notifications table (if it doesn't exist)
-- ========================================================================

CREATE TABLE IF NOT EXISTS customer_notifications (
    -- Primary Key (UUID as TEXT or UUID type - both work)
    id TEXT PRIMARY KEY,
    
    -- Foreign Key to customers table
    customer_id TEXT NOT NULL REFERENCES customers(uid) ON DELETE CASCADE,
    
    -- Notification Content
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    type TEXT NOT NULL DEFAULT 'notification',
    
    -- Notification Metadata
    order_id TEXT,  -- Optional: related order ID if notification is order-related
    is_read BOOLEAN DEFAULT FALSE,
    
    -- FCM Tracking (NEW - prevents duplicate notifications)
    fcm_sent BOOLEAN DEFAULT FALSE,  -- Whether FCM push notification was already sent
    
    -- Timestamp (Unix timestamp in milliseconds)
    timestamp BIGINT NOT NULL,
    
    -- Timestamps for tracking
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ========================================================================
-- 2. Add fcm_sent column if table exists but column doesn't
-- ========================================================================

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

-- ========================================================================
-- 3. Create indexes
-- ========================================================================

CREATE INDEX IF NOT EXISTS idx_customer_notifications_customer_id 
ON customer_notifications(customer_id);

CREATE INDEX IF NOT EXISTS idx_customer_notifications_customer_timestamp 
ON customer_notifications(customer_id, timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_customer_notifications_is_read 
ON customer_notifications(customer_id, is_read) 
WHERE is_read = FALSE;

CREATE INDEX IF NOT EXISTS idx_customer_notifications_type 
ON customer_notifications(customer_id, type);

CREATE INDEX IF NOT EXISTS idx_customer_notifications_order_id 
ON customer_notifications(order_id) 
WHERE order_id IS NOT NULL;

-- Index for fcm_sent (for faster lookups of unsent notifications)
CREATE INDEX IF NOT EXISTS idx_customer_notifications_fcm_sent 
ON customer_notifications(customer_id, fcm_sent) 
WHERE fcm_sent = FALSE;

-- ========================================================================
-- 4. Enable Row Level Security (RLS)
-- ========================================================================

ALTER TABLE customer_notifications ENABLE ROW LEVEL SECURITY;

-- ========================================================================
-- 5. Drop existing policies if they exist (to avoid errors on re-run)
-- ========================================================================

DROP POLICY IF EXISTS "Customers can view their own notifications" ON customer_notifications;
DROP POLICY IF EXISTS "Customers can insert their own notifications" ON customer_notifications;
DROP POLICY IF EXISTS "Customers can update their own notifications" ON customer_notifications;
DROP POLICY IF EXISTS "Customers can delete their own notifications" ON customer_notifications;
DROP POLICY IF EXISTS "Service role can insert notifications" ON customer_notifications;
DROP POLICY IF EXISTS "Service role can view all notifications" ON customer_notifications;
DROP POLICY IF EXISTS "Service role can update all notifications" ON customer_notifications;
DROP POLICY IF EXISTS "Service role can delete all notifications" ON customer_notifications;

-- ========================================================================
-- 6. Create RLS Policies
-- ========================================================================

CREATE POLICY "Customers can view their own notifications"
ON customer_notifications FOR SELECT TO authenticated
USING (auth.uid()::text = customer_id);

CREATE POLICY "Customers can insert their own notifications"
ON customer_notifications FOR INSERT TO authenticated
WITH CHECK (auth.uid()::text = customer_id);

CREATE POLICY "Customers can update their own notifications"
ON customer_notifications FOR UPDATE TO authenticated
USING (auth.uid()::text = customer_id)
WITH CHECK (auth.uid()::text = customer_id);

CREATE POLICY "Customers can delete their own notifications"
ON customer_notifications FOR DELETE TO authenticated
USING (auth.uid()::text = customer_id);

-- Service role policies (for Edge Functions and backend)
CREATE POLICY "Service role can insert notifications"
ON customer_notifications FOR INSERT TO service_role
WITH CHECK (true);

CREATE POLICY "Service role can view all notifications"
ON customer_notifications FOR SELECT TO service_role
USING (true);

CREATE POLICY "Service role can update all notifications"
ON customer_notifications FOR UPDATE TO service_role
USING (true);

CREATE POLICY "Service role can delete all notifications"
ON customer_notifications FOR DELETE TO service_role
USING (true);

-- ========================================================================
-- 7. Create trigger for updated_at
-- ========================================================================

CREATE OR REPLACE FUNCTION update_customer_notifications_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_customer_notifications_updated_at ON customer_notifications;
CREATE TRIGGER update_customer_notifications_updated_at
    BEFORE UPDATE ON customer_notifications
    FOR EACH ROW
    EXECUTE FUNCTION update_customer_notifications_updated_at();

-- ========================================================================
-- 8. Add comments
-- ========================================================================

COMMENT ON TABLE customer_notifications IS 'Customer notifications table. Stores all in-app notifications for customers.';
COMMENT ON COLUMN customer_notifications.id IS 'Notification ID (text format for compatibility)';
COMMENT ON COLUMN customer_notifications.customer_id IS 'Foreign key to customers table (uid)';
COMMENT ON COLUMN customer_notifications.timestamp IS 'Unix timestamp in milliseconds when the notification was created';
COMMENT ON COLUMN customer_notifications.fcm_sent IS 'Whether FCM push notification was already sent. Prevents duplicate notifications.';

-- ========================================================================
-- Done! The table is now ready with fcm_sent column
-- ========================================================================

