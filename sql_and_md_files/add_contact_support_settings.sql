-- Add Contact Support Settings to system_data table
-- This stores the cooperative's contact information (gmail and phone number)
-- Used for display on customer app login and contact pages

-- STEP 1: Add columns if they don't exist (MUST BE FIRST)
DO $$ 
BEGIN
    -- Add support_email column if it doesn't exist
    BEGIN
        ALTER TABLE system_data ADD COLUMN support_email TEXT;
    EXCEPTION
        WHEN duplicate_column THEN
            -- Column already exists, do nothing
            NULL;
    END;
    
    -- Add support_phone column if it doesn't exist
    BEGIN
        ALTER TABLE system_data ADD COLUMN support_phone TEXT;
    EXCEPTION
        WHEN duplicate_column THEN
            -- Column already exists, do nothing
            NULL;
    END;
END $$;

-- STEP 2: Insert or update contact support settings row
INSERT INTO system_data (id, support_email, support_phone, epoch_ms, updated_at)
VALUES (
    'contactSupport',
    'calcoacoop@gmail.com', -- Default email
    '+63 123 456 7890', -- Default phone number
    EXTRACT(EPOCH FROM NOW())::BIGINT * 1000,
    EXTRACT(EPOCH FROM NOW())::BIGINT * 1000
)
ON CONFLICT (id) DO UPDATE SET
    support_email = COALESCE(system_data.support_email, EXCLUDED.support_email),
    support_phone = COALESCE(system_data.support_phone, EXCLUDED.support_phone),
    updated_at = EXCLUDED.updated_at;

-- Ensure public read access (already set by create_system_data_table.sql, but included for completeness)
-- This allows the customer app to read contact support information

COMMENT ON COLUMN system_data.support_email IS 'Cooperative support email for customer inquiries';
COMMENT ON COLUMN system_data.support_phone IS 'Cooperative support phone number for customer inquiries';

