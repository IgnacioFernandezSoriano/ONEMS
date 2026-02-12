-- J+K Performance Report SQL Function (Segment-based)
-- Sprint 11: Diagnosis Module - J+K Performance for journey_segments

-- Main function: Get J+K Performance data from journey_segments
-- Converts segment times (minutes) to days for J+K calculation
-- Replicates E2E Reporting structure but uses journey_segments as source

CREATE OR REPLACE FUNCTION get_jk_performance_segments(
  p_account_id UUID,
  p_start_date TIMESTAMP WITH TIME ZONE DEFAULT NOW() - INTERVAL '30 days',
  p_end_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  p_origin_city TEXT DEFAULT NULL,
  p_destination_city TEXT DEFAULT NULL,
  p_carrier TEXT DEFAULT NULL,
  p_segment_type TEXT DEFAULT NULL -- 'operational' or 'distribution'
)
RETURNS TABLE (
  route_key TEXT,
  origin_city TEXT,
  destination_city TEXT,
  carrier TEXT,
  segment_type TEXT,
  total_segments BIGINT,
  jk_standard_days NUMERIC,
  jk_actual_days NUMERIC,
  deviation_days NUMERIC,
  on_time_percentage NUMERIC,
  on_time_segments BIGINT,
  before_standard_segments BIGINT,
  after_standard_segments BIGINT,
  standard_percentage NUMERIC,
  warning_threshold NUMERIC,
  critical_threshold NUMERIC,
  status TEXT,
  distribution JSONB
) AS $$
BEGIN
  RETURN QUERY
  WITH segment_data AS (
    SELECT 
      js.id,
      js.tag_id,
      COALESCE(js.from_postal_center_name_snapshot, pc_from.name, 'Unknown') AS origin_city,
      COALESCE(js.to_postal_center_name_snapshot, pc_to.name, 'Unknown') AS destination_city,
      COALESCE(js.carrier_name_snapshot, 'N/A') AS carrier,
      js.segment_type,
      js.actual_time_minutes,
      js.expected_time_minutes,
      js.sla_compliance,
      -- Convert minutes to days (rounded to 1 decimal)
      ROUND((js.actual_time_minutes::NUMERIC / 1440), 1) AS actual_days,
      ROUND((COALESCE(js.expected_time_minutes, js.actual_time_minutes)::NUMERIC / 1440), 1) AS expected_days
    FROM journey_segments js
    LEFT JOIN postal_centers pc_from ON js.from_postal_center_id = pc_from.id
    LEFT JOIN postal_centers pc_to ON js.to_postal_center_id = pc_to.id
    WHERE js.account_id = p_account_id
      AND js.entry_timestamp BETWEEN p_start_date AND p_end_date
      AND js.exit_timestamp IS NOT NULL
      AND (p_origin_city IS NULL OR COALESCE(js.from_postal_center_name_snapshot, pc_from.name) = p_origin_city)
      AND (p_destination_city IS NULL OR COALESCE(js.to_postal_center_name_snapshot, pc_to.name) = p_destination_city)
      AND (p_carrier IS NULL OR js.carrier_name_snapshot = p_carrier)
      AND (p_segment_type IS NULL OR js.segment_type = p_segment_type)
  ),
  route_aggregates AS (
    SELECT 
      sd.origin_city || ' → ' || sd.destination_city || ' (' || sd.carrier || ', ' || sd.segment_type || ')' AS route_key,
      sd.origin_city,
      sd.destination_city,
      sd.carrier,
      sd.segment_type,
      COUNT(sd.id) AS total_segments,
      -- J+K Standard: Average expected days
      ROUND(AVG(sd.expected_days)::NUMERIC, 2) AS jk_standard_days,
      -- J+K Actual: Average actual days
      ROUND(AVG(sd.actual_days)::NUMERIC, 2) AS jk_actual_days,
      -- Deviation
      ROUND((AVG(sd.actual_days) - AVG(sd.expected_days))::NUMERIC, 2) AS deviation_days,
      -- On-time percentage
      ROUND((COUNT(CASE WHEN sd.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(sd.id)::NUMERIC, 0) * 100), 2) AS on_time_percentage,
      COUNT(CASE WHEN sd.sla_compliance = 'on_time' THEN 1 END) AS on_time_segments,
      COUNT(CASE WHEN sd.actual_days <= sd.expected_days THEN 1 END) AS before_standard_segments,
      COUNT(CASE WHEN sd.actual_days > sd.expected_days THEN 1 END) AS after_standard_segments,
      -- Distribution: Count by day buckets
      jsonb_object_agg(
        COALESCE(sd.actual_days::TEXT, '0'),
        COUNT(sd.id)
      ) AS distribution
    FROM segment_data sd
    GROUP BY sd.origin_city, sd.destination_city, sd.carrier, sd.segment_type
  )
  SELECT 
    ra.route_key,
    ra.origin_city,
    ra.destination_city,
    ra.carrier,
    ra.segment_type,
    ra.total_segments,
    ra.jk_standard_days,
    ra.jk_actual_days,
    ra.deviation_days,
    ra.on_time_percentage,
    ra.on_time_segments,
    ra.before_standard_segments,
    ra.after_standard_segments,
    85.0 AS standard_percentage, -- Default target
    80.0 AS warning_threshold,
    75.0 AS critical_threshold,
    CASE 
      WHEN ra.on_time_percentage >= 80 THEN 'compliant'
      WHEN ra.on_time_percentage >= 75 THEN 'warning'
      ELSE 'critical'
    END AS status,
    ra.distribution
  FROM route_aggregates ra
  ORDER BY ra.on_time_percentage ASC, ra.total_segments DESC;
END;
$$ LANGUAGE plpgsql;

-- Function: Get City-level aggregates for J+K Performance
CREATE OR REPLACE FUNCTION get_jk_city_performance_segments(
  p_account_id UUID,
  p_start_date TIMESTAMP WITH TIME ZONE DEFAULT NOW() - INTERVAL '30 days',
  p_end_date TIMESTAMP WITH TIME ZONE DEFAULT NOW()
)
RETURNS TABLE (
  city_name TEXT,
  direction TEXT,
  routes BIGINT,
  total_segments BIGINT,
  jk_standard_days NUMERIC,
  jk_actual_days NUMERIC,
  deviation_days NUMERIC,
  on_time_percentage NUMERIC,
  standard_percentage NUMERIC,
  warning_threshold NUMERIC,
  critical_threshold NUMERIC,
  status TEXT
) AS $$
BEGIN
  RETURN QUERY
  WITH segment_data AS (
    SELECT 
      js.id,
      COALESCE(js.from_postal_center_name_snapshot, pc_from.name, 'Unknown') AS from_city,
      COALESCE(js.to_postal_center_name_snapshot, pc_to.name, 'Unknown') AS to_city,
      ROUND((js.actual_time_minutes::NUMERIC / 1440), 2) AS actual_days,
      ROUND((COALESCE(js.expected_time_minutes, js.actual_time_minutes)::NUMERIC / 1440), 2) AS expected_days,
      js.sla_compliance
    FROM journey_segments js
    LEFT JOIN postal_centers pc_from ON js.from_postal_center_id = pc_from.id
    LEFT JOIN postal_centers pc_to ON js.to_postal_center_id = pc_to.id
    WHERE js.account_id = p_account_id
      AND js.entry_timestamp BETWEEN p_start_date AND p_end_date
      AND js.exit_timestamp IS NOT NULL
  ),
  city_outbound AS (
    SELECT 
      sd.from_city AS city_name,
      'outbound' AS direction,
      COUNT(DISTINCT (sd.from_city || '-' || sd.to_city)) AS routes,
      COUNT(sd.id) AS total_segments,
      ROUND(AVG(sd.expected_days)::NUMERIC, 2) AS jk_standard_days,
      ROUND(AVG(sd.actual_days)::NUMERIC, 2) AS jk_actual_days,
      ROUND((AVG(sd.actual_days) - AVG(sd.expected_days))::NUMERIC, 2) AS deviation_days,
      ROUND((COUNT(CASE WHEN sd.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(sd.id)::NUMERIC, 0) * 100), 2) AS on_time_percentage
    FROM segment_data sd
    GROUP BY sd.from_city
  ),
  city_inbound AS (
    SELECT 
      sd.to_city AS city_name,
      'inbound' AS direction,
      COUNT(DISTINCT (sd.from_city || '-' || sd.to_city)) AS routes,
      COUNT(sd.id) AS total_segments,
      ROUND(AVG(sd.expected_days)::NUMERIC, 2) AS jk_standard_days,
      ROUND(AVG(sd.actual_days)::NUMERIC, 2) AS jk_actual_days,
      ROUND((AVG(sd.actual_days) - AVG(sd.expected_days))::NUMERIC, 2) AS deviation_days,
      ROUND((COUNT(CASE WHEN sd.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(sd.id)::NUMERIC, 0) * 100), 2) AS on_time_percentage
    FROM segment_data sd
    GROUP BY sd.to_city
  ),
  combined AS (
    SELECT * FROM city_outbound
    UNION ALL
    SELECT * FROM city_inbound
  )
  SELECT 
    c.city_name,
    c.direction,
    c.routes,
    c.total_segments,
    c.jk_standard_days,
    c.jk_actual_days,
    c.deviation_days,
    c.on_time_percentage,
    85.0 AS standard_percentage,
    80.0 AS warning_threshold,
    75.0 AS critical_threshold,
    CASE 
      WHEN c.on_time_percentage >= 80 THEN 'compliant'
      WHEN c.on_time_percentage >= 75 THEN 'warning'
      ELSE 'critical'
    END AS status
  FROM combined c
  ORDER BY c.city_name, c.direction;
END;
$$ LANGUAGE plpgsql;

-- Function: Get Carrier-level aggregates for J+K Performance
CREATE OR REPLACE FUNCTION get_jk_carrier_performance_segments(
  p_account_id UUID,
  p_start_date TIMESTAMP WITH TIME ZONE DEFAULT NOW() - INTERVAL '30 days',
  p_end_date TIMESTAMP WITH TIME ZONE DEFAULT NOW()
)
RETURNS TABLE (
  carrier TEXT,
  routes BIGINT,
  total_segments BIGINT,
  jk_standard_days NUMERIC,
  jk_actual_days NUMERIC,
  deviation_days NUMERIC,
  on_time_percentage NUMERIC,
  problematic_routes BIGINT,
  standard_percentage NUMERIC,
  warning_threshold NUMERIC,
  critical_threshold NUMERIC,
  status TEXT
) AS $$
BEGIN
  RETURN QUERY
  WITH segment_data AS (
    SELECT 
      js.id,
      COALESCE(js.carrier_name_snapshot, 'N/A') AS carrier,
      COALESCE(js.from_postal_center_name_snapshot, 'Unknown') || ' → ' || COALESCE(js.to_postal_center_name_snapshot, 'Unknown') AS route_key,
      ROUND((js.actual_time_minutes::NUMERIC / 1440), 2) AS actual_days,
      ROUND((COALESCE(js.expected_time_minutes, js.actual_time_minutes)::NUMERIC / 1440), 2) AS expected_days,
      js.sla_compliance
    FROM journey_segments js
    WHERE js.account_id = p_account_id
      AND js.entry_timestamp BETWEEN p_start_date AND p_end_date
      AND js.exit_timestamp IS NOT NULL
      AND js.segment_type = 'distribution' -- Only distribution segments have carriers
  ),
  route_performance AS (
    SELECT 
      sd.carrier,
      sd.route_key,
      COUNT(sd.id) AS total_segments,
      ROUND((COUNT(CASE WHEN sd.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(sd.id)::NUMERIC, 0) * 100), 2) AS on_time_percentage
    FROM segment_data sd
    GROUP BY sd.carrier, sd.route_key
  )
  SELECT 
    sd.carrier,
    COUNT(DISTINCT sd.route_key) AS routes,
    COUNT(sd.id) AS total_segments,
    ROUND(AVG(sd.expected_days)::NUMERIC, 2) AS jk_standard_days,
    ROUND(AVG(sd.actual_days)::NUMERIC, 2) AS jk_actual_days,
    ROUND((AVG(sd.actual_days) - AVG(sd.expected_days))::NUMERIC, 2) AS deviation_days,
    ROUND((COUNT(CASE WHEN sd.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(sd.id)::NUMERIC, 0) * 100), 2) AS on_time_percentage,
    (SELECT COUNT(*) FROM route_performance rp WHERE rp.carrier = sd.carrier AND rp.on_time_percentage < 75) AS problematic_routes,
    85.0 AS standard_percentage,
    80.0 AS warning_threshold,
    75.0 AS critical_threshold,
    CASE 
      WHEN (COUNT(CASE WHEN sd.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(sd.id)::NUMERIC, 0) * 100) >= 80 THEN 'compliant'
      WHEN (COUNT(CASE WHEN sd.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(sd.id)::NUMERIC, 0) * 100) >= 75 THEN 'warning'
      ELSE 'critical'
    END AS status
  FROM segment_data sd
  GROUP BY sd.carrier
  ORDER BY on_time_percentage ASC;
END;
$$ LANGUAGE plpgsql;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_jk_performance_segments(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_jk_city_performance_segments(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE) TO authenticated;
GRANT EXECUTE ON FUNCTION get_jk_carrier_performance_segments(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE) TO authenticated;
