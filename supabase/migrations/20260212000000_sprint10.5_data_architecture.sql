-- =====================================================
-- Sprint 10.5: Data Architecture & Preparation
-- Phase 1: Schema Modifications
-- Date: 2026-02-12
-- =====================================================

-- =====================================================
-- 1. MODIFY readers TABLE
-- Allow readers to have NULL postal_center_id
-- =====================================================

ALTER TABLE readers 
ALTER COLUMN postal_center_id DROP NOT NULL;

COMMENT ON COLUMN readers.postal_center_id IS 'Current location of the reader (nullable). For historical locations, see reader_location_history table.';

-- =====================================================
-- 2. CREATE reader_location_history TABLE
-- Track reader location changes over time
-- =====================================================

CREATE TABLE IF NOT EXISTS reader_location_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reader_id UUID NOT NULL REFERENCES readers(id) ON DELETE CASCADE,
    postal_center_id UUID NOT NULL REFERENCES postal_centers(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ NOT NULL,
    unassigned_at TIMESTAMPTZ,
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id),
    updated_by UUID REFERENCES auth.users(id),
    
    -- Ensure no overlapping periods for the same reader
    CONSTRAINT check_assignment_period CHECK (unassigned_at IS NULL OR unassigned_at > assigned_at)
);

-- Indexes for performance
CREATE INDEX idx_reader_location_history_reader_id ON reader_location_history(reader_id);
CREATE INDEX idx_reader_location_history_postal_center_id ON reader_location_history(postal_center_id);
CREATE INDEX idx_reader_location_history_period ON reader_location_history(reader_id, assigned_at, unassigned_at);

-- Comments
COMMENT ON TABLE reader_location_history IS 'Historical record of reader assignments to postal centers. Enables tracking of mobile/temporary readers.';
COMMENT ON COLUMN reader_location_history.assigned_at IS 'Timestamp when the reader was assigned to this postal center';
COMMENT ON COLUMN reader_location_history.unassigned_at IS 'Timestamp when the reader was unassigned (NULL if currently assigned)';
COMMENT ON COLUMN reader_location_history.notes IS 'Optional notes about this assignment (e.g., "Temporary deployment for peak season")';

-- =====================================================
-- 3. CREATE postal_center_carriers TABLE
-- Many-to-many relationship between centers and carriers
-- =====================================================

CREATE TABLE IF NOT EXISTS postal_center_carriers (
    postal_center_id UUID NOT NULL REFERENCES postal_centers(id) ON DELETE CASCADE,
    carrier_id UUID NOT NULL REFERENCES carriers(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id),
    
    PRIMARY KEY (postal_center_id, carrier_id)
);

-- Index for reverse lookup
CREATE INDEX idx_postal_center_carriers_carrier_id ON postal_center_carriers(carrier_id);

-- Comments
COMMENT ON TABLE postal_center_carriers IS 'Junction table for N:M relationship between postal centers and carriers. Defines which carriers operate at each center.';

-- =====================================================
-- 4. MODIFY slas TABLE
-- Add carrier_id to enable carrier-specific SLAs
-- =====================================================

-- Add carrier_id column
ALTER TABLE slas 
ADD COLUMN carrier_id UUID REFERENCES carriers(id) ON DELETE SET NULL;

COMMENT ON COLUMN slas.carrier_id IS 'The carrier this SLA applies to. NULL means generic SLA (applies to all carriers).';

-- Drop existing unique constraint
ALTER TABLE slas 
DROP CONSTRAINT IF EXISTS unique_distribution_sla;

-- Add new unique constraint including carrier_id
-- Note: Using from_postal_center_id and to_postal_center_id (NOT origin/destination)
ALTER TABLE slas 
ADD CONSTRAINT slas_unique_route_carrier 
UNIQUE (account_id, from_postal_center_id, to_postal_center_id, carrier_id);

-- =====================================================
-- 5. MODIFY journey_segments TABLE
-- Add carrier information for distribution segments
-- =====================================================

-- Add carrier columns
ALTER TABLE journey_segments 
ADD COLUMN carrier_id UUID;

ALTER TABLE journey_segments 
ADD COLUMN carrier_name_snapshot TEXT;

-- Comments
COMMENT ON COLUMN journey_segments.carrier_id IS 'ID of the carrier responsible for this distribution segment (NULL for operational segments)';
COMMENT ON COLUMN journey_segments.carrier_name_snapshot IS 'Name of the carrier at the time of processing (snapshot for historical accuracy)';

-- Index for filtering by carrier
CREATE INDEX idx_journey_segments_carrier_id ON journey_segments(carrier_id) WHERE carrier_id IS NOT NULL;

-- =====================================================
-- 6. MIGRATE EXISTING READER DATA
-- Populate reader_location_history with current assignments
-- =====================================================

INSERT INTO reader_location_history (
    reader_id,
    postal_center_id,
    assigned_at,
    unassigned_at,
    notes,
    created_at
)
SELECT 
    id as reader_id,
    postal_center_id,
    created_at as assigned_at,
    NULL as unassigned_at,
    'Migrated from existing reader assignment' as notes,
    NOW() as created_at
FROM readers
WHERE postal_center_id IS NOT NULL;

-- =====================================================
-- 7. VERIFICATION QUERIES
-- Run these to verify the migration succeeded
-- =====================================================

-- Verify reader_location_history was populated
-- Expected: Count should match number of readers with postal_center_id
DO $$
DECLARE
    reader_count INT;
    history_count INT;
BEGIN
    SELECT COUNT(*) INTO reader_count FROM readers WHERE postal_center_id IS NOT NULL;
    SELECT COUNT(*) INTO history_count FROM reader_location_history;
    
    RAISE NOTICE 'Readers with location: %', reader_count;
    RAISE NOTICE 'Location history records: %', history_count;
    
    IF reader_count != history_count THEN
        RAISE WARNING 'Mismatch: % readers but % history records', reader_count, history_count;
    ELSE
        RAISE NOTICE 'Migration successful: All reader locations migrated to history';
    END IF;
END $$;

-- =====================================================
-- END OF MIGRATION
-- =====================================================
