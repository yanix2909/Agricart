-- SQL command to add birthday column to customers table in Supabase
-- Run this in the Supabase SQL Editor

-- Add birthday column (stored as DATE type)
ALTER TABLE customers 
ADD COLUMN IF NOT EXISTS birthday DATE;

-- Add comment for documentation
COMMENT ON COLUMN customers.birthday IS 'Customer birthday stored as DATE type';

