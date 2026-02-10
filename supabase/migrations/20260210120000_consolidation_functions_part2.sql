-- =====================================================
-- Sprint 7: Event Consolidation - SQL Functions (Part 2)
-- =====================================================
-- Description: Consolidation functions by reader type
-- Author: Development Team
-- Date: 2026-02-10
-- =====================================================

-- =====================================================
-- 4. Consolidate Mixed Reader Events
-- =====================================================
-- Detects sequences separated by gap > threshold
-- Generates entry (first) and exit (last) for each sequence

CREATE OR REPLACE FUNCTION consolidate_mixed_reader_events(
    p_account_id UUID,
    p_tag_id TEXT,
    p_reader_code TEXT,
    p_gap_threshold_minutes INTEGER
) RETURNS TABLE (
    event_type TEXT,
    timestamp TIMESTAMPTZ,
    raw_event_count INTEGER
) AS $$
DECLARE
    v_events RECORD;
    v_prev_timestamp TIMESTAMPTZ;
    v_gap_minutes NUMERIC;
    v_sequence_start TIMESTAMPTZ;
    v_sequence_end TIMESTAMPTZ;
    v_sequence_count INTEGER;
    v_max_gap_minutes NUMERIC := 0;
    v_max_gap_index INTEGER := 0;
    v_event_array TIMESTAMPTZ[];
    v_i INTEGER;
BEGIN
    -- Get all events ordered by timestamp
    SELECT ARRAY_AGG(read_local_datetime ORDER BY read_local_datetime)
    INTO v_event_array
    FROM rfid_events_raw
    WHERE account_id = p_account_id
    AND tag_id = p_tag_id
    AND reader_id = p_reader_code
    AND is_processed = FALSE;
    
    -- If no events or only one event, return nothing
    IF v_event_array IS NULL OR array_length(v_event_array, 1) < 2 THEN
        RETURN;
    END IF;
    
    -- Find the maximum gap between consecutive events
    FOR v_i IN 2..array_length(v_event_array, 1) LOOP
        v_gap_minutes := EXTRACT(EPOCH FROM (v_event_array[v_i] - v_event_array[v_i-1]))::NUMERIC / 60;
        
        IF v_gap_minutes > v_max_gap_minutes THEN
            v_max_gap_minutes := v_gap_minutes;
            v_max_gap_index := v_i;
        END IF;
    END LOOP;
    
    -- If max gap > threshold, we have entry and exit
    IF v_max_gap_minutes > p_gap_threshold_minutes THEN
        -- Entry event: first reading before the gap
        event_type := 'entry';
        timestamp := v_event_array[1];
        raw_event_count := v_max_gap_index - 1;
        RETURN NEXT;
        
        -- Exit event: last reading after the gap
        event_type := 'exit';
        timestamp := v_event_array[array_length(v_event_array, 1)];
        raw_event_count := array_length(v_event_array, 1) - v_max_gap_index + 1;
        RETURN NEXT;
    ELSE
        -- No significant gap, only entry event (still inside center)
        event_type := 'entry';
        timestamp := v_event_array[1];
        raw_event_count := array_length(v_event_array, 1);
        RETURN NEXT;
    END IF;
    
    RETURN;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 5. Detect Missing Exits
-- =====================================================
-- Finds tags with entry but no exit after 24 hours
-- Creates estimated exit events using SLA

CREATE OR REPLACE FUNCTION detect_missing_exits(
    p_account_id UUID
) RETURNS INTEGER AS $$
DECLARE
    v_missing_exit RECORD;
    v_estimated_exit_timestamp TIMESTAMPTZ;
    v_sla_minutes INTEGER;
    v_count INTEGER := 0;
BEGIN
    FOR v_missing_exit IN
        SELECT DISTINCT ON (pe_entry.tag_id, pe_entry.postal_center_id)
            pe_entry.tag_id,
            pe_entry.postal_center_id,
            pe_entry.reader_id,
            pe_entry.timestamp AS entry_timestamp,
            pe_entry.analysis_datetime AS entry_analysis_datetime,
            pc.name AS postal_center_name,
            pc.code AS postal_center_code,
            sla.expected_time_minutes
        FROM processed_events pe_entry
        JOIN postal_centers pc ON pe_entry.postal_center_id = pc.id
        LEFT JOIN processed_events pe_exit
            ON pe_entry.tag_id = pe_exit.tag_id
            AND pe_entry.postal_center_id = pe_exit.postal_center_id
            AND pe_exit.event_type = 'exit'
            AND pe_exit.timestamp > pe_entry.timestamp
        LEFT JOIN slas sla
            ON sla.postal_center_id = pe_entry.postal_center_id
            AND sla.sla_type = 'operational'
            AND sla.deleted_at IS NULL
        WHERE pe_entry.account_id = p_account_id
        AND pe_entry.event_type = 'entry'
        AND pe_exit.id IS NULL
        AND pe_entry.timestamp < NOW() - INTERVAL '24 hours'
        AND pe_entry.is_estimated = FALSE
        ORDER BY pe_entry.tag_id, pe_entry.postal_center_id, pe_entry.timestamp DESC
    LOOP
        -- Get SLA time or default to 3 hours
        v_sla_minutes := COALESCE(v_missing_exit.expected_time_minutes, 180);
        
        -- Calculate estimated exit timestamp
        v_estimated_exit_timestamp := v_missing_exit.entry_timestamp + 
                                      (v_sla_minutes || ' minutes')::INTERVAL;
        
        -- Create estimated exit event
        INSERT INTO processed_events (
            account_id,
            tag_id,
            reader_id,
            postal_center_id,
            postal_center_name_snapshot,
            postal_center_code_snapshot,
            event_type,
            timestamp,
            analysis_datetime,
            raw_event_count,
            is_consolidated,
            is_estimated
        ) VALUES (
            p_account_id,
            v_missing_exit.tag_id,
            v_missing_exit.reader_id,
            v_missing_exit.postal_center_id,
            v_missing_exit.postal_center_name,
            v_missing_exit.postal_center_code,
            'exit',
            v_estimated_exit_timestamp,
            v_estimated_exit_timestamp, -- No adjustment for exit
            0, -- No raw events
            TRUE,
            TRUE -- Marked as estimated
        );
        
        -- Create incident
        INSERT INTO incidents (
            account_id,
            tag_id,
            incident_type,
            severity,
            description,
            detected_at,
            metadata
        ) VALUES (
            p_account_id,
            v_missing_exit.tag_id,
            'missing_exit',
            'medium',
            'Exit event missing for ' || v_missing_exit.tag_id || ' at ' || 
            v_missing_exit.postal_center_name || '. Exit estimated using SLA (' || 
            v_sla_minutes || ' minutes).',
            NOW(),
            jsonb_build_object(
                'postal_center_id', v_missing_exit.postal_center_id,
                'entry_timestamp', v_missing_exit.entry_timestamp,
                'estimated_exit_timestamp', v_estimated_exit_timestamp,
                'sla_minutes', v_sla_minutes
            )
        );
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 6. Archive Raw Events
-- =====================================================
-- Moves processed raw events to audit table and deletes them

CREATE OR REPLACE FUNCTION archive_raw_events(
    p_account_id UUID,
    p_tag_id TEXT,
    p_reader_code TEXT
) RETURNS VOID AS $$
BEGIN
    -- Insert into audit table
    INSERT INTO audit_raw_reads (
        account_id,
        tag_id,
        reader_id,
        first_read_datetime,
        last_read_datetime,
        read_count
    )
    SELECT
        account_id,
        tag_id,
        reader_id,
        MIN(read_local_datetime),
        MAX(read_local_datetime),
        COUNT(*)
    FROM rfid_events_raw
    WHERE account_id = p_account_id
    AND tag_id = p_tag_id
    AND reader_id = p_reader_code
    AND is_processed = FALSE
    GROUP BY account_id, tag_id, reader_id;
    
    -- Delete from raw table
    DELETE FROM rfid_events_raw
    WHERE account_id = p_account_id
    AND tag_id = p_tag_id
    AND reader_id = p_reader_code
    AND is_processed = FALSE;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- Summary
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '✅ Consolidation functions created successfully';
    RAISE NOTICE '   - consolidate_mixed_reader_events()';
    RAISE NOTICE '   - detect_missing_exits()';
    RAISE NOTICE '   - archive_raw_events()';
END $$;
