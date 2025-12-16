-- Migration: Add phone_number column to delivery_addresses table
-- Run this in the Supabase SQL Editor if the column doesn't exist yet

-- Add phone_number column if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'delivery_addresses' 
        AND column_name = 'phone_number'
    ) THEN
        ALTER TABLE delivery_addresses 
        ADD COLUMN phone_number TEXT;
        
        COMMENT ON COLUMN delivery_addresses.phone_number IS 'Phone number associated with this delivery address';
        
        RAISE NOTICE 'phone_number column added to delivery_addresses table';
    ELSE
        RAISE NOTICE 'phone_number column already exists in delivery_addresses table';
    END IF;
END $$;

