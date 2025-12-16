-- ========================================
-- Customer Rejection/Removal with Auth Cleanup
-- ========================================
-- This SQL function handles customer rejection and removal properly
-- It deletes the Supabase auth.users record so the email can be reused

-- Step 1: Create a function to delete auth user (requires service role)
-- Note: This must be run by a Supabase admin with service role permissions

CREATE OR REPLACE FUNCTION delete_customer_auth_user(customer_uid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Delete from auth.users table
    DELETE FROM auth.users WHERE id = customer_uid;
    
    -- Return success
    RETURN TRUE;
EXCEPTION
    WHEN OTHERS THEN
        -- Log error but don't fail the transaction
        RAISE WARNING 'Failed to delete auth user: %', SQLERRM;
        RETURN FALSE;
END;
$$;

-- Step 2: Create function to mark customer as rejected and clean up auth
CREATE OR REPLACE FUNCTION reject_customer_account(
    p_customer_uid UUID,
    p_rejection_reason TEXT,
    p_rejected_by UUID,
    p_rejected_by_name TEXT,
    p_rejected_by_role TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_customer_email TEXT;
    v_customer_name TEXT;
BEGIN
    -- Get customer details for email notification
    SELECT email, full_name INTO v_customer_email, v_customer_name
    FROM customers
    WHERE uid = p_customer_uid;
    
    IF v_customer_email IS NULL THEN
        RAISE EXCEPTION 'Customer not found';
    END IF;
    
    -- Update customer record with rejection info
    UPDATE customers
    SET 
        verification_status = 'rejected',
        account_status = 'inactive',
        status = 'inactive',
        rejection_reason = p_rejection_reason,
        rejected_at = EXTRACT(EPOCH FROM NOW()) * 1000,
        rejected_by = p_rejected_by,
        rejected_by_name = p_rejected_by_name,
        rejected_by_role = p_rejected_by_role,
        updated_at = EXTRACT(EPOCH FROM NOW()) * 1000
    WHERE uid = p_customer_uid;
    
    -- Store email info for notification (before deleting auth user)
    INSERT INTO customer_rejection_notifications (
        customer_uid,
        customer_email,
        customer_name,
        rejection_reason,
        rejected_by_name,
        rejected_by_role,
        created_at,
        notification_sent
    ) VALUES (
        p_customer_uid,
        v_customer_email,
        v_customer_name,
        p_rejection_reason,
        p_rejected_by_name,
        p_rejected_by_role,
        NOW(),
        FALSE
    );
    
    -- Delete auth user to allow email reuse
    PERFORM delete_customer_auth_user(p_customer_uid);
    
    RETURN TRUE;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to reject customer: %', SQLERRM;
        RETURN FALSE;
END;
$$;

-- Step 3: Create function to permanently remove customer and clean up auth
CREATE OR REPLACE FUNCTION remove_customer_account(
    p_customer_uid UUID,
    p_removal_reason TEXT,
    p_removed_by UUID,
    p_removed_by_name TEXT,
    p_removed_by_role TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_customer_email TEXT;
    v_customer_name TEXT;
BEGIN
    -- Get customer details for email notification
    SELECT email, full_name INTO v_customer_email, v_customer_name
    FROM customers
    WHERE uid = p_customer_uid;
    
    IF v_customer_email IS NULL THEN
        RAISE EXCEPTION 'Customer not found';
    END IF;
    
    -- Store notification info before deletion
    INSERT INTO customer_removal_notifications (
        customer_uid,
        customer_email,
        customer_name,
        removal_reason,
        removed_by_name,
        removed_by_role,
        created_at,
        notification_sent
    ) VALUES (
        p_customer_uid,
        v_customer_email,
        v_customer_name,
        p_removal_reason,
        p_removed_by_name,
        p_removed_by_role,
        NOW(),
        FALSE
    );
    
    -- Delete auth user first (to allow email reuse)
    PERFORM delete_customer_auth_user(p_customer_uid);
    
    -- Delete customer record
    DELETE FROM customers WHERE uid = p_customer_uid;
    
    RETURN TRUE;
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Failed to remove customer: %', SQLERRM;
        RETURN FALSE;
END;
$$;

-- Step 4: Create tables to store notification queue
CREATE TABLE IF NOT EXISTS customer_rejection_notifications (
    id BIGSERIAL PRIMARY KEY,
    customer_uid UUID NOT NULL,
    customer_email TEXT NOT NULL,
    customer_name TEXT NOT NULL,
    rejection_reason TEXT,
    rejected_by_name TEXT,
    rejected_by_role TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    notification_sent BOOLEAN DEFAULT FALSE,
    notification_sent_at TIMESTAMP WITH TIME ZONE,
    notification_error TEXT
);

CREATE INDEX IF NOT EXISTS idx_rejection_notifications_pending 
ON customer_rejection_notifications(notification_sent, created_at) 
WHERE notification_sent = FALSE;

CREATE TABLE IF NOT EXISTS customer_removal_notifications (
    id BIGSERIAL PRIMARY KEY,
    customer_uid UUID NOT NULL,
    customer_email TEXT NOT NULL,
    customer_name TEXT NOT NULL,
    removal_reason TEXT,
    removed_by_name TEXT,
    removed_by_role TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    notification_sent BOOLEAN DEFAULT FALSE,
    notification_sent_at TIMESTAMP WITH TIME ZONE,
    notification_error TEXT
);

CREATE INDEX IF NOT EXISTS idx_removal_notifications_pending 
ON customer_removal_notifications(notification_sent, created_at) 
WHERE notification_sent = FALSE;

-- Step 5: Grant execute permissions (adjust role as needed)
GRANT EXECUTE ON FUNCTION delete_customer_auth_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION reject_customer_account(UUID, TEXT, UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION remove_customer_account(UUID, TEXT, UUID, TEXT, TEXT) TO authenticated;

-- Step 6: Create function to get pending notifications
CREATE OR REPLACE FUNCTION get_pending_rejection_notifications()
RETURNS TABLE (
    id BIGINT,
    customer_email TEXT,
    customer_name TEXT,
    rejection_reason TEXT,
    rejected_by_name TEXT,
    rejected_by_role TEXT,
    created_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT 
        id,
        customer_email,
        customer_name,
        rejection_reason,
        rejected_by_name,
        rejected_by_role,
        created_at
    FROM customer_rejection_notifications
    WHERE notification_sent = FALSE
    ORDER BY created_at ASC
    LIMIT 100;
$$;

CREATE OR REPLACE FUNCTION get_pending_removal_notifications()
RETURNS TABLE (
    id BIGINT,
    customer_email TEXT,
    customer_name TEXT,
    removal_reason TEXT,
    removed_by_name TEXT,
    removed_by_role TEXT,
    created_at TIMESTAMP WITH TIME ZONE
)
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT 
        id,
        customer_email,
        customer_name,
        removal_reason,
        removed_by_name,
        removed_by_role,
        created_at
    FROM customer_removal_notifications
    WHERE notification_sent = FALSE
    ORDER BY created_at ASC
    LIMIT 100;
$$;

-- Step 7: Create function to mark notification as sent
CREATE OR REPLACE FUNCTION mark_rejection_notification_sent(p_notification_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
AS $$
    UPDATE customer_rejection_notifications
    SET 
        notification_sent = TRUE,
        notification_sent_at = NOW()
    WHERE id = p_notification_id;
    
    SELECT TRUE;
$$;

CREATE OR REPLACE FUNCTION mark_removal_notification_sent(p_notification_id BIGINT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
AS $$
    UPDATE customer_removal_notifications
    SET 
        notification_sent = TRUE,
        notification_sent_at = NOW()
    WHERE id = p_notification_id;
    
    SELECT TRUE;
$$;

-- ========================================
-- USAGE EXAMPLES
-- ========================================

-- Example 1: Reject a customer
/*
SELECT reject_customer_account(
    'customer-uuid-here'::UUID,
    'Invalid ID documents',
    'staff-uuid-here'::UUID,
    'John Staff',
    'Staff'
);
*/

-- Example 2: Remove a customer permanently
/*
SELECT remove_customer_account(
    'customer-uuid-here'::UUID,
    'Duplicate account',
    'admin-uuid-here'::UUID,
    'Admin Name',
    'Administrator'
);
*/

-- Example 3: Get pending notifications to send
/*
SELECT * FROM get_pending_rejection_notifications();
SELECT * FROM get_pending_removal_notifications();
*/

-- Example 4: Mark notification as sent
/*
SELECT mark_rejection_notification_sent(1);
*/

