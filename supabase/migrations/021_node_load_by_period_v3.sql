-- Function to analyze node load for a date period with custom reference and deviation
-- V3: Uses allocation_plan_details instead of material_shipments
CREATE OR REPLACE FUNCTION rpc_get_node_load_by_period(
  p_account_id UUID,
  p_start_date DATE,
  p_end_date DATE,
  p_reference_load NUMERIC DEFAULT 63,
  p_deviation_percent NUMERIC DEFAULT 20
)
RETURNS TABLE (
  account_id UUID,
  node_id UUID,
  node_code TEXT,
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
  deviation_threshold NUMERIC
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
  -- Count both sent (origin_node_id) and received (destination_node_id)
  shipments_by_week AS (
    SELECT 
      p_account_id AS account_id,
      n.id AS node_id,
      n.auto_id AS node_code,
      c.name AS city_name,
      c.id AS city_id,
      w.week_num,
      w.week_start,
      w.week_end,
      -- Total shipments (sent + received)
      COUNT(DISTINCT apd.id) AS shipment_count,
      -- Sent: where node is origin and status is sent/delivered
      COUNT(DISTINCT CASE 
        WHEN apd.origin_node_id = n.id 
          AND apd.status IN ('sent', 'delivered', 'received')
        THEN apd.id 
      END) AS sent_count,
      -- Received: where node is destination and status is delivered/received
      COUNT(DISTINCT CASE 
        WHEN apd.destination_node_id = n.id 
          AND apd.status IN ('delivered', 'received')
        THEN apd.id 
      END) AS received_count,
      -- Pending: where node is origin or destination and status is pending/assigned
      COUNT(DISTINCT CASE 
        WHEN (apd.origin_node_id = n.id OR apd.destination_node_id = n.id)
          AND apd.status IN ('pending', 'assigned', 'planned')
        THEN apd.id 
      END) AS pending_count
    FROM weeks_numbered w
    CROSS JOIN nodes n
    LEFT JOIN allocation_plan_details apd ON 
      (apd.origin_node_id = n.id OR apd.destination_node_id = n.id) AND
      apd.account_id = p_account_id AND
      apd.fecha_programada >= GREATEST(w.week_start, p_start_date) AND
      apd.fecha_programada <= LEAST(w.week_end, p_end_date)
    LEFT JOIN cities c ON n.city_id = c.id
    WHERE n.account_id = p_account_id
      AND n.city_id IS NOT NULL
    GROUP BY n.id, n.auto_id, c.name, c.id, w.week_num, w.week_start, w.week_end
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
      sbw2.city_id,
      AVG(sbw2.shipment_count) AS period_avg,
      STDDEV(sbw2.shipment_count) AS period_stddev,
      SUM(sbw2.shipment_count) AS period_total,
      COUNT(DISTINCT sbw2.node_id) AS node_count
    FROM shipments_by_week sbw2
    GROUP BY sbw2.city_id
  )
  -- Final result with saturation classification
  SELECT 
    p_account_id AS account_id,
    sbw.node_id,
    sbw.node_code,
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
    CASE 
      WHEN sbw.shipment_count >= v_saturated_threshold THEN 'saturated'
      WHEN sbw.shipment_count >= v_high_threshold THEN 'high'
      ELSE 'normal'
    END AS saturation_level,
    CASE 
      WHEN p_reference_load > 0 THEN (sbw.shipment_count::NUMERIC / p_reference_load * 100)
      ELSE 0
    END AS load_percentage,
    CASE 
      WHEN sbw.shipment_count > p_reference_load THEN (sbw.shipment_count - p_reference_load)
      ELSE 0
    END AS excess_load,
    p_reference_load AS reference_load,
    v_high_threshold AS deviation_threshold
  FROM shipments_by_week sbw
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
Counts both sent (origin_node_id) and received (destination_node_id) shipments per node.
Classifies nodes as normal, high load, or saturated based on configurable thresholds.';
