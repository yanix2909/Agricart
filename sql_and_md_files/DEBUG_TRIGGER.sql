-- ========================================================================
-- Debug script to check if trigger is set up correctly
-- ========================================================================

-- 1. Check if HTTP extension is enabled
SELECT * FROM pg_extension WHERE extname = 'http';

-- 2. Check if trigger exists
SELECT 
    tgname as trigger_name,
    tgrelid::regclass as table_name,
    tgenabled as enabled
FROM pg_trigger 
WHERE tgname = 'trigger_send_fcm_notification_trigger';

-- 3. Check if function exists
SELECT 
    proname as function_name,
    prosrc as function_source
FROM pg_proc 
WHERE proname = 'trigger_send_fcm_notification';

-- 4. Check database settings
SELECT name, setting 
FROM pg_settings 
WHERE name LIKE 'app.settings%';

-- 5. Test the function manually (replace with actual notification data)
-- This will help us see if the function works
-- SELECT trigger_send_fcm_notification();

