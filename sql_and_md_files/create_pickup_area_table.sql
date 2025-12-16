-- Create pickup_area table with columns based on Firebase structure
-- This table stores pickup locations where customers can collect their orders

CREATE TABLE IF NOT EXISTS pickup_area (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Basic information
    name VARCHAR(255) NOT NULL,
    map_link TEXT,
    landmark TEXT,
    instructions TEXT,
    
    -- Address components
    address TEXT, -- Full address string (for backward compatibility)
    street VARCHAR(255),
    sitio VARCHAR(255),
    barangay VARCHAR(255) NOT NULL,
    city VARCHAR(100) DEFAULT 'Ormoc',
    province VARCHAR(100) DEFAULT 'Leyte',
    
    -- Status
    active BOOLEAN DEFAULT false,
    
    -- Metadata
    updated_at_timestamp BIGINT -- Firebase timestamp (updatedAt) for migration reference
);

-- Create index on active flag for faster queries
CREATE INDEX IF NOT EXISTS idx_pickup_area_active ON pickup_area(active);

-- Create index on updated_at for faster sorting
CREATE INDEX IF NOT EXISTS idx_pickup_area_updated_at ON pickup_area(updated_at);

-- Add comment to table
COMMENT ON TABLE pickup_area IS 'Stores pickup locations where customers can collect their orders. Only one pickup area should be active at a time.';

