-- SQL command to clear all chat message records from the chat_messages table
-- Run this in the Supabase SQL Editor
-- WARNING: This will permanently delete ALL chat message records. Use only during development or for resetting data!

-- Option 1: TRUNCATE (Recommended - faster and resets sequences)
-- This removes all rows and resets any auto-increment sequences
-- Note: TRUNCATE cannot be used if there are foreign key constraints referencing this table
TRUNCATE TABLE chat_messages;

-- Option 2: DELETE (Alternative - works with foreign keys)
-- Use this if TRUNCATE fails due to foreign key constraints
-- Uncomment the line below if you need to use DELETE instead:
-- DELETE FROM chat_messages;

-- Optional: Also clear conversations table if you want to reset all conversations
-- Uncomment the lines below if you also want to clear conversations:
-- TRUNCATE TABLE conversations;
-- Or use DELETE if TRUNCATE fails:
-- DELETE FROM conversations;

-- Verify the table is empty (optional check)
-- SELECT COUNT(*) FROM chat_messages;

