-- SQL command to set up Row Level Security (RLS) policies for order_staff_notes table
-- Run this in the Supabase SQL Editor after creating the table
-- This ensures only authorized staff/admin can access and modify notes

-- Enable RLS on the table
ALTER TABLE order_staff_notes ENABLE ROW LEVEL SECURITY;

-- Policy 1: Allow SELECT (read) for authenticated users
-- Staff/admin should be able to read all notes for orders they have access to
CREATE POLICY "Allow authenticated users to read order staff notes"
    ON order_staff_notes
    FOR SELECT
    TO authenticated
    USING (true);

-- Policy 2: Allow INSERT (create) for authenticated users
-- Staff/admin can add new notes
CREATE POLICY "Allow authenticated users to insert order staff notes"
    ON order_staff_notes
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- Policy 3: Allow UPDATE for authenticated users
-- Staff/admin can update their own notes or any notes (depending on your business logic)
-- For now, allowing all authenticated users to update any note
-- You can restrict this further if needed (e.g., only allow updating own notes)
CREATE POLICY "Allow authenticated users to update order staff notes"
    ON order_staff_notes
    FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);

-- Policy 4: Allow DELETE for authenticated users
-- Staff/admin can delete notes
CREATE POLICY "Allow authenticated users to delete order staff notes"
    ON order_staff_notes
    FOR DELETE
    TO authenticated
    USING (true);

-- Note: If you want to restrict updates/deletes to only the creator or specific roles,
-- you can modify the policies. For example:
-- 
-- To only allow updating/deleting own notes:
-- CREATE POLICY "Allow users to update own notes"
--     ON order_staff_notes
--     FOR UPDATE
--     TO authenticated
--     USING (noted_by_name = current_setting('app.current_user_name', true))
--     WITH CHECK (true);
--
-- To only allow admins to delete:
-- CREATE POLICY "Allow admins to delete notes"
--     ON order_staff_notes
--     FOR DELETE
--     TO authenticated
--     USING (current_setting('app.current_user_role', true) = 'Admin');
