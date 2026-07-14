-- Sprint 9: Assemble Journeys Function (Adapted to existing schema)
-- This function aggregates journey_segments by tag_id into complete journey records

CREATE OR REPLACE FUNCTION assemble_journeys(p_account_id UUID DEFAULT NULL)
RETURNS TABLE (
    journeys_created BIGINT,
    journeys_updated BIGINT,
    execution_time_ms BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_end_time TIMESTAMPTZ;
    v_created_count BIGINT := 0;
    v_updated_count BIGINT := 0;
    v_journey_record RECORD;
BEGIN
    v_start_time := clock_timestamp();
    
    -- Aggregate journey_segments by tag_id
    FOR v_journey_record IN
        SELECT 
            js.account_id,
            js.tag_id,
            
            -- Route path as JSONB array
            jsonb_agg(
                jsonb_build_object(
                    'segment_type', js.segment_type,
                    'center_id', COALESCE(js.postal_center_id, js.from_postal_center_id),
                    'center_code', COALESCE(js.postal_center_code_snapshot, js.from_postal_center_code_snapshot),
                    'center_name', COALESCE(js.postal_center_name_snapshot, js.from_postal_center_name_snapshot),
                    'entry_time', js.entry_timestamp,
                    'exit_time', js.exit_timestamp,
                    'sla_compliance', js.sla_compliance
                ) ORDER BY js.entry_timestamp
            ) as route_path,
            
            -- Count unique centers visited
            COUNT(DISTINCT COALESCE(js.postal_center_id, js.from_postal_center_id)) as total_centers_visited,
            
            -- Time metrics
            SUM(js.actual_time_minutes) as total_actual_time_minutes,
            SUM(js.adjusted_time_minutes) as total_adjusted_time_minutes,
            SUM(CASE WHEN js.segment_type = 'operational' THEN js.adjusted_time_minutes ELSE 0 END) as total_operational_time_minutes,
            SUM(CASE WHEN js.segment_type = 'distribution' THEN js.adjusted_time_minutes ELSE 0 END) as total_distribution_time_minutes,
            SUM(COALESCE(js.pre_operational_wait_minutes, 0)) as total_pre_operational_wait_minutes,
            
            -- Journey status determination
            CASE 
                WHEN MAX(js.exit_timestamp) > NOW() - INTERVAL '24 hours' THEN 'in_progress'
                WHEN COUNT(*) FILTER (WHERE js.sla_compliance IN ('violated', 'critical')) > 0 THEN 'anomalous'
                ELSE 'completed'
            END as journey_status,
            
            -- Timestamps
            MIN(js.entry_timestamp) as first_event_timestamp,
            MAX(js.exit_timestamp) as last_event_timestamp,
            
            -- SLA metrics
            COUNT(*) FILTER (WHERE js.sla_compliance = 'violated') as total_sla_violations,
            COUNT(*) as total_segments,
            COUNT(*) FILTER (WHERE js.sla_compliance = 'on_time') as on_time_segments,
            
            -- Get first and last postal centers for origin/destination
            (array_agg(js.postal_center_id ORDER BY js.entry_timestamp))[1] as first_center_id,
            (array_agg(js.postal_center_id ORDER BY js.entry_timestamp DESC))[1] as last_center_id
            
        FROM journey_segments js
        WHERE (p_account_id IS NULL OR js.account_id = p_account_id)
        GROUP BY js.account_id, js.tag_id
    LOOP
        -- Insert or update journey record
        INSERT INTO journeys (
            account_id,
            tag_id,
            origin_city_id,
            destination_city_id,
            origin_city_name,
            destination_city_name,
            route_path,
            total_centers_visited,
            total_actual_time_minutes,
            total_adjusted_time_minutes,
            total_operational_time_minutes,
            total_distribution_time_minutes,
            total_pre_operational_wait_minutes,
            journey_status,
            is_missroute,
            missroute_reason,
            first_event_timestamp,
            last_event_timestamp,
            total_sla_violations,
            total_segments,
            on_time_segments,
            created_at,
            updated_at
        )
        VALUES (
            v_journey_record.account_id,
            v_journey_record.tag_id,
            NULL, -- origin_city_id (to be populated from ONE DB integration)
            NULL, -- destination_city_id
            NULL, -- origin_city_name
            NULL, -- destination_city_name
            v_journey_record.route_path,
            v_journey_record.total_centers_visited,
            v_journey_record.total_actual_time_minutes,
            v_journey_record.total_adjusted_time_minutes,
            v_journey_record.total_operational_time_minutes,
            v_journey_record.total_distribution_time_minutes,
            v_journey_record.total_pre_operational_wait_minutes,
            v_journey_record.journey_status,
            false, -- is_missroute (to be determined by route validation logic)
            NULL, -- missroute_reason
            v_journey_record.first_event_timestamp,
            v_journey_record.last_event_timestamp,
            v_journey_record.total_sla_violations,
            v_journey_record.total_segments,
            v_journey_record.on_time_segments,
            NOW(),
            NOW()
        )
        ON CONFLICT (account_id, tag_id)
        DO UPDATE SET
            route_path = EXCLUDED.route_path,
            total_centers_visited = EXCLUDED.total_centers_visited,
            total_actual_time_minutes = EXCLUDED.total_actual_time_minutes,
            total_adjusted_time_minutes = EXCLUDED.total_adjusted_time_minutes,
            total_operational_time_minutes = EXCLUDED.total_operational_time_minutes,
            total_distribution_time_minutes = EXCLUDED.total_distribution_time_minutes,
            total_pre_operational_wait_minutes = EXCLUDED.total_pre_operational_wait_minutes,
            journey_status = EXCLUDED.journey_status,
            first_event_timestamp = EXCLUDED.first_event_timestamp,
            last_event_timestamp = EXCLUDED.last_event_timestamp,
            total_sla_violations = EXCLUDED.total_sla_violations,
            total_segments = EXCLUDED.total_segments,
            on_time_segments = EXCLUDED.on_time_segments,
            updated_at = NOW()
        WHERE journeys.account_id = EXCLUDED.account_id 
          AND journeys.tag_id = EXCLUDED.tag_id;
        
        -- Track if this was an insert or update
        IF FOUND THEN
            IF journeys.created_at = journeys.updated_at THEN
                v_created_count := v_created_count + 1;
            ELSE
                v_updated_count := v_updated_count + 1;
            END IF;
        END IF;
    END LOOP;
    
    v_end_time := clock_timestamp();
    
    -- Return summary
    RETURN QUERY SELECT 
        v_created_count,
        v_updated_count,
        EXTRACT(MILLISECONDS FROM (v_end_time - v_start_time))::BIGINT;
END;
$$;

-- Add comment
COMMENT ON FUNCTION assemble_journeys IS 'Aggregates journey_segments by tag_id into complete journey records in the journeys table';
