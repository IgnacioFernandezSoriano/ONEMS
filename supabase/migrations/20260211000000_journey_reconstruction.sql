-- =====================================================
-- Sprint 8: Journey Reconstruction
-- =====================================================
-- Description: Reconstruct journey segments from processed events
-- Author: Development Team
-- Date: 2026-02-11
-- =====================================================

-- =====================================================
-- 1. Helper Function: Calculate Adjusted Time
-- =====================================================
-- Calculates time excluding non-working hours and days
-- This function will be enhanced in future sprints to consider:
-- - Cut-off times
-- - Non-working day calendars
-- For now, it returns the actual time (no adjustment)

CREATE OR REPLACE FUNCTION calculate_adjusted_time(
    p_start_time TIMESTAMPTZ,
    p_end_time TIMESTAMPTZ,
    p_postal_center_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_actual_minutes INTEGER;
BEGIN
    -- Calculate actual time in minutes
    v_actual_minutes := EXTRACT(EPOCH FROM (p_end_time - p_start_time))::INTEGER / 60;
    
    -- TODO: Future enhancement - subtract non-working hours
    -- For now, return actual time
    RETURN v_actual_minutes;
END;
$$;

COMMENT ON FUNCTION calculate_adjusted_time IS 
'Calculates time excluding non-working hours and days. Currently returns actual time; will be enhanced with cut-off and calendar logic.';

-- =====================================================
-- 2. Helper Function: Calculate Pre-Operational Wait
-- =====================================================
-- Calculates wait time before processing starts
-- (difference between analysis_datetime and actual timestamp)

CREATE OR REPLACE FUNCTION calculate_pre_operational_wait(
    p_actual_entry_time TIMESTAMPTZ,
    p_analysis_entry_time TIMESTAMPTZ
)
RETURNS INTEGER
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_wait_minutes INTEGER;
BEGIN
    -- Calculate difference in minutes
    v_wait_minutes := EXTRACT(EPOCH FROM (p_analysis_entry_time - p_actual_entry_time))::INTEGER / 60;
    
    -- Return 0 if negative (shouldn't happen, but safety check)
    RETURN GREATEST(v_wait_minutes, 0);
END;
$$;

COMMENT ON FUNCTION calculate_pre_operational_wait IS 
'Calculates wait time before processing starts (arrival after cut-off time)';

-- =====================================================
-- 3. Helper Function: Find Applicable SLA
-- =====================================================

CREATE OR REPLACE FUNCTION find_applicable_sla(
    p_account_id UUID,
    p_segment_type TEXT,
    p_postal_center_id UUID DEFAULT NULL,
    p_from_postal_center_id UUID DEFAULT NULL,
    p_to_postal_center_id UUID DEFAULT NULL
)
RETURNS TABLE (
    sla_id UUID,
    expected_time_minutes INTEGER,
    on_time_percentage NUMERIC,
    warning_threshold NUMERIC,
    critical_threshold NUMERIC
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF p_segment_type = 'operational' THEN
        -- Find operational SLA
        RETURN QUERY
        SELECT 
            s.id,
            s.expected_time_minutes,
            s.on_time_percentage,
            s.warning_threshold,
            s.critical_threshold
        FROM slas s
        WHERE s.account_id = p_account_id
          AND s.sla_type = 'operational'
          AND s.postal_center_id = p_postal_center_id
          AND s.is_active = true
          AND s.deleted_at IS NULL
        LIMIT 1;
    ELSE
        -- Find distribution SLA
        RETURN QUERY
        SELECT 
            s.id,
            s.expected_time_minutes,
            s.on_time_percentage,
            s.warning_threshold,
            s.critical_threshold
        FROM slas s
        WHERE s.account_id = p_account_id
          AND s.sla_type = 'distribution'
          AND s.from_postal_center_id = p_from_postal_center_id
          AND s.to_postal_center_id = p_to_postal_center_id
          AND s.is_active = true
          AND s.deleted_at IS NULL
        LIMIT 1;
    END IF;
END;
$$;

COMMENT ON FUNCTION find_applicable_sla IS 
'Finds the applicable SLA for a segment (operational or distribution)';

-- =====================================================
-- 4. Helper Function: Determine SLA Compliance
-- =====================================================

CREATE OR REPLACE FUNCTION determine_sla_compliance(
    p_adjusted_time_minutes INTEGER,
    p_expected_time_minutes INTEGER,
    p_on_time_percentage NUMERIC,
    p_warning_threshold NUMERIC,
    p_critical_threshold NUMERIC
)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    v_performance_percentage NUMERIC;
BEGIN
    -- If no SLA, return 'no_sla'
    IF p_expected_time_minutes IS NULL THEN
        RETURN 'no_sla';
    END IF;
    
    -- Calculate performance percentage
    -- (adjusted_time / expected_time) * 100
    v_performance_percentage := (p_adjusted_time_minutes::NUMERIC / p_expected_time_minutes::NUMERIC) * 100;
    
    -- Determine compliance level
    IF v_performance_percentage <= p_on_time_percentage THEN
        RETURN 'on_time';
    ELSIF v_performance_percentage <= p_warning_threshold THEN
        RETURN 'warning';
    ELSIF v_performance_percentage <= p_critical_threshold THEN
        RETURN 'critical';
    ELSE
        RETURN 'violated';
    END IF;
END;
$$;

COMMENT ON FUNCTION determine_sla_compliance IS 
'Determines SLA compliance level based on performance vs thresholds';

-- =====================================================
-- 5. Main Function: Reconstruct Journeys
-- =====================================================

CREATE OR REPLACE FUNCTION reconstruct_journeys(
    p_account_id UUID DEFAULT NULL,
    p_tag_id TEXT DEFAULT NULL
)
RETURNS TABLE (
    segments_created INTEGER,
    events_processed INTEGER,
    execution_time_ms INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_segments_created INTEGER := 0;
    v_events_processed INTEGER := 0;
    v_event RECORD;
    v_prev_event RECORD := NULL;
    v_current_tag TEXT := NULL;
    v_segment_id BIGINT;
    v_sla RECORD;
    v_adjusted_time INTEGER;
    v_pre_op_wait INTEGER;
    v_compliance TEXT;
    v_pc RECORD; -- Postal center info
    v_from_pc RECORD; -- From postal center info
    v_to_pc RECORD; -- To postal center info
BEGIN
    v_start_time := clock_timestamp();
    
    RAISE NOTICE 'Starting journey reconstruction...';
    
    -- Process events in chronological order
    FOR v_event IN
        SELECT 
            pe.id,
            pe.account_id,
            pe.tag_id,
            pe.event_type,
            pe.postal_center_id,
            pe.timestamp,
            pe.analysis_datetime,
            pe.reader_id,
            pe.postal_center_code_snapshot,
            pe.postal_center_name_snapshot,
            pe.reader_id_snapshot,
            pe.reader_type_snapshot
        FROM processed_events pe
        WHERE pe.is_consolidated = false
          AND (p_account_id IS NULL OR pe.account_id = p_account_id)
          AND (p_tag_id IS NULL OR pe.tag_id = p_tag_id)
        ORDER BY pe.tag_id, pe.timestamp
    LOOP
        -- Check if we're starting a new tag
        IF v_current_tag IS NULL OR v_current_tag != v_event.tag_id THEN
            v_current_tag := v_event.tag_id;
            v_prev_event := NULL;
            RAISE NOTICE 'Processing tag: %', v_current_tag;
        END IF;
        
        -- If we have a previous event, try to create a segment
        IF v_prev_event IS NOT NULL THEN
            
            -- CASE 1: Operational Segment (same postal center, entry → exit)
            IF v_prev_event.postal_center_id = v_event.postal_center_id 
               AND v_prev_event.event_type = 'entry' 
               AND v_event.event_type = 'exit' THEN
                
                -- Calculate times
                v_adjusted_time := calculate_adjusted_time(
                    v_prev_event.timestamp,
                    v_event.timestamp,
                    v_event.postal_center_id
                );
                
                v_pre_op_wait := calculate_pre_operational_wait(
                    v_prev_event.timestamp,
                    v_prev_event.analysis_datetime
                );
                
                -- Find applicable SLA
                SELECT * INTO v_sla
                FROM find_applicable_sla(
                    v_event.account_id,
                    'operational',
                    p_postal_center_id => v_event.postal_center_id
                );
                
                -- Determine compliance
                v_compliance := determine_sla_compliance(
                    v_adjusted_time,
                    v_sla.expected_time_minutes,
                    v_sla.on_time_percentage,
                    v_sla.warning_threshold,
                    v_sla.critical_threshold
                );
                
                -- Insert operational segment
                INSERT INTO journey_segments (
                    account_id,
                    tag_id,
                    segment_type,
                    postal_center_id,
                    entry_event_id,
                    exit_event_id,
                    entry_timestamp,
                    exit_timestamp,
                    entry_analysis_datetime,
                    exit_analysis_datetime,
                    actual_time_minutes,
                    adjusted_time_minutes,
                    pre_operational_wait_minutes,
                    sla_id,
                    expected_time_minutes,
                    sla_compliance,
                    postal_center_code_snapshot,
                    postal_center_name_snapshot
                ) VALUES (
                    v_event.account_id,
                    v_event.tag_id,
                    'operational',
                    v_event.postal_center_id,
                    v_prev_event.id,
                    v_event.id,
                    v_prev_event.timestamp,
                    v_event.timestamp,
                    v_prev_event.analysis_datetime,
                    v_event.analysis_datetime,
                    EXTRACT(EPOCH FROM (v_event.timestamp - v_prev_event.timestamp))::INTEGER / 60,
                    v_adjusted_time,
                    v_pre_op_wait,
                    v_sla.sla_id,
                    v_sla.expected_time_minutes,
                    v_compliance,
                    v_event.postal_center_code_snapshot,
                    v_event.postal_center_name_snapshot
                )
                RETURNING id INTO v_segment_id;
                
                v_segments_created := v_segments_created + 1;
                
                -- Mark both events as consolidated
                UPDATE processed_events
                SET is_consolidated = true, processed_at = NOW()
                WHERE id IN (v_prev_event.id, v_event.id);
                
                v_events_processed := v_events_processed + 2;
                
                RAISE NOTICE 'Created operational segment % for tag % at center %', 
                    v_segment_id, v_event.tag_id, v_event.postal_center_code_snapshot;
                
            -- CASE 2: Distribution Segment (different postal centers, exit → entry)
            ELSIF v_prev_event.postal_center_id != v_event.postal_center_id 
                  AND v_prev_event.event_type = 'exit' 
                  AND v_event.event_type = 'entry' THEN
                
                -- Calculate times
                v_adjusted_time := calculate_adjusted_time(
                    v_prev_event.timestamp,
                    v_event.timestamp,
                    NULL -- Distribution doesn't have a single center
                );
                
                -- Find applicable SLA
                SELECT * INTO v_sla
                FROM find_applicable_sla(
                    v_event.account_id,
                    'distribution',
                    p_from_postal_center_id => v_prev_event.postal_center_id,
                    p_to_postal_center_id => v_event.postal_center_id
                );
                
                -- Determine compliance
                v_compliance := determine_sla_compliance(
                    v_adjusted_time,
                    v_sla.expected_time_minutes,
                    v_sla.on_time_percentage,
                    v_sla.warning_threshold,
                    v_sla.critical_threshold
                );
                
                -- Insert distribution segment
                INSERT INTO journey_segments (
                    account_id,
                    tag_id,
                    segment_type,
                    from_postal_center_id,
                    to_postal_center_id,
                    entry_event_id,
                    exit_event_id,
                    entry_timestamp,
                    exit_timestamp,
                    entry_analysis_datetime,
                    exit_analysis_datetime,
                    actual_time_minutes,
                    adjusted_time_minutes,
                    pre_operational_wait_minutes,
                    sla_id,
                    expected_time_minutes,
                    sla_compliance,
                    from_postal_center_code_snapshot,
                    from_postal_center_name_snapshot,
                    to_postal_center_code_snapshot,
                    to_postal_center_name_snapshot
                ) VALUES (
                    v_event.account_id,
                    v_event.tag_id,
                    'distribution',
                    v_prev_event.postal_center_id,
                    v_event.postal_center_id,
                    v_prev_event.id,
                    v_event.id,
                    v_prev_event.timestamp,
                    v_event.timestamp,
                    v_prev_event.analysis_datetime,
                    v_event.analysis_datetime,
                    EXTRACT(EPOCH FROM (v_event.timestamp - v_prev_event.timestamp))::INTEGER / 60,
                    v_adjusted_time,
                    NULL, -- No pre-op wait for distribution
                    v_sla.sla_id,
                    v_sla.expected_time_minutes,
                    v_compliance,
                    v_prev_event.postal_center_code_snapshot,
                    v_prev_event.postal_center_name_snapshot,
                    v_event.postal_center_code_snapshot,
                    v_event.postal_center_name_snapshot
                )
                RETURNING id INTO v_segment_id;
                
                v_segments_created := v_segments_created + 1;
                
                -- Mark both events as consolidated
                UPDATE processed_events
                SET is_consolidated = true, processed_at = NOW()
                WHERE id IN (v_prev_event.id, v_event.id);
                
                v_events_processed := v_events_processed + 2;
                
                RAISE NOTICE 'Created distribution segment % for tag % from % to %', 
                    v_segment_id, v_event.tag_id, 
                    v_prev_event.postal_center_code_snapshot,
                    v_event.postal_center_code_snapshot;
            END IF;
        END IF;
        
        -- Store current event as previous for next iteration
        v_prev_event := v_event;
    END LOOP;
    
    RAISE NOTICE 'Journey reconstruction completed: % segments created, % events processed',
        v_segments_created, v_events_processed;
    
    -- Return results
    RETURN QUERY SELECT 
        v_segments_created,
        v_events_processed,
        EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_start_time))::INTEGER;
END;
$$;

COMMENT ON FUNCTION reconstruct_journeys IS 
'Reconstructs journey segments from processed events. Creates operational (within center) and distribution (between centers) segments with SLA compliance.';

-- Grant execute permission
GRANT EXECUTE ON FUNCTION reconstruct_journeys(UUID, TEXT) TO authenticated;

-- =====================================================
-- Summary
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '✅ Journey reconstruction functions created';
    RAISE NOTICE '';
    RAISE NOTICE '📋 Functions:';
    RAISE NOTICE '   - calculate_adjusted_time()';
    RAISE NOTICE '   - calculate_pre_operational_wait()';
    RAISE NOTICE '   - find_applicable_sla()';
    RAISE NOTICE '   - determine_sla_compliance()';
    RAISE NOTICE '   - reconstruct_journeys()';
    RAISE NOTICE '';
    RAISE NOTICE '🔍 Usage:';
    RAISE NOTICE '   - Reconstruct all: SELECT * FROM reconstruct_journeys();';
    RAISE NOTICE '   - Reconstruct for account: SELECT * FROM reconstruct_journeys(''account-uuid'');';
    RAISE NOTICE '   - Reconstruct for tag: SELECT * FROM reconstruct_journeys(NULL, ''TAG-001'');';
END $$;
