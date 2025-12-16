-- SQL command to add password column to admins table in Supabase
-- Run this in the Supabase SQL Editor

-- Add password column (plain text, matching staff table implementation)
ALTER TABLE admins 
ADD COLUMN IF NOT EXISTS password TEXT;

-- Add comment to column for documentation
COMMENT ON COLUMN admins.password IS 'Admin login password (plain text, same as staff table)';

-- Create index on email if it doesn't exist (for faster login lookups)
CREATE INDEX IF NOT EXISTS idx_admins_email ON admins(email);

-- After running this, update existing admin records with their passwords:
-- UPDATE admins SET password = 'your_admin_password' WHERE email = 'admin@agricart.com';

