-- SQL command to create the customers table in Supabase
-- Run this in the Supabase SQL Editor
-- This table matches the Firebase customers collection structure

CREATE TABLE IF NOT EXISTS customers (
    -- Primary Key (Firebase Auth UID)
    uid TEXT PRIMARY KEY,
    
    -- Basic Information
    email TEXT NOT NULL,
    full_name TEXT NOT NULL,
    first_name TEXT,
    last_name TEXT,
    middle_initial TEXT,
    suffix TEXT,
    username TEXT,
    age INTEGER,
    gender TEXT,
    
    -- Contact & Address
    phone_number TEXT,
    address TEXT,
    street TEXT,
    sitio TEXT,
    barangay TEXT,
    city TEXT DEFAULT 'Ormoc',
    state TEXT DEFAULT 'Leyte',
    zip_code TEXT,
    
    -- Profile
    profile_image_url TEXT,
    
    -- Account Status & Verification
    status TEXT DEFAULT 'active',
    account_status TEXT DEFAULT 'pending',
    verification_status TEXT DEFAULT 'pending',
    rejection_reason TEXT,
    verification_date BIGINT,
    verified_by TEXT,
    verified_by_name TEXT,
    verified_by_role TEXT,
    
    -- ID Verification
    id_type TEXT DEFAULT 'Not specified',
    id_front_photo TEXT,
    id_back_photo TEXT,
    
    -- Activity
    is_online BOOLEAN DEFAULT FALSE,
    last_seen BIGINT,
    has_logged_in_before BOOLEAN DEFAULT FALSE,
    
    -- Statistics
    total_orders INTEGER DEFAULT 0,
    total_spent NUMERIC(10, 2) DEFAULT 0.0,
    favorite_products TEXT[] DEFAULT '{}',
    
    -- Timestamps (Unix timestamp in milliseconds)
    created_at BIGINT NOT NULL,
    updated_at BIGINT NOT NULL,
    registration_date BIGINT
);

-- Create indexes for faster lookups and searches
CREATE INDEX IF NOT EXISTS idx_customers_email ON customers(email);
CREATE INDEX IF NOT EXISTS idx_customers_username ON customers(username);
CREATE INDEX IF NOT EXISTS idx_customers_phone_number ON customers(phone_number);
CREATE INDEX IF NOT EXISTS idx_customers_account_status ON customers(account_status);
CREATE INDEX IF NOT EXISTS idx_customers_verification_status ON customers(verification_status);
CREATE INDEX IF NOT EXISTS idx_customers_status ON customers(status);
CREATE INDEX IF NOT EXISTS idx_customers_created_at ON customers(created_at);
CREATE INDEX IF NOT EXISTS idx_customers_full_name ON customers(full_name);

-- Add comments to table and key columns for documentation
COMMENT ON TABLE customers IS 'Customer accounts table migrated from Firebase. Stores all customer registration and profile data.';
COMMENT ON COLUMN customers.uid IS 'Firebase Auth user ID - used as primary key';
COMMENT ON COLUMN customers.created_at IS 'Unix timestamp in milliseconds when the customer account was created';
COMMENT ON COLUMN customers.updated_at IS 'Unix timestamp in milliseconds when the customer account was last updated';
COMMENT ON COLUMN customers.registration_date IS 'Unix timestamp in milliseconds when the customer registered';
COMMENT ON COLUMN customers.last_seen IS 'Unix timestamp in milliseconds when the customer was last seen online';
COMMENT ON COLUMN customers.verification_date IS 'Unix timestamp in milliseconds when the customer account was verified';
COMMENT ON COLUMN customers.verified_by IS 'UID of the staff/admin who verified the customer account';
COMMENT ON COLUMN customers.verified_by_name IS 'Full name of the staff/admin who verified the customer account';
COMMENT ON COLUMN customers.verified_by_role IS 'Role/title of the reviewer who verified the customer account';
COMMENT ON COLUMN customers.favorite_products IS 'Array of product IDs that the customer has favorited';

