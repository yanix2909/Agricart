-- SQL command to create the farmers table in Supabase
-- Run this in the Supabase SQL Editor

CREATE TABLE IF NOT EXISTS farmers (
    id BIGSERIAL PRIMARY KEY,
    uid TEXT UNIQUE NOT NULL,
    age INTEGER,
    birth_date DATE,
    created_at BIGINT NOT NULL,
    created_by TEXT,
    created_by_name TEXT,
    created_by_role TEXT,
    farm_location TEXT,
    farm_size NUMERIC(10, 2),
    full_name TEXT NOT NULL,
    gender TEXT,
    home_location TEXT,
    id_back_photo TEXT,
    id_front_photo TEXT,
    id_type TEXT,
    phone_number TEXT,
    updated_at BIGINT,
    updated_by TEXT,
    updated_by_name TEXT,
    updated_by_role TEXT,
    verified_by TEXT,
    verified_by_name TEXT,
    verified_by_role TEXT
);

-- Create index on uid for faster lookups
CREATE INDEX IF NOT EXISTS idx_farmers_uid ON farmers(uid);

-- Create index on phone_number for faster searches
CREATE INDEX IF NOT EXISTS idx_farmers_phone_number ON farmers(phone_number);

-- Create index on full_name for faster searches
CREATE INDEX IF NOT EXISTS idx_farmers_full_name ON farmers(full_name);

