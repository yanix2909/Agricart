-- SQL command to track verifier metadata for approved customer accounts
-- Run this in the Supabase SQL Editor after deploying the customers table
-- Adds auditing fields so the Staff Dashboard can display who verified each customer

-- Full name of the staff/admin who verified the account
ALTER TABLE customers
ADD COLUMN IF NOT EXISTS verified_by_name TEXT;
COMMENT ON COLUMN customers.verified_by_name IS 'Full name of the staff/admin who verified the customer account';

-- Role/title of the verifier (e.g., Administrator, Staff)
ALTER TABLE customers
ADD COLUMN IF NOT EXISTS verified_by_role TEXT;
COMMENT ON COLUMN customers.verified_by_role IS 'Role/title of the reviewer who verified the customer account';

-- Optional index to quickly filter verified records by reviewer
CREATE INDEX IF NOT EXISTS idx_customers_verified_by ON customers(verified_by);


