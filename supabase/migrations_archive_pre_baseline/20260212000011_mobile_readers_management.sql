-- =====================================================
-- Sprint 10.5: Mobile Readers Management System
-- =====================================================
-- This migration implements automatic tracking of reader location changes
-- and provides functions for managing reader assignments.

-- =====================================================
-- 1. TRIGGER: Automatic Location History Tracking
-- =====================================================

CREATE OR REPLACE FUNCTION log_reader_location_change()
RETURNS TRIGGER AS $$
BEGIN
    -- Only process if postal_center_id actually changed
    IF OLD.postal_center_id IS DISTINCT FROM NEW.postal_center_id THEN
        
        -- Close previous assignment (if exists)
        IF OLD.postal_center_id IS NOT NULL THEN
            UPDATE reader_location_history
            SET unassigned_at = NOW(),
                updated_at = NOW()
            WHERE reader_id = OLD.id
              AND postal_center_id = OLD.postal_center_id
              AND unassigned_at IS NULL;
        END IF;
        
        -- Create new assignment (if not unassigning)
        IF NEW.postal_center_id IS NOT NULL THEN
            INSERT INTO reader_location_history (
                reader_id,
                postal_center_id,
                assigned_at,
                notes
            ) VALUES (
                NEW.id,
                NEW.postal_center_id,
                NOW(),
                'Automatic assignment via reader update'
            );
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS reader_location_change_trigger ON readers;
CREATE TRIGGER reader_location_change_trigger
    AFTER UPDATE ON readers
    FOR EACH ROW
    EXECUTE FUNCTION log_reader_location_change();

COMMENT ON FUNCTION log_reader_location_change() IS 'Automatically logs reader location changes to reader_location_history table';

-- =====================================================
-- 2. FUNCTION: Assign Reader to Center
-- =====================================================

CREATE OR REPLACE FUNCTION assign_reader_to_center(
    p_reader_id UUID,
    p_postal_center_id UUID,
    p_assigned_at TIMESTAMPTZ DEFAULT NOW(),
    p_unassigned_at TIMESTAMPTZ DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_history_id UUID;
BEGIN
    -- Close any existing open assignment
    UPDATE reader_location_history
    SET unassigned_at = p_assigned_at,
        updated_at = NOW()
    WHERE reader_id = p_reader_id
      AND unassigned_at IS NULL;
    
    -- Create new assignment
    INSERT INTO reader_location_history (
        reader_id,
        postal_center_id,
        assigned_at,
        unassigned_at,
        notes
    ) VALUES (
        p_reader_id,
        p_postal_center_id,
        p_assigned_at,
        p_unassigned_at,
        p_notes
    ) RETURNING id INTO v_history_id;
    
    -- Update reader's current location
    UPDATE readers
    SET postal_center_id = p_postal_center_id,
        updated_at = NOW()
    WHERE id = p_reader_id;
    
    RETURN v_history_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION assign_reader_to_center IS 'Assigns a reader to a postal center with optional start/end dates and notes';

-- =====================================================
-- 3. FUNCTION: Unassign Reader from Center
-- =====================================================

CREATE OR REPLACE FUNCTION unassign_reader_from_center(
    p_reader_id UUID,
    p_unassigned_at TIMESTAMPTZ DEFAULT NOW()
) RETURNS BOOLEAN AS $$
BEGIN
    -- Close current assignment
    UPDATE reader_location_history
    SET unassigned_at = p_unassigned_at,
        updated_at = NOW()
    WHERE reader_id = p_reader_id
      AND unassigned_at IS NULL;
    
    -- Update reader's current location to NULL
    UPDATE readers
    SET postal_center_id = NULL,
        updated_at = NOW()
    WHERE id = p_reader_id;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION unassign_reader_from_center IS 'Unassigns a reader from its current postal center';

-- =====================================================
-- 4. FUNCTION: Get Reader Location History
-- =====================================================

CREATE OR REPLACE FUNCTION get_reader_location_history(
    p_reader_id UUID
) RETURNS TABLE (
    id UUID,
    postal_center_id UUID,
    postal_center_code TEXT,
    postal_center_name TEXT,
    assigned_at TIMESTAMPTZ,
    unassigned_at TIMESTAMPTZ,
    duration_days INTEGER,
    is_current BOOLEAN,
    notes TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        rlh.id,
        rlh.postal_center_id,
        pc.code AS postal_center_code,
        pc.name AS postal_center_name,
        rlh.assigned_at,
        rlh.unassigned_at,
        CASE 
            WHEN rlh.unassigned_at IS NULL THEN 
                EXTRACT(DAY FROM NOW() - rlh.assigned_at)::INTEGER
            ELSE 
                EXTRACT(DAY FROM rlh.unassigned_at - rlh.assigned_at)::INTEGER
        END AS duration_days,
        (rlh.unassigned_at IS NULL) AS is_current,
        rlh.notes
    FROM reader_location_history rlh
    JOIN postal_centers pc ON pc.id = rlh.postal_center_id
    WHERE rlh.reader_id = p_reader_id
    ORDER BY rlh.assigned_at DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_reader_location_history IS 'Returns the complete location history for a reader with center details';

-- =====================================================
-- 5. FUNCTION: Get Mobile Readers Summary
-- =====================================================

CREATE OR REPLACE FUNCTION get_mobile_readers_summary(
    p_account_id UUID
) RETURNS TABLE (
    reader_id UUID,
    reader_code TEXT,
    reader_name TEXT,
    reader_type TEXT,
    current_center_id UUID,
    current_center_name TEXT,
    assigned_since TIMESTAMPTZ,
    total_assignments INTEGER,
    is_mobile BOOLEAN
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        r.id AS reader_id,
        r.reader_id AS reader_code,
        r.name AS reader_name,
        r.type AS reader_type,
        r.postal_center_id AS current_center_id,
        pc.name AS current_center_name,
        rlh_current.assigned_at AS assigned_since,
        (
            SELECT COUNT(*)::INTEGER
            FROM reader_location_history rlh2
            WHERE rlh2.reader_id = r.id
        ) AS total_assignments,
        (
            SELECT COUNT(*)::INTEGER > 1
            FROM reader_location_history rlh3
            WHERE rlh3.reader_id = r.id
        ) AS is_mobile
    FROM readers r
    LEFT JOIN postal_centers pc ON pc.id = r.postal_center_id
    LEFT JOIN reader_location_history rlh_current ON 
        rlh_current.reader_id = r.id 
        AND rlh_current.unassigned_at IS NULL
    WHERE r.account_id = p_account_id
      AND r.is_active = true
    ORDER BY is_mobile DESC, r.name;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_mobile_readers_summary IS 'Returns a summary of all readers with their mobility status and current assignment';

-- =====================================================
-- 6. VIEW: Mobile Readers Overview
-- =====================================================

CREATE OR REPLACE VIEW v_mobile_readers AS
SELECT 
    r.id AS reader_id,
    r.account_id,
    r.reader_id AS reader_code,
    r.name AS reader_name,
    r.type AS reader_type,
    r.postal_center_id AS current_center_id,
    pc.code AS current_center_code,
    pc.name AS current_center_name,
    rlh_current.assigned_at AS current_assignment_since,
    rlh_current.notes AS current_assignment_notes,
    (
        SELECT COUNT(*)
        FROM reader_location_history rlh2
        WHERE rlh2.reader_id = r.id
    ) AS total_assignments,
    (
        SELECT COUNT(*) > 1
        FROM reader_location_history rlh3
        WHERE rlh3.reader_id = r.id
    ) AS is_mobile,
    r.is_active,
    r.created_at,
    r.updated_at
FROM readers r
LEFT JOIN postal_centers pc ON pc.id = r.postal_center_id
LEFT JOIN reader_location_history rlh_current ON 
    rlh_current.reader_id = r.id 
    AND rlh_current.unassigned_at IS NULL
WHERE r.is_active = true;

COMMENT ON VIEW v_mobile_readers IS 'Consolidated view of all readers with their mobility status and current assignment';

-- =====================================================
-- 7. INDEXES for Performance
-- =====================================================

-- Already created in previous migration, but ensure they exist
CREATE INDEX IF NOT EXISTS idx_reader_location_history_reader_id 
    ON reader_location_history(reader_id);

CREATE INDEX IF NOT EXISTS idx_reader_location_history_postal_center_id 
    ON reader_location_history(postal_center_id);

CREATE INDEX IF NOT EXISTS idx_reader_location_history_period 
    ON reader_location_history(reader_id, assigned_at, unassigned_at);

CREATE INDEX IF NOT EXISTS idx_reader_location_history_current 
    ON reader_location_history(reader_id) 
    WHERE unassigned_at IS NULL;

-- =====================================================
-- 8. RLS POLICIES
-- =====================================================

-- Enable RLS on reader_location_history if not already enabled
ALTER TABLE reader_location_history ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view reader location history for their account" ON reader_location_history;
DROP POLICY IF EXISTS "Users can insert reader location history for their account" ON reader_location_history;
DROP POLICY IF EXISTS "Users can update reader location history for their account" ON reader_location_history;

-- Policy: View reader location history
CREATE POLICY "Users can view reader location history for their account"
    ON reader_location_history FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM readers r
            WHERE r.id = reader_location_history.reader_id
              AND r.account_id IN (
                  SELECT account_id FROM profiles WHERE id = auth.uid()
              )
        )
    );

-- Policy: Insert reader location history
CREATE POLICY "Users can insert reader location history for their account"
    ON reader_location_history FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM readers r
            WHERE r.id = reader_location_history.reader_id
              AND r.account_id IN (
                  SELECT account_id FROM profiles WHERE id = auth.uid()
              )
        )
    );

-- Policy: Update reader location history
CREATE POLICY "Users can update reader location history for their account"
    ON reader_location_history FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM readers r
            WHERE r.id = reader_location_history.reader_id
              AND r.account_id IN (
                  SELECT account_id FROM profiles WHERE id = auth.uid()
              )
        )
    );

-- =====================================================
-- END OF MIGRATION
-- =====================================================
