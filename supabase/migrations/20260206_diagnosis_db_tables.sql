-- ============================================
-- DIAGNOSIS DATABASE - MAIN TABLES
-- ============================================
-- This database stores processed diagnostic data permanently
-- for reporting and analysis

-- ============================================
-- 1. DIAGNOSIS ROUTES TABLE
-- ============================================
-- Stores the complete route of each package (TagID)

CREATE TABLE diagnosis_routes (
  id BIGSERIAL PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  tag_id TEXT NOT NULL,
  route_start_time TIMESTAMPTZ NOT NULL,
  route_end_time TIMESTAMPTZ NOT NULL,
  total_duration_hours NUMERIC(10,2) NOT NULL,
  reader_sequence TEXT[] NOT NULL, -- Array of reader IDs in order
  event_count INTEGER NOT NULL,
  is_complete BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for diagnosis_routes
CREATE INDEX diagnosis_routes_account_id_idx ON diagnosis_routes(account_id);
CREATE INDEX diagnosis_routes_tag_id_idx ON diagnosis_routes(tag_id);
CREATE INDEX diagnosis_routes_start_time_idx ON diagnosis_routes(route_start_time);
CREATE INDEX diagnosis_routes_end_time_idx ON diagnosis_routes(route_end_time);

-- Triggers for diagnosis_routes
CREATE TRIGGER set_diagnosis_routes_account_id
  BEFORE INSERT ON diagnosis_routes
  FOR EACH ROW
  EXECUTE FUNCTION set_account_id();

CREATE TRIGGER prevent_diagnosis_routes_account_change
  BEFORE UPDATE ON diagnosis_routes
  FOR EACH ROW
  EXECUTE FUNCTION prevent_account_id_change();

-- RLS Policies for diagnosis_routes
ALTER TABLE diagnosis_routes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "diagnosis_routes_select"
  ON diagnosis_routes FOR SELECT
  USING (
    current_user_role() = 'superadmin' OR
    account_id = current_user_account_id()
  );

CREATE POLICY "diagnosis_routes_insert"
  ON diagnosis_routes FOR INSERT
  WITH CHECK (
    current_user_role() IN ('superadmin', 'admin')
  );

CREATE POLICY "diagnosis_routes_update"
  ON diagnosis_routes FOR UPDATE
  USING (
    current_user_role() = 'superadmin' OR
    (current_user_role() = 'admin' AND account_id = current_user_account_id())
  );

CREATE POLICY "diagnosis_routes_delete"
  ON diagnosis_routes FOR DELETE
  USING (
    current_user_role() = 'superadmin' OR
    (current_user_role() = 'admin' AND account_id = current_user_account_id())
  );

-- ============================================
-- 2. DIAGNOSIS TIME METRICS TABLE
-- ============================================
-- Stores time-based metrics for each route segment

CREATE TABLE diagnosis_time_metrics (
  id BIGSERIAL PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  route_id BIGINT NOT NULL REFERENCES diagnosis_routes(id) ON DELETE CASCADE,
  tag_id TEXT NOT NULL,
  from_reader_id TEXT NOT NULL,
  to_reader_id TEXT NOT NULL,
  segment_duration_hours NUMERIC(10,2) NOT NULL,
  segment_start_time TIMESTAMPTZ NOT NULL,
  segment_end_time TIMESTAMPTZ NOT NULL,
  expected_duration_hours NUMERIC(10,2), -- For comparison
  is_delayed BOOLEAN DEFAULT false,
  delay_hours NUMERIC(10,2),
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for diagnosis_time_metrics
CREATE INDEX diagnosis_time_metrics_account_id_idx ON diagnosis_time_metrics(account_id);
CREATE INDEX diagnosis_time_metrics_route_id_idx ON diagnosis_time_metrics(route_id);
CREATE INDEX diagnosis_time_metrics_tag_id_idx ON diagnosis_time_metrics(tag_id);
CREATE INDEX diagnosis_time_metrics_readers_idx ON diagnosis_time_metrics(from_reader_id, to_reader_id);

-- Triggers for diagnosis_time_metrics
CREATE TRIGGER set_diagnosis_time_metrics_account_id
  BEFORE INSERT ON diagnosis_time_metrics
  FOR EACH ROW
  EXECUTE FUNCTION set_account_id();

CREATE TRIGGER prevent_diagnosis_time_metrics_account_change
  BEFORE UPDATE ON diagnosis_time_metrics
  FOR EACH ROW
  EXECUTE FUNCTION prevent_account_id_change();

-- RLS Policies for diagnosis_time_metrics
ALTER TABLE diagnosis_time_metrics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "diagnosis_time_metrics_select"
  ON diagnosis_time_metrics FOR SELECT
  USING (
    current_user_role() = 'superadmin' OR
    account_id = current_user_account_id()
  );

CREATE POLICY "diagnosis_time_metrics_insert"
  ON diagnosis_time_metrics FOR INSERT
  WITH CHECK (
    current_user_role() IN ('superadmin', 'admin')
  );

CREATE POLICY "diagnosis_time_metrics_update"
  ON diagnosis_time_metrics FOR UPDATE
  USING (
    current_user_role() = 'superadmin' OR
    (current_user_role() = 'admin' AND account_id = current_user_account_id())
  );

CREATE POLICY "diagnosis_time_metrics_delete"
  ON diagnosis_time_metrics FOR DELETE
  USING (
    current_user_role() = 'superadmin' OR
    (current_user_role() = 'admin' AND account_id = current_user_account_id())
  );

-- ============================================
-- 3. DIAGNOSIS ANOMALIES TABLE
-- ============================================
-- Stores detected anomalies and issues

CREATE TABLE diagnosis_anomalies (
  id BIGSERIAL PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  route_id BIGINT REFERENCES diagnosis_routes(id) ON DELETE CASCADE,
  tag_id TEXT NOT NULL,
  anomaly_type TEXT NOT NULL, -- 'missing_reading', 'excessive_delay', 'duplicate_reading', 'out_of_sequence'
  severity TEXT NOT NULL, -- 'low', 'medium', 'high', 'critical'
  description TEXT NOT NULL,
  reader_id TEXT,
  detected_at TIMESTAMPTZ NOT NULL,
  metadata JSONB, -- Additional context
  resolved BOOLEAN DEFAULT false,
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for diagnosis_anomalies
CREATE INDEX diagnosis_anomalies_account_id_idx ON diagnosis_anomalies(account_id);
CREATE INDEX diagnosis_anomalies_route_id_idx ON diagnosis_anomalies(route_id);
CREATE INDEX diagnosis_anomalies_tag_id_idx ON diagnosis_anomalies(tag_id);
CREATE INDEX diagnosis_anomalies_type_idx ON diagnosis_anomalies(anomaly_type);
CREATE INDEX diagnosis_anomalies_severity_idx ON diagnosis_anomalies(severity);
CREATE INDEX diagnosis_anomalies_resolved_idx ON diagnosis_anomalies(resolved);

-- Triggers for diagnosis_anomalies
CREATE TRIGGER set_diagnosis_anomalies_account_id
  BEFORE INSERT ON diagnosis_anomalies
  FOR EACH ROW
  EXECUTE FUNCTION set_account_id();

CREATE TRIGGER prevent_diagnosis_anomalies_account_change
  BEFORE UPDATE ON diagnosis_anomalies
  FOR EACH ROW
  EXECUTE FUNCTION prevent_account_id_change();

-- RLS Policies for diagnosis_anomalies
ALTER TABLE diagnosis_anomalies ENABLE ROW LEVEL SECURITY;

CREATE POLICY "diagnosis_anomalies_select"
  ON diagnosis_anomalies FOR SELECT
  USING (
    current_user_role() = 'superadmin' OR
    account_id = current_user_account_id()
  );

CREATE POLICY "diagnosis_anomalies_insert"
  ON diagnosis_anomalies FOR INSERT
  WITH CHECK (
    current_user_role() IN ('superadmin', 'admin')
  );

CREATE POLICY "diagnosis_anomalies_update"
  ON diagnosis_anomalies FOR UPDATE
  USING (
    current_user_role() = 'superadmin' OR
    (current_user_role() = 'admin' AND account_id = current_user_account_id())
  );

CREATE POLICY "diagnosis_anomalies_delete"
  ON diagnosis_anomalies FOR DELETE
  USING (
    current_user_role() = 'superadmin' OR
    (current_user_role() = 'admin' AND account_id = current_user_account_id())
  );

-- Verify
SELECT 'Diagnosis DB tables created successfully' as status;
