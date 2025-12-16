-- SQL command to add phone column to admins table in Supabase
-- Run this in the Supabase SQL Editor

-- Add phone column
ALTER TABLE admins 
ADD COLUMN IF NOT EXISTS phone TEXT;

-- Add comment to column for documentation
COMMENT ON COLUMN admins.phone IS 'Admin phone number';

