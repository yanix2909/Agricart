-- SQL command to add last_updated_by_name and last_updated_by_role columns to the staff table
-- Run this in the Supabase SQL Editor
-- This adds columns to track who last updated each staff account

-- Full name of the staff/admin who last updated the account
ALTER TABLE staff
ADD COLUMN IF NOT EXISTS last_updated_by_name TEXT;

COMMENT ON COLUMN staff.last_updated_by_name IS 'Full name of the staff/admin who last updated the staff account';

-- Role/title of the updater (e.g., Administrator, Staff)
ALTER TABLE staff
ADD COLUMN IF NOT EXISTS last_updated_by_role TEXT;

COMMENT ON COLUMN staff.last_updated_by_role IS 'Role/title of the staff/admin who last updated the staff account';

-- Create index for better query performance
CREATE INDEX IF NOT EXISTS idx_staff_last_updated_by_name ON staff(last_updated_by_name);

