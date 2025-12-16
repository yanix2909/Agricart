-- ============================================================================
-- SQL commands to add updated_by_name and updated_by_role columns to products table
-- Run this in the Supabase SQL Editor
-- ============================================================================

-- Add updated_by_name and updated_by_role columns to the existing products table
ALTER TABLE products
ADD COLUMN IF NOT EXISTS updated_by_name TEXT,
ADD COLUMN IF NOT EXISTS updated_by_role TEXT;

-- Add comments for documentation
COMMENT ON COLUMN products.updated_by_name IS 'Full name of the staff member who last updated the product';
COMMENT ON COLUMN products.updated_by_role IS 'Role of the staff member who last updated the product (e.g., Administrator, Staff)';

