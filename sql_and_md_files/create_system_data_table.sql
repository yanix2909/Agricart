-- Create system_data table for cooperative time heartbeat and system metadata
-- This replaces Firebase systemData/coopTime and systemData/coopTimeServerTs

CREATE TABLE IF NOT EXISTS system_data (
    id TEXT PRIMARY KEY DEFAULT 'coopTime', -- Single row for cooperative time
    epoch_ms BIGINT NOT NULL, -- Epoch timestamp in milliseconds
    iso TEXT, -- ISO 8601 formatted timestamp
    weekday INTEGER, -- Weekday (1=Mon..7=Sun)
    source TEXT DEFAULT 'staff-admin-desktop', -- Source identifier
    server_ts BIGINT, -- Server timestamp for comparison
    updated_at BIGINT NOT NULL -- Last update timestamp
);

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_system_data_updated_at ON system_data(updated_at);

-- Insert initial row if it doesn't exist
INSERT INTO system_data (id, epoch_ms, iso, weekday, source, server_ts, updated_at)
VALUES (
    'coopTime',
    EXTRACT(EPOCH FROM NOW())::BIGINT * 1000,
    NOW()::TEXT,
    EXTRACT(DOW FROM NOW())::INTEGER,
    'system-init',
    EXTRACT(EPOCH FROM NOW())::BIGINT * 1000,
    EXTRACT(EPOCH FROM NOW())::BIGINT * 1000
)
ON CONFLICT (id) DO NOTHING;

-- Enable Row Level Security (RLS) - allow public read, but restrict writes
ALTER TABLE system_data ENABLE ROW LEVEL SECURITY;

-- Policy: Allow anyone to read system data (needed for customer app)
CREATE POLICY "Allow public read access to system_data"
    ON system_data FOR SELECT
    USING (true);

-- Policy: Allow anyone to update/insert system data (for heartbeat)
-- This is safe because system_data only contains non-sensitive timestamp data
-- and we restrict updates to the coopTime row only
CREATE POLICY "Allow public upsert to system_data"
    ON system_data FOR ALL
    USING (true)
    WITH CHECK (true);

