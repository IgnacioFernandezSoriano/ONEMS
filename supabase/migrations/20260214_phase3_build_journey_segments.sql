-- ============================================================================
-- Phase 3: build_journey_segments() with Dual Time Tracking
-- ============================================================================
-- Creates journey segments from processed_events with:
-- 1. Entry/Exit detection per postal center
-- 2. Dual time tracking (natural + working)
-- 3. SLA lookup and compliance calculation
-- 4. Propagation of carrier/product/origin/destination
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
        -- For each postal center visited by this tag
        FOR v_center_visit IN
            WITH center_events AS (
                SELECT 
                    postal_center_id,
                    postal_center_city_snapshot,
                    event_type,
                    timestamp,
                    ROW_NUMBER() OVER (PARTITION BY postal_center_id ORDER BY timestamp) as visit_order
                FROM processed_events
                WHERE account_id = p_account_id
                  AND tag_id = v_tag.tag_id
                ORDER BY timestamp
            )
            SELECT DISTINCT
                postal_center_id,
                postal_center_city_snapshot,
                MIN(CASE WHEN event_type = 'entry' THEN timestamp END) as entry_time,
                MAX(CASE WHEN event_type = 'exit' THEN timestamp END) as exit_time
            FROM center_events
            GROUP BY postal_center_id, postal_center_city_snapshot
            ORDER BY COALESCE(entry_time, exit_time)
        LOOP
            v_entry_time := v_center_visit.entry_time;
            v_exit_time := v_center_visit.exit_time;
            
            -- Get next entry time (for transit calculation)
            SELECT MIN(timestamp) INTO v_next_entry_time
            FROM processed_events
            WHERE account_id = p_account_id
              AND tag_id = v_tag.tag_id
              AND event_type = 'entry'
              AND timestamp > COALESCE(v_exit_time, v_entry_time);
            
            -- ========================================
            -- Calculate Time in Center (Dual Tracking)
            -- ========================================
            IF v_entry_time IS NOT NULL AND v_exit_time IS NOT NULL THEN
                -- Natural time (always calculated)
                v_natural_time_in_center := EXTRACT(EPOCH FROM (v_exit_time - v_entry_time)) / 60;
                
                -- Working time (depends on calculation_mode)
                SELECT 
                    CASE 
                        WHEN pc.calculation_mode = 'working_days' THEN
                            calculate_working_time_minutes(v_entry_time, v_exit_time, pc.id)
                        ELSE
                            v_natural_time_in_center
                    END
                INTO v_working_time_in_center
                FROM postal_centers pc
                WHERE pc.id = v_center_visit.postal_center_id;
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
                SELECT 
                    CASE 
                        WHEN pc.calculation_mode = 'working_days' THEN
                            calculate_working_time_minutes(v_exit_time, v_next_entry_time, pc.id)
                        ELSE
                            v_natural_transit_time
                    END
                INTO v_working_transit_time
                FROM postal_centers pc
                WHERE pc.id = v_center_visit.postal_center_id;
            ELSE
                v_natural_transit_time := NULL;
                v_working_transit_time := NULL;
            END IF;
            
            -- ========================================
            -- SLA Lookup and Compliance
            -- ========================================
            -- Get expected time from delivery_standards
            SELECT standard_time INTO v_expected_time
            FROM delivery_standards
            WHERE carrier_id = v_tag.carrier_id
              AND product_id = v_tag.product_id
              AND origin_city_name = v_tag.origin_city_name
              AND destination_city_name = v_tag.destination_city_name
            LIMIT 1;
            
            -- Calculate compliance (using working time)
            IF v_expected_time IS NOT NULL AND v_working_time_in_center IS NOT NULL AND v_working_transit_time IS NOT NULL THEN
                v_sla_compliance := (v_working_time_in_center + v_working_transit_time) <= v_expected_time;
            ELSE
                v_sla_compliance := NULL;
            END IF;
            
            -- ========================================
            -- Insert Journey Segment
            -- ========================================
            INSERT INTO journey_segments (
                account_id,
                tag_id,
                carrier_id,
                product_id,
                origin_city_name,
                destination_city_name,
                from_postal_center_id,
                from_postal_center_city,
                to_postal_center_id,
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
            SELECT
                p_account_id,
                v_tag.tag_id,
                v_tag.carrier_id,
                v_tag.product_id,
                v_tag.origin_city_name,
                v_tag.destination_city_name,
                v_center_visit.postal_center_id,
                v_center_visit.postal_center_city_snapshot,
                -- Get next center ID
                (SELECT postal_center_id 
                 FROM processed_events 
                 WHERE account_id = p_account_id 
                   AND tag_id = v_tag.tag_id 
                   AND timestamp = v_next_entry_time 
                 LIMIT 1),
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
            WHERE v_entry_time IS NOT NULL OR v_exit_time IS NOT NULL;  -- Only insert if we have at least one timestamp
            
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

-- ============================================================================
-- Helper Function: calculate_working_time_minutes
-- ============================================================================
-- Calculates working time between two timestamps excluding weekends and 
-- non-working hours based on postal center's weekly_schedule.
-- ============================================================================

CREATE OR REPLACE FUNCTION calculate_working_time_minutes(
    p_start_time TIMESTAMPTZ,
    p_end_time TIMESTAMPTZ,
    p_postal_center_id UUID
) RETURNS INTEGER AS $$
DECLARE
    v_working_minutes INTEGER := 0;
    v_current_time TIMESTAMPTZ;
    v_day_of_week INTEGER;
    v_hour_of_day INTEGER;
    v_opening_hour TIME;
    v_closing_hour TIME;
BEGIN
    -- Get postal center working hours
    SELECT opening_hour, working_hours_end
    INTO v_opening_hour, v_closing_hour
    FROM postal_centers
    WHERE id = p_postal_center_id;
    
    -- If no working hours defined, return natural time
    IF v_opening_hour IS NULL OR v_closing_hour IS NULL THEN
        RETURN EXTRACT(EPOCH FROM (p_end_time - p_start_time)) / 60;
    END IF;
    
    -- Iterate through each hour between start and end
    v_current_time := date_trunc('hour', p_start_time);
    
    WHILE v_current_time < p_end_time LOOP
        v_day_of_week := EXTRACT(DOW FROM v_current_time);  -- 0=Sunday, 6=Saturday
        v_hour_of_day := EXTRACT(HOUR FROM v_current_time);
        
        -- Check if it's a working day and working hour
        IF v_day_of_week BETWEEN 1 AND 5 THEN  -- Monday to Friday
            IF v_hour_of_day::TIME >= v_opening_hour AND v_hour_of_day::TIME < v_closing_hour THEN
                -- Add minutes from this hour
                IF v_current_time + INTERVAL '1 hour' <= p_end_time THEN
                    v_working_minutes := v_working_minutes + 60;
                ELSE
                    v_working_minutes := v_working_minutes + EXTRACT(EPOCH FROM (p_end_time - v_current_time)) / 60;
                END IF;
            END IF;
        END IF;
        
        v_current_time := v_current_time + INTERVAL '1 hour';
    END LOOP;
    
    RETURN v_working_minutes;
END;
$$ LANGUAGE plpgsql;
