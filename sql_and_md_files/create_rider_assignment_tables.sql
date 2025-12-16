-- ============================================================================
-- SQL Commands for Rider Assignment Functionality in Supabase
-- ============================================================================
-- This script creates/updates tables and columns needed for assigning orders to riders
-- Run this in the Supabase SQL Editor
-- ============================================================================

-- ============================================================================
-- 1. ADD RIDER ASSIGNMENT COLUMNS TO ORDERS TABLE
-- ============================================================================
-- Add rider assignment fields to the existing orders table

-- Rider ID (references riders.uid)
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS rider_id TEXT;
COMMENT ON COLUMN orders.rider_id IS 'UID of the assigned rider (references riders.uid)';

-- Rider Name (denormalized for quick display)
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS rider_name TEXT;
COMMENT ON COLUMN orders.rider_name IS 'Full name of the assigned rider (denormalized)';

-- Rider Phone (denormalized for quick access)
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS rider_phone TEXT;
COMMENT ON COLUMN orders.rider_phone IS 'Phone number of the assigned rider (denormalized)';

-- Assignment timestamp
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS assigned_at BIGINT;
COMMENT ON COLUMN orders.assigned_at IS 'Unix timestamp (milliseconds) when rider was assigned to the order';

-- Out for delivery timestamp
ALTER TABLE orders 
ADD COLUMN IF NOT EXISTS out_for_delivery_at BIGINT;
COMMENT ON COLUMN orders.out_for_delivery_at IS 'Unix timestamp (milliseconds) when order was marked as out for delivery';

-- Create indexes for rider assignment queries
CREATE INDEX IF NOT EXISTS idx_orders_rider_id ON orders(rider_id);
CREATE INDEX IF NOT EXISTS idx_orders_assigned_at ON orders(assigned_at);
CREATE INDEX IF NOT EXISTS idx_orders_out_for_delivery_at ON orders(out_for_delivery_at);

-- Composite index for querying orders by rider and status
CREATE INDEX IF NOT EXISTS idx_orders_rider_status ON orders(rider_id, status);

-- ============================================================================
-- 2. CREATE DELIVERY_ORDERS TABLE
-- ============================================================================
-- Separate table for delivery app to query orders assigned to riders
-- This mirrors order data but is optimized for delivery app queries

CREATE TABLE IF NOT EXISTS delivery_orders (
    -- Primary Key (order ID)
    id TEXT PRIMARY KEY,
    
    -- Order Status
    status TEXT DEFAULT 'pending',
    
    -- Rider Assignment Fields (REQUIRED)
    rider_id TEXT NOT NULL,
    rider_name TEXT NOT NULL,
    rider_phone TEXT,
    assigned_at BIGINT NOT NULL,
    out_for_delivery_at BIGINT,
    
    -- Customer Information
    customer_id TEXT,
    customer_name TEXT,
    customer_phone TEXT,
    customer_address TEXT,
    
    -- Delivery Information
    delivery_address TEXT,
    pickup_address TEXT,
    pickup_location JSONB,
    delivery_location JSONB,
    
    -- Payment Information
    payment_method TEXT,
    total_amount NUMERIC(10, 2),
    delivery_fee NUMERIC(10, 2),
    
    -- Order Items (JSONB array)
    items JSONB,
    
    -- Delivery Proof
    delivery_proof JSONB, -- Array of image URLs for proof of delivery (null initially)
    proof_delivery_images JSONB, -- Legacy field for proof images (array of URLs)
    
    -- Notes and Additional Info
    notes TEXT,
    
    -- Timestamps
    created_at BIGINT,
    updated_at BIGINT,
    
    -- Delivery completion fields
    delivered_at BIGINT,
    delivered_by TEXT,
    delivered_by_name TEXT,
    
    -- Failed delivery fields
    failed_at BIGINT,
    failure_reason TEXT,
    failed_by TEXT,
    failed_by_name TEXT,
    
    -- Pickup fields
    picked_up_at BIGINT,
    ready_for_pickup BOOLEAN DEFAULT FALSE,
    
    -- Delivery schedule (for tracking)
    delivery_schedule BIGINT
);

-- Create indexes for delivery_orders table
CREATE INDEX IF NOT EXISTS idx_delivery_orders_rider_id ON delivery_orders(rider_id);
CREATE INDEX IF NOT EXISTS idx_delivery_orders_status ON delivery_orders(status);
CREATE INDEX IF NOT EXISTS idx_delivery_orders_rider_status ON delivery_orders(rider_id, status);
CREATE INDEX IF NOT EXISTS idx_delivery_orders_assigned_at ON delivery_orders(assigned_at);
CREATE INDEX IF NOT EXISTS idx_delivery_orders_created_at ON delivery_orders(created_at);

-- Add comments for documentation
COMMENT ON TABLE delivery_orders IS 'Orders assigned to riders for delivery - optimized for delivery app queries';
COMMENT ON COLUMN delivery_orders.id IS 'Order ID (references orders.uid)';
COMMENT ON COLUMN delivery_orders.rider_id IS 'UID of the assigned rider (references riders.uid)';
COMMENT ON COLUMN delivery_orders.rider_name IS 'Full name of the assigned rider';
COMMENT ON COLUMN delivery_orders.delivery_proof IS 'Array of image URLs for proof of delivery (null = no proof yet)';
COMMENT ON COLUMN delivery_orders.proof_delivery_images IS 'Legacy field for proof of delivery images (array of URLs)';

-- ============================================================================
-- 3. CREATE ORDER_ASSIGNMENTS TABLE (OPTIONAL - FOR FALLBACK/RECOVERY)
-- ============================================================================
-- This table stores rider assignments separately as a backup/fallback mechanism
-- Used to recover missing assignment data if orders table loses rider info

CREATE TABLE IF NOT EXISTS order_assignments (
    -- Primary Key (order ID)
    order_id TEXT PRIMARY KEY,
    
    -- Rider Assignment Fields
    rider_id TEXT NOT NULL,
    rider_name TEXT NOT NULL,
    rider_phone TEXT,
    
    -- Timestamps
    assigned_at BIGINT NOT NULL,
    created_at BIGINT DEFAULT EXTRACT(EPOCH FROM NOW()) * 1000,
    updated_at BIGINT DEFAULT EXTRACT(EPOCH FROM NOW()) * 1000
);

-- Create indexes for order_assignments table
CREATE INDEX IF NOT EXISTS idx_order_assignments_rider_id ON order_assignments(rider_id);
CREATE INDEX IF NOT EXISTS idx_order_assignments_assigned_at ON order_assignments(assigned_at);

-- Add comments for documentation
COMMENT ON TABLE order_assignments IS 'Backup/fallback table for rider assignments - used to recover missing assignment data';
COMMENT ON COLUMN order_assignments.order_id IS 'Order ID (references orders.uid)';
COMMENT ON COLUMN order_assignments.rider_id IS 'UID of the assigned rider (references riders.uid)';

-- ============================================================================
-- 4. ADD FOREIGN KEY CONSTRAINTS (OPTIONAL - FOR DATA INTEGRITY)
-- ============================================================================
-- Uncomment these if you want referential integrity between tables

-- Foreign key from orders.rider_id to riders.uid
-- ALTER TABLE orders 
-- ADD CONSTRAINT fk_orders_rider_id 
-- FOREIGN KEY (rider_id) REFERENCES riders(uid) 
-- ON DELETE SET NULL;

-- Foreign key from delivery_orders.rider_id to riders.uid
-- ALTER TABLE delivery_orders 
-- ADD CONSTRAINT fk_delivery_orders_rider_id 
-- FOREIGN KEY (rider_id) REFERENCES riders(uid) 
-- ON DELETE RESTRICT;

-- Foreign key from delivery_orders.id to orders.uid
-- ALTER TABLE delivery_orders 
-- ADD CONSTRAINT fk_delivery_orders_order_id 
-- FOREIGN KEY (id) REFERENCES orders(uid) 
-- ON DELETE CASCADE;

-- Foreign key from order_assignments.order_id to orders.uid
-- ALTER TABLE order_assignments 
-- ADD CONSTRAINT fk_order_assignments_order_id 
-- FOREIGN KEY (order_id) REFERENCES orders(uid) 
-- ON DELETE CASCADE;

-- Foreign key from order_assignments.rider_id to riders.uid
-- ALTER TABLE order_assignments 
-- ADD CONSTRAINT fk_order_assignments_rider_id 
-- FOREIGN KEY (rider_id) REFERENCES riders(uid) 
-- ON DELETE RESTRICT;

-- ============================================================================
-- 5. VERIFY TABLES AND COLUMNS CREATED
-- ============================================================================
-- Run these queries to verify everything was created correctly

-- Check orders table has rider columns
-- SELECT column_name, data_type 
-- FROM information_schema.columns 
-- WHERE table_name = 'orders' 
-- AND column_name IN ('rider_id', 'rider_name', 'rider_phone', 'assigned_at', 'out_for_delivery_at');

-- Check delivery_orders table exists
-- SELECT table_name 
-- FROM information_schema.tables 
-- WHERE table_name = 'delivery_orders';

-- Check order_assignments table exists
-- SELECT table_name 
-- FROM information_schema.tables 
-- WHERE table_name = 'order_assignments';

-- Check indexes were created
-- SELECT indexname, indexdef 
-- FROM pg_indexes 
-- WHERE tablename IN ('orders', 'delivery_orders', 'order_assignments')
-- ORDER BY tablename, indexname;

-- ============================================================================
-- END OF SCRIPT
-- ============================================================================

