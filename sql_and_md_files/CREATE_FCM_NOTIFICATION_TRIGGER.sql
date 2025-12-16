-- ========================================================================
-- Database Trigger to call Supabase Edge Function when notification is inserted
-- ========================================================================
-- This trigger calls the send-fcm-notification Edge Function via HTTP
-- Note: Requires the http extension to be enabled in Supabase

-- Enable http extension (if not already enabled)
CREATE EXTENSION IF NOT EXISTS http;

-- Function to call Edge Function via HTTP
CREATE OR REPLACE FUNCTION trigger_send_fcm_notification()
RETURNS TRIGGER AS $$
DECLARE
  edge_function_url TEXT;
  supabase_anon_key TEXT;
  response_status INT;
  response_content TEXT;
BEGIN
  -- Only process if fcm_sent is false (not already sent)
  IF NEW.fcm_sent = TRUE THEN
    RETURN NEW;
  END IF;

  -- Get Supabase project URL and anon key from environment
  -- These should be set in Supabase project settings
  -- For now, we'll construct the URL from the current database
  -- In production, you might want to store these in a config table
  
  -- Get the project reference from current_database() or use a config
  -- For Supabase, the URL format is: https://{project_ref}.supabase.co
  -- We'll use pg_settings or a simpler approach
  
  -- Construct Edge Function URL
  -- Note: Replace {project_ref} with your actual Supabase project reference
  -- You can also use Supabase's built-in function to get the project URL
  edge_function_url := current_setting('app.settings.supabase_url', true) || '/functions/v1/send-fcm-notification';
  
  -- If the setting is not available, try to construct from database name
  -- Supabase databases are named like: postgres.{project_ref}
  IF edge_function_url IS NULL OR edge_function_url = '/functions/v1/send-fcm-notification' THEN
    -- Fallback: construct from database name
    -- This is a workaround - in production, set app.settings.supabase_url
    DECLARE
      db_name TEXT;
      project_ref TEXT;
    BEGIN
      db_name := current_database();
      -- Extract project ref from database name (format: postgres.{ref})
      IF db_name LIKE 'postgres.%' THEN
        project_ref := substring(db_name from 'postgres\.(.+)');
        edge_function_url := 'https://' || project_ref || '.supabase.co/functions/v1/send-fcm-notification';
      ELSE
        -- If we can't determine, log and skip
        RAISE NOTICE 'Could not determine Supabase project URL, skipping FCM notification';
        RETURN NEW;
      END IF;
    END;
  END IF;

  -- Get anon key from settings (should be set in Supabase)
  supabase_anon_key := current_setting('app.settings.supabase_anon_key', true);
  
  IF supabase_anon_key IS NULL THEN
    -- Try to get from service role key setting
    supabase_anon_key := current_setting('app.settings.supabase_service_role_key', true);
  END IF;

  IF supabase_anon_key IS NULL THEN
    RAISE NOTICE 'Supabase anon key not configured, skipping FCM notification';
    RETURN NEW;
  END IF;

  -- Call Edge Function via HTTP
  SELECT status, content INTO response_status, response_content
  FROM http((
    'POST',
    edge_function_url,
    ARRAY[
      http_header('Content-Type', 'application/json'),
      http_header('Authorization', 'Bearer ' || supabase_anon_key),
      http_header('apikey', supabase_anon_key)
    ],
    'application/json',
    json_build_object('record', row_to_json(NEW))::text
  )::http_request);

  -- Log response (optional)
  IF response_status != 200 THEN
    RAISE WARNING 'Edge Function returned status %: %', response_status, response_content;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger
DROP TRIGGER IF EXISTS trigger_send_fcm_notification_trigger ON customer_notifications;
CREATE TRIGGER trigger_send_fcm_notification_trigger
  AFTER INSERT ON customer_notifications
  FOR EACH ROW
  WHEN (NEW.fcm_sent = FALSE)  -- Only trigger if fcm_sent is false
  EXECUTE FUNCTION trigger_send_fcm_notification();

-- Add comment
COMMENT ON FUNCTION trigger_send_fcm_notification() IS 'Triggers FCM notification via Edge Function when a new notification is inserted with fcm_sent = false';

