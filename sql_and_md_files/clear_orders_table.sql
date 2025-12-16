-- SQL command to clear all order records from the orders table
-- Run this in the Supabase SQL Editor
-- WARNING: This will permanently delete ALL order records. Use only during development!

-- Option 1: TRUNCATE (Recommended - faster and resets sequences)
-- This removes all rows and resets any auto-increment sequences
-- Note: TRUNCATE cannot be used if there are foreign key constraints referencing this table
TRUNCATE TABLE orders;

-- Option 2: DELETE (Alternative - works with foreign keys)
-- Use this if TRUNCATE fails due to foreign key constraints
-- Uncomment the line below if you need to use DELETE instead:
-- DELETE FROM orders;

-- Optional: Reset any sequences if you have auto-incrementing IDs
-- Uncomment and modify if needed (replace 'orders_id_seq' with your actual sequence name):
-- ALTER SEQUENCE orders_id_seq RESTART WITH 1;

-- Verify the table is empty (optional check)
-- SELECT COUNT(*) FROM orders;

