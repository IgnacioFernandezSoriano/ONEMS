-- ============================================================================
-- Fix: build_journey_segments() - Correct working time calculation
-- ============================================================================
-- Changes:
-- 1. Always calculate natural time
-- 2. For working time:
--    - If calculation_mode = 'working_days' → use calculate_working_time_minutes()
--    - If calculation_mode = 'natural_days' or NULL → working_time = natural_time
-- 3. Ensure working time is NEVER NULL when natural time exists
-- ============================================================================

CREATE OR REPLACE FUNCTION build_journey_segments(
    p_account_id UUID
) RETURNS JSON AS $$
DECLARE
    v_tag RECORD;
    v_center_visit RECORD;
    v_entry_time TIMESTAMPTZ;
    v_exit_time TIMESTAMPTZ;
    v_next_entry_time TIMESTAMPTZ;
    v_natural_time_in_center INTEGER;
    v_working_time_in_center INTEGER;
    v_natural_transit_time INTEGER;
    v_working_transit_time INTEGER;
    v_expected_time INTEGER;
    v_sla_compliance BOOLEAN;
    v_segments_created INTEGER := 0;
    v_start_time TIMESTAMPTZ := NOW();
    v_end_time TIMESTAMPTZ;
    v_duration_seconds NUMERIC;
    v_postal_center_code TEXT;
    v_postal_center_name TEXT;
    v_next_postal_center_code TEXT;
    v_next_postal_center_name TEXT;
    v_carrier_name TEXT;
    v_calculation_mode TEXT;
BEGIN
    -- Process each tag that has processed events
    FOR v_tag IN
        SELECT DISTINCT
            tag_id,
            carrier_id,
            product_id,
            origin_city_name,
            destination_city_name
        FROM processed_events
        WHERE account_id = p_account_id
          AND processed_at IS NULL  -- Not yet built into segments
        ORDER BY tag_id
    LOOP
        -- Get carrier name for snapshot
        SELECT name INTO v_carrier_name
        FROM carriers
        WHERE id = v_tag.carrier_id;
        
        -- For each postal center visited by this tag
        FOR v_center_visit IN
            WITH center_events AS (
                SELECT 
                    postal_center_id,
                    postal_center_code_snapshot,
                    postal_center_name_snapshot,
                    postal_center_city_snapshot,
                    event_type,
                    timestamp,
                    ROW_NUMBER() OVER (PARTITION BY postal_center_id ORDER BY timestamp) as visit_order
                FROM processed_events
                WHERE account_id = p_account_id
                  AND tag_id = v_tag.tag_id
                ORDER BY timestamp
            )
            SELECT
                postal_center_id,
                postal_center_code_snapshot,
                postal_center_name_snapshot,
                postal_center_city_snapshot,
                MIN(CASE WHEN event_type = 'entry' THEN timestamp END) as entry_time,
                MAX(CASE WHEN event_type = 'exit' THEN timestamp END) as exit_time
            FROM center_events
            GROUP BY postal_center_id, postal_center_code_snapshot, postal_center_name_snapshot, postal_center_city_snapshot
            ORDER BY entry_time, exit_time
        LOOP
            v_entry_time := v_center_visit.entry_time;
            v_exit_time := v_center_visit.exit_time;
            v_postal_center_code := v_center_visit.postal_center_code_snapshot;
            v_postal_center_name := v_center_visit.postal_center_name_snapshot;
            
            -- Get calculation_mode for this center
            SELECT COALESCE(calculation_mode, 'natural_days') INTO v_calculation_mode
            FROM postal_centers
            WHERE id = v_center_visit.postal_center_id;
            
            -- Get next entry time and next center info (for transit calculation)
            SELECT 
                MIN(pe.timestamp),
                pe.postal_center_code_snapshot,
                pe.postal_center_name_snapshot
            INTO 
                v_next_entry_time,
                v_next_postal_center_code,
                v_next_postal_center_name
            FROM processed_events pe
            WHERE pe.account_id = p_account_id
              AND pe.tag_id = v_tag.tag_id
              AND pe.event_type = 'entry'
              AND pe.timestamp > COALESCE(v_exit_time, v_entry_time)
            GROUP BY pe.postal_center_code_snapshot, pe.postal_center_name_snapshot
            LIMIT 1;
            
            -- ========================================
            -- Calculate Time in Center (Dual Tracking)
            -- ========================================
            IF v_entry_time IS NOT NULL AND v_exit_time IS NOT NULL THEN
                -- Natural time (always calculated)
                v_natural_time_in_center := EXTRACT(EPOCH FROM (v_exit_time - v_entry_time)) / 60;
                
                -- Working time (depends on calculation_mode)
                IF v_calculation_mode = 'working_days' THEN
                    v_working_time_in_center := calculate_working_time_minutes(v_entry_time, v_exit_time, v_center_visit.postal_center_id);
                ELSE
                    v_working_time_in_center := v_natural_time_in_center;
                END IF;
            ELSE
                v_natural_time_in_center := NULL;
                v_working_time_in_center := NULL;
            END IF;
            
            -- ========================================
            -- Calculate Transit Time (Dual Tracking)
            -- ========================================
            IF v_exit_time IS NOT NULL AND v_next_entry_time IS NOT NULL THEN
                -- Natural transit time (always calculated)
                v_natural_transit_time := EXTRACT(EPOCH FROM (v_next_entry_time - v_exit_time)) / 60;
                
                -- Working transit time (depends on calculation_mode of FROM center)
                IF v_calculation_mode = 'working_days' THEN
                    v_working_transit_time := calculate_working_time_minutes(v_exit_time, v_next_entry_time, v_center_visit.postal_center_id);
                ELSE
                    v_working_transit_time := v_natural_transit_time;
                END IF;
            ELSE
                v_natural_transit_time := NULL;
                v_working_transit_time := NULL;
            END IF;
            
            -- ========================================
            -- SLA Lookup and Compliance
            -- ========================================
            -- TODO: Fix delivery_standards lookup (uses city_id not city_name)
            -- For now, set to NULL
            v_expected_time := NULL;
            
            -- Calculate compliance (using working time)
            IF v_expected_time IS NOT NULL AND v_working_time_in_center IS NOT NULL AND v_working_transit_time IS NOT NULL THEN
                v_sla_compliance := (v_working_time_in_center + v_working_transit_time) <= v_expected_time;
            ELSE
                v_sla_compliance := NULL;
            END IF;
            
            -- ========================================
            -- Insert Journey Segment with ALL snapshot fields
            -- ========================================
            INSERT INTO journey_segments (
                account_id,
                tag_id,
                segment_type,
                carrier_id,
                carrier_name_snapshot,
                product_id,
                origin_city_name,
                destination_city_name,
                postal_center_id,
                postal_center_code_snapshot,
                postal_center_name_snapshot,
                from_postal_center_id,
                from_postal_center_code_snapshot,
                from_postal_center_name_snapshot,
                from_postal_center_city,
                to_postal_center_id,
                to_postal_center_code_snapshot,
                to_postal_center_name_snapshot,
                to_postal_center_city,
                entry_timestamp,
                exit_timestamp,
                next_entry_timestamp,
                natural_time_in_center_minutes,
                working_time_in_center_minutes,
                natural_transit_time_minutes,
                working_transit_time_minutes,
                expected_time_minutes,
                sla_compliance,
                created_at
            )
            VALUES (
                p_account_id,
                v_tag.tag_id,
                'distribution',  -- All segments are distribution type
                v_tag.carrier_id,
                v_carrier_name,
                v_tag.product_id,
                v_tag.origin_city_name,
                v_tag.destination_city_name,
                v_center_visit.postal_center_id,
                v_postal_center_code,
                v_postal_center_name,
                v_center_visit.postal_center_id,  -- from = current center
                v_postal_center_code,
                v_postal_center_name,
                v_center_visit.postal_center_city_snapshot,
                -- Get next center ID
                (SELECT postal_center_id 
                 FROM processed_events 
                 WHERE account_id = p_account_id 
                   AND tag_id = v_tag.tag_id 
                   AND timestamp = v_next_entry_time 
                 LIMIT 1),
                v_next_postal_center_code,
                v_next_postal_center_name,
                -- Get next center city
                (SELECT postal_center_city_snapshot 
                 FROM processed_events 
                 WHERE account_id = p_account_id 
                   AND tag_id = v_tag.tag_id 
                   AND timestamp = v_next_entry_time 
                 LIMIT 1),
                v_entry_time,
                v_exit_time,
                v_next_entry_time,
                v_natural_time_in_center,
                v_working_time_in_center,
                v_natural_transit_time,
                v_working_transit_time,
                v_expected_time,
                v_sla_compliance,
                NOW()
            );
            
            v_segments_created := v_segments_created + 1;
        END LOOP;
        
        -- Mark processed_events as processed
        UPDATE processed_events
        SET processed_at = NOW()
        WHERE account_id = p_account_id
          AND tag_id = v_tag.tag_id
          AND processed_at IS NULL;
    END LOOP;
    
    -- Calculate duration
    v_end_time := NOW();
    v_duration_seconds := EXTRACT(EPOCH FROM (v_end_time - v_start_time));
    
    -- Return summary
    RETURN json_build_object(
        'success', TRUE,
        'segments_created', v_segments_created,
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
