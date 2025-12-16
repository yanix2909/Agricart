-- ============================================================================
-- Fix RLS Policies for Conversations and Chat Messages
-- ============================================================================
-- This script ensures that conversations and chat_messages tables are accessible
-- to both authenticated users (customer app) and anonymous users (web dashboard)
-- Run this in the Supabase SQL Editor
-- ============================================================================

-- ============================================================================
-- CONVERSATIONS TABLE POLICIES
-- ============================================================================

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Allow public to read conversations" ON conversations;
DROP POLICY IF EXISTS "Allow public to insert conversations" ON conversations;
DROP POLICY IF EXISTS "Allow public to update conversations" ON conversations;
DROP POLICY IF EXISTS "Allow authenticated to read conversations" ON conversations;
DROP POLICY IF EXISTS "Allow authenticated to insert conversations" ON conversations;
DROP POLICY IF EXISTS "Allow authenticated to update conversations" ON conversations;

-- Enable RLS on conversations table
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

-- Policy: Allow public (anonymous) users to read conversations
-- This allows the web dashboard (using anon key) to read conversations
CREATE POLICY "Allow public to read conversations"
    ON conversations
    FOR SELECT
    TO public
    USING (true);

-- Policy: Allow authenticated users to read conversations
-- This allows the customer app (authenticated) to read conversations
CREATE POLICY "Allow authenticated to read conversations"
    ON conversations
    FOR SELECT
    TO authenticated
    USING (true);

-- Policy: Allow public (anonymous) users to insert conversations
-- This allows the web dashboard to create conversations
CREATE POLICY "Allow public to insert conversations"
    ON conversations
    FOR INSERT
    TO public
    WITH CHECK (true);

-- Policy: Allow authenticated users to insert conversations
-- This allows the customer app to create conversations
CREATE POLICY "Allow authenticated to insert conversations"
    ON conversations
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- Policy: Allow public (anonymous) users to update conversations
-- This allows the web dashboard to update conversations
CREATE POLICY "Allow public to update conversations"
    ON conversations
    FOR UPDATE
    TO public
    USING (true)
    WITH CHECK (true);

-- Policy: Allow authenticated users to update conversations
-- This allows the customer app to update conversations
CREATE POLICY "Allow authenticated to update conversations"
    ON conversations
    FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);

-- Policy: Allow public (anonymous) users to delete conversations
-- This allows the web dashboard to delete conversations
CREATE POLICY "Allow public to delete conversations"
    ON conversations
    FOR DELETE
    TO public
    USING (true);

-- Policy: Allow authenticated users to delete conversations
-- This allows the customer app to delete conversations
CREATE POLICY "Allow authenticated to delete conversations"
    ON conversations
    FOR DELETE
    TO authenticated
    USING (true);

-- ============================================================================
-- CHAT_MESSAGES TABLE POLICIES
-- ============================================================================

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Allow public to read chat_messages" ON chat_messages;
DROP POLICY IF EXISTS "Allow public to insert chat_messages" ON chat_messages;
DROP POLICY IF EXISTS "Allow public to update chat_messages" ON chat_messages;
DROP POLICY IF EXISTS "Allow authenticated to read chat_messages" ON chat_messages;
DROP POLICY IF EXISTS "Allow authenticated to insert chat_messages" ON chat_messages;
DROP POLICY IF EXISTS "Allow authenticated to update chat_messages" ON chat_messages;

-- Enable RLS on chat_messages table
ALTER TABLE chat_messages ENABLE ROW LEVEL SECURITY;

-- Policy: Allow public (anonymous) users to read chat_messages
-- This allows the web dashboard (using anon key) to read messages
CREATE POLICY "Allow public to read chat_messages"
    ON chat_messages
    FOR SELECT
    TO public
    USING (true);

-- Policy: Allow authenticated users to read chat_messages
-- This allows the customer app (authenticated) to read messages
CREATE POLICY "Allow authenticated to read chat_messages"
    ON chat_messages
    FOR SELECT
    TO authenticated
    USING (true);

-- Policy: Allow public (anonymous) users to insert chat_messages
-- This allows the web dashboard to send messages
CREATE POLICY "Allow public to insert chat_messages"
    ON chat_messages
    FOR INSERT
    TO public
    WITH CHECK (true);

-- Policy: Allow authenticated users to insert chat_messages
-- This allows the customer app to send messages
CREATE POLICY "Allow authenticated to insert chat_messages"
    ON chat_messages
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- Policy: Allow public (anonymous) users to update chat_messages
-- This allows the web dashboard to update messages (e.g., mark as read)
CREATE POLICY "Allow public to update chat_messages"
    ON chat_messages
    FOR UPDATE
    TO public
    USING (true)
    WITH CHECK (true);

-- Policy: Allow authenticated users to update chat_messages
-- This allows the customer app to update messages
CREATE POLICY "Allow authenticated to update chat_messages"
    ON chat_messages
    FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);

-- Policy: Allow public (anonymous) users to delete chat_messages
-- This allows the web dashboard to delete messages
CREATE POLICY "Allow public to delete chat_messages"
    ON chat_messages
    FOR DELETE
    TO public
    USING (true);

-- Policy: Allow authenticated users to delete chat_messages
-- This allows the customer app to delete messages
CREATE POLICY "Allow authenticated to delete chat_messages"
    ON chat_messages
    FOR DELETE
    TO authenticated
    USING (true);

-- ============================================================================
-- VERIFICATION
-- ============================================================================
-- After running this script, verify the policies exist:
-- SELECT * FROM pg_policies WHERE tablename IN ('conversations', 'chat_messages');
-- ============================================================================
