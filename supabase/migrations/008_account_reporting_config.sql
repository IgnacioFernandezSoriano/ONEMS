-- Migration 008: Account Reporting Configuration
-- Purpose: Allow superadmin to configure reporting settings per account

-- Table: account_reporting_config
-- Stores reporting configuration settings for each account
CREATE TABLE IF NOT EXISTS account_reporting_config (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  compliance_threshold_warning INTEGER DEFAULT 85 CHECK (compliance_threshold_warning >= 0 AND compliance_threshold_warning <= 100),
  compliance_threshold_critical INTEGER DEFAULT 75 CHECK (compliance_threshold_critical >= 0 AND compliance_threshold_critical <= 100),
  default_report_period VARCHAR(20) DEFAULT 'week' CHECK (default_report_period IN ('week', 'month', 'quarter')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(account_id),
  CONSTRAINT threshold_order CHECK (compliance_threshold_warning > compliance_threshold_critical)
);

-- Table: account_city_classification
-- Stores custom city classifications per account
CREATE TABLE IF NOT EXISTS account_city_classification (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  city_id UUID NOT NULL REFERENCES cities(id) ON DELETE CASCADE,
  classification VARCHAR(20) NOT NULL CHECK (classification IN ('capital', 'major', 'minor')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(account_id, city_id)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_account_reporting_config_account_id ON account_reporting_config(account_id);
CREATE INDEX IF NOT EXISTS idx_account_city_classification_account_id ON account_city_classification(account_id);
CREATE INDEX IF NOT EXISTS idx_account_city_classification_city_id ON account_city_classification(city_id);

-- RLS Policies: Only superadmin can access

-- Enable RLS
ALTER TABLE account_reporting_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE account_city_classification ENABLE ROW LEVEL SECURITY;

-- Policy: Superadmin can do everything on account_reporting_config
CREATE POLICY account_reporting_config_superadmin 
ON account_reporting_config
FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.user_id = auth.uid() 
    AND profiles.role = 'superadmin'
  )
);

-- Policy: Superadmin can do everything on account_city_classification
CREATE POLICY account_city_classification_superadmin 
ON account_city_classification
FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.user_id = auth.uid() 
    AND profiles.role = 'superadmin'
  )
);

-- Function: Get or create default config for an account
CREATE OR REPLACE FUNCTION get_account_reporting_config(p_account_id UUID)
RETURNS TABLE (
  account_id UUID,
  compliance_threshold_warning INTEGER,
  compliance_threshold_critical INTEGER,
  default_report_period VARCHAR(20)
) AS $$
BEGIN
  -- Try to get existing config
  RETURN QUERY
  SELECT 
    arc.account_id,
    arc.compliance_threshold_warning,
    arc.compliance_threshold_critical,
    arc.default_report_period
  FROM account_reporting_config arc
  WHERE arc.account_id = p_account_id;
  
  -- If no config exists, return defaults
  IF NOT FOUND THEN
    RETURN QUERY
    SELECT 
      p_account_id,
      85::INTEGER,
      75::INTEGER,
      'week'::VARCHAR(20);
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Get city classification for an account (with fallback to default)
CREATE OR REPLACE FUNCTION get_city_classification(p_account_id UUID, p_city_id UUID)
RETURNS VARCHAR(20) AS $$
DECLARE
  v_classification VARCHAR(20);
BEGIN
  -- Try to get account-specific classification
  SELECT classification INTO v_classification
  FROM account_city_classification
  WHERE account_id = p_account_id AND city_id = p_city_id;
  
  -- If not found, use default from cities table
  IF v_classification IS NULL THEN
    SELECT city_type INTO v_classification
    FROM cities
    WHERE id = p_city_id;
  END IF;
  
  RETURN COALESCE(v_classification, 'minor');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger: Update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_account_reporting_config_updated_at
BEFORE UPDATE ON account_reporting_config
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_account_city_classification_updated_at
BEFORE UPDATE ON account_city_classification
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- Insert default config for existing accounts
INSERT INTO account_reporting_config (account_id)
SELECT id FROM accounts
WHERE id NOT IN (SELECT account_id FROM account_reporting_config)
ON CONFLICT (account_id) DO NOTHING;

-- Comments
COMMENT ON TABLE account_reporting_config IS 'Reporting configuration settings per account';
COMMENT ON TABLE account_city_classification IS 'Custom city classifications per account for reporting';
COMMENT ON FUNCTION get_account_reporting_config(UUID) IS 'Get reporting config for an account with defaults';
COMMENT ON FUNCTION get_city_classification(UUID, UUID) IS 'Get city classification with account override or default';
