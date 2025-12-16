-- ========================================================================
-- Disable RLS on customer_fcm_tokens and customer_notifications tables
-- ========================================================================
-- This allows inserts without authentication checks
-- Use this if RLS policies are blocking operations

-- Disable RLS on customer_fcm_tokens
ALTER TABLE customer_fcm_tokens DISABLE ROW LEVEL SECURITY;

-- Disable RLS on customer_notifications
ALTER TABLE customer_notifications DISABLE ROW LEVEL SECURITY;

-- Option 2: Keep RLS enabled but allow all operations (if you want to keep RLS structure)
-- Uncomment the lines below if you prefer this approach:

-- Drop all existing policies
-- DROP POLICY IF EXISTS "Customers can view their own FCM tokens" ON customer_fcm_tokens;
-- DROP POLICY IF EXISTS "Customers can insert their own FCM tokens" ON customer_fcm_tokens;
-- DROP POLICY IF EXISTS "Customers can update their own FCM tokens" ON customer_fcm_tokens;
-- DROP POLICY IF EXISTS "Customers can delete their own FCM tokens" ON customer_fcm_tokens;
-- DROP POLICY IF EXISTS "Service role can view all FCM tokens" ON customer_fcm_tokens;
-- DROP POLICY IF EXISTS "Service role can insert FCM tokens" ON customer_fcm_tokens;
-- DROP POLICY IF EXISTS "Service role can update FCM tokens" ON customer_fcm_tokens;
-- DROP POLICY IF EXISTS "Service role can delete FCM tokens" ON customer_fcm_tokens;

-- Create permissive policies that allow all operations
-- CREATE POLICY "Allow all operations on FCM tokens"
-- ON customer_fcm_tokens FOR ALL
-- TO public
-- USING (true)
-- WITH CHECK (true);

-- Verify RLS is disabled for both tables
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE tablename IN ('customer_fcm_tokens', 'customer_notifications')
ORDER BY tablename;

-- Should show: rowsecurity = false for both tables

