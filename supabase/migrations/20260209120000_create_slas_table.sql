-- Create SLAs table for Network Diagnostics Module
-- Sprint 5: SLAs Configuration

CREATE TABLE slas (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  sla_type TEXT NOT NULL CHECK (sla_type IN ('operational', 'distribution')),
  
  -- Operational SLA fields (within a postal center)
  postal_center_id UUID REFERENCES postal_centers(id) ON DELETE CASCADE,
  from_reader_id UUID REFERENCES readers(id) ON DELETE CASCADE,
  to_reader_id UUID REFERENCES readers(id) ON DELETE CASCADE,
  
  -- Distribution SLA fields (between postal centers)
  from_postal_center_id UUID REFERENCES postal_centers(id) ON DELETE CASCADE,
  to_postal_center_id UUID REFERENCES postal_centers(id) ON DELETE CASCADE,
  
  -- Common fields
  expected_time_minutes INTEGER NOT NULL CHECK (expected_time_minutes > 0),
  time_unit TEXT NOT NULL DEFAULT 'minutes' CHECK (time_unit IN ('minutes', 'hours')),
  on_time_percentage INTEGER NOT NULL CHECK (on_time_percentage >= 0 AND on_time_percentage <= 100),
  warning_threshold INTEGER NOT NULL CHECK (warning_threshold >= 0 AND warning_threshold <= 100),
  critical_threshold INTEGER NOT NULL CHECK (critical_threshold >= 0 AND critical_threshold <= 100),
  is_active BOOLEAN DEFAULT true,
  
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_by UUID REFERENCES users(id),
  updated_by UUID REFERENCES users(id),
  
  -- Constraints
  CONSTRAINT slas_operational_fields_check CHECK (
    (sla_type = 'operational' AND postal_center_id IS NOT NULL AND from_reader_id IS NOT NULL AND to_reader_id IS NOT NULL AND from_postal_center_id IS NULL AND to_postal_center_id IS NULL)
    OR
    (sla_type = 'distribution' AND from_postal_center_id IS NOT NULL AND to_postal_center_id IS NOT NULL AND postal_center_id IS NULL AND from_reader_id IS NULL AND to_reader_id IS NULL)
  ),
  CONSTRAINT slas_thresholds_check CHECK (on_time_percentage >= warning_threshold AND warning_threshold >= critical_threshold),
  CONSTRAINT slas_operational_different_readers CHECK (sla_type != 'operational' OR from_reader_id != to_reader_id),
  CONSTRAINT slas_distribution_different_centers CHECK (sla_type != 'distribution' OR from_postal_center_id != to_postal_center_id),
  
  -- Unique constraints
  UNIQUE (account_id, postal_center_id, from_reader_id, to_reader_id),
  UNIQUE (account_id, from_postal_center_id, to_postal_center_id)
);

-- Indexes for performance
CREATE INDEX idx_slas_account_type ON slas(account_id, sla_type);
CREATE INDEX idx_slas_operational_combo ON slas(account_id, postal_center_id, from_reader_id, to_reader_id) WHERE sla_type = 'operational';
CREATE INDEX idx_slas_distribution_combo ON slas(account_id, from_postal_center_id, to_postal_center_id) WHERE sla_type = 'distribution';
CREATE INDEX idx_slas_active ON slas(is_active) WHERE is_active = true;

-- RLS Policies
ALTER TABLE slas ENABLE ROW LEVEL SECURITY;

CREATE POLICY slas_select_policy ON slas FOR SELECT
  USING (account_id = public.current_user_account_id() OR public.current_user_role() = 'superadmin');

CREATE POLICY slas_insert_policy ON slas FOR INSERT
  WITH CHECK (account_id = public.current_user_account_id());

CREATE POLICY slas_update_policy ON slas FOR UPDATE
  USING (account_id = public.current_user_account_id());

CREATE POLICY slas_delete_policy ON slas FOR DELETE
  USING (account_id = public.current_user_account_id());

-- Comments
COMMENT ON TABLE slas IS 'Service Level Agreements for Network Diagnostics - defines expected times for operational (within center) and distribution (between centers) routes';
COMMENT ON COLUMN slas.sla_type IS 'Type of SLA: operational (within center) or distribution (between centers)';
COMMENT ON COLUMN slas.expected_time_minutes IS 'Expected time in minutes for the route';
COMMENT ON COLUMN slas.time_unit IS 'Unit for displaying time: minutes or hours';
COMMENT ON COLUMN slas.on_time_percentage IS 'Target percentage for on-time performance (0-100)';
COMMENT ON COLUMN slas.warning_threshold IS 'Warning threshold percentage (0-100), must be <= on_time_percentage';
COMMENT ON COLUMN slas.critical_threshold IS 'Critical threshold percentage (0-100), must be <= warning_threshold';
