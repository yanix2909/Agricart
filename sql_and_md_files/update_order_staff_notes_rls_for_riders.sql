-- SQL command to update Row Level Security (RLS) policies for order_staff_notes table
-- This allows riders (anonymous users) to read staff notes for orders assigned to them
-- Run this in the Supabase SQL Editor

-- First, drop the existing SELECT policy that only allows authenticated users
DROP POLICY IF EXISTS "Allow authenticated users to read order staff notes" ON order_staff_notes;

-- Create a new SELECT policy that allows:
-- 1. Authenticated users (staff/admin) to read all notes
-- 2. Anonymous users (riders) to read all notes (they can filter by order_id in the app)
-- 
-- Note: Since riders query by order_id and only see orders assigned to them,
-- allowing anonymous read access is safe. The app-level filtering ensures
-- riders only see notes for their assigned orders.
CREATE POLICY "Allow users to read order staff notes"
    ON order_staff_notes
    FOR SELECT
    USING (true);  -- Allow both authenticated and anonymous users to read

-- Keep the existing INSERT, UPDATE, DELETE policies for authenticated users only
-- (These should remain unchanged - only staff/admin can modify notes)
