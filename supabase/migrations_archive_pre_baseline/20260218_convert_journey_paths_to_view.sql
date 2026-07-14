-- Migration: Convert journey_paths to VIEW with automatic calculations
-- Backup existing table first, then replace with VIEW

-- 1. Rename existing table as backup
ALTER TABLE journey_paths RENAME TO journey_paths_backup;

-- 2. Create VIEW with automatic calculations from journey_segments
CREATE OR REPLACE VIEW journey_paths AS
SELECT
    gen_random_uuid() AS id,
    js.account_id,
    js.carrier_id,
    js.product_id,
    js.origin_city_name,
    js.destination_city_name,
    
    -- Path signature: concatenate all center codes in order
    STRING_AGG(
        COALESCE(js.postal_center_code_snapshot, js.from_postal_center_code_snapshot),
        ' → '
        ORDER BY js.entry_timestamp
    ) AS path_signature,
    
    -- Path segments as JSONB array
    JSONB_AGG(
        JSONB_BUILD_OBJECT(
            'center_code', js.postal_center_code_snapshot,
            'entry_time', js.entry_timestamp,
            'exit_time', js.exit_timestamp
        )
        ORDER BY js.entry_timestamp
    ) AS path_segments,
    
    -- Total tags (distinct tags following this path)
    COUNT(DISTINCT js.tag_id) AS total_tags,
    
    -- NATURAL TIME: Sum of natural_time_in_center + natural_transit_time
    SUM(
        COALESCE(js.natural_time_in_center_minutes, 0) + 
        COALESCE(js.natural_transit_time_minutes, 0)
    )::INTEGER AS avg_natural_time_minutes,
    
    -- WORKING TIME: Sum of working_time_in_center + working_transit_time
    SUM(
        COALESCE(js.working_time_in_center_minutes, 0) + 
        COALESCE(js.working_transit_time_minutes, 0)
    )::INTEGER AS avg_working_time_minutes,
    
    -- J+K STD: Sum of expected_time
    SUM(COALESCE(js.expected_time_minutes, 0))::INTEGER AS expected_time_minutes,
    
    -- % STD: Average of (working_time / expected_time) * 100 for segments with expected_time
    AVG(
        CASE 
            WHEN js.expected_time_minutes > 0 THEN
                ((COALESCE(js.working_time_in_center_minutes, 0) + COALESCE(js.working_transit_time_minutes, 0))::NUMERIC / 
                 js.expected_time_minutes::NUMERIC) * 100
            ELSE NULL
        END
    ) AS compliance_rate,
    
    -- % REAL: Average of non-zero values
    AVG(
        CASE 
            WHEN (COALESCE(js.working_time_in_center_minutes, 0) + COALESCE(js.working_transit_time_minutes, 0)) > 0 THEN
                ((COALESCE(js.working_time_in_center_minutes, 0) + COALESCE(js.working_transit_time_minutes, 0))::NUMERIC / 
                 NULLIF(COALESCE(js.expected_time_minutes, 1), 0)::NUMERIC) * 100
            ELSE NULL
        END
    ) AS percent_real,
    
    -- DIFF %: compliance_rate - percent_real (calculated in subquery)
    -- Will be calculated as compliance_rate - percent_real
    
    -- Segment details with threshold percentages
    JSONB_BUILD_OBJECT(
        'total_segments', COUNT(*),
        'critical_count', COUNT(*) FILTER (WHERE js.sla_compliance = 'critical'),
        'warning_count', COUNT(*) FILTER (WHERE js.sla_compliance = 'warning'),
        'compliant_count', COUNT(*) FILTER (WHERE js.sla_compliance = 'on_time'),
        'critical_percent', ROUND((COUNT(*) FILTER (WHERE js.sla_compliance = 'critical')::NUMERIC / COUNT(*)::NUMERIC) * 100, 2),
        'warning_percent', ROUND((COUNT(*) FILTER (WHERE js.sla_compliance = 'warning')::NUMERIC / COUNT(*)::NUMERIC) * 100, 2),
        'compliant_percent', ROUND((COUNT(*) FILTER (WHERE js.sla_compliance = 'on_time')::NUMERIC / COUNT(*)::NUMERIC) * 100, 2)
    ) AS segment_details,
    
    -- Timestamps
    MIN(js.created_at) AS created_at,
    MAX(js.created_at) AS updated_at,
    
    -- Standard deviations
    STDDEV(COALESCE(js.natural_time_in_center_minutes, 0) + COALESCE(js.natural_transit_time_minutes, 0)) AS stddev_natural_time_minutes,
    STDDEV(COALESCE(js.working_time_in_center_minutes, 0) + COALESCE(js.working_transit_time_minutes, 0)) AS stddev_working_time_minutes

FROM journey_segments js
WHERE js.segment_type IN ('operational', 'distribution')
GROUP BY 
    js.account_id,
    js.carrier_id,
    js.product_id,
    js.origin_city_name,
    js.destination_city_name,
    js.tag_id;

-- 3. Grant permissions
GRANT SELECT ON journey_paths TO authenticated;
GRANT SELECT ON journey_paths TO service_role;

COMMENT ON VIEW journey_paths IS 'Aggregated journey paths calculated automatically from journey_segments. Replaces materialized table for real-time accuracy.';
