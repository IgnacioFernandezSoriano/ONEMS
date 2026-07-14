-- Center Analysis Report SQL Functions
-- Sprint 11: Diagnosis Module - Center Analysis

-- Function 1: Get Center Performance Metrics
CREATE OR REPLACE FUNCTION get_center_performance(
  p_account_id UUID,
  p_start_date TIMESTAMP WITH TIME ZONE DEFAULT NOW() - INTERVAL '30 days',
  p_end_date TIMESTAMP WITH TIME ZONE DEFAULT NOW()
)
RETURNS TABLE (
  center_id UUID,
  center_name TEXT,
  center_code TEXT,
  total_segments INTEGER,
  avg_processing_minutes NUMERIC,
  min_processing_minutes INTEGER,
  max_processing_minutes INTEGER,
  p95_processing_minutes NUMERIC,
  throughput_per_hour NUMERIC,
  efficiency_percentage NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    pc.id AS center_id,
    pc.name AS center_name,
    pc.code AS center_code,
    COUNT(js.id)::INTEGER AS total_segments,
    ROUND(AVG(js.actual_time_minutes)::NUMERIC, 2) AS avg_processing_minutes,
    MIN(js.actual_time_minutes) AS min_processing_minutes,
    MAX(js.actual_time_minutes) AS max_processing_minutes,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY js.actual_time_minutes)::NUMERIC, 2) AS p95_processing_minutes,
    ROUND((COUNT(js.id)::NUMERIC / NULLIF(SUM(js.actual_time_minutes)::NUMERIC / 60, 0)), 2) AS throughput_per_hour,
    ROUND((COUNT(CASE WHEN js.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(js.id)::NUMERIC, 0) * 100), 2) AS efficiency_percentage
  FROM journey_segments js
  JOIN postal_centers pc ON js.postal_center_id = pc.id
  WHERE js.account_id = p_account_id
    AND js.segment_type = 'operational'
    AND js.entry_timestamp BETWEEN p_start_date AND p_end_date
  GROUP BY pc.id, pc.name, pc.code
  HAVING COUNT(js.id) >= 3
  ORDER BY total_segments DESC;
END;
$$ LANGUAGE plpgsql;

-- Function 2: Get Center Comparison
CREATE OR REPLACE FUNCTION get_center_comparison(
  p_account_id UUID,
  p_start_date TIMESTAMP WITH TIME ZONE DEFAULT NOW() - INTERVAL '30 days',
  p_end_date TIMESTAMP WITH TIME ZONE DEFAULT NOW()
)
RETURNS TABLE (
  center_name TEXT,
  center_code TEXT,
  items_processed INTEGER,
  avg_processing_minutes NUMERIC,
  efficiency_score NUMERIC,
  performance_rank INTEGER
) AS $$
BEGIN
  RETURN QUERY
  WITH center_metrics AS (
    SELECT 
      pc.name AS center_name,
      pc.code AS center_code,
      COUNT(js.id)::INTEGER AS items_processed,
      ROUND(AVG(js.actual_time_minutes)::NUMERIC, 2) AS avg_processing_minutes,
      ROUND((COUNT(CASE WHEN js.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(js.id)::NUMERIC, 0) * 100), 2) AS efficiency_score
    FROM journey_segments js
    JOIN postal_centers pc ON js.postal_center_id = pc.id
    WHERE js.account_id = p_account_id
      AND js.segment_type = 'operational'
      AND js.entry_timestamp BETWEEN p_start_date AND p_end_date
    GROUP BY pc.id, pc.name, pc.code
    HAVING COUNT(js.id) >= 3
  )
  SELECT 
    cm.center_name,
    cm.center_code,
    cm.items_processed,
    cm.avg_processing_minutes,
    cm.efficiency_score,
    RANK() OVER (ORDER BY cm.efficiency_score DESC, cm.avg_processing_minutes ASC)::INTEGER AS performance_rank
  FROM center_metrics cm
  ORDER BY performance_rank;
END;
$$ LANGUAGE plpgsql;

-- Function 3: Get Center Trends
CREATE OR REPLACE FUNCTION get_center_trends(
  p_account_id UUID,
  p_period TEXT DEFAULT 'daily', -- 'daily', 'weekly', 'monthly'
  p_start_date TIMESTAMP WITH TIME ZONE DEFAULT NOW() - INTERVAL '30 days',
  p_end_date TIMESTAMP WITH TIME ZONE DEFAULT NOW()
)
RETURNS TABLE (
  period_date DATE,
  center_name TEXT,
  items_count INTEGER,
  avg_processing_minutes NUMERIC,
  efficiency_percentage NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    CASE 
      WHEN p_period = 'weekly' THEN DATE_TRUNC('week', js.entry_timestamp)::DATE
      WHEN p_period = 'monthly' THEN DATE_TRUNC('month', js.entry_timestamp)::DATE
      ELSE DATE_TRUNC('day', js.entry_timestamp)::DATE
    END AS period_date,
    pc.name AS center_name,
    COUNT(js.id)::INTEGER AS items_count,
    ROUND(AVG(js.actual_time_minutes)::NUMERIC, 2) AS avg_processing_minutes,
    ROUND((COUNT(CASE WHEN js.sla_compliance = 'on_time' THEN 1 END)::NUMERIC / NULLIF(COUNT(js.id)::NUMERIC, 0) * 100), 2) AS efficiency_percentage
  FROM journey_segments js
  JOIN postal_centers pc ON js.postal_center_id = pc.id
  WHERE js.account_id = p_account_id
    AND js.segment_type = 'operational'
    AND js.entry_timestamp BETWEEN p_start_date AND p_end_date
  GROUP BY period_date, pc.name
  ORDER BY period_date DESC, center_name;
END;
$$ LANGUAGE plpgsql;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION get_center_performance(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE) TO authenticated;
GRANT EXECUTE ON FUNCTION get_center_comparison(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE) TO authenticated;
GRANT EXECUTE ON FUNCTION get_center_trends(UUID, TEXT, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE) TO authenticated;
