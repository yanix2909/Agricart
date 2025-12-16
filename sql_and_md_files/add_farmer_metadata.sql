-- SQL command to extend farmers metadata with staff name + role tracking
-- Run this in the Supabase SQL Editor after the farmers table exists

ALTER TABLE farmers
ADD COLUMN IF NOT EXISTS created_by_role TEXT;
COMMENT ON COLUMN farmers.created_by_role IS 'Role/title of the staff/admin who registered the farmer';

ALTER TABLE farmers
ADD COLUMN IF NOT EXISTS updated_by_name TEXT;
COMMENT ON COLUMN farmers.updated_by_name IS 'Full name of the staff/admin who last updated the farmer record';

ALTER TABLE farmers
ADD COLUMN IF NOT EXISTS updated_by_role TEXT;
COMMENT ON COLUMN farmers.updated_by_role IS 'Role/title of the staff/admin who last updated the farmer record';

ALTER TABLE farmers
ADD COLUMN IF NOT EXISTS verified_by TEXT;
COMMENT ON COLUMN farmers.verified_by IS 'UID of the staff/admin who verified the farmer account';

ALTER TABLE farmers
ADD COLUMN IF NOT EXISTS verified_by_name TEXT;
COMMENT ON COLUMN farmers.verified_by_name IS 'Full name of the staff/admin who verified the farmer account';

ALTER TABLE farmers
ADD COLUMN IF NOT EXISTS verified_by_role TEXT;
COMMENT ON COLUMN farmers.verified_by_role IS 'Role/title of the staff/admin who verified the farmer account';

