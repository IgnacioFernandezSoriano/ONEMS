-- =====================================================
-- Fix: Change return type from INTEGER to BIGINT
-- =====================================================
-- Issue: Supabase RPC expects BIGINT for numeric types
-- This fixes "Returned type integer does not match expected type numeric" error

CREATE OR REPLACE FUNCTION reconstruct_journeys(
    p_account_id UUID DEFAULT NULL,
    p_tag_id TEXT DEFAULT NULL
)
RETURNS TABLE (
    segments_created BIGINT,
    events_processed BIGINT,
    execution_time_ms BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_segments_created BIGINT := 0;
    v_events_processed BIGINT := 0;
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
                SET is_consolidated = true 
                WHERE id IN (v_prev_event.id, v_event.id);
                
                v_events_processed := v_events_processed + 2;
                
                RAISE NOTICE 'Created operational segment % for tag % at center %', 
                    v_segment_id, v_event.tag_id, v_event.postal_center_code_snapshot;
                
            -- CASE 2: Distribution Segment (different centers, exit → entry)
            ELSIF v_prev_event.postal_center_id != v_event.postal_center_id 
                  AND v_prev_event.event_type = 'exit' 
                  AND v_event.event_type = 'entry' THEN
                
                -- Calculate times
                v_adjusted_time := calculate_adjusted_time(
                    v_prev_event.timestamp,
                    v_event.timestamp,
                    NULL -- No single postal center for distribution
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
                SET is_consolidated = true 
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
        EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time))::BIGINT * 1000;
END;
$$;

COMMENT ON FUNCTION reconstruct_journeys IS 
'Reconstructs journey segments from processed events. Returns BIGINT types for Supabase RPC compatibility.';
