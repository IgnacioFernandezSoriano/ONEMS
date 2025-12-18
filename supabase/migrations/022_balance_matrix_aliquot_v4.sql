-- Drop existing function
DROP FUNCTION IF EXISTS rpc_balance_node_load_by_period(uuid, date, date, boolean);

-- V4: Added NULLIF to prevent division by zero errors
-- Create improved aliquot balancing function with round-robin distribution
CREATE OR REPLACE FUNCTION rpc_balance_node_load_by_period(
  p_city_id UUID,
  p_start_date DATE,
  p_end_date DATE,
  p_apply_changes BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
AS $$
DECLARE
  v_total_shipments INTEGER;
  v_total_cells INTEGER;
  v_target_avg NUMERIC;
  v_stddev_before NUMERIC;
  v_stddev_after NUMERIC;
  v_movements JSONB := '[]'::JSONB;
  v_movements_count INTEGER := 0;
  v_improvement NUMERIC;
  v_iteration INTEGER := 0;
  v_max_iterations INTEGER := 50;
  v_shipment_id UUID;
  v_moved_count INTEGER := 0;
  
  -- Cell tracking
  v_from_cell RECORD;
  v_to_cell RECORD;
  v_distribute_count INTEGER;
  v_shipments_to_move UUID[];
  v_matrix_before JSONB;
  v_matrix_after JSONB;
  v_reference_load INTEGER := 63; -- Default reference samples per node
  v_deviation_percent NUMERIC := 20; -- Default 20% deviation tolerance
  v_max_acceptable_load NUMERIC;
  v_avg_load_per_node NUMERIC;
  v_nodes_count INTEGER;
  v_nodes_needed INTEGER := 0;
BEGIN
  -- Calculate total shipments and target average
  WITH cell_matrix AS (
    SELECT 
      n.id AS node_id,
      n.auto_id AS node_code,
      w.week_num,
      ws.week_start,
      w.week_end,
      COUNT(DISTINCT apd.id) AS load_count
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
  )
  SELECT 
    SUM(load_count),
    COUNT(*),
    COALESCE(STDDEV(load_count), 0),
    jsonb_agg(jsonb_build_object(
      'node_code', node_code,
      'week_num', week_num,
      'load_count', load_count
    ) ORDER BY node_code, week_num)
  INTO v_total_shipments, v_total_cells, v_stddev_before, v_matrix_before
  FROM cell_matrix;
  
  IF v_total_shipments = 0 OR v_total_cells = 0 THEN
    RETURN jsonb_build_object(
      'success', true,
      'message', 'No shipments found in the specified period',
      'movements_count', 0,
      'stddev_before', 0,
      'stddev_after', 0,
      'improvement_percentage', 0,
      'movements', '[]'::jsonb
    );
  END IF;
  
  -- Calculate target average per cell
  v_target_avg := v_total_shipments::NUMERIC / v_total_cells::NUMERIC;
  
  -- Create temporary table for underloaded cells
  CREATE TEMP TABLE IF NOT EXISTS temp_underloaded_cells (
    node_id UUID,
    node_code TEXT,
    week_num INTEGER,
    week_start DATE,
    week_end DATE,
    load_count INTEGER,
    deficit NUMERIC,
    processed BOOLEAN DEFAULT FALSE
  ) ON COMMIT DROP;
  
  -- Balancing loop: round-robin distribution
  WHILE v_iteration < v_max_iterations LOOP
    v_iteration := v_iteration + 1;
    
    -- Find the most overloaded cell
    SELECT 
      n.id AS node_id,
      n.auto_id AS node_code,
      w.week_num,
      ws.week_start,
      w.week_end,
      COUNT(DISTINCT apd.id) AS load_count,
      COUNT(DISTINCT apd.id) - v_target_avg AS excess
    INTO v_from_cell
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
    HAVING COUNT(DISTINCT apd.id) > v_target_avg + 1  -- More than 1 above target
    ORDER BY (COUNT(DISTINCT apd.id) - v_target_avg) DESC
    LIMIT 1;
    
    -- If no overloaded cell found, we're done
    EXIT WHEN v_from_cell.node_id IS NULL OR v_from_cell.excess <= 1;
    
    -- Populate underloaded cells table
    TRUNCATE temp_underloaded_cells;
    INSERT INTO temp_underloaded_cells (node_id, node_code, week_num, week_start, week_end, load_count, deficit)
    SELECT 
      n.id,
      n.auto_id,
      w.week_num,
      ws.week_start,
      w.week_end,
      COUNT(DISTINCT apd.id),
      v_target_avg - COUNT(DISTINCT apd.id)
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
      AND NOT (n.id = v_from_cell.node_id AND w.week_num = v_from_cell.week_num)
    GROUP BY n.id, n.auto_id, w.week_num, ws.week_start, w.week_end
    HAVING COUNT(DISTINCT apd.id) < v_target_avg - 1  -- More than 1 below target
    ORDER BY RANDOM();  -- Random order for round-robin effect
    
    -- If no underloaded cells, we're done
    EXIT WHEN NOT EXISTS (SELECT 1 FROM temp_underloaded_cells);
    
    -- Distribute shipments round-robin to underloaded cells
    FOR v_to_cell IN 
      SELECT * FROM temp_underloaded_cells 
      WHERE NOT processed 
      ORDER BY week_num, node_code
    LOOP
      -- Calculate how many to move to this cell
      -- Use NULLIF to prevent division by zero
      v_distribute_count := LEAST(
        CEIL(v_from_cell.excess / NULLIF((SELECT COUNT(*) FROM temp_underloaded_cells WHERE NOT processed), 0))::INTEGER,
        FLOOR(v_to_cell.deficit)::INTEGER,
        FLOOR(v_from_cell.load_count - v_target_avg)::INTEGER
      );
      
      EXIT WHEN v_distribute_count <= 0;
      
      -- Get shipments to move
      SELECT ARRAY_AGG(id) INTO v_shipments_to_move
      FROM (
        SELECT apd.id
        FROM allocation_plan_details apd
        WHERE (apd.origin_node_id = v_from_cell.node_id OR apd.destination_node_id = v_from_cell.node_id)
          AND apd.fecha_programada >= v_from_cell.week_start
          AND apd.fecha_programada <= v_from_cell.week_end
        ORDER BY apd.fecha_programada
        LIMIT v_distribute_count
      ) sub;
      
      IF v_shipments_to_move IS NOT NULL AND array_length(v_shipments_to_move, 1) > 0 THEN
        -- Apply changes if requested
        IF p_apply_changes THEN
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
            
            v_moved_count := v_moved_count + 1;
          END LOOP;
        END IF;
        
        -- Record movement
        v_movements := v_movements || jsonb_build_object(
          'from_node_id', v_from_cell.node_id,
          'from_node_code', v_from_cell.node_code,
          'from_week', v_from_cell.week_num,
          'to_node_id', v_to_cell.node_id,
          'to_node_code', v_to_cell.node_code,
          'to_week', v_to_cell.week_num,
          'count', array_length(v_shipments_to_move, 1)
        );
        
        v_movements_count := v_movements_count + array_length(v_shipments_to_move, 1);
        
        -- Update from_cell load
        v_from_cell.load_count := v_from_cell.load_count - array_length(v_shipments_to_move, 1);
        v_from_cell.excess := v_from_cell.load_count - v_target_avg;
        
        -- Mark this cell as processed
        UPDATE temp_underloaded_cells SET processed = TRUE WHERE node_id = v_to_cell.node_id AND week_num = v_to_cell.week_num;
      END IF;
      
      -- If from_cell is no longer overloaded, exit
      EXIT WHEN v_from_cell.excess <= 1;
    END LOOP;
  END LOOP;
  
  -- Calculate final stddev
  WITH cell_matrix AS (
    SELECT 
      n.id AS node_id,
      COUNT(DISTINCT apd.id) AS load_count
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
        (ws.week_start + interval '6 days')::date AS week_end
    ) w
    LEFT JOIN allocation_plan_details apd ON 
      (apd.origin_node_id = n.id OR apd.destination_node_id = n.id) AND
      apd.fecha_programada >= ws.week_start AND
      apd.fecha_programada <= w.week_end
    WHERE n.city_id = p_city_id
      AND ws.week_start <= p_end_date
      AND w.week_end >= p_start_date
    GROUP BY n.id, ws.week_start
  )
  SELECT COALESCE(STDDEV(load_count), 0)
  INTO v_stddev_after
  FROM cell_matrix;
  
  -- Calculate improvement
  IF v_stddev_before > 0 THEN
    v_improvement := ((v_stddev_before - v_stddev_after) / v_stddev_before * 100);
  ELSE
    v_improvement := 0;
  END IF;
  
  -- Clean up
  DROP TABLE IF EXISTS temp_underloaded_cells;
  
  -- Build matrix_after for visualization
  WITH matrix_after AS (
    SELECT 
      n.auto_id AS node_code,
      w.week_num,
      COUNT(DISTINCT apd.id) AS load_count
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
    GROUP BY n.auto_id, w.week_num
  )
  SELECT jsonb_agg(jsonb_build_object(
    'node_code', node_code,
    'week_num', week_num,
    'load_count', load_count
  ) ORDER BY node_code, week_num)
  INTO v_matrix_after
  FROM matrix_after;
  
  -- Calculate nodes needed if load exceeds acceptable threshold
  -- Get number of nodes in the city
  SELECT COUNT(*) INTO v_nodes_count
  FROM nodes
  WHERE city_id = p_city_id;
  
  -- Calculate average load per node after balancing
  IF v_nodes_count > 0 THEN
    v_avg_load_per_node := v_total_shipments::NUMERIC / v_nodes_count;
    
    -- Calculate maximum acceptable load (reference + deviation tolerance)
    v_max_acceptable_load := v_reference_load * (1 + v_deviation_percent / 100);
    
    -- If average load exceeds acceptable threshold, calculate nodes needed
    IF v_avg_load_per_node > v_max_acceptable_load THEN
      -- Calculate how many nodes we would need to bring average below threshold
      v_nodes_needed := CEIL(v_total_shipments::NUMERIC / v_max_acceptable_load) - v_nodes_count;
    END IF;
  END IF;
  
  -- Return result
  RETURN jsonb_build_object(
    'success', true,
    'message', CASE 
      WHEN v_movements_count = 0 THEN 'Load is already well balanced'
      WHEN p_apply_changes THEN format('Successfully balanced %s shipments', v_moved_count)
      ELSE format('Preview: would balance %s shipments', v_movements_count)
    END,
    'movements_count', v_movements_count,
    'stddev_before', ROUND(v_stddev_before, 2),
    'stddev_after', ROUND(v_stddev_after, 2),
    'improvement_percentage', ROUND(v_improvement, 2),
    'target_avg', ROUND(v_target_avg, 2),
    'total_cells', v_total_cells,
    'movements', v_movements,
    'matrix_before', v_matrix_before,
    'matrix_after', v_matrix_after,
    'nodes_count', v_nodes_count,
    'avg_load_per_node', ROUND(v_avg_load_per_node, 2),
    'max_acceptable_load', ROUND(v_max_acceptable_load, 2),
    'nodes_needed', v_nodes_needed,
    'reference_load', v_reference_load,
    'deviation_percent', v_deviation_percent
  );
END;
$$;
