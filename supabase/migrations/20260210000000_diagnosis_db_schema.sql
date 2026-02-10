-- Sprint 6: Diagnosis DB Schema Complete
-- Part 1: Add soft delete to existing configuration tables
-- Part 2: Create new diagnosis tables (processed_events, journey_segments, incidents, journeys)

-- ============================================================================
-- PART 1: SOFT DELETE IMPLEMENTATION
-- ============================================================================

-- Add deleted_at column to existing tables
ALTER TABLE postal_centers ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE readers ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;
ALTER TABLE slas ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

-- Create indexes for soft delete filtering
CREATE INDEX IF NOT EXISTS idx_postal_centers_deleted_at ON postal_centers(deleted_at) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_readers_deleted_at ON readers(deleted_at) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_slas_deleted_at ON slas(deleted_at) WHERE deleted_at IS NULL;

-- Update RLS policies to filter out soft-deleted records
-- Drop existing SELECT policies
DROP POLICY IF EXISTS "postal_centers_select_own_account" ON postal_centers;
DROP POLICY IF EXISTS "readers_select_own_account" ON readers;
DROP POLICY IF EXISTS "slas_select_policy" ON slas;

-- Recreate SELECT policies with soft delete filter
CREATE POLICY "postal_centers_select_own_account"
  ON postal_centers FOR SELECT
  TO authenticated
  USING (account_id = public.current_user_account_id() AND deleted_at IS NULL);

CREATE POLICY "postal_centers_select_superadmin"
  ON postal_centers FOR SELECT
  TO authenticated
  USING (public.current_user_role() = 'superadmin');

CREATE POLICY "readers_select_own_account"
  ON readers FOR SELECT
  TO authenticated
  USING (account_id = public.current_user_account_id() AND deleted_at IS NULL);

CREATE POLICY "readers_select_superadmin"
  ON readers FOR SELECT
  TO authenticated
  USING (public.current_user_role() = 'superadmin');

CREATE POLICY "slas_select_policy"
  ON slas FOR SELECT
  TO authenticated
  USING ((account_id = public.current_user_account_id() OR public.current_user_role() = 'superadmin') AND deleted_at IS NULL);

-- ============================================================================
-- PART 2: DIAGNOSIS DB TABLES
-- ============================================================================

-- Table 1: processed_events
-- Stores consolidated RFID events after processing from raw_events
CREATE TABLE IF NOT EXISTS processed_events (
  id BIGSERIAL PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  tag_id TEXT NOT NULL,
  reader_id UUID NOT NULL REFERENCES readers(id) ON DELETE RESTRICT,
  postal_center_id UUID NOT NULL REFERENCES postal_centers(id) ON DELETE RESTRICT,
  event_type TEXT NOT NULL CHECK (event_type IN ('entry', 'exit')),
  
  -- Timestamps
  timestamp TIMESTAMPTZ NOT NULL, -- Actual event time
  analysis_datetime TIMESTAMPTZ NOT NULL, -- Adjusted time (considering cut-off, non-working days)
  
  -- Snapshot fields (for historical reporting even if config changes)
  postal_center_code_snapshot TEXT NOT NULL,
  postal_center_name_snapshot TEXT NOT NULL,
  reader_id_snapshot TEXT NOT NULL,
  reader_type_snapshot TEXT NOT NULL,
  
  -- Processing metadata
  is_consolidated BOOLEAN NOT NULL DEFAULT false, -- If already processed into journey_segments
  raw_event_count INTEGER NOT NULL DEFAULT 1, -- Number of raw events consolidated into this one
  
  -- Audit fields
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at TIMESTAMPTZ, -- When this event was processed into journey_segments
  
  -- Indexes for performance
  CONSTRAINT processed_events_reader_type_check CHECK (reader_type_snapshot IN ('Entry', 'Exit', 'Mixed'))
);

-- Indexes for processed_events
CREATE INDEX idx_processed_events_account ON processed_events(account_id);
CREATE INDEX idx_processed_events_tag_id ON processed_events(tag_id);
CREATE INDEX idx_processed_events_tag_timestamp ON processed_events(tag_id, timestamp);
CREATE INDEX idx_processed_events_postal_center ON processed_events(postal_center_id);
CREATE INDEX idx_processed_events_reader ON processed_events(reader_id);
CREATE INDEX idx_processed_events_timestamp ON processed_events(timestamp);
CREATE INDEX idx_processed_events_analysis_datetime ON processed_events(analysis_datetime);
CREATE INDEX idx_processed_events_unconsolidated ON processed_events(account_id, is_consolidated) WHERE is_consolidated = false;

-- Comments
COMMENT ON TABLE processed_events IS 'Consolidated RFID events after processing from RFID Intermediate DB';
COMMENT ON COLUMN processed_events.timestamp IS 'Actual event timestamp (raw, unmodified)';
COMMENT ON COLUMN processed_events.analysis_datetime IS 'Adjusted timestamp considering cut-off times and non-working days';
COMMENT ON COLUMN processed_events.is_consolidated IS 'Whether this event has been processed into journey_segments';

-- ============================================================================
-- Table 2: journey_segments
-- Stores calculated time segments (operational and distribution)
CREATE TABLE IF NOT EXISTS journey_segments (
  id BIGSERIAL PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  tag_id TEXT NOT NULL,
  segment_type TEXT NOT NULL CHECK (segment_type IN ('operational', 'distribution')),
  
  -- Segment definition
  postal_center_id UUID REFERENCES postal_centers(id) ON DELETE RESTRICT, -- For operational segments
  from_postal_center_id UUID REFERENCES postal_centers(id) ON DELETE RESTRICT, -- For distribution segments
  to_postal_center_id UUID REFERENCES postal_centers(id) ON DELETE RESTRICT, -- For distribution segments
  
  -- Event references
  entry_event_id BIGINT REFERENCES processed_events(id) ON DELETE CASCADE,
  exit_event_id BIGINT REFERENCES processed_events(id) ON DELETE CASCADE,
  
  -- Timestamps
  entry_timestamp TIMESTAMPTZ NOT NULL,
  exit_timestamp TIMESTAMPTZ NOT NULL,
  entry_analysis_datetime TIMESTAMPTZ NOT NULL,
  exit_analysis_datetime TIMESTAMPTZ NOT NULL,
  
  -- Calculated times (in minutes)
  actual_time_minutes INTEGER NOT NULL, -- Raw time difference
  adjusted_time_minutes INTEGER NOT NULL, -- Time excluding non-working hours
  pre_operational_wait_minutes INTEGER, -- Wait time before processing starts (only for operational)
  
  -- SLA comparison
  sla_id UUID REFERENCES slas(id) ON DELETE SET NULL,
  expected_time_minutes INTEGER, -- From SLA at time of calculation
  sla_compliance TEXT CHECK (sla_compliance IN ('on_time', 'warning', 'critical', 'violated', 'no_sla')),
  
  -- Snapshot fields
  postal_center_code_snapshot TEXT,
  postal_center_name_snapshot TEXT,
  from_postal_center_code_snapshot TEXT,
  from_postal_center_name_snapshot TEXT,
  to_postal_center_code_snapshot TEXT,
  to_postal_center_name_snapshot TEXT,
  
  -- Audit fields
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- Constraints
  CONSTRAINT journey_segments_operational_fields_check CHECK (
    (segment_type = 'operational' AND postal_center_id IS NOT NULL AND from_postal_center_id IS NULL AND to_postal_center_id IS NULL)
    OR
    (segment_type = 'distribution' AND from_postal_center_id IS NOT NULL AND to_postal_center_id IS NOT NULL AND postal_center_id IS NULL)
  ),
  CONSTRAINT journey_segments_times_check CHECK (
    exit_timestamp >= entry_timestamp AND
    exit_analysis_datetime >= entry_analysis_datetime AND
    actual_time_minutes >= 0 AND
    adjusted_time_minutes >= 0
  )
);

-- Indexes for journey_segments
CREATE INDEX idx_journey_segments_account ON journey_segments(account_id);
CREATE INDEX idx_journey_segments_tag_id ON journey_segments(tag_id);
CREATE INDEX idx_journey_segments_segment_type ON journey_segments(account_id, segment_type);
CREATE INDEX idx_journey_segments_operational ON journey_segments(account_id, postal_center_id) WHERE segment_type = 'operational';
CREATE INDEX idx_journey_segments_distribution ON journey_segments(account_id, from_postal_center_id, to_postal_center_id) WHERE segment_type = 'distribution';
CREATE INDEX idx_journey_segments_sla ON journey_segments(sla_id) WHERE sla_id IS NOT NULL;
CREATE INDEX idx_journey_segments_compliance ON journey_segments(account_id, sla_compliance);
CREATE INDEX idx_journey_segments_entry_timestamp ON journey_segments(entry_timestamp);

-- Comments
COMMENT ON TABLE journey_segments IS 'Calculated time segments for operational (within center) and distribution (between centers) routes';
COMMENT ON COLUMN journey_segments.actual_time_minutes IS 'Raw time difference between entry and exit';
COMMENT ON COLUMN journey_segments.adjusted_time_minutes IS 'Time excluding non-working hours and days';
COMMENT ON COLUMN journey_segments.pre_operational_wait_minutes IS 'Wait time before processing starts (arrival after cut-off)';
COMMENT ON COLUMN journey_segments.sla_compliance IS 'Performance against SLA: on_time, warning, critical, violated, or no_sla';

-- ============================================================================
-- Table 3: incidents
-- Stores detected anomalies and data quality issues
CREATE TABLE IF NOT EXISTS incidents (
  id BIGSERIAL PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  incident_type TEXT NOT NULL CHECK (incident_type IN (
    'exit_before_entry',
    'missing_entry',
    'missing_exit',
    'sla_violation',
    'stuck_sample',
    'missroute',
    'duplicate_event',
    'invalid_sequence'
  )),
  severity TEXT NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  
  -- Related entities
  tag_id TEXT,
  postal_center_id UUID REFERENCES postal_centers(id) ON DELETE SET NULL,
  reader_id UUID REFERENCES readers(id) ON DELETE SET NULL,
  event_id BIGINT REFERENCES processed_events(id) ON DELETE CASCADE,
  segment_id BIGINT REFERENCES journey_segments(id) ON DELETE CASCADE,
  
  -- Incident details
  description TEXT NOT NULL,
  metadata JSONB, -- Additional context (timestamps, values, etc.)
  
  -- Resolution
  is_resolved BOOLEAN NOT NULL DEFAULT false,
  resolved_at TIMESTAMPTZ,
  resolved_by UUID REFERENCES auth.users(id),
  resolution_notes TEXT,
  
  -- Audit fields
  detected_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for incidents
CREATE INDEX idx_incidents_account ON incidents(account_id);
CREATE INDEX idx_incidents_tag_id ON incidents(tag_id);
CREATE INDEX idx_incidents_type ON incidents(account_id, incident_type);
CREATE INDEX idx_incidents_severity ON incidents(account_id, severity);
CREATE INDEX idx_incidents_postal_center ON incidents(postal_center_id);
CREATE INDEX idx_incidents_unresolved ON incidents(account_id, is_resolved) WHERE is_resolved = false;
CREATE INDEX idx_incidents_detected_at ON incidents(detected_at);

-- Comments
COMMENT ON TABLE incidents IS 'Detected anomalies, data quality issues, and SLA violations';
COMMENT ON COLUMN incidents.incident_type IS 'Type of incident: exit_before_entry, missing_entry, missing_exit, sla_violation, stuck_sample, missroute, duplicate_event, invalid_sequence';
COMMENT ON COLUMN incidents.severity IS 'Severity level: low, medium, high, critical';
COMMENT ON COLUMN incidents.metadata IS 'Additional context in JSON format (timestamps, values, expected vs actual, etc.)';

-- ============================================================================
-- Table 4: journeys
-- Stores complete reconstructed journeys for each tag
CREATE TABLE IF NOT EXISTS journeys (
  id BIGSERIAL PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  tag_id TEXT NOT NULL,
  
  -- Route information (from ONE DB)
  origin_city_id UUID REFERENCES cities(id) ON DELETE SET NULL,
  destination_city_id UUID REFERENCES cities(id) ON DELETE SET NULL,
  origin_city_name TEXT,
  destination_city_name TEXT,
  
  -- Journey path
  route_path JSONB NOT NULL, -- Array of postal center IDs in visit order: [{center_id, code, name, entry_time, exit_time}, ...]
  total_centers_visited INTEGER NOT NULL DEFAULT 0,
  
  -- Calculated times (in minutes)
  total_actual_time_minutes INTEGER,
  total_adjusted_time_minutes INTEGER,
  total_operational_time_minutes INTEGER, -- Sum of all operational segments
  total_distribution_time_minutes INTEGER, -- Sum of all distribution segments
  total_pre_operational_wait_minutes INTEGER,
  
  -- Journey status
  journey_status TEXT NOT NULL CHECK (journey_status IN ('in_progress', 'completed', 'anomalous', 'stuck')),
  is_missroute BOOLEAN NOT NULL DEFAULT false,
  missroute_reason TEXT,
  
  -- Timestamps
  first_event_timestamp TIMESTAMPTZ,
  last_event_timestamp TIMESTAMPTZ,
  
  -- SLA summary
  total_sla_violations INTEGER NOT NULL DEFAULT 0,
  total_segments INTEGER NOT NULL DEFAULT 0,
  on_time_segments INTEGER NOT NULL DEFAULT 0,
  
  -- Audit fields
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- Unique constraint
  UNIQUE(account_id, tag_id)
);

-- Indexes for journeys
CREATE INDEX idx_journeys_account ON journeys(account_id);
CREATE INDEX idx_journeys_tag_id ON journeys(tag_id);
CREATE INDEX idx_journeys_status ON journeys(account_id, journey_status);
CREATE INDEX idx_journeys_origin_dest ON journeys(account_id, origin_city_id, destination_city_id);
CREATE INDEX idx_journeys_missroute ON journeys(account_id, is_missroute) WHERE is_missroute = true;
CREATE INDEX idx_journeys_first_event ON journeys(first_event_timestamp);
CREATE INDEX idx_journeys_last_event ON journeys(last_event_timestamp);

-- Comments
COMMENT ON TABLE journeys IS 'Complete reconstructed journeys for each tag with aggregated metrics';
COMMENT ON COLUMN journeys.route_path IS 'JSON array of postal centers visited in order with timestamps';
COMMENT ON COLUMN journeys.journey_status IS 'Status: in_progress (active), completed (finished), anomalous (has incidents), stuck (no movement)';
COMMENT ON COLUMN journeys.is_missroute IS 'Whether the journey path deviates from the statistically normal route';

-- ============================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

-- Enable RLS on all diagnosis tables
ALTER TABLE processed_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE journey_segments ENABLE ROW LEVEL SECURITY;
ALTER TABLE incidents ENABLE ROW LEVEL SECURITY;
ALTER TABLE journeys ENABLE ROW LEVEL SECURITY;

-- processed_events policies
CREATE POLICY "processed_events_select_policy" ON processed_events FOR SELECT
  USING (account_id = public.current_user_account_id() OR public.current_user_role() = 'superadmin');

CREATE POLICY "processed_events_insert_policy" ON processed_events FOR INSERT
  WITH CHECK (account_id = public.current_user_account_id());

CREATE POLICY "processed_events_update_policy" ON processed_events FOR UPDATE
  USING (account_id = public.current_user_account_id());

CREATE POLICY "processed_events_delete_policy" ON processed_events FOR DELETE
  USING (account_id = public.current_user_account_id());

-- journey_segments policies
CREATE POLICY "journey_segments_select_policy" ON journey_segments FOR SELECT
  USING (account_id = public.current_user_account_id() OR public.current_user_role() = 'superadmin');

CREATE POLICY "journey_segments_insert_policy" ON journey_segments FOR INSERT
  WITH CHECK (account_id = public.current_user_account_id());

CREATE POLICY "journey_segments_update_policy" ON journey_segments FOR UPDATE
  USING (account_id = public.current_user_account_id());

CREATE POLICY "journey_segments_delete_policy" ON journey_segments FOR DELETE
  USING (account_id = public.current_user_account_id());

-- incidents policies
CREATE POLICY "incidents_select_policy" ON incidents FOR SELECT
  USING (account_id = public.current_user_account_id() OR public.current_user_role() = 'superadmin');

CREATE POLICY "incidents_insert_policy" ON incidents FOR INSERT
  WITH CHECK (account_id = public.current_user_account_id());

CREATE POLICY "incidents_update_policy" ON incidents FOR UPDATE
  USING (account_id = public.current_user_account_id());

CREATE POLICY "incidents_delete_policy" ON incidents FOR DELETE
  USING (account_id = public.current_user_account_id());

-- journeys policies
CREATE POLICY "journeys_select_policy" ON journeys FOR SELECT
  USING (account_id = public.current_user_account_id() OR public.current_user_role() = 'superadmin');

CREATE POLICY "journeys_insert_policy" ON journeys FOR INSERT
  WITH CHECK (account_id = public.current_user_account_id());

CREATE POLICY "journeys_update_policy" ON journeys FOR UPDATE
  USING (account_id = public.current_user_account_id());

CREATE POLICY "journeys_delete_policy" ON journeys FOR DELETE
  USING (account_id = public.current_user_account_id());
