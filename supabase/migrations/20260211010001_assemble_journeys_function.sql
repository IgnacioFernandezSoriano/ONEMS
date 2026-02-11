-- =====================================================
-- Function: assemble_journeys
-- =====================================================
-- Purpose: Assemble complete journey records from journey_segments
-- Groups segments by tag_id and calculates aggregate metrics

CREATE OR REPLACE FUNCTION assemble_journeys(
    p_account_id UUID DEFAULT NULL
)
RETURNS TABLE (
    journeys_created INTEGER,
    journeys_updated INTEGER,
    execution_time_ms INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_journeys_created INTEGER := 0;
    v_journeys_updated INTEGER := 0;
    v_tag RECORD;
    v_journey_id BIGINT;
    v_overall_compliance TEXT;
BEGIN
    v_start_time := clock_timestamp();
    
    RAISE NOTICE 'Starting journey assembly...';
    
    -- Process each unique tag_id
    FOR v_tag IN
        SELECT DISTINCT
            js.account_id,
            js.tag_id
        FROM journey_segments js
        WHERE (p_account_id IS NULL OR js.account_id = p_account_id)
        ORDER BY js.tag_id
    LOOP
        -- Check if journey already exists
        SELECT id INTO v_journey_id
        FROM journeys
        WHERE account_id = v_tag.account_id
          AND tag_id = v_tag.tag_id;
        
        -- Determine overall compliance
        WITH compliance_counts AS (
            SELECT 
                COUNT(*) FILTER (WHERE sla_compliance = 'on_time') as on_time_count,
                COUNT(*) FILTER (WHERE sla_compliance = 'warning') as warning_count,
                COUNT(*) FILTER (WHERE sla_compliance = 'critical') as critical_count,
                COUNT(*) FILTER (WHERE sla_compliance = 'violated') as violated_count,
                COUNT(*) FILTER (WHERE sla_compliance = 'no_sla') as no_sla_count,
                COUNT(*) as total_count
            FROM journey_segments
            WHERE account_id = v_tag.account_id
              AND tag_id = v_tag.tag_id
        )
        SELECT 
            CASE
                WHEN violated_count > 0 THEN 'violated'
                WHEN critical_count > 0 THEN 'critical'
                WHEN warning_count > 0 THEN 'warning'
                WHEN on_time_count = total_count AND total_count > 0 THEN 'on_time'
                WHEN no_sla_count = total_count THEN 'no_sla'
                ELSE 'mixed'
            END
        INTO v_overall_compliance
        FROM compliance_counts;
        
        IF v_journey_id IS NULL THEN
            -- Insert new journey
            INSERT INTO journeys (
                account_id,
                tag_id,
                total_segments,
                operational_segments,
                distribution_segments,
                journey_start_timestamp,
                journey_end_timestamp,
                centers_visited,
                center_ids_visited,
                total_actual_time_minutes,
                total_adjusted_time_minutes,
                total_operational_time_minutes,
                total_distribution_time_minutes,
                total_pre_operational_wait_minutes,
                overall_sla_compliance,
                segments_on_time,
                segments_warning,
                segments_critical,
                segments_violated,
                segments_no_sla,
                is_complete,
                has_gaps
            )
            SELECT
                v_tag.account_id,
                v_tag.tag_id,
                COUNT(*) as total_segments,
                COUNT(*) FILTER (WHERE segment_type = 'operational') as operational_segments,
                COUNT(*) FILTER (WHERE segment_type = 'distribution') as distribution_segments,
                MIN(entry_timestamp) as journey_start_timestamp,
                MAX(exit_timestamp) as journey_end_timestamp,
                ARRAY_AGG(DISTINCT COALESCE(postal_center_name_snapshot, from_postal_center_name_snapshot, to_postal_center_name_snapshot) ORDER BY COALESCE(postal_center_name_snapshot, from_postal_center_name_snapshot, to_postal_center_name_snapshot)) FILTER (WHERE COALESCE(postal_center_name_snapshot, from_postal_center_name_snapshot, to_postal_center_name_snapshot) IS NOT NULL) as centers_visited,
                ARRAY_AGG(DISTINCT COALESCE(postal_center_id, from_postal_center_id, to_postal_center_id) ORDER BY COALESCE(postal_center_id, from_postal_center_id, to_postal_center_id)) FILTER (WHERE COALESCE(postal_center_id, from_postal_center_id, to_postal_center_id) IS NOT NULL) as center_ids_visited,
                SUM(actual_time_minutes) as total_actual_time_minutes,
                SUM(adjusted_time_minutes) as total_adjusted_time_minutes,
                SUM(adjusted_time_minutes) FILTER (WHERE segment_type = 'operational') as total_operational_time_minutes,
                SUM(adjusted_time_minutes) FILTER (WHERE segment_type = 'distribution') as total_distribution_time_minutes,
                SUM(pre_operational_wait_minutes) as total_pre_operational_wait_minutes,
                v_overall_compliance as overall_sla_compliance,
                COUNT(*) FILTER (WHERE sla_compliance = 'on_time') as segments_on_time,
                COUNT(*) FILTER (WHERE sla_compliance = 'warning') as segments_warning,
                COUNT(*) FILTER (WHERE sla_compliance = 'critical') as segments_critical,
                COUNT(*) FILTER (WHERE sla_compliance = 'violated') as segments_violated,
                COUNT(*) FILTER (WHERE sla_compliance = 'no_sla') as segments_no_sla,
                false as is_complete, -- TODO: Implement completion logic
                false as has_gaps     -- TODO: Implement gap detection
            FROM journey_segments
            WHERE account_id = v_tag.account_id
              AND tag_id = v_tag.tag_id
            RETURNING id INTO v_journey_id;
            
            v_journeys_created := v_journeys_created + 1;
            
            RAISE NOTICE 'Created journey % for tag %', v_journey_id, v_tag.tag_id;
        ELSE
            -- Update existing journey
            UPDATE journeys
            SET
                total_segments = subq.total_segments,
                operational_segments = subq.operational_segments,
                distribution_segments = subq.distribution_segments,
                journey_start_timestamp = subq.journey_start_timestamp,
                journey_end_timestamp = subq.journey_end_timestamp,
                centers_visited = subq.centers_visited,
                center_ids_visited = subq.center_ids_visited,
                total_actual_time_minutes = subq.total_actual_time_minutes,
                total_adjusted_time_minutes = subq.total_adjusted_time_minutes,
                total_operational_time_minutes = subq.total_operational_time_minutes,
                total_distribution_time_minutes = subq.total_distribution_time_minutes,
                total_pre_operational_wait_minutes = subq.total_pre_operational_wait_minutes,
                overall_sla_compliance = v_overall_compliance,
                segments_on_time = subq.segments_on_time,
                segments_warning = subq.segments_warning,
                segments_critical = subq.segments_critical,
                segments_violated = subq.segments_violated,
                segments_no_sla = subq.segments_no_sla,
                updated_at = NOW()
            FROM (
                SELECT
                    COUNT(*) as total_segments,
                    COUNT(*) FILTER (WHERE segment_type = 'operational') as operational_segments,
                    COUNT(*) FILTER (WHERE segment_type = 'distribution') as distribution_segments,
                    MIN(entry_timestamp) as journey_start_timestamp,
                    MAX(exit_timestamp) as journey_end_timestamp,
                    ARRAY_AGG(DISTINCT COALESCE(postal_center_name_snapshot, from_postal_center_name_snapshot, to_postal_center_name_snapshot) ORDER BY COALESCE(postal_center_name_snapshot, from_postal_center_name_snapshot, to_postal_center_name_snapshot)) FILTER (WHERE COALESCE(postal_center_name_snapshot, from_postal_center_name_snapshot, to_postal_center_name_snapshot) IS NOT NULL) as centers_visited,
                    ARRAY_AGG(DISTINCT COALESCE(postal_center_id, from_postal_center_id, to_postal_center_id) ORDER BY COALESCE(postal_center_id, from_postal_center_id, to_postal_center_id)) FILTER (WHERE COALESCE(postal_center_id, from_postal_center_id, to_postal_center_id) IS NOT NULL) as center_ids_visited,
                    SUM(actual_time_minutes) as total_actual_time_minutes,
                    SUM(adjusted_time_minutes) as total_adjusted_time_minutes,
                    SUM(adjusted_time_minutes) FILTER (WHERE segment_type = 'operational') as total_operational_time_minutes,
                    SUM(adjusted_time_minutes) FILTER (WHERE segment_type = 'distribution') as total_distribution_time_minutes,
                    SUM(pre_operational_wait_minutes) as total_pre_operational_wait_minutes,
                    COUNT(*) FILTER (WHERE sla_compliance = 'on_time') as segments_on_time,
                    COUNT(*) FILTER (WHERE sla_compliance = 'warning') as segments_warning,
                    COUNT(*) FILTER (WHERE sla_compliance = 'critical') as segments_critical,
                    COUNT(*) FILTER (WHERE sla_compliance = 'violated') as segments_violated,
                    COUNT(*) FILTER (WHERE sla_compliance = 'no_sla') as segments_no_sla
                FROM journey_segments
                WHERE account_id = v_tag.account_id
                  AND tag_id = v_tag.tag_id
            ) subq
            WHERE id = v_journey_id;
            
            v_journeys_updated := v_journeys_updated + 1;
            
            RAISE NOTICE 'Updated journey % for tag %', v_journey_id, v_tag.tag_id;
        END IF;
    END LOOP;
    
    RAISE NOTICE 'Journey assembly completed: % created, % updated', 
        v_journeys_created, v_journeys_updated;
    
    -- Return results
    RETURN QUERY SELECT 
        v_journeys_created,
        v_journeys_updated,
        EXTRACT(EPOCH FROM (clock_timestamp() - v_start_time))::INTEGER * 1000;
END;
$$;

COMMENT ON FUNCTION assemble_journeys IS 
'Assembles complete journey records from journey_segments grouped by tag_id. Creates new journeys or updates existing ones.';
