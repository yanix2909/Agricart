-- ========================================================================
-- Create customer_fcm_tokens table
-- ========================================================================
-- This table stores FCM tokens for push notifications

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

-- RLS Policies
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

-- Service role policies (for Edge Functions and backend)
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
-- Done! The customer_fcm_tokens table is now ready
-- ========================================================================

