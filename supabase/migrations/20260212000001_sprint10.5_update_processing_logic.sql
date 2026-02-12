-- =====================================================
-- Sprint 10.5: Data Architecture & Preparation
-- Phase 2: Update Processing Logic
-- Date: 2026-02-12
-- =====================================================

-- =====================================================
-- 1. CREATE HELPER FUNCTION: Get Reader Location at Timestamp
-- =====================================================
-- Returns the postal_center_id where a reader was located at a specific time

CREATE OR REPLACE FUNCTION get_reader_location_at_time(
    p_reader_id UUID,
    p_timestamp TIMESTAMPTZ
)
RETURNS UUID
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_postal_center_id UUID;
BEGIN
    -- Find the location assignment that was active at the given timestamp
    SELECT postal_center_id INTO v_postal_center_id
    FROM reader_location_history
    WHERE reader_id = p_reader_id
      AND assigned_at <= p_timestamp
      AND (unassigned_at IS NULL OR unassigned_at > p_timestamp)
    ORDER BY assigned_at DESC
    LIMIT 1;
    
    -- If no history found, try current location from readers table
    IF v_postal_center_id IS NULL THEN
        SELECT postal_center_id INTO v_postal_center_id
        FROM readers
        WHERE id = p_reader_id;
    END IF;
    
    RETURN v_postal_center_id;
END;
$$;

COMMENT ON FUNCTION get_reader_location_at_time IS 
'Returns the postal center where a reader was located at a specific timestamp, using reader_location_history';

-- =====================================================
-- 2. UPDATE FUNCTION: Find Applicable SLA (with carrier support)
-- =====================================================
-- Enhanced to support carrier-specific SLAs

-- Drop old version first
DROP FUNCTION IF EXISTS find_applicable_sla(UUID, TEXT, UUID, UUID, UUID);

CREATE OR REPLACE FUNCTION find_applicable_sla(
    p_account_id UUID,
    p_segment_type TEXT,
    p_postal_center_id UUID DEFAULT NULL,
    p_from_postal_center_id UUID DEFAULT NULL,
    p_to_postal_center_id UUID DEFAULT NULL,
    p_carrier_id UUID DEFAULT NULL
)
RETURNS TABLE (
    sla_id UUID,
    expected_time_minutes INTEGER,
    on_time_percentage NUMERIC,
    warning_threshold NUMERIC,
    critical_threshold NUMERIC,
    carrier_id UUID
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF p_segment_type = 'operational' THEN
        -- Find operational SLA (carrier not relevant for operational)
        RETURN QUERY
        SELECT 
            s.id,
            s.expected_time_minutes,
            s.on_time_percentage,
            s.warning_threshold,
            s.critical_threshold,
            s.carrier_id
        FROM slas s
        WHERE s.account_id = p_account_id
          AND s.sla_type = 'operational'
          AND s.postal_center_id = p_postal_center_id
          AND s.is_active = TRUE
        LIMIT 1;
        
    ELSIF p_segment_type = 'distribution' THEN
        -- Find distribution SLA
        -- Priority: 1) Carrier-specific SLA, 2) Generic SLA (carrier_id IS NULL)
        RETURN QUERY
        SELECT 
            s.id,
            s.expected_time_minutes,
            s.on_time_percentage,
            s.warning_threshold,
            s.critical_threshold,
            s.carrier_id
        FROM slas s
        WHERE s.account_id = p_account_id
          AND s.sla_type = 'distribution'
          AND s.from_postal_center_id = p_from_postal_center_id
          AND s.to_postal_center_id = p_to_postal_center_id
          AND s.is_active = TRUE
          AND (
              -- Exact carrier match
              (p_carrier_id IS NOT NULL AND s.carrier_id = p_carrier_id)
              OR
              -- Generic SLA (no carrier specified)
              (s.carrier_id IS NULL)
          )
        ORDER BY 
            -- Prioritize carrier-specific SLAs
            CASE WHEN s.carrier_id IS NOT NULL THEN 1 ELSE 2 END
        LIMIT 1;
    END IF;
END;
$$;

COMMENT ON FUNCTION find_applicable_sla IS 
'Finds applicable SLA for a segment. For distribution segments, prioritizes carrier-specific SLAs over generic ones.';

-- =====================================================
-- 3. UPDATE FUNCTION: Reconstruct Journeys (with carrier support)
-- =====================================================
-- Enhanced to populate carrier information in journey_segments

-- Drop old version first
DROP FUNCTION IF EXISTS reconstruct_journeys(UUID, TEXT);

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
    v_carrier_id UUID;
    v_carrier_name TEXT;
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
                
                -- Find applicable SLA (no carrier for operational)
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
                
                -- Insert operational segment (no carrier)
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
                    postal_center_name_snapshot,
                    carrier_id,
                    carrier_name_snapshot
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
                    v_event.postal_center_name_snapshot,
                    NULL, -- No carrier for operational segments
                    NULL
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
                
                -- Identify carrier from postal_center_carriers
                -- For now, pick the first carrier associated with the destination center
                -- TODO: Future enhancement - identify carrier from tag or shipment data
                SELECT pcc.carrier_id, c.name INTO v_carrier_id, v_carrier_name
                FROM postal_center_carriers pcc
                JOIN carriers c ON c.id = pcc.carrier_id
                WHERE pcc.postal_center_id = v_event.postal_center_id
                LIMIT 1;
                
                -- Calculate times
                v_adjusted_time := calculate_adjusted_time(
                    v_prev_event.timestamp,
                    v_event.timestamp,
                    NULL -- Distribution doesn't have a single center
                );
                
                -- Find applicable SLA (with carrier if available)
                SELECT * INTO v_sla
                FROM find_applicable_sla(
                    v_event.account_id,
                    'distribution',
                    p_from_postal_center_id => v_prev_event.postal_center_id,
                    p_to_postal_center_id => v_event.postal_center_id,
                    p_carrier_id => v_carrier_id
                );
                
                -- Determine compliance
                v_compliance := determine_sla_compliance(
                    v_adjusted_time,
                    v_sla.expected_time_minutes,
                    v_sla.on_time_percentage,
                    v_sla.warning_threshold,
                    v_sla.critical_threshold
                );
                
                -- Insert distribution segment (with carrier)
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
                    to_postal_center_name_snapshot,
                    carrier_id,
                    carrier_name_snapshot
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
                    v_event.postal_center_name_snapshot,
                    v_carrier_id,
                    v_carrier_name
                )
                RETURNING id INTO v_segment_id;
                
                v_segments_created := v_segments_created + 1;
                
                -- Mark both events as consolidated
                UPDATE processed_events
                SET is_consolidated = true, processed_at = NOW()
                WHERE id IN (v_prev_event.id, v_event.id);
                
                v_events_processed := v_events_processed + 2;
                
                RAISE NOTICE 'Created distribution segment % for tag % from % to % (carrier: %)', 
                    v_segment_id, v_event.tag_id, 
                    v_prev_event.postal_center_code_snapshot,
                    v_event.postal_center_code_snapshot,
                    COALESCE(v_carrier_name, 'none');
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
'Reconstructs journey segments from processed events. Creates operational (within center) and distribution (between centers) segments with SLA compliance and carrier information.';

-- Grant execute permission
GRANT EXECUTE ON FUNCTION reconstruct_journeys(UUID, TEXT) TO authenticated;

-- =====================================================
-- END OF MIGRATION
-- =====================================================
