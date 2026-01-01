-- Create api_keys table for ONE DB API access
CREATE TABLE IF NOT EXISTS api_keys (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id UUID REFERENCES accounts(id) ON DELETE CASCADE NOT NULL,
  api_key TEXT UNIQUE NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_used_at TIMESTAMPTZ,
  usage_count INTEGER DEFAULT 0,
  created_by UUID REFERENCES auth.users(id)
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_api_keys_account_id ON api_keys(account_id);
CREATE INDEX IF NOT EXISTS idx_api_keys_api_key ON api_keys(api_key) WHERE is_active = true;

-- Enable RLS
ALTER TABLE api_keys ENABLE ROW LEVEL SECURITY;

-- RLS Policies
-- Users can view API keys for their own account
CREATE POLICY "Users can view their account's API keys"
  ON api_keys FOR SELECT
  USING (
    account_id IN (
      SELECT account_id FROM profiles WHERE id = auth.uid()
    )
  );

-- Only admins and superadmins can create API keys
CREATE POLICY "Admins can create API keys"
  ON api_keys FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() 
      AND role IN ('admin', 'superadmin')
      AND account_id = api_keys.account_id
    )
  );

-- Only admins and superadmins can update API keys
CREATE POLICY "Admins can update API keys"
  ON api_keys FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() 
      AND role IN ('admin', 'superadmin')
      AND account_id = api_keys.account_id
    )
  );

-- Only admins and superadmins can delete API keys
CREATE POLICY "Admins can delete API keys"
  ON api_keys FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM profiles 
      WHERE id = auth.uid() 
      AND role IN ('admin', 'superadmin')
      AND account_id = api_keys.account_id
    )
  );

-- Create table for API usage tracking (rate limiting)
CREATE TABLE IF NOT EXISTS api_usage_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  api_key_id UUID REFERENCES api_keys(id) ON DELETE CASCADE NOT NULL,
  endpoint TEXT NOT NULL,
  request_timestamp TIMESTAMPTZ DEFAULT NOW(),
  response_status INTEGER,
  response_time_ms INTEGER,
  ip_address INET
);

-- Create index for rate limiting queries
CREATE INDEX IF NOT EXISTS idx_api_usage_log_key_timestamp 
  ON api_usage_log(api_key_id, request_timestamp DESC);

-- Enable RLS
ALTER TABLE api_usage_log ENABLE ROW LEVEL SECURITY;

-- RLS Policy for usage log (only viewable by account owners)
CREATE POLICY "Users can view their account's API usage"
  ON api_usage_log FOR SELECT
  USING (
    api_key_id IN (
      SELECT id FROM api_keys 
      WHERE account_id IN (
        SELECT account_id FROM profiles WHERE id = auth.uid()
      )
    )
  );
