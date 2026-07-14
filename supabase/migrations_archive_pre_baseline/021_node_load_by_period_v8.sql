-- Function to analyze node load for a date period with custom reference and deviation
-- V8: Fixed type mismatch - cast panelist_name to TEXT to match return type
--     V7: Fixed origin_city_id error - simplified to count origin shipments only

-- Drop existing function first
DROP FUNCTION IF EXISTS rpc_get_node_load_by_period(uuid,date,date,numeric,numeric);

CREATE OR REPLACE FUNCTION rpc_get_node_load_by_period(
  p_account_id UUID,
  p_start_date DATE,
  p_end_date DATE,
  p_reference_load NUMERIC DEFAULT 6,
  p_deviation_percent NUMERIC DEFAULT 20
)
RETURNS TABLE (
  account_id UUID,
  node_id UUID,
  node_code TEXT,
  panelist_name TEXT,
  city_name TEXT,
  city_id UUID,
  week_number INTEGER,
  week_start_date DATE,
  week_end_date DATE,
  shipment_count INTEGER,
  sent_count INTEGER,
  received_count INTEGER,
  pending_count INTEGER,
  city_weekly_avg NUMERIC,
  city_weekly_stddev NUMERIC,
  city_weekly_total INTEGER,
  city_node_count INTEGER,
  city_period_avg NUMERIC,
  city_period_stddev NUMERIC,
  city_period_total INTEGER,
  total_weeks_in_period INTEGER,
  saturation_level TEXT,
  load_percentage NUMERIC,
  excess_load NUMERIC,
  reference_load NUMERIC,
  deviation_threshold NUMERIC,
  node_period_avg NUMERIC
) AS $$
DECLARE
  v_total_weeks INTEGER;
  v_high_threshold NUMERIC;
  v_saturated_threshold NUMERIC;
BEGIN
  -- Calculate total weeks in the period
  v_total_weeks := CEIL((p_end_date - p_start_date + 1) / 7.0);
  
  -- Calculate thresholds based on reference and deviation
  v_high_threshold := p_reference_load * (1 + p_deviation_percent / 100.0);
  v_saturated_threshold := p_reference_load * (1 + (p_deviation_percent * 1.5) / 100.0);
  
  RETURN QUERY
  WITH 
  -- Get all weeks in the period
  week_series AS (
    SELECT 
      generate_series(
        date_trunc('week', p_start_date::timestamp),
        date_trunc('week', p_end_date::timestamp),
        '1 week'::interval
      )::date AS week_start
  ),
  weeks_numbered AS (
    SELECT 
      week_start,
      (week_start + interval '6 days')::date AS week_end,
      EXTRACT(WEEK FROM week_start)::INTEGER AS week_num
    FROM week_series
    WHERE week_start <= p_end_date
      AND (week_start + interval '6 days')::date >= p_start_date
  ),
  -- Get shipments from allocation_plan_details grouped by node and week
  -- Count shipments where this node is ORIGIN (sent shipments)
  shipments_by_week AS (
    SELECT 
      p_account_id AS account_id,
      n.id AS node_id,
      n.auto_id AS node_code,
      pan.name::TEXT AS panelist_name,
      c.name AS city_name,
      c.id AS city_id,
      w.week_num,
      w.week_start,
      w.week_end,
      -- Count shipments where this node is origin
      COUNT(DISTINCT apd.id) AS shipment_count,
      -- Sent: where node is origin
      COUNT(DISTINCT apd.id) AS sent_count,
      -- Received: 0 (we only count origin shipments)
      0 AS received_count,
      -- Pending: status = pending/assigned/planned
      COUNT(DISTINCT CASE 
        WHEN apd.status IN ('pending', 'assigned', 'planned')
        THEN apd.id 
      END) AS pending_count
    FROM weeks_numbered w
    CROSS JOIN nodes n
    LEFT JOIN panelists pan ON pan.node_id = n.id AND pan.status = 'active'
    LEFT JOIN allocation_plan_details apd ON 
      apd.origin_node_id = n.id AND
      apd.account_id = p_account_id AND
      apd.fecha_programada >= GREATEST(w.week_start, p_start_date) AND
      apd.fecha_programada <= LEAST(w.week_end, p_end_date)
    LEFT JOIN cities c ON n.city_id = c.id
    WHERE n.account_id = p_account_id
      AND n.city_id IS NOT NULL
    GROUP BY n.id, n.auto_id, pan.name, c.name, c.id, w.week_num, w.week_start, w.week_end
  ),
  -- Calculate NODE period average (total shipments / number of weeks)
  node_period_avg AS (
    SELECT
      sbw_npa.node_id,
      sbw_npa.city_id,
      AVG(sbw_npa.shipment_count) AS period_avg
    FROM shipments_by_week sbw_npa
    GROUP BY sbw_npa.node_id, sbw_npa.city_id
  ),
  -- Calculate city-level statistics
  city_stats AS (
    SELECT 
      sbw.city_id,
      sbw.week_num,
      AVG(sbw.shipment_count) AS weekly_avg,
      STDDEV(sbw.shipment_count) AS weekly_stddev,
      SUM(sbw.shipment_count) AS weekly_total,
      COUNT(DISTINCT sbw.node_id) AS node_count
    FROM shipments_by_week sbw
    GROUP BY sbw.city_id, sbw.week_num
  ),
  city_period_stats AS (
    SELECT 
      npa.city_id,
      AVG(npa.period_avg) AS period_avg,
      STDDEV(npa.period_avg) AS period_stddev,
      (SELECT SUM(sbw3.shipment_count) FROM shipments_by_week sbw3 WHERE sbw3.city_id = npa.city_id) AS period_total,
      COUNT(DISTINCT npa.node_id) AS node_count
    FROM node_period_avg npa
    GROUP BY npa.city_id
  )
  -- Final result with saturation classification based on NODE PERIOD AVERAGE
  SELECT 
    p_account_id AS account_id,
    sbw.node_id,
    sbw.node_code,
    sbw.panelist_name,
    sbw.city_name,
    sbw.city_id,
    sbw.week_num::INTEGER,
    sbw.week_start,
    sbw.week_end,
    sbw.shipment_count::INTEGER,
    sbw.sent_count::INTEGER,
    sbw.received_count::INTEGER,
    sbw.pending_count::INTEGER,
    COALESCE(cs.weekly_avg, 0)::NUMERIC AS city_weekly_avg,
    COALESCE(cs.weekly_stddev, 0)::NUMERIC AS city_weekly_stddev,
    COALESCE(cs.weekly_total, 0)::INTEGER AS city_weekly_total,
    COALESCE(cs.node_count, 0)::INTEGER AS city_node_count,
    COALESCE(cps.period_avg, 0)::NUMERIC AS city_period_avg,
    COALESCE(cps.period_stddev, 0)::NUMERIC AS city_period_stddev,
    COALESCE(cps.period_total, 0)::INTEGER AS city_period_total,
    v_total_weeks AS total_weeks_in_period,
    -- Classify based on NODE PERIOD AVERAGE, not individual week
    CASE 
      WHEN COALESCE(npa.period_avg, 0) >= v_saturated_threshold THEN 'saturated'
      WHEN COALESCE(npa.period_avg, 0) >= v_high_threshold THEN 'high'
      ELSE 'normal'
    END AS saturation_level,
    CASE 
      WHEN p_reference_load > 0 THEN (COALESCE(npa.period_avg, 0) / p_reference_load * 100)
      ELSE 0
    END AS load_percentage,
    CASE 
      WHEN COALESCE(npa.period_avg, 0) > p_reference_load THEN (COALESCE(npa.period_avg, 0) - p_reference_load)
      ELSE 0
    END AS excess_load,
    p_reference_load AS reference_load,
    v_high_threshold AS deviation_threshold,
    COALESCE(npa.period_avg, 0)::NUMERIC AS node_period_avg
  FROM shipments_by_week sbw
  LEFT JOIN node_period_avg npa ON sbw.node_id = npa.node_id
  LEFT JOIN city_stats cs ON sbw.city_id = cs.city_id AND sbw.week_num = cs.week_num
  LEFT JOIN city_period_stats cps ON sbw.city_id = cps.city_id
  WHERE sbw.week_start <= p_end_date AND sbw.week_end >= p_start_date
  ORDER BY sbw.city_name, sbw.week_num, sbw.node_code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION rpc_get_node_load_by_period TO authenticated;

COMMENT ON FUNCTION rpc_get_node_load_by_period IS 
'Analyzes node load distribution for a custom date period using allocation_plan_details.
V8: Fixed type mismatch - cast panelist_name to TEXT to match return type.
V7: Fixed origin_city_id error - simplified to count only origin shipments per node.
Includes panelist_name for each node.';
