-- SQL commands to add ALL columns needed for reschedule functionality
-- Run this in the Supabase SQL Editor
-- This combines all necessary columns for rescheduling orders during cut-off time

-- ============================================
-- 1. Reschedule Metadata Columns
-- ============================================

-- Timestamp (milliseconds) for when the order was rescheduled
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS rescheduled_at BIGINT;
COMMENT ON COLUMN orders.rescheduled_at IS 'Unix timestamp (milliseconds) when the order was rescheduled';

-- UID of the staff/admin who rescheduled the order
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS rescheduled_by TEXT;
COMMENT ON COLUMN orders.rescheduled_by IS 'UID of the staff/admin who rescheduled the order';

-- Full name of the staff/admin who rescheduled the order
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS rescheduled_by_name TEXT;
COMMENT ON COLUMN orders.rescheduled_by_name IS 'Full name of the staff/admin who rescheduled the order (e.g., "John Doe")';

-- Role/title of the staff/admin who rescheduled the order (e.g., Administrator, Staff)
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS rescheduled_by_role TEXT;
COMMENT ON COLUMN orders.rescheduled_by_role IS 'Role/title of the staff/admin who rescheduled the order (e.g., "System Administrator", "Staff Member")';

-- Boolean flag to indicate if order was rescheduled to next week
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS rescheduled_next_week BOOLEAN DEFAULT FALSE;
COMMENT ON COLUMN orders.rescheduled_next_week IS 'Flag indicating if the order was rescheduled to next week (cut-off time reschedule)';

-- ============================================
-- 2. To Receive Metadata Columns
-- ============================================

-- Timestamp (milliseconds) for when the order was moved to "to_receive" status
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS to_receive_at BIGINT;
COMMENT ON COLUMN orders.to_receive_at IS 'Unix timestamp (milliseconds) when the order was moved to "to_receive" status';

-- UID of the staff/admin who moved the order to "to_receive" status
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS to_receive_by TEXT;
COMMENT ON COLUMN orders.to_receive_by IS 'UID of the staff/admin who moved the order to "to_receive" status';

-- Full name of the staff/admin who moved the order to "to_receive" status
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS to_receive_by_name TEXT;
COMMENT ON COLUMN orders.to_receive_by_name IS 'Full name of the staff/admin who moved the order to "to_receive" status';

-- ============================================
-- 3. Estimated Delivery Columns
-- ============================================

-- Estimated delivery start timestamp (milliseconds)
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS estimated_delivery_start BIGINT;
COMMENT ON COLUMN orders.estimated_delivery_start IS 'Unix timestamp (milliseconds) for estimated delivery/pickup start time';

-- Estimated delivery end timestamp (milliseconds)
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS estimated_delivery_end BIGINT;
COMMENT ON COLUMN orders.estimated_delivery_end IS 'Unix timestamp (milliseconds) for estimated delivery/pickup end time';

-- ============================================
-- 4. Create Indexes for Better Performance
-- ============================================

CREATE INDEX IF NOT EXISTS idx_orders_rescheduled_at ON orders(rescheduled_at);
CREATE INDEX IF NOT EXISTS idx_orders_rescheduled_by ON orders(rescheduled_by);
CREATE INDEX IF NOT EXISTS idx_orders_rescheduled_next_week ON orders(rescheduled_next_week);
CREATE INDEX IF NOT EXISTS idx_orders_to_receive_at ON orders(to_receive_at);
CREATE INDEX IF NOT EXISTS idx_orders_to_receive_by ON orders(to_receive_by);
CREATE INDEX IF NOT EXISTS idx_orders_estimated_delivery_start ON orders(estimated_delivery_start);
CREATE INDEX IF NOT EXISTS idx_orders_estimated_delivery_end ON orders(estimated_delivery_end);

