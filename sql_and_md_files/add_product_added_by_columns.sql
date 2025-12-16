-- ============================================================================
-- SQL commands to add added_by, added_by_name, and added_by_role columns to products table
-- Run this in the Supabase SQL Editor
-- ============================================================================

-- Add added_by, added_by_name, and added_by_role columns to the existing products table
ALTER TABLE products
ADD COLUMN IF NOT EXISTS added_by TEXT,
ADD COLUMN IF NOT EXISTS added_by_name TEXT,
ADD COLUMN IF NOT EXISTS added_by_role TEXT;

-- Ensure updated_by_name and updated_by_role columns exist (in case they don't)
ALTER TABLE products
ADD COLUMN IF NOT EXISTS updated_by_name TEXT,
ADD COLUMN IF NOT EXISTS updated_by_role TEXT;

-- Add comments for documentation
COMMENT ON COLUMN products.added_by IS 'UID of the staff member who created/uploaded the product first';
COMMENT ON COLUMN products.added_by_name IS 'Full name of the staff member who created/uploaded the product first';
COMMENT ON COLUMN products.added_by_role IS 'Role of the staff member who created/uploaded the product first (e.g., Administrator, Staff)';
COMMENT ON COLUMN products.updated_by_name IS 'Full name of the staff member who last updated the product';
COMMENT ON COLUMN products.updated_by_role IS 'Role of the staff member who last updated the product (e.g., Administrator, Staff)';

-- For existing products, populate added_by fields from created_by if available
-- This ensures existing products have the added_by information
UPDATE products
SET 
  added_by = COALESCE(created_by, staff_id, 'system'),
  added_by_name = COALESCE(
    (SELECT name FROM staff WHERE uid = products.created_by LIMIT 1),
    (SELECT name FROM staff WHERE uid = products.staff_id LIMIT 1),
    'System'
  ),
  added_by_role = COALESCE(
    (SELECT role FROM staff WHERE uid = products.created_by LIMIT 1),
    (SELECT role FROM staff WHERE uid = products.staff_id LIMIT 1),
    'System'
  )
WHERE added_by IS NULL;

-- For existing products, populate updated_by_name and updated_by_role from updated_by if available
UPDATE products
SET 
  updated_by_name = COALESCE(
    updated_by_name,
    (SELECT name FROM staff WHERE uid = products.updated_by LIMIT 1),
    (SELECT name FROM admins WHERE uid = products.updated_by LIMIT 1)
  ),
  updated_by_role = COALESCE(
    updated_by_role,
    (SELECT role FROM staff WHERE uid = products.updated_by LIMIT 1),
    'Administrator'
  )
WHERE updated_by IS NOT NULL 
  AND (updated_by_name IS NULL OR updated_by_role IS NULL);

