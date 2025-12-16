-- Create riders table in Supabase
CREATE TABLE IF NOT EXISTS riders (
    -- Primary Key
    uid TEXT PRIMARY KEY,
    
    -- Personal Information
    first_name TEXT NOT NULL,
    middle_name TEXT,
    last_name TEXT NOT NULL,
    suffix TEXT,
    full_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    phone_number TEXT NOT NULL,
    gender TEXT,
    birth_date BIGINT,
    
    -- Address Information
    street TEXT,
    sitio TEXT,
    barangay TEXT,
    city TEXT NOT NULL,
    province TEXT NOT NULL,
    postal_code TEXT,
    address TEXT NOT NULL,
    
    -- ID Information
    id_type TEXT,
    id_number TEXT,
    id_front_photo TEXT,
    id_back_photo TEXT,
    id_verified BOOLEAN DEFAULT FALSE,
    
    -- Vehicle Information
    vehicle_type TEXT,
    vehicle_number TEXT,
    license_number TEXT,
    
    -- Account Information
    login_password_hash TEXT NOT NULL,
    status TEXT DEFAULT 'pending',
    is_active BOOLEAN DEFAULT TRUE,
    is_online BOOLEAN DEFAULT FALSE,
    total_deliveries INTEGER DEFAULT 0,
    
    -- Metadata
    created_at BIGINT NOT NULL,
    created_by TEXT
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_riders_email ON riders(email);
CREATE INDEX IF NOT EXISTS idx_riders_phone_number ON riders(phone_number);
CREATE INDEX IF NOT EXISTS idx_riders_status ON riders(status);
CREATE INDEX IF NOT EXISTS idx_riders_is_active ON riders(is_active);
CREATE INDEX IF NOT EXISTS idx_riders_is_online ON riders(is_online);
CREATE INDEX IF NOT EXISTS idx_riders_created_at ON riders(created_at);

-- Add comments to columns for documentation
COMMENT ON TABLE riders IS 'Rider accounts table for delivery service';
COMMENT ON COLUMN riders.uid IS 'Unique identifier for the rider';
COMMENT ON COLUMN riders.login_password_hash IS 'SHA256 hash of the login password';
COMMENT ON COLUMN riders.created_at IS 'Unix timestamp in milliseconds when the rider account was created';
COMMENT ON COLUMN riders.birth_date IS 'Unix timestamp in milliseconds for birth date';
COMMENT ON COLUMN riders.id_front_photo IS 'URL to the front photo of the valid ID';
COMMENT ON COLUMN riders.id_back_photo IS 'URL to the back photo of the valid ID';

