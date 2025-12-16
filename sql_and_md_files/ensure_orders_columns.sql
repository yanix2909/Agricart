-- SQL command to ensure all required columns exist in the orders table
-- Run this in the Supabase SQL Editor
-- This adds any missing columns needed for order placement

-- Core order columns
-- uid is the PRIMARY KEY (required, not-null)
ALTER TABLE orders ADD COLUMN IF NOT EXISTS uid TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS id TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS order_id TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_id TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_name TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_phone TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_address TEXT;

-- Amount columns
ALTER TABLE orders ADD COLUMN IF NOT EXISTS subtotal NUMERIC(10, 2);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_fee NUMERIC(10, 2);
ALTER TABLE orders ADD COLUMN IF NOT EXISTS total NUMERIC(10, 2);

-- Status and payment columns
ALTER TABLE orders ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'pending';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_method TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'pending';
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_option TEXT;

-- Address columns
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_address TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pickup_address TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pickup_name TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pickup_street TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pickup_sitio TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pickup_barangay TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pickup_city TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pickup_province TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pickup_landmark TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pickup_instructions TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pickup_map_link TEXT;

-- Date columns
ALTER TABLE orders ADD COLUMN IF NOT EXISTS order_date BIGINT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS created_at BIGINT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS updated_at BIGINT;

-- Items column (JSONB or JSON)
ALTER TABLE orders ADD COLUMN IF NOT EXISTS items JSONB;

-- GCash columns
ALTER TABLE orders ADD COLUMN IF NOT EXISTS gcash_receipt_url TEXT;

-- Farmer columns
ALTER TABLE orders ADD COLUMN IF NOT EXISTS farmer_id TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS farmer_name TEXT;

-- Cancellation columns (from previous migration)
ALTER TABLE orders ADD COLUMN IF NOT EXISTS cancellation_requested BOOLEAN DEFAULT FALSE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS cancellation_requested_at BIGINT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS cancellation_initiated_by TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS cancellation_reason TEXT;

-- Create primary key if it doesn't exist
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'orders_pkey'
    ) THEN
        -- Try to set uid as primary key (this is the required column)
        ALTER TABLE orders ADD PRIMARY KEY (uid);
    END IF;
EXCEPTION
    WHEN others THEN
        -- If uid doesn't work, try id
        BEGIN
            ALTER TABLE orders ADD PRIMARY KEY (id);
        EXCEPTION
            WHEN others THEN
                -- If id doesn't work, try order_id
                BEGIN
                    ALTER TABLE orders ADD PRIMARY KEY (order_id);
                EXCEPTION
                    WHEN others THEN
                        RAISE NOTICE 'Could not set primary key - table may already have one or columns are not unique';
                END;
        END;
END $$;

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_orders_customer_id ON orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at);
CREATE INDEX IF NOT EXISTS idx_orders_order_date ON orders(order_date);

