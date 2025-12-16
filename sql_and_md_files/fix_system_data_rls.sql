-- Fix RLS policies for system_data table to allow heartbeat updates
-- Run this SQL in Supabase SQL Editor to fix the 401 Unauthorized errors

-- Drop existing restrictive policies
DROP POLICY IF EXISTS "Allow authenticated users to update system_data" ON public.system_data;
DROP POLICY IF EXISTS "Allow authenticated users to insert system_data" ON public.system_data;
DROP POLICY IF EXISTS "Allow public upsert to system_data" ON public.system_data;

-- Create a single policy that allows public upsert (for heartbeat)
-- This is safe because system_data only contains non-sensitive timestamp data
CREATE POLICY "Allow public upsert to system_data"
    ON public.system_data
    FOR ALL
    USING (true)
    WITH CHECK (true);

-- Verify the policy was created
SELECT * FROM pg_policies WHERE tablename = 'system_data';

