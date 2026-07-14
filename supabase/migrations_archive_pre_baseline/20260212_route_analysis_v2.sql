-- Route Analysis SQL Foundation v2
-- Fix: Cast to NUMERIC before ROUND to avoid type errors

-- Drop existing functions
DROP FUNCTION IF EXISTS get_route_performance(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE);
DROP FUNCTION IF EXISTS get_carrier_comparison(UUID, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE);
DROP FUNCTION IF EXISTS get_route_trends(UUID, TEXT, TEXT, TIMESTAMP WITH TIME ZONE, TIMESTAMP WITH TIME ZONE, TEXT);

-- Function: Get route performance metrics
CREATE OR REPLACE FUNCTION get_route_performance(
  p_account_id UUID,
  p_start_date TIMESTAMP WITH TIME ZONE DEFAULT NULL,
  p_end_date TIMESTAMP WITH TIME ZONE DEFAULT NULL
)
RETURNS TABLE (
  origin_city_name TEXT,
  destination_city_name TEXT,
  total_journeys BIGINT,
  completed_journeys BIGINT,
  on_time_rate NUMERIC,
  avg_transit_hours NUMERIC,
  median_transit_hours NUMERIC,
  p95_transit_hours NUMERIC,
  total_sla_violations BIGINT,
  missroute_count BIGINT,
  missroute_rate NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    j.origin_city_name,
    j.destination_city_name,
    COUNT(*)::BIGINT as total_journeys,
    SUM(CASE WHEN j.journey_status = 'completed' THEN 1 ELSE 0 END)::BIGINT as completed_journeys,
    ROUND((SUM(CASE WHEN j.total_sla_violations = 0 AND j.journey_status = 'completed' THEN 1 ELSE 0 END)::NUMERIC / 
           NULLIF(SUM(CASE WHEN j.journey_status = 'completed' THEN 1 ELSE 0 END), 0)::NUMERIC * 100)::NUMERIC, 2) as on_time_rate,
    ROUND((AVG(CASE WHEN j.journey_status = 'completed' THEN j.total_actual_time_minutes / 60.0 END))::NUMERIC, 2) as avg_transit_hours,
    ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY CASE WHEN j.journey_status = 'completed' THEN j.total_actual_time_minutes / 60.0 END))::NUMERIC, 2) as median_transit_hours,
    ROUND((PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY CASE WHEN j.journey_status = 'completed' THEN j.total_actual_time_minutes / 60.0 END))::NUMERIC, 2) as p95_transit_hours,
    SUM(j.total_sla_violations)::BIGINT as total_sla_violations,
    SUM(CASE WHEN j.is_missroute THEN 1 ELSE 0 END)::BIGINT as missroute_count,
    ROUND((SUM(CASE WHEN j.is_missroute THEN 1 ELSE 0 END)::NUMERIC / NULLIF(COUNT(*), 0)::NUMERIC * 100)::NUMERIC, 2) as missroute_rate
  FROM journeys j
  WHERE j.account_id = p_account_id
    AND j.origin_city_name IS NOT NULL
    AND j.destination_city_name IS NOT NULL
    AND (p_start_date IS NULL OR j.first_event_timestamp >= p_start_date)
    AND (p_end_date IS NULL OR j.first_event_timestamp <= p_end_date)
  GROUP BY j.origin_city_name, j.destination_city_name
  HAVING COUNT(*) >= 3
  ORDER BY total_journeys DESC;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function: Get carrier comparison by route
CREATE OR REPLACE FUNCTION get_carrier_comparison(
  p_account_id UUID,
  p_start_date TIMESTAMP WITH TIME ZONE DEFAULT NULL,
  p_end_date TIMESTAMP WITH TIME ZONE DEFAULT NULL
)
RETURNS TABLE (
  carrier_name TEXT,
  total_segments BIGINT,
  on_time_segments BIGINT,
  on_time_rate NUMERIC,
  avg_transit_hours NUMERIC,
  total_routes BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    c.name as carrier_name,
    COUNT(*)::BIGINT as total_segments,
    SUM(CASE WHEN js.sla_compliance = 'on_time' THEN 1 ELSE 0 END)::BIGINT as on_time_segments,
    ROUND((SUM(CASE WHEN js.sla_compliance = 'on_time' THEN 1 ELSE 0 END)::NUMERIC / 
           NULLIF(COUNT(*), 0)::NUMERIC * 100)::NUMERIC, 2) as on_time_rate,
    ROUND((AVG(js.actual_time_minutes / 60.0))::NUMERIC, 2) as avg_transit_hours,
    COUNT(DISTINCT CONCAT(js.from_postal_center_id, '-', js.to_postal_center_id))::BIGINT as total_routes
  FROM journey_segments js
  JOIN carriers c ON js.carrier_id = c.id
  WHERE js.account_id = p_account_id
    AND js.segment_type = 'distribution'
    AND js.carrier_id IS NOT NULL
    AND (p_start_date IS NULL OR js.entry_timestamp >= p_start_date)
    AND (p_end_date IS NULL OR js.entry_timestamp <= p_end_date)
  GROUP BY c.name
  HAVING COUNT(*) >= 5
  ORDER BY on_time_rate DESC, total_segments DESC;
END;
$$ LANGUAGE plpgsql STABLE;

-- Function: Get route performance trends over time
CREATE OR REPLACE FUNCTION get_route_trends(
  p_account_id UUID,
  p_origin_city TEXT DEFAULT NULL,
  p_destination_city TEXT DEFAULT NULL,
  p_start_date TIMESTAMP WITH TIME ZONE DEFAULT NULL,
  p_end_date TIMESTAMP WITH TIME ZONE DEFAULT NULL,
  p_interval TEXT DEFAULT 'week' -- 'day', 'week', 'month'
)
RETURNS TABLE (
  period_start TIMESTAMP WITH TIME ZONE,
  total_journeys BIGINT,
  on_time_rate NUMERIC,
  avg_transit_hours NUMERIC
) AS $$
DECLARE
  v_trunc_format TEXT;
BEGIN
  -- Determine date truncation format
  v_trunc_format := CASE p_interval
    WHEN 'day' THEN 'day'
    WHEN 'month' THEN 'month'
    ELSE 'week'
  END;

  RETURN QUERY
  EXECUTE format($sql$
    SELECT
      DATE_TRUNC(%L, j.first_event_timestamp) as period_start,
      COUNT(*)::BIGINT as total_journeys,
      ROUND((SUM(CASE WHEN j.total_sla_violations = 0 AND j.journey_status = 'completed' THEN 1 ELSE 0 END)::NUMERIC / 
             NULLIF(SUM(CASE WHEN j.journey_status = 'completed' THEN 1 ELSE 0 END), 0)::NUMERIC * 100)::NUMERIC, 2) as on_time_rate,
      ROUND((AVG(CASE WHEN j.journey_status = 'completed' THEN j.total_actual_time_minutes / 60.0 END))::NUMERIC, 2) as avg_transit_hours
    FROM journeys j
    WHERE j.account_id = $1
      AND j.first_event_timestamp IS NOT NULL
      AND ($2 IS NULL OR j.origin_city_name = $2)
      AND ($3 IS NULL OR j.destination_city_name = $3)
      AND ($4 IS NULL OR j.first_event_timestamp >= $4)
      AND ($5 IS NULL OR j.first_event_timestamp <= $5)
    GROUP BY DATE_TRUNC(%L, j.first_event_timestamp)
    HAVING COUNT(*) >= 3
    ORDER BY period_start ASC
  $sql$, v_trunc_format, v_trunc_format)
  USING p_account_id, p_origin_city, p_destination_city, p_start_date, p_end_date;
END;
$$ LANGUAGE plpgsql STABLE;
