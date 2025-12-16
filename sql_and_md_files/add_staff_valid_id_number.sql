-- Add valid_id_number column to staff table
ALTER TABLE staff 
ADD COLUMN IF NOT EXISTS valid_id_number TEXT;

-- Add comment to column for documentation
COMMENT ON COLUMN staff.valid_id_number IS 'Valid ID number corresponding to the valid_id_type';

