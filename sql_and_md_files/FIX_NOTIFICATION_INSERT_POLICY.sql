-- ========================================================================
-- QUICK FIX: Add missing INSERT policy for customer_notifications
-- ========================================================================
-- This policy allows authenticated users (customers) to insert their own notifications
-- Run this SQL in your Supabase SQL Editor immediately

-- Check if policy already exists and drop it if it does
DROP POLICY IF EXISTS "Customers can insert their own notifications" ON customer_notifications;

-- Create the INSERT policy for authenticated users
CREATE POLICY "Customers can insert their own notifications"
ON customer_notifications FOR INSERT TO authenticated
WITH CHECK (auth.uid()::text = customer_id);

-- Verify the policy was created
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
WHERE tablename = 'customer_notifications'
ORDER BY policyname;

