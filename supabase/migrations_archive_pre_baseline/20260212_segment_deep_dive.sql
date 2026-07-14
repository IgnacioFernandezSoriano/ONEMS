-- Segment Deep Dive Report SQL Functions
-- Sprint 11: Diagnosis Module - Segment Deep Dive (Simplified 3 tabs)

-- Function 1: Get Segment Overview by Type
CREATE OR REPLACE FUNCTION get_segment_overview(
  p_account_id UUID,
  p_start_date TIMESTAMP WITH TIME ZONE DEFAULT NOW() - INTERVAL '30 days',
  p_end_date TIMESTAMP WITH TIME ZONE DEFAULT NOW()
)
RETURNS TABLE (
  segment_type TEXT,
  total_count BIGINT,
  avg_duration_minutes NUMERIC,
  min_duration_minutes INTEGER,
  max_duration_minutes INTEGER,
  p50_duration_minutes NUMERIC,
  p95_duration_minutes NUMERIC,
  sla_compliance_rate NUMERIC,
  on_time_count BIGINT,
  warning_count BIGINT,
  critical_count BIGINT,
  violated_count BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    js.segment_type,
    COUNT(js.id) AS total_count,
    ROUND(AVG(js.actual_time_minutes)::NUMERIC, 2) AS avg_duration_minutes,
    MIN(js.actual_time_minutes) AS min_duration_minutes,
    MAX(js.actual_time_minutes) AS max_duration_minutes,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY js.actual_time_minutes)::NUMERIC, 2) AS p50_duration_minutes,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY js.actual_time_minutes)::NUMERIC, 2) AS p95_duration_minutes,
    ROUND((COUNT(CASE WHEN js.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(js.id)::NUMERIC, 0) * 100), 2) AS sla_compliance_rate,
    COUNT(CASE WHEN js.sla_compliance = 'on_time' THEN 1 END) AS on_time_count,
    COUNT(CASE WHEN js.sla_compliance = 'warning' THEN 1 END) AS warning_count,
    COUNT(CASE WHEN js.sla_compliance = 'critical' THEN 1 END) AS critical_count,
    COUNT(CASE WHEN js.sla_compliance = 'violated' THEN 1 END) AS violated_count
  FROM journey_segments js
  WHERE js.account_id = p_account_id
    AND js.entry_timestamp BETWEEN p_start_date AND p_end_date
  GROUP BY js.segment_type
  ORDER BY js.segment_type;
END;
$$ LANGUAGE plpgsql;

-- Function 2: Get Segment Time Analysis with Hourly Patterns
CREATE OR REPLACE FUNCTION get_segment_time_analysis(
  p_account_id UUID,
  p_segment_type TEXT DEFAULT NULL, -- 'operational' or 'distribution' or NULL for all
  p_start_date TIMESTAMP WITH TIME ZONE DEFAULT NOW() - INTERVAL '30 days',
  p_end_date TIMESTAMP WITH TIME ZONE DEFAULT NOW()
)
RETURNS TABLE (
  hour_of_day INTEGER,
  segment_count BIGINT,
  avg_duration_minutes NUMERIC,
  p50_duration_minutes NUMERIC,
  p95_duration_minutes NUMERIC,
  outlier_count BIGINT,
  sla_compliance_rate NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  WITH segment_stats AS (
    SELECT 
      EXTRACT(HOUR FROM js.entry_timestamp)::INTEGER AS hour_of_day,
      js.actual_time_minutes,
      js.sla_compliance,
      AVG(js.actual_time_minutes) OVER () AS overall_avg,
      STDDEV(js.actual_time_minutes) OVER () AS overall_stddev
    FROM journey_segments js
    WHERE js.account_id = p_account_id
      AND js.entry_timestamp BETWEEN p_start_date AND p_end_date
      AND (p_segment_type IS NULL OR js.segment_type = p_segment_type)
  )
  SELECT 
    ss.hour_of_day,
    COUNT(*)::BIGINT AS segment_count,
    ROUND(AVG(ss.actual_time_minutes)::NUMERIC, 2) AS avg_duration_minutes,
    ROUND(PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY ss.actual_time_minutes)::NUMERIC, 2) AS p50_duration_minutes,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ss.actual_time_minutes)::NUMERIC, 2) AS p95_duration_minutes,
    COUNT(CASE WHEN ss.actual_time_minutes > (ss.overall_avg + 2 * ss.overall_stddev) THEN 1 END)::BIGINT AS outlier_count,
    ROUND((COUNT(CASE WHEN ss.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(*)::NUMERIC, 0) * 100), 2) AS sla_compliance_rate
  FROM segment_stats ss
  GROUP BY ss.hour_of_day
  ORDER BY ss.hour_of_day;
END;
$$ LANGUAGE plpgsql;

-- Function 3: Get Segment Anomalies
CREATE OR REPLACE FUNCTION get_segment_anomalies(
  p_account_id UUID,
  p_start_date TIMESTAMP WITH TIME ZONE DEFAULT NOW() - INTERVAL '30 days',
  p_end_date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  p_min_deviation_pct NUMERIC DEFAULT 100.0 -- Segments exceeding 2x expected time (100% deviation)
)
RETURNS TABLE (
  segment_id BIGINT,
  tag_id TEXT,
  segment_type TEXT,
  center_name TEXT,
  carrier_name TEXT,
  entry_timestamp TIMESTAMP WITH TIME ZONE,
  exit_timestamp TIMESTAMP WITH TIME ZONE,
  actual_duration_minutes INTEGER,
  expected_duration_minutes INTEGER,
  deviation_minutes INTEGER,
  deviation_percentage NUMERIC,
  sla_compliance TEXT,
  anomaly_type TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    js.id AS segment_id,
    js.tag_id,
    js.segment_type,
    COALESCE(pc.name, 'Unknown') AS center_name,
    COALESCE(js.carrier_name_snapshot, 'N/A') AS carrier_name,
    js.entry_timestamp,
    js.exit_timestamp,
    js.actual_time_minutes AS actual_duration_minutes,
    COALESCE(js.expected_time_minutes, 0) AS expected_duration_minutes,
    (js.actual_time_minutes - COALESCE(js.expected_time_minutes, 0)) AS deviation_minutes,
    ROUND(
      CASE 
        WHEN COALESCE(js.expected_time_minutes, 0) > 0 
        THEN ((js.actual_time_minutes - js.expected_time_minutes)::NUMERIC / js.expected_time_minutes::NUMERIC * 100)
        ELSE 0
      END, 2
    ) AS deviation_percentage,
    js.sla_compliance,
    CASE 
      WHEN js.sla_compliance IN ('critical', 'violated') THEN 'sla_violation'
      WHEN js.actual_time_minutes > (COALESCE(js.expected_time_minutes, 0) * 3) THEN 'extremely_slow'
      WHEN js.actual_time_minutes > (COALESCE(js.expected_time_minutes, 0) * 2) THEN 'slow'
      WHEN js.exit_timestamp IS NULL AND NOW() - js.entry_timestamp > INTERVAL '24 hours' THEN 'stalled'
      ELSE 'other'
    END AS anomaly_type
  FROM journey_segments js
  LEFT JOIN postal_centers pc ON js.postal_center_id = pc.id
  WHERE js.account_id = p_account_id
    AND js.entry_timestamp BETWEEN p_start_date AND p_end_date
    AND (
      -- Deviation exceeds threshold
      (COALESCE(js.expected_time_minutes, 0) > 0 
       AND ((js.actual_time_minutes - js.expected_time_minutes)::NUMERIC / js.expected_time_minutes::NUMERIC * 100) >= p_min_deviation_pct)
      -- OR SLA violated
      OR js.sla_compliance IN ('critical', 'violated')
      -- OR stalled (no exit after 24h)
      OR (js.exit_timestamp IS NULL AND NOW() - js.entry_timestamp > INTERVAL '24 hours')
    )
  ORDER BY deviation_percentage DESC NULLS LAST, js.entry_timestamp DESC
  LIMIT 100;
END;
$$ LANGUAGE plpgsql;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_segment_overview(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE) TO authenticated;
GRANT EXECUTE ON FUNCTION get_segment_time_analysis(UUID, TEXT, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE) TO authenticated;
GRANT EXECUTE ON FUNCTION get_segment_anomalies(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE, NUMERIC) TO authenticated;
