-- SQL command to track rejection metadata for customer accounts
-- Run this in the Supabase SQL Editor
-- Adds auditing fields so the Staff Dashboard can display rejected accounts

-- Timestamp (milliseconds) for when the account was rejected
ALTER TABLE customers
ADD COLUMN IF NOT EXISTS rejected_at BIGINT;
COMMENT ON COLUMN customers.rejected_at IS 'Unix timestamp (ms) of when the customer verification was rejected';

-- UID of the staff/admin who rejected the account
ALTER TABLE customers
ADD COLUMN IF NOT EXISTS rejected_by TEXT;
COMMENT ON COLUMN customers.rejected_by IS 'UID of the staff/admin who rejected the customer verification';

-- Full name of the staff/admin who rejected the account
ALTER TABLE customers
ADD COLUMN IF NOT EXISTS rejected_by_name TEXT;
COMMENT ON COLUMN customers.rejected_by_name IS 'Full name of the staff/admin who rejected the customer verification';

-- Role/title of the reviewer (e.g., Administrator, Staff)
ALTER TABLE customers
ADD COLUMN IF NOT EXISTS rejected_by_role TEXT;
COMMENT ON COLUMN customers.rejected_by_role IS 'Role/title of the reviewer who rejected the customer verification';

-- Optional index to quickly filter by rejection date
CREATE INDEX IF NOT EXISTS idx_customers_rejected_at ON customers(rejected_at);

