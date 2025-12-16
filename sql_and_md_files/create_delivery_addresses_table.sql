-- SQL command to create the delivery_addresses table in Supabase
-- Run this in the Supabase SQL Editor
-- This table stores customer delivery addresses

CREATE TABLE IF NOT EXISTS delivery_addresses (
    -- Primary Key (auto-generated UUID)
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Foreign Key to customers table
    customer_id TEXT NOT NULL REFERENCES customers(uid) ON DELETE CASCADE,
    
    -- Address Information
    address TEXT NOT NULL,
    label TEXT NOT NULL DEFAULT 'Address',
    phone_number TEXT,
    
    -- Default Address Flag
    is_default BOOLEAN DEFAULT FALSE,
    
    -- Timestamps (Unix timestamp in milliseconds)
    created_at BIGINT NOT NULL,
    updated_at BIGINT NOT NULL
);

-- Create indexes for faster lookups
CREATE INDEX IF NOT EXISTS idx_delivery_addresses_customer_id ON delivery_addresses(customer_id);
CREATE INDEX IF NOT EXISTS idx_delivery_addresses_is_default ON delivery_addresses(customer_id, is_default) WHERE is_default = TRUE;

-- Add comments to table and key columns for documentation
COMMENT ON TABLE delivery_addresses IS 'Customer delivery addresses table. Stores multiple delivery addresses per customer.';
COMMENT ON COLUMN delivery_addresses.customer_id IS 'Foreign key to customers table (uid)';
COMMENT ON COLUMN delivery_addresses.is_default IS 'Flag indicating if this is the default delivery address for the customer';
COMMENT ON COLUMN delivery_addresses.created_at IS 'Unix timestamp in milliseconds when the address was created';
COMMENT ON COLUMN delivery_addresses.updated_at IS 'Unix timestamp in milliseconds when the address was last updated';

