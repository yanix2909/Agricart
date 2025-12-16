-- SQL command to create the products table in Supabase
-- Run this in the Supabase SQL Editor
-- This table matches the Firebase products collection structure

CREATE TABLE IF NOT EXISTS products (
    -- Primary Key (unique product ID)
    uid TEXT PRIMARY KEY,
    
    -- Core Product Information
    name TEXT NOT NULL,
    description TEXT NOT NULL,
    category TEXT NOT NULL,
    price NUMERIC(10, 2) NOT NULL,
    unit TEXT NOT NULL DEFAULT 'kg',
    harvest_date TEXT,
    
    -- Stock Management Fields
    available_quantity INTEGER DEFAULT 0,
    quantity INTEGER, -- Legacy field for backward compatibility
    current_reserved INTEGER DEFAULT 0,
    sold_quantity INTEGER DEFAULT 0,
    
    -- Image Fields
    image_url TEXT,
    image_urls TEXT[] DEFAULT '{}',
    images_stored BOOLEAN DEFAULT FALSE,
    
    -- Status & Availability
    status TEXT DEFAULT 'active',
    is_available BOOLEAN DEFAULT TRUE,
    
    -- Farmer/Staff Information
    farmer_id TEXT,
    farmer_name TEXT,
    created_by TEXT,
    staff_id TEXT,
    managed_by TEXT,
    updated_by TEXT,
    
    -- Ratings & Reviews
    rating NUMERIC(3, 2) DEFAULT 0.0,
    review_count INTEGER DEFAULT 0,
    
    -- Additional Fields
    tags TEXT[] DEFAULT '{}',
    location TEXT DEFAULT '',
    
    -- Timestamps (Unix timestamp in milliseconds)
    created_at BIGINT NOT NULL,
    updated_at BIGINT NOT NULL
);

-- Create indexes for faster lookups and searches
CREATE INDEX IF NOT EXISTS idx_products_name ON products(name);
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);
CREATE INDEX IF NOT EXISTS idx_products_status ON products(status);
CREATE INDEX IF NOT EXISTS idx_products_farmer_id ON products(farmer_id);
CREATE INDEX IF NOT EXISTS idx_products_created_at ON products(created_at);
CREATE INDEX IF NOT EXISTS idx_products_updated_at ON products(updated_at);
CREATE INDEX IF NOT EXISTS idx_products_is_available ON products(is_available);

-- Add comments to table and key columns for documentation
COMMENT ON TABLE products IS 'Products table migrated from Firebase. Stores all product information including stock, images, and metadata.';
COMMENT ON COLUMN products.uid IS 'Unique product ID - used as primary key';
COMMENT ON COLUMN products.available_quantity IS 'Base quantity set by staff - total available stock';
COMMENT ON COLUMN products.current_reserved IS 'Quantity currently reserved by pending orders';
COMMENT ON COLUMN products.sold_quantity IS 'Quantity from confirmed orders';
COMMENT ON COLUMN products.image_urls IS 'Array of all product image URLs (up to 5 images)';
COMMENT ON COLUMN products.created_at IS 'Unix timestamp in milliseconds when the product was created';
COMMENT ON COLUMN products.updated_at IS 'Unix timestamp in milliseconds when the product was last updated';
COMMENT ON COLUMN products.harvest_date IS 'Harvest date stored as text (ISO date format)';

