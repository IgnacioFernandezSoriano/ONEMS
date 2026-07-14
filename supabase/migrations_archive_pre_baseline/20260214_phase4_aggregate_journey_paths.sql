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
    WITH segment_aggregated AS (
        -- First, aggregate metrics per unique segment (from_center → to_center)
        SELECT
            js.account_id,
            js.carrier_id,
            js.product_id,
            js.origin_city_name,
            js.destination_city_name,
            js.from_postal_center_id,
            js.to_postal_center_id,
            js.from_postal_center_city,
            js.to_postal_center_city,
            MIN(js.entry_timestamp) as first_entry_timestamp,
            
            -- Get center names
            (SELECT name FROM postal_centers WHERE id = js.from_postal_center_id LIMIT 1) as from_center_name,
            (SELECT name FROM postal_centers WHERE id = js.to_postal_center_id LIMIT 1) as to_center_name,
            (SELECT calculation_mode FROM postal_centers WHERE id = js.from_postal_center_id LIMIT 1) as calculation_mode,
            
            -- Determine segment type
            CASE 
                WHEN AVG(COALESCE(js.natural_time_in_center_minutes, 0)) > 0 
                THEN 'operational'
                ELSE 'distribution'
            END as segment_type,
            
            -- Aggregate time metrics
            AVG(COALESCE(js.natural_time_in_center_minutes, 0)) as avg_time_in_center_natural,
            AVG(COALESCE(js.working_time_in_center_minutes, 0)) as avg_time_in_center_working,
            AVG(COALESCE(js.natural_transit_time_minutes, 0)) as avg_transit_time_natural,
            AVG(COALESCE(js.working_transit_time_minutes, 0)) as avg_transit_time_working,
            AVG(COALESCE(js.natural_time_in_center_minutes, 0) + COALESCE(js.natural_transit_time_minutes, 0)) as avg_total_time_natural,
            AVG(COALESCE(js.working_time_in_center_minutes, 0) + COALESCE(js.working_transit_time_minutes, 0)) as avg_total_time_working,
            
            -- SLA metrics
            AVG(js.expected_time_minutes) as expected_time_minutes,
            AVG(CASE WHEN js.sla_compliance = TRUE THEN 100.0 ELSE 0.0 END) as compliance_rate,
            
            -- Count tags
            COUNT(DISTINCT js.tag_id) as tags_count
            
        FROM journey_segments js
        WHERE js.account_id = p_account_id
          AND js.created_at >= v_since
          AND js.from_postal_center_city IS NOT NULL
          AND js.to_postal_center_city IS NOT NULL
        GROUP BY
            js.account_id,
            js.carrier_id,
            js.product_id,
            js.origin_city_name,
            js.destination_city_name,
            js.from_postal_center_id,
            js.to_postal_center_id,
            js.from_postal_center_city,
            js.to_postal_center_city
    ),
    sla_data AS (
        SELECT DISTINCT ON (carrier_id, product_id, origin_city, destination_city)
            carrier_id,
            product_id,
            origin_city,
            destination_city,
            on_time_percentage
        FROM slas
        WHERE account_id = p_account_id
    )
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
        expected_time_minutes,
        segment_details,
        created_at,
        last_updated
    )
    SELECT
        sa.account_id,
        sa.carrier_id,
        sa.product_id,
        sa.origin_city_name,
        sa.destination_city_name,
        
        -- ========================================
        -- Path Signature: Concatenate cities in order
        -- ========================================
        array_to_string(
            array_agg(DISTINCT sa.from_postal_center_city ORDER BY sa.from_postal_center_city),
            '→'
        ) as path_signature,
        
        -- ========================================
        -- Path Segments: Ordered list of segments
        -- ========================================
        jsonb_agg(
            jsonb_build_object(
                'from', sa.from_postal_center_city,
                'to', sa.to_postal_center_city,
                'from_center_id', sa.from_postal_center_id,
                'to_center_id', sa.to_postal_center_id
            ) ORDER BY sa.first_entry_timestamp
        ) as path_segments,
        
        -- ========================================
        -- Total Tags: Sum of unique tags across segments
        -- ========================================
        SUM(sa.tags_count)::INTEGER as total_tags,
        
        -- ========================================
        -- Average Natural Time
        -- ========================================
        AVG(sa.avg_total_time_natural)::INTEGER as avg_natural_time_minutes,
        
        -- ========================================
        -- Average Working Time
        -- ========================================
        AVG(sa.avg_total_time_working)::INTEGER as avg_working_time_minutes,
        
        -- ========================================
        -- Compliance Rate (weighted average)
        -- ========================================
        (SUM(sa.compliance_rate * sa.tags_count) / NULLIF(SUM(sa.tags_count), 0))::NUMERIC(5,2) as compliance_rate,
        
        -- ========================================
        -- Expected Time (average)
        -- ========================================
        AVG(sa.expected_time_minutes)::INTEGER as expected_time_minutes,
        
        -- ========================================
        -- Segment Details: Pre-aggregated segment data
        -- ========================================
        jsonb_agg(
            jsonb_build_object(
                -- Center identification
                'from_center_id', sa.from_postal_center_id,
                'to_center_id', sa.to_postal_center_id,
                'from_center_name', sa.from_center_name,
                'to_center_name', sa.to_center_name,
                'from_city', sa.from_postal_center_city,
                'to_city', sa.to_postal_center_city,
                
                -- Segment type
                'segment_type', sa.segment_type,
                
                -- Time metrics (natural)
                'avg_time_in_center_natural', sa.avg_time_in_center_natural,
                'avg_transit_time_natural', sa.avg_transit_time_natural,
                'avg_total_time_natural', sa.avg_total_time_natural,
                
                -- Time metrics (working)
                'avg_time_in_center_working', sa.avg_time_in_center_working,
                'avg_transit_time_working', sa.avg_transit_time_working,
                'avg_total_time_working', sa.avg_total_time_working,
                
                -- SLA metrics
                'expected_time_minutes', sa.expected_time_minutes,
                'on_time_percentage_std', COALESCE(
                    (SELECT sla.on_time_percentage 
                     FROM sla_data sla 
                     WHERE sla.carrier_id = sa.carrier_id 
                       AND sla.product_id = sa.product_id
                       AND sla.origin_city = sa.origin_city_name
                       AND sla.destination_city = sa.destination_city_name
                     LIMIT 1),
                    95.0
                ),
                'compliance_rate', sa.compliance_rate,
                'warning_threshold', 90.0,
                'critical_threshold', 80.0,
                
                -- Additional info
                'tags_count', sa.tags_count,
                'calculation_mode', COALESCE(sa.calculation_mode, 'natural_days')
            ) ORDER BY sa.first_entry_timestamp
        ) as segment_details,
        
        NOW() as created_at,
        NOW() as last_updated
        
    FROM segment_aggregated sa
    GROUP BY
        sa.account_id,
        sa.carrier_id,
        sa.product_id,
        sa.origin_city_name,
        sa.destination_city_name,
        -- Group by path signature
        array_to_string(
            array_agg(DISTINCT sa.from_postal_center_city ORDER BY sa.from_postal_center_city),
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

COMMENT ON FUNCTION aggregate_journey_paths IS 'Aggregates journey segments into unique paths with complete segment details including center names and types';
