-- SQL command to create order_staff_notes table for staff/admin notes
-- Run this in the Supabase SQL Editor
-- This table stores multiple notes that staff/admin can add to orders

-- Create the order_staff_notes table
CREATE TABLE IF NOT EXISTS order_staff_notes (
    -- Primary Key
    id BIGSERIAL PRIMARY KEY,
    
    -- Foreign Key: Reference to the order
    order_id TEXT NOT NULL,
    
    -- Note Content
    note_text TEXT NOT NULL,
    
    -- Creation Metadata
    noted_by_name TEXT NOT NULL,
    noted_by_role TEXT NOT NULL,
    noted_at BIGINT NOT NULL,
    
    -- Update Metadata (null if never updated)
    note_updated_by_name TEXT,
    note_updated_by_role TEXT,
    note_updated_at BIGINT,
    
    -- Timestamps for tracking
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_order_staff_notes_order_id ON order_staff_notes(order_id);
CREATE INDEX IF NOT EXISTS idx_order_staff_notes_noted_at ON order_staff_notes(noted_at);
CREATE INDEX IF NOT EXISTS idx_order_staff_notes_order_noted ON order_staff_notes(order_id, noted_at);

-- Add comment to table
COMMENT ON TABLE order_staff_notes IS 'Stores staff/admin notes for orders. Customer notes are stored in orders.order_notes and cannot be edited by staff.';

-- Add comments to columns
COMMENT ON COLUMN order_staff_notes.order_id IS 'Reference to orders.id - the order this note belongs to';
COMMENT ON COLUMN order_staff_notes.note_text IS 'The actual note content';
COMMENT ON COLUMN order_staff_notes.noted_by_name IS 'Name of the staff/admin who created the note';
COMMENT ON COLUMN order_staff_notes.noted_by_role IS 'Role of the staff/admin who created the note (e.g., Admin, Staff)';
COMMENT ON COLUMN order_staff_notes.noted_at IS 'Unix timestamp (milliseconds) when the note was created';
COMMENT ON COLUMN order_staff_notes.note_updated_by_name IS 'Name of the staff/admin who last updated the note (null if never updated)';
COMMENT ON COLUMN order_staff_notes.note_updated_by_role IS 'Role of the staff/admin who last updated the note (null if never updated)';
COMMENT ON COLUMN order_staff_notes.note_updated_at IS 'Unix timestamp (milliseconds) when the note was last updated (null if never updated)';

-- Create a function to automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_order_staff_notes_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update updated_at on row update
CREATE TRIGGER trigger_update_order_staff_notes_updated_at
    BEFORE UPDATE ON order_staff_notes
    FOR EACH ROW
    EXECUTE FUNCTION update_order_staff_notes_updated_at();
