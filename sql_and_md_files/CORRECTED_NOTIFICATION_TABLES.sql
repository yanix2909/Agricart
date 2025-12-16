-- ========================================================================
-- CORRECTED SQL for customer_notifications and customer_fcm_tokens tables
-- ========================================================================
-- These corrections ensure compatibility with the Flutter app code

-- ========================================================================
-- 1. customer_notifications table
-- ========================================================================
-- The original SQL is mostly correct, but ensure id is TEXT or UUID

CREATE TABLE IF NOT EXISTS customer_notifications (
    -- Primary Key (UUID as TEXT or UUID type - both work)
    id TEXT PRIMARY KEY,  -- Changed from UUID to TEXT to match app code expectations
    
    -- Foreign Key to customers table
    customer_id TEXT NOT NULL REFERENCES customers(uid) ON DELETE CASCADE,
    
    -- Notification Content
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    type TEXT NOT NULL DEFAULT 'notification',
    
    -- Notification Metadata
    order_id TEXT,  -- Optional: related order ID if notification is order-related
    is_read BOOLEAN DEFAULT FALSE,
    
    -- Timestamp (Unix timestamp in milliseconds)
    timestamp BIGINT NOT NULL,
    
    -- Timestamps for tracking
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes for faster lookups
CREATE INDEX IF NOT EXISTS idx_customer_notifications_customer_id ON customer_notifications(customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_notifications_customer_timestamp ON customer_notifications(customer_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_customer_notifications_is_read ON customer_notifications(customer_id, is_read) WHERE is_read = FALSE;
CREATE INDEX IF NOT EXISTS idx_customer_notifications_type ON customer_notifications(customer_id, type);
CREATE INDEX IF NOT EXISTS idx_customer_notifications_order_id ON customer_notifications(order_id) WHERE order_id IS NOT NULL;

-- Add comments
COMMENT ON TABLE customer_notifications IS 'Customer notifications table migrated from Firebase. Stores all in-app notifications for customers.';
COMMENT ON COLUMN customer_notifications.id IS 'Notification ID (text format for compatibility)';
COMMENT ON COLUMN customer_notifications.customer_id IS 'Foreign key to customers table (uid)';
COMMENT ON COLUMN customer_notifications.timestamp IS 'Unix timestamp in milliseconds when the notification was created';

-- Enable Row Level Security (RLS)
ALTER TABLE customer_notifications ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (to avoid errors on re-run)
DROP POLICY IF EXISTS "Customers can view their own notifications" ON customer_notifications;
DROP POLICY IF EXISTS "Customers can insert their own notifications" ON customer_notifications;
DROP POLICY IF EXISTS "Customers can update their own notifications" ON customer_notifications;
DROP POLICY IF EXISTS "Customers can delete their own notifications" ON customer_notifications;
DROP POLICY IF EXISTS "Service role can insert notifications" ON customer_notifications;
DROP POLICY IF EXISTS "Service role can view all notifications" ON customer_notifications;
DROP POLICY IF EXISTS "Service role can update all notifications" ON customer_notifications;
DROP POLICY IF EXISTS "Service role can delete all notifications" ON customer_notifications;

-- RLS Policies (same as your original)
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

-- Service role policies
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

-- Trigger for updated_at
CREATE OR REPLACE FUNCTION update_customer_notifications_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop trigger if exists, then create
DROP TRIGGER IF EXISTS update_customer_notifications_updated_at ON customer_notifications;
CREATE TRIGGER update_customer_notifications_updated_at
    BEFORE UPDATE ON customer_notifications
    FOR EACH ROW
    EXECUTE FUNCTION update_customer_notifications_updated_at();

-- ========================================================================
-- 2. customer_fcm_tokens table
-- ========================================================================
-- IMPORTANT: Added UNIQUE constraint on customer_id for upsert to work correctly

CREATE TABLE IF NOT EXISTS customer_fcm_tokens (
    -- Primary Key (auto-generated UUID)
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Foreign Key to customers table
    -- CRITICAL: Added UNIQUE constraint so upsert with onConflict works
    customer_id TEXT NOT NULL UNIQUE REFERENCES customers(uid) ON DELETE CASCADE,
    
    -- FCM Token
    fcm_token TEXT NOT NULL UNIQUE,  -- FCM device token (unique per device)
    
    -- Device Information (optional, for better token management)
    device_type TEXT,  -- 'android', 'ios', 'web', etc.
    device_info TEXT,  -- Additional device information (optional JSON string)
    
    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    last_used_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_customer_fcm_tokens_customer_id ON customer_fcm_tokens(customer_id);
CREATE INDEX IF NOT EXISTS idx_customer_fcm_tokens_fcm_token ON customer_fcm_tokens(fcm_token);
CREATE INDEX IF NOT EXISTS idx_customer_fcm_tokens_last_used ON customer_fcm_tokens(customer_id, last_used_at DESC);

-- Add comments
COMMENT ON TABLE customer_fcm_tokens IS 'Customer FCM tokens table. Stores device tokens for push notifications.';
COMMENT ON COLUMN customer_fcm_tokens.customer_id IS 'Foreign key to customers table (uid) - UNIQUE to allow one token per customer';
COMMENT ON COLUMN customer_fcm_tokens.fcm_token IS 'Firebase Cloud Messaging device token (unique per device)';

-- Enable RLS
ALTER TABLE customer_fcm_tokens ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (to avoid errors on re-run)
DROP POLICY IF EXISTS "Customers can view their own FCM tokens" ON customer_fcm_tokens;
DROP POLICY IF EXISTS "Customers can insert their own FCM tokens" ON customer_fcm_tokens;
DROP POLICY IF EXISTS "Customers can update their own FCM tokens" ON customer_fcm_tokens;
DROP POLICY IF EXISTS "Customers can delete their own FCM tokens" ON customer_fcm_tokens;
DROP POLICY IF EXISTS "Service role can view all FCM tokens" ON customer_fcm_tokens;
DROP POLICY IF EXISTS "Service role can insert FCM tokens" ON customer_fcm_tokens;
DROP POLICY IF EXISTS "Service role can update FCM tokens" ON customer_fcm_tokens;
DROP POLICY IF EXISTS "Service role can delete FCM tokens" ON customer_fcm_tokens;

-- RLS Policies (same as your original)
CREATE POLICY "Customers can view their own FCM tokens"
ON customer_fcm_tokens FOR SELECT TO authenticated
USING (auth.uid()::text = customer_id);

CREATE POLICY "Customers can insert their own FCM tokens"
ON customer_fcm_tokens FOR INSERT TO authenticated
WITH CHECK (auth.uid()::text = customer_id);

CREATE POLICY "Customers can update their own FCM tokens"
ON customer_fcm_tokens FOR UPDATE TO authenticated
USING (auth.uid()::text = customer_id)
WITH CHECK (auth.uid()::text = customer_id);

CREATE POLICY "Customers can delete their own FCM tokens"
ON customer_fcm_tokens FOR DELETE TO authenticated
USING (auth.uid()::text = customer_id);

-- Service role policies
CREATE POLICY "Service role can view all FCM tokens"
ON customer_fcm_tokens FOR SELECT TO service_role
USING (true);

CREATE POLICY "Service role can insert FCM tokens"
ON customer_fcm_tokens FOR INSERT TO service_role
WITH CHECK (true);

CREATE POLICY "Service role can update FCM tokens"
ON customer_fcm_tokens FOR UPDATE TO service_role
USING (true);

CREATE POLICY "Service role can delete FCM tokens"
ON customer_fcm_tokens FOR DELETE TO service_role
USING (true);

-- Trigger for updated_at and last_used_at
CREATE OR REPLACE FUNCTION update_customer_fcm_tokens_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    NEW.last_used_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop trigger if exists, then create
DROP TRIGGER IF EXISTS update_customer_fcm_tokens_updated_at ON customer_fcm_tokens;
CREATE TRIGGER update_customer_fcm_tokens_updated_at
    BEFORE UPDATE ON customer_fcm_tokens
    FOR EACH ROW
    EXECUTE FUNCTION update_customer_fcm_tokens_updated_at();

-- ========================================================================
-- 3. Push Notification Trigger (OPTIONAL - for backend integration)
-- ========================================================================
-- Note: This requires the http extension and a backend service
-- You can skip this if you'll handle push notifications differently

-- Enable http extension (if you want to use the trigger approach)
-- CREATE EXTENSION IF NOT EXISTS http;

-- Function to send push notification via HTTP endpoint
-- CREATE OR REPLACE FUNCTION send_push_notification()
-- RETURNS TRIGGER AS $$
-- DECLARE
--   fcm_token_record RECORD;
--   notification_payload JSONB;
-- BEGIN
--   IF TG_OP = 'INSERT' THEN
--     SELECT fcm_token INTO fcm_token_record
--     FROM customer_fcm_tokens
--     WHERE customer_id = NEW.customer_id
--     ORDER BY last_used_at DESC
--     LIMIT 1;
--
--     IF fcm_token_record IS NOT NULL AND fcm_token_record.fcm_token IS NOT NULL THEN
--       notification_payload := jsonb_build_object(
--         'customer_id', NEW.customer_id,
--         'notification_id', NEW.id::text,
--         'fcm_token', fcm_token_record.fcm_token,
--         'title', NEW.title,
--         'body', NEW.message,
--         'type', NEW.type,
--         'order_id', NEW.order_id,
--         'timestamp', NEW.timestamp
--       );
--
--       -- Call your backend service (Supabase Edge Function or other)
--       -- PERFORM http_post(
--       --   'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-push-notification',
--       --   notification_payload::text,
--       --   'application/json'
--       -- );
--
--       RAISE NOTICE 'Push notification trigger fired for customer % notification %', NEW.customer_id, NEW.id;
--     END IF;
--   END IF;
--   RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger (commented out - enable if using trigger approach)
-- CREATE TRIGGER trigger_send_push_notification
--   AFTER INSERT ON customer_notifications
--   FOR EACH ROW
--   EXECUTE FUNCTION send_push_notification();

