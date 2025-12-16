-- ========================================================================
-- Debug FCM Token Issue
-- ========================================================================

-- 1. Check if table exists and has data
SELECT COUNT(*) as token_count FROM customer_fcm_tokens;
SELECT * FROM customer_fcm_tokens WHERE customer_id = '9255a3d2-5cf6-47fb-950a-358006fd5c02';

-- 2. Check RLS policies
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE tablename = 'customer_fcm_tokens';

-- 3. Check if RLS is enabled
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE tablename = 'customer_fcm_tokens';

-- 4. Test manual insert (replace with actual FCM token from app logs)
-- This will help identify if it's an RLS issue
-- Run this as the authenticated user (from app) or with service role

-- Example (replace YOUR_FCM_TOKEN with actual token):
-- INSERT INTO customer_fcm_tokens (customer_id, fcm_token, device_type, last_used_at)
-- VALUES (
--   '9255a3d2-5cf6-47fb-950a-358006fd5c02',
--   'YOUR_FCM_TOKEN_HERE',
--   'android',
--   NOW()
-- )
-- ON CONFLICT (customer_id) 
-- DO UPDATE SET 
--   fcm_token = EXCLUDED.fcm_token,
--   last_used_at = NOW();

-- 5. Check if customer exists
SELECT uid, email FROM customers WHERE uid = '9255a3d2-5cf6-47fb-950a-358006fd5c02';

-- 6. Check auth users (if you have access)
-- SELECT id, email FROM auth.users WHERE id = '9255a3d2-5cf6-47fb-950a-358006fd5c02';

