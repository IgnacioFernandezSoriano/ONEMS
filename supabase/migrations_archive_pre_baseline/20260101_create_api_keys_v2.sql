-- Create api_keys table for ONE DB API access (Simplified version)
-- This version includes better error handling and simpler RLS policies

-- Drop existing tables if they exist (for clean reinstall)
DROP TABLE IF EXISTS api_usage_log CASCADE;
DROP TABLE IF EXISTS api_keys CASCADE;

-- Create api_keys table
CREATE TABLE api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL,
  api_key TEXT UNIQUE NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_used_at TIMESTAMPTZ,
  usage_count INTEGER DEFAULT 0,
  created_by UUID
);

-- Create indexes for faster lookups
CREATE INDEX idx_api_keys_account_id ON api_keys(account_id);
CREATE INDEX idx_api_keys_api_key ON api_keys(api_key) WHERE is_active = true;

-- Enable RLS
ALTER TABLE api_keys ENABLE ROW LEVEL SECURITY;

-- Simple RLS Policy: Users can view and manage API keys for their own account
CREATE POLICY "Users can manage their account's API keys"
  ON api_keys
  FOR ALL
  USING (
    account_id IN (
      SELECT account_id FROM profiles WHERE id = auth.uid()
    )
  )
  WITH CHECK (
    account_id IN (
      SELECT account_id FROM profiles WHERE id = auth.uid()
    )
  );

-- Create table for API usage tracking (rate limiting)
CREATE TABLE api_usage_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  api_key_id UUID REFERENCES api_keys(id) ON DELETE CASCADE NOT NULL,
  endpoint TEXT NOT NULL,
  request_timestamp TIMESTAMPTZ DEFAULT NOW(),
  response_status INTEGER,
  response_time_ms INTEGER,
  ip_address TEXT
);

-- Create index for rate limiting queries
CREATE INDEX idx_api_usage_log_key_timestamp 
  ON api_usage_log(api_key_id, request_timestamp DESC);

-- Enable RLS
ALTER TABLE api_usage_log ENABLE ROW LEVEL SECURITY;

-- RLS Policy for usage log
CREATE POLICY "Users can view their account's API usage"
  ON api_usage_log
  FOR SELECT
  USING (
    api_key_id IN (
      SELECT id FROM api_keys 
      WHERE account_id IN (
        SELECT account_id FROM profiles WHERE id = auth.uid()
      )
    )
  );

-- Grant necessary permissions
GRANT ALL ON api_keys TO authenticated;
GRANT ALL ON api_usage_log TO authenticated;

-- Insert a test comment to verify migration ran
COMMENT ON TABLE api_keys IS 'API keys for ONE DB REST API access - Created 2026-01-01';
