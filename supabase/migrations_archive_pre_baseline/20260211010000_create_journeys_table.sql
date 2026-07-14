-- =====================================================
-- Sprint 9: Complete Journey Assembly
-- =====================================================
-- Table: journeys
-- Purpose: Aggregate journey_segments by tag_id to create complete journey records

CREATE TABLE IF NOT EXISTS journeys (
    id BIGSERIAL PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    tag_id TEXT NOT NULL,
    
    -- Journey metadata
    total_segments INTEGER NOT NULL DEFAULT 0,
    operational_segments INTEGER NOT NULL DEFAULT 0,
    distribution_segments INTEGER NOT NULL DEFAULT 0,
    
    -- Timestamps
    journey_start_timestamp TIMESTAMPTZ NOT NULL,
    journey_end_timestamp TIMESTAMPTZ NOT NULL,
    
    -- Centers visited (ordered array)
    centers_visited TEXT[] NOT NULL DEFAULT '{}',
    center_ids_visited UUID[] NOT NULL DEFAULT '{}',
    
    -- Time metrics (minutes)
    total_actual_time_minutes INTEGER NOT NULL DEFAULT 0,
    total_adjusted_time_minutes INTEGER NOT NULL DEFAULT 0,
    total_operational_time_minutes INTEGER NOT NULL DEFAULT 0,
    total_distribution_time_minutes INTEGER NOT NULL DEFAULT 0,
    total_pre_operational_wait_minutes INTEGER,
    
    -- SLA compliance
    overall_sla_compliance TEXT CHECK (overall_sla_compliance IN ('on_time', 'warning', 'critical', 'violated', 'no_sla', 'mixed')),
    segments_on_time INTEGER NOT NULL DEFAULT 0,
    segments_warning INTEGER NOT NULL DEFAULT 0,
    segments_critical INTEGER NOT NULL DEFAULT 0,
    segments_violated INTEGER NOT NULL DEFAULT 0,
    segments_no_sla INTEGER NOT NULL DEFAULT 0,
    
    -- Journey status
    is_complete BOOLEAN NOT NULL DEFAULT false,
    has_gaps BOOLEAN NOT NULL DEFAULT false,
    
    -- Audit
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Constraints
    UNIQUE(account_id, tag_id)
);

-- Indexes for performance
CREATE INDEX idx_journeys_account_id ON journeys(account_id);
CREATE INDEX idx_journeys_tag_id ON journeys(tag_id);
CREATE INDEX idx_journeys_start_timestamp ON journeys(journey_start_timestamp);
CREATE INDEX idx_journeys_compliance ON journeys(overall_sla_compliance);
CREATE INDEX idx_journeys_complete ON journeys(is_complete);

-- RLS Policies
ALTER TABLE journeys ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view journeys from their account"
    ON journeys FOR SELECT
    USING (
        account_id IN (
            SELECT account_id FROM user_accounts WHERE user_id = auth.uid()
        )
    );

CREATE POLICY "System can insert journeys"
    ON journeys FOR INSERT
    WITH CHECK (true);

CREATE POLICY "System can update journeys"
    ON journeys FOR UPDATE
    USING (true);

CREATE POLICY "System can delete journeys"
    ON journeys FOR DELETE
    USING (true);

-- Comments
COMMENT ON TABLE journeys IS 'Complete journey records assembled from journey_segments, grouped by tag_id';
COMMENT ON COLUMN journeys.tag_id IS 'Unique identifier for the tracked item (e.g., RFID tag)';
COMMENT ON COLUMN journeys.centers_visited IS 'Ordered array of postal center names visited during journey';
COMMENT ON COLUMN journeys.overall_sla_compliance IS 'Overall compliance status: on_time, warning, critical, violated, no_sla, or mixed';
COMMENT ON COLUMN journeys.is_complete IS 'Whether journey has reached final destination';
COMMENT ON COLUMN journeys.has_gaps IS 'Whether journey has missing segments or gaps in timeline';
