-- ============================================================================
-- Fix: Correct consolidate_rfid_events() with actual column names
-- ============================================================================
-- Based on actual schema verification:
-- - processed_events has: postal_center_id (not postal_center_id_snapshot)
-- - processed_events has: reader_id (UUID) and reader_id_snapshot (TEXT)
-- - products has: code (not name)
-- ============================================================================

CREATE OR REPLACE FUNCTION consolidate_rfid_events(
    p_account_id UUID
) RETURNS JSON AS $$
DECLARE
    v_raw_event RECORD;
    v_reader_info RECORD;
    v_one_db_info RECORD;
    v_carrier_id UUID;
    v_product_id UUID;
    v_consolidated_event RECORD;
    v_analysis_datetime TIMESTAMPTZ;
    v_calculation_mode TEXT;
    v_gap_threshold_minutes INTEGER;
    v_events_processed INTEGER := 0;
    v_events_created INTEGER := 0;
    v_incidents_created INTEGER := 0;
    v_unknown_readers INTEGER := 0;
    v_unknown_tags INTEGER := 0;
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
            reader_id  -- TEXT (LPI)
        FROM rfid_events_raw
        WHERE account_id = p_account_id
        AND is_processed = FALSE
        ORDER BY tag_id, reader_id
    LOOP
        -- ========================================
        -- STEP 1: Get Reader Information by LPI
        -- ========================================
        SELECT 
            r.id AS reader_uuid,
            r.reader_id AS reader_lpi,
            r.type AS reader_type,
            r.mixed_reader_gap_minutes,
            pc.id AS postal_center_id,
            pc.name AS postal_center_name,
            pc.code AS postal_center_code,
            pc.city AS postal_center_city,
            pc.calculation_mode AS postal_center_calculation_mode
        INTO v_reader_info
        FROM readers r
        JOIN postal_centers pc ON pc.id = r.postal_center_id
        WHERE r.reader_id = v_raw_event.reader_id
          AND r.account_id = p_account_id;
        
        -- Check if reader exists
        IF v_reader_info.reader_uuid IS NULL THEN
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
                'Events detected from unknown reader LPI: ' || v_raw_event.reader_id,
                NOW(),
                jsonb_build_object(
                    'reader_lpi', v_raw_event.reader_id,
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
            
            CONTINUE;
        END IF;
        
        -- ========================================
        -- STEP 2: Get Journey Info from ONE DB
        -- ========================================
        SELECT 
            carrier_name,
            product_name,
            origin_city_name,
            destination_city_name
        INTO v_one_db_info
        FROM one_db
        WHERE tag_id = v_raw_event.tag_id
          AND account_id = p_account_id
        LIMIT 1;
        
        -- Check if tag exists in ONE DB
        IF v_one_db_info.carrier_name IS NULL THEN
            -- Unknown tag - create incident
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
                'unknown_tag',
                'medium',
                'Tag not found in ONE DB: ' || v_raw_event.tag_id,
                NOW(),
                jsonb_build_object(
                    'tag_id', v_raw_event.tag_id,
                    'reader_lpi', v_raw_event.reader_id
                )
            );
            
            v_unknown_tags := v_unknown_tags + 1;
            
            -- Mark events as processed but don't consolidate
            UPDATE rfid_events_raw
            SET is_processed = TRUE
            WHERE account_id = p_account_id
            AND tag_id = v_raw_event.tag_id
            AND reader_id = v_raw_event.reader_id
            AND is_processed = FALSE;
            
            CONTINUE;
        END IF;
        
        -- ========================================
        -- STEP 3: Convert Names to IDs
        -- ========================================
        -- Get carrier_id
        SELECT id INTO v_carrier_id
        FROM carriers
        WHERE name = v_one_db_info.carrier_name
          AND account_id = p_account_id
        LIMIT 1;
        
        -- Get product_id by code
        SELECT id INTO v_product_id
        FROM products
        WHERE code = v_one_db_info.product_name
        AND carrier_id = v_carrier_id
        LIMIT 1;
        
        -- ========================================
        -- STEP 4: Consolidate Based on Reader Type
        -- ========================================
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
                IF v_reader_info.postal_center_calculation_mode = 'working_days' THEN
                    v_analysis_datetime := calculate_next_working_datetime(
                        v_consolidated_event.timestamp,
                        v_reader_info.postal_center_id
                    );
                ELSE
                    v_analysis_datetime := v_consolidated_event.timestamp;
                END IF;
                
                -- Insert consolidated event with correct column names
                INSERT INTO processed_events (
                    account_id,
                    tag_id,
                    reader_id,
                    reader_id_snapshot,
                    reader_type_snapshot,
                    postal_center_id,
                    postal_center_name_snapshot,
                    postal_center_code_snapshot,
                    postal_center_city_snapshot,
                    carrier_id,
                    product_id,
                    origin_city_name,
                    destination_city_name,
                    event_type,
                    timestamp,
                    analysis_datetime,
                    raw_event_count,
                    is_consolidated,
                    is_estimated
                ) VALUES (
                    p_account_id,
                    v_raw_event.tag_id,
                    v_reader_info.reader_uuid,
                    v_reader_info.reader_lpi,
                    v_reader_info.reader_type,
                    v_reader_info.postal_center_id,
                    v_reader_info.postal_center_name,
                    v_reader_info.postal_center_code,
                    v_reader_info.postal_center_city,
                    v_carrier_id,
                    v_product_id,
                    v_one_db_info.origin_city_name,
                    v_one_db_info.destination_city_name,
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
                    reader_id_snapshot,
                    reader_type_snapshot,
                    postal_center_id,
                    postal_center_name_snapshot,
                    postal_center_code_snapshot,
                    postal_center_city_snapshot,
                    carrier_id,
                    product_id,
                    origin_city_name,
                    destination_city_name,
                    event_type,
                    timestamp,
                    analysis_datetime,
                    raw_event_count,
                    is_consolidated,
                    is_estimated
                ) VALUES (
                    p_account_id,
                    v_raw_event.tag_id,
                    v_reader_info.reader_uuid,
                    v_reader_info.reader_lpi,
                    v_reader_info.reader_type,
                    v_reader_info.postal_center_id,
                    v_reader_info.postal_center_name,
                    v_reader_info.postal_center_code,
                    v_reader_info.postal_center_city,
                    v_carrier_id,
                    v_product_id,
                    v_one_db_info.origin_city_name,
                    v_one_db_info.destination_city_name,
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
            -- Mixed reader: Use consolidate_mixed_reader_events function
            PERFORM consolidate_mixed_reader_events(
                p_account_id,
                v_raw_event.tag_id,
                v_raw_event.reader_id,
                v_reader_info.reader_uuid,
                v_reader_info.postal_center_id,
                COALESCE(v_reader_info.mixed_reader_gap_minutes, v_gap_threshold_minutes),
                v_carrier_id,
                v_product_id,
                v_one_db_info.origin_city_name,
                v_one_db_info.destination_city_name
            );
            
            v_events_created := v_events_created + 1;
        END IF;
        
        -- Mark raw events as processed
        UPDATE rfid_events_raw
        SET is_processed = TRUE
        WHERE account_id = p_account_id
        AND tag_id = v_raw_event.tag_id
        AND reader_id = v_raw_event.reader_id
        AND is_processed = FALSE;
        
        v_events_processed := v_events_processed + 1;
    END LOOP;
    
    -- Calculate duration
    v_end_time := NOW();
    v_duration_seconds := EXTRACT(EPOCH FROM (v_end_time - v_start_time));
    
    -- Return summary
    RETURN json_build_object(
        'success', TRUE,
        'events_processed', v_events_processed,
        'events_created', v_events_created,
        'unknown_readers', v_unknown_readers,
        'unknown_tags', v_unknown_tags,
        'duration_seconds', v_duration_seconds
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', FALSE,
            'error', SQLERRM
        );
END;
$$ LANGUAGE plpgsql;
