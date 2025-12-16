-- SQL command to add customer_last_updated_at column to customers table
-- This column tracks when the customer last updated their own profile information
-- Run this in the Supabase SQL Editor

-- Add customer_last_updated_at column (Unix timestamp in milliseconds)
ALTER TABLE customers
ADD COLUMN IF NOT EXISTS customer_last_updated_at BIGINT;

-- Add comment for documentation
COMMENT ON COLUMN customers.customer_last_updated_at IS 'Unix timestamp in milliseconds when the customer last updated their own profile information (phone number, address, etc.). This is separate from updated_at which tracks all updates including admin/staff changes.';

-- Create index for faster queries and sorting
CREATE INDEX IF NOT EXISTS idx_customers_customer_last_updated_at ON customers(customer_last_updated_at);
