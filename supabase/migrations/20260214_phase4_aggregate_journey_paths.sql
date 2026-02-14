-- ============================================================================
-- Phase 4: aggregate_journey_paths() - Route Aggregation
-- ============================================================================
-- Aggregates journey segments into unique paths for analysis and visualization.
-- Groups segments by carrier/product/origin/destination/path_signature and
-- calculates performance metrics.
-- ============================================================================

CREATE OR REPLACE FUNCTION aggregate_journey_paths(
    p_account_id UUID,
    p_since TIMESTAMPTZ DEFAULT NULL
) RETURNS JSON AS $$
DECLARE
    v_paths_created INTEGER := 0;
    v_paths_updated INTEGER := 0;
    v_start_time TIMESTAMPTZ := NOW();
    v_end_time TIMESTAMPTZ;
    v_duration_seconds NUMERIC;
    v_since TIMESTAMPTZ;
BEGIN
    -- Default to last 24 hours if not specified
    v_since := COALESCE(p_since, NOW() - INTERVAL '24 hours');
    
    -- Clear existing paths for the period (to recalculate)
    DELETE FROM journey_paths
    WHERE account_id = p_account_id
      AND last_updated >= v_since;
    
    -- ========================================
    -- Aggregate Segments into Paths
    -- ========================================
    INSERT INTO journey_paths (
        account_id,
        carrier_id,
        product_id,
        origin_city_name,
        destination_city_name,
        path_signature,
        path_segments,
        total_tags,
        avg_natural_time_minutes,
        avg_working_time_minutes,
        compliance_rate,
        segment_details,
        created_at,
        last_updated
    )
    SELECT
        p_account_id,
        carrier_id,
        product_id,
        origin_city_name,
        destination_city_name,
        
        -- ========================================
        -- Path Signature: Concatenate cities in order
        -- ========================================
        array_to_string(
            array_agg(DISTINCT from_postal_center_city ORDER BY from_postal_center_city),
            '→'
        ) as path_signature,
        
        -- ========================================
        -- Path Segments: Ordered list of segments
        -- ========================================
        jsonb_agg(
            jsonb_build_object(
                'from', from_postal_center_city,
                'to', to_postal_center_city,
                'from_center_id', from_postal_center_id,
                'to_center_id', to_postal_center_id
            ) ORDER BY entry_timestamp
        ) as path_segments,
        
        -- ========================================
        -- Total Tags: Count distinct tags
        -- ========================================
        COUNT(DISTINCT tag_id) as total_tags,
        
        -- ========================================
        -- Average Natural Time
        -- ========================================
        AVG(
            COALESCE(natural_time_in_center_minutes, 0) + 
            COALESCE(natural_transit_time_minutes, 0)
        )::INTEGER as avg_natural_time_minutes,
        
        -- ========================================
        -- Average Working Time
        -- ========================================
        AVG(
            COALESCE(working_time_in_center_minutes, 0) + 
            COALESCE(working_transit_time_minutes, 0)
        )::INTEGER as avg_working_time_minutes,
        
        -- ========================================
        -- Compliance Rate (percentage)
        -- ========================================
        (AVG(CASE WHEN sla_compliance = TRUE THEN 100.0 ELSE 0.0 END))::NUMERIC(5,2) as compliance_rate,
        
        -- ========================================
        -- Segment Details: Detailed metrics per segment
        -- ========================================
        jsonb_agg(
            jsonb_build_object(
                'from', from_postal_center_city,
                'to', to_postal_center_city,
                'avg_natural_time_in_center', AVG(natural_time_in_center_minutes),
                'avg_working_time_in_center', AVG(working_time_in_center_minutes),
                'avg_natural_transit_time', AVG(natural_transit_time_minutes),
                'avg_working_transit_time', AVG(working_transit_time_minutes),
                'expected_time', AVG(expected_time_minutes),
                'compliance_rate', AVG(CASE WHEN sla_compliance = TRUE THEN 100.0 ELSE 0.0 END),
                'tags_count', COUNT(DISTINCT tag_id)
            ) ORDER BY entry_timestamp
        ) as segment_details,
        
        NOW() as created_at,
        NOW() as last_updated
        
    FROM journey_segments
    WHERE account_id = p_account_id
      AND created_at >= v_since
      AND from_postal_center_city IS NOT NULL
      AND to_postal_center_city IS NOT NULL
    GROUP BY
        carrier_id,
        product_id,
        origin_city_name,
        destination_city_name,
        -- Group by path signature (ordered list of cities)
        array_to_string(
            array_agg(DISTINCT from_postal_center_city ORDER BY from_postal_center_city),
            '→'
        );
    
    GET DIAGNOSTICS v_paths_created = ROW_COUNT;
    
    -- Calculate duration
    v_end_time := NOW();
    v_duration_seconds := EXTRACT(EPOCH FROM (v_end_time - v_start_time));
    
    -- Return summary
    RETURN json_build_object(
        'success', TRUE,
        'paths_created', v_paths_created,
        'duration_seconds', v_duration_seconds,
        'period_start', v_since,
        'period_end', v_end_time
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', FALSE,
            'error', SQLERRM
        );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION aggregate_journey_paths IS 'Aggregates journey segments into unique paths with performance metrics';
