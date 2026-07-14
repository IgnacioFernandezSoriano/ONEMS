-- =====================================================
-- Sprint 7: Event Consolidation - Main Function
-- =====================================================
-- Description: Main consolidation orchestrator function
-- Author: Development Team
-- Date: 2026-02-10
-- =====================================================

-- =====================================================
-- 7. Main Consolidation Function
-- =====================================================
-- Orchestrates the entire consolidation process

CREATE OR REPLACE FUNCTION consolidate_rfid_events(
    p_account_id UUID
) RETURNS JSON AS $$
DECLARE
    v_raw_event RECORD;
    v_reader_info RECORD;
    v_consolidated_event RECORD;
    v_analysis_datetime TIMESTAMPTZ;
    v_calculation_mode TEXT;
    v_gap_threshold_minutes INTEGER;
    v_events_processed INTEGER := 0;
    v_events_created INTEGER := 0;
    v_incidents_created INTEGER := 0;
    v_unknown_readers INTEGER := 0;
    v_start_time TIMESTAMPTZ := NOW();
    v_end_time TIMESTAMPTZ;
    v_duration_seconds NUMERIC;
BEGIN
    -- Get account configuration
    SELECT 
        calculation_mode,
        gap_threshold_minutes
    INTO 
        v_calculation_mode,
        v_gap_threshold_minutes
    FROM accounts
    WHERE id = p_account_id;
    
    -- Default values if not set
    v_calculation_mode := COALESCE(v_calculation_mode, 'natural_days');
    v_gap_threshold_minutes := COALESCE(v_gap_threshold_minutes, 30);
    
    -- Process each unique tag + reader combination
    FOR v_raw_event IN
        SELECT DISTINCT
            tag_id,
            reader_id
        FROM rfid_events_raw
        WHERE account_id = p_account_id
        AND is_processed = FALSE
        ORDER BY tag_id, reader_id
    LOOP
        -- Get reader information
        SELECT * INTO v_reader_info
        FROM get_reader_info(v_raw_event.reader_id, p_account_id);
        
        -- Check if reader exists
        IF v_reader_info.reader_id IS NULL THEN
            -- Unknown reader - create incident
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
                v_raw_event.tag_id,
                'unknown_reader',
                'low',
                'Events detected from unknown reader: ' || v_raw_event.reader_id,
                NOW(),
                jsonb_build_object(
                    'reader_code', v_raw_event.reader_id,
                    'tag_id', v_raw_event.tag_id
                )
            );
            
            v_unknown_readers := v_unknown_readers + 1;
            
            -- Mark events as processed but don't consolidate
            UPDATE rfid_events_raw
            SET is_processed = TRUE
            WHERE account_id = p_account_id
            AND tag_id = v_raw_event.tag_id
            AND reader_id = v_raw_event.reader_id
            AND is_processed = FALSE;
            
            -- Archive raw events
            PERFORM archive_raw_events(p_account_id, v_raw_event.tag_id, v_raw_event.reader_id);
            
            CONTINUE;
        END IF;
        
        -- Consolidate based on reader type
        IF v_reader_info.reader_type = 'Entry' THEN
            -- Entry reader: MIN timestamp
            FOR v_consolidated_event IN
                SELECT
                    'entry' AS event_type,
                    MIN(read_local_datetime) AS timestamp,
                    COUNT(*) AS raw_event_count
                FROM rfid_events_raw
                WHERE account_id = p_account_id
                AND tag_id = v_raw_event.tag_id
                AND reader_id = v_raw_event.reader_id
                AND is_processed = FALSE
            LOOP
                -- Calculate analysis_datetime if working_days mode
                IF v_calculation_mode = 'working_days' THEN
                    v_analysis_datetime := calculate_next_working_datetime(
                        v_consolidated_event.timestamp,
                        v_reader_info.postal_center_id
                    );
                ELSE
                    v_analysis_datetime := v_consolidated_event.timestamp;
                END IF;
                
                -- Insert consolidated event
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
                    v_raw_event.tag_id,
                    v_reader_info.reader_id,
                    v_reader_info.postal_center_id,
                    v_reader_info.postal_center_name,
                    v_reader_info.postal_center_code,
                    v_consolidated_event.event_type,
                    v_consolidated_event.timestamp,
                    v_analysis_datetime,
                    v_consolidated_event.raw_event_count,
                    TRUE,
                    FALSE
                );
                
                v_events_created := v_events_created + 1;
            END LOOP;
            
        ELSIF v_reader_info.reader_type = 'Exit' THEN
            -- Exit reader: MAX timestamp
            FOR v_consolidated_event IN
                SELECT
                    'exit' AS event_type,
                    MAX(read_local_datetime) AS timestamp,
                    COUNT(*) AS raw_event_count
                FROM rfid_events_raw
                WHERE account_id = p_account_id
                AND tag_id = v_raw_event.tag_id
                AND reader_id = v_raw_event.reader_id
                AND is_processed = FALSE
            LOOP
                -- No analysis_datetime adjustment for exit events
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
                    v_raw_event.tag_id,
                    v_reader_info.reader_id,
                    v_reader_info.postal_center_id,
                    v_reader_info.postal_center_name,
                    v_reader_info.postal_center_code,
                    v_consolidated_event.event_type,
                    v_consolidated_event.timestamp,
                    v_consolidated_event.timestamp, -- No adjustment
                    v_consolidated_event.raw_event_count,
                    TRUE,
                    FALSE
                );
                
                v_events_created := v_events_created + 1;
            END LOOP;
            
        ELSIF v_reader_info.reader_type = 'Mixed' THEN
            -- Mixed reader: Detect sequences with gap
            FOR v_consolidated_event IN
                SELECT * FROM consolidate_mixed_reader_events(
                    p_account_id,
                    v_raw_event.tag_id,
                    v_raw_event.reader_id,
                    v_gap_threshold_minutes
                )
            LOOP
                -- Calculate analysis_datetime only for entry events
                IF v_consolidated_event.event_type = 'entry' AND v_calculation_mode = 'working_days' THEN
                    v_analysis_datetime := calculate_next_working_datetime(
                        v_consolidated_event.timestamp,
                        v_reader_info.postal_center_id
                    );
                ELSE
                    v_analysis_datetime := v_consolidated_event.timestamp;
                END IF;
                
                -- Insert consolidated event
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
                    v_raw_event.tag_id,
                    v_reader_info.reader_id,
                    v_reader_info.postal_center_id,
                    v_reader_info.postal_center_name,
                    v_reader_info.postal_center_code,
                    v_consolidated_event.event_type,
                    v_consolidated_event.timestamp,
                    v_analysis_datetime,
                    v_consolidated_event.raw_event_count,
                    TRUE,
                    FALSE
                );
                
                v_events_created := v_events_created + 1;
            END LOOP;
        END IF;
        
        -- Mark raw events as processed
        UPDATE rfid_events_raw
        SET is_processed = TRUE
        WHERE account_id = p_account_id
        AND tag_id = v_raw_event.tag_id
        AND reader_id = v_raw_event.reader_id
        AND is_processed = FALSE;
        
        -- Archive raw events
        PERFORM archive_raw_events(p_account_id, v_raw_event.tag_id, v_raw_event.reader_id);
        
        v_events_processed := v_events_processed + 1;
    END LOOP;
    
    -- Detect missing exits
    v_incidents_created := detect_missing_exits(p_account_id);
    
    -- Calculate duration
    v_end_time := NOW();
    v_duration_seconds := EXTRACT(EPOCH FROM (v_end_time - v_start_time));
    
    -- Return summary
    RETURN json_build_object(
        'success', TRUE,
        'events_processed', v_events_processed,
        'events_created', v_events_created,
        'incidents_created', v_incidents_created,
        'unknown_readers', v_unknown_readers,
        'duration_seconds', v_duration_seconds,
        'start_time', v_start_time,
        'end_time', v_end_time
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', FALSE,
            'error', SQLERRM,
            'events_processed', v_events_processed,
            'events_created', v_events_created
        );
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- Summary
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '✅ Main consolidation function created successfully';
    RAISE NOTICE '   - consolidate_rfid_events(account_id)';
    RAISE NOTICE '';
    RAISE NOTICE '📋 All consolidation functions ready:';
    RAISE NOTICE '   1. calculate_next_working_datetime()';
    RAISE NOTICE '   2. calculate_working_days_time()';
    RAISE NOTICE '   3. get_reader_info()';
    RAISE NOTICE '   4. consolidate_mixed_reader_events()';
    RAISE NOTICE '   5. detect_missing_exits()';
    RAISE NOTICE '   6. archive_raw_events()';
    RAISE NOTICE '   7. consolidate_rfid_events() [MAIN]';
END $$;
