-- Function to balance node load using aliquot matrix distribution
-- Distributes shipments across nodes×weeks matrix to minimize standard deviation

-- Drop existing function first
DROP FUNCTION IF EXISTS rpc_balance_node_load_by_period(uuid,date,date,boolean);

CREATE OR REPLACE FUNCTION rpc_balance_node_load_by_period(
  p_city_id UUID,
  p_start_date DATE,
  p_end_date DATE,
  p_apply_changes BOOLEAN DEFAULT FALSE
)
RETURNS JSONB AS $$
DECLARE
  v_result JSONB;
  v_movements JSONB[] := '{}';
  v_movement JSONB;
  v_stddev_before NUMERIC;
  v_stddev_after NUMERIC;
  v_movements_count INTEGER := 0;
  v_improvement NUMERIC;
  v_total_shipments INTEGER;
  v_total_cells INTEGER;
  v_target_avg NUMERIC;
  v_cell RECORD;
  v_from_cell RECORD;
  v_to_cell RECORD;
  v_shipments_to_move UUID[];
  v_shipment_id UUID;
  v_move_count INTEGER;
BEGIN
  -- Calculate current standard deviation across all cells (node×week)
  WITH 
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
  cell_loads AS (
    SELECT 
      n.id AS node_id,
      n.auto_id AS node_code,
      w.week_num,
      w.week_start,
      w.week_end,
      COUNT(DISTINCT apd.id) AS load_count
    FROM nodes n
    CROSS JOIN weeks_numbered w
    LEFT JOIN allocation_plan_details apd ON 
      (apd.origin_node_id = n.id OR apd.destination_node_id = n.id) AND
      apd.fecha_programada >= w.week_start AND
      apd.fecha_programada <= w.week_end
    WHERE n.city_id = p_city_id
    GROUP BY n.id, n.auto_id, w.week_num, w.week_start, w.week_end
  )
  SELECT 
    STDDEV(load_count),
    SUM(load_count),
    COUNT(*)
  INTO v_stddev_before, v_total_shipments, v_total_cells
  FROM cell_loads;
  
  v_stddev_before := COALESCE(v_stddev_before, 0);
  v_total_shipments := COALESCE(v_total_shipments, 0);
  v_total_cells := COALESCE(v_total_cells, 1);
  
  -- Calculate target average per cell
  v_target_avg := v_total_shipments::NUMERIC / v_total_cells;
  
  -- Always allow balancing (no stddev threshold check)
  
  -- Balance algorithm: Move shipments from overloaded cells to underloaded cells
  FOR v_from_cell IN
    WITH 
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
    cell_loads AS (
      SELECT 
        n.id AS node_id,
        n.auto_id AS node_code,
        w.week_num,
        w.week_start,
        w.week_end,
        COUNT(DISTINCT apd.id) AS load_count
      FROM nodes n
      CROSS JOIN weeks_numbered w
      LEFT JOIN allocation_plan_details apd ON 
        (apd.origin_node_id = n.id OR apd.destination_node_id = n.id) AND
        apd.fecha_programada >= w.week_start AND
        apd.fecha_programada <= w.week_end
      WHERE n.city_id = p_city_id
      GROUP BY n.id, n.auto_id, w.week_num, w.week_start, w.week_end
    )
    SELECT 
      node_id,
      node_code,
      week_num,
      week_start,
      week_end,
      load_count,
      (load_count - v_target_avg) AS excess
    FROM cell_loads
    WHERE load_count > v_target_avg * 1.2  -- 20% above target
    ORDER BY excess DESC
    LIMIT 10  -- Limit iterations to prevent infinite loops
  LOOP
    -- Find underloaded cell to transfer to
    SELECT 
      n.id AS node_id,
      n.auto_id AS node_code,
      w.week_num,
      ws.week_start,
      w.week_end,
      COUNT(DISTINCT apd.id) AS load_count
    INTO v_to_cell
    FROM nodes n
    CROSS JOIN (
      SELECT 
        generate_series(
          date_trunc('week', p_start_date::timestamp),
          date_trunc('week', p_end_date::timestamp),
          '1 week'::interval
        )::date AS week_start
    ) ws
    CROSS JOIN LATERAL (
      SELECT 
        (ws.week_start + interval '6 days')::date AS week_end,
        EXTRACT(WEEK FROM ws.week_start)::INTEGER AS week_num
    ) w
    LEFT JOIN allocation_plan_details apd ON 
      (apd.origin_node_id = n.id OR apd.destination_node_id = n.id) AND
      apd.fecha_programada >= ws.week_start AND
      apd.fecha_programada <= w.week_end
    WHERE n.city_id = p_city_id
      AND ws.week_start <= p_end_date
      AND w.week_end >= p_start_date
    GROUP BY n.id, n.auto_id, w.week_num, ws.week_start, w.week_end
    HAVING COUNT(DISTINCT apd.id) < v_target_avg * 0.9  -- 10% below target
    ORDER BY COUNT(DISTINCT apd.id) ASC
    LIMIT 1;
    
    IF v_to_cell.node_id IS NOT NULL THEN
      -- Calculate how many to move
      v_move_count := LEAST(
        CEIL(v_from_cell.excess / 2),
        FLOOR((v_target_avg - v_to_cell.load_count) * 0.8)
      )::INTEGER;
      
      IF v_move_count > 0 THEN
        -- Get shipments to move from the overloaded cell
        SELECT ARRAY_AGG(id) INTO v_shipments_to_move
        FROM (
          SELECT apd.id
          FROM allocation_plan_details apd
          WHERE (apd.origin_node_id = v_from_cell.node_id OR apd.destination_node_id = v_from_cell.node_id)
            AND apd.fecha_programada >= v_from_cell.week_start
            AND apd.fecha_programada <= v_from_cell.week_end
            AND apd.status IN ('pending', 'assigned', 'planned')
          ORDER BY apd.fecha_programada
          LIMIT v_move_count
        ) sub;
        
        -- Apply changes if requested
        IF p_apply_changes AND v_shipments_to_move IS NOT NULL THEN
          FOREACH v_shipment_id IN ARRAY v_shipments_to_move
          LOOP
            UPDATE allocation_plan_details
            SET 
              origin_node_id = CASE 
                WHEN origin_node_id = v_from_cell.node_id THEN v_to_cell.node_id 
                ELSE origin_node_id 
              END,
              destination_node_id = CASE 
                WHEN destination_node_id = v_from_cell.node_id THEN v_to_cell.node_id 
                ELSE destination_node_id 
              END,
              fecha_programada = v_to_cell.week_start + (fecha_programada - v_from_cell.week_start),
              reassignment_reason = 'rebalancing',
              reassigned_at = NOW(),
              updated_at = NOW()
            WHERE id = v_shipment_id;
          END LOOP;
        END IF;
        
        -- Record movement
        v_movement := jsonb_build_object(
          'from_node_id', v_from_cell.node_id,
          'from_node_code', v_from_cell.node_code,
          'from_week', v_from_cell.week_num,
          'to_node_id', v_to_cell.node_id,
          'to_node_code', v_to_cell.node_code,
          'to_week', v_to_cell.week_num,
          'shipment_ids', v_shipments_to_move,
          'count', COALESCE(array_length(v_shipments_to_move, 1), 0)
        );
        
        v_movements := array_append(v_movements, v_movement);
        v_movements_count := v_movements_count + COALESCE(array_length(v_shipments_to_move, 1), 0);
      END IF;
    END IF;
  END LOOP;
  
  -- Calculate new standard deviation
  WITH 
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
      (week_start + interval '6 days')::date AS week_end
    FROM week_series
    WHERE week_start <= p_end_date
      AND (week_start + interval '6 days')::date >= p_start_date
  ),
  cell_loads AS (
    SELECT 
      COUNT(DISTINCT apd.id) AS load_count
    FROM nodes n
    CROSS JOIN weeks_numbered w
    LEFT JOIN allocation_plan_details apd ON 
      (apd.origin_node_id = n.id OR apd.destination_node_id = n.id) AND
      apd.fecha_programada >= w.week_start AND
      apd.fecha_programada <= w.week_end
    WHERE n.city_id = p_city_id
    GROUP BY n.id, w.week_start
  )
  SELECT STDDEV(load_count) INTO v_stddev_after
  FROM cell_loads;
  
  v_stddev_after := COALESCE(v_stddev_after, 0);
  
  -- Calculate improvement
  IF v_stddev_before > 0 THEN
    v_improvement := ((v_stddev_before - v_stddev_after) / v_stddev_before) * 100;
  ELSE
    v_improvement := 0;
  END IF;
  
  -- Build result
  v_result := jsonb_build_object(
    'success', true,
    'movements_count', v_movements_count,
    'stddev_before', ROUND(v_stddev_before, 2),
    'stddev_after', ROUND(v_stddev_after, 2),
    'improvement_percentage', ROUND(v_improvement, 1),
    'target_avg', ROUND(v_target_avg, 2),
    'total_shipments', v_total_shipments,
    'total_cells', v_total_cells,
    'movements', array_to_json(v_movements)::jsonb,
    'message', format('Balanced %s shipments across %s cells (nodes×weeks). Target avg: %s. Std dev: %s → %s (%s%%%% improvement)',
                      v_movements_count,
                      v_total_cells,
                      ROUND(v_target_avg, 2)::text,
                      ROUND(v_stddev_before, 2)::text, 
                      ROUND(v_stddev_after, 2)::text,
                      ROUND(v_improvement, 1)::text)
  );
  
  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION rpc_balance_node_load_by_period TO authenticated;

COMMENT ON FUNCTION rpc_balance_node_load_by_period IS 
'Balances node load using aliquot matrix distribution algorithm.
Treats the entire nodes×weeks matrix as a single distribution space.
Moves shipments from overloaded cells to underloaded cells to minimize standard deviation.
Target: All cells approach the global average (total_shipments / total_cells).';
