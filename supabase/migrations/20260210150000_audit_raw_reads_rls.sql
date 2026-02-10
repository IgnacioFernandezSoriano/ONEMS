-- =====================================================
-- Migration: Add RLS policies for audit_raw_reads
-- Description: Enable Row Level Security and add policies
--              to allow authenticated users to read audit data
-- Date: 2026-02-10
-- =====================================================

-- Enable RLS on audit_raw_reads
ALTER TABLE audit_raw_reads ENABLE ROW LEVEL SECURITY;

-- Policy: Allow authenticated users to read audit data from their account
CREATE POLICY "Users can read audit data from their account"
ON audit_raw_reads
FOR SELECT
TO authenticated
USING (
  account_id IN (
    SELECT account_id 
    FROM profiles 
    WHERE id = auth.uid()
  )
);

-- Policy: Allow service role to read all audit data
CREATE POLICY "Service role can read all audit data"
ON audit_raw_reads
FOR SELECT
TO service_role
USING (true);

-- Grant SELECT permission to authenticated users
GRANT SELECT ON audit_raw_reads TO authenticated;
GRANT SELECT ON audit_raw_reads TO service_role;

-- =====================================================
-- Summary
-- =====================================================
COMMENT ON TABLE audit_raw_reads IS 'Audit log of consolidated RFID raw reads with RLS enabled';
