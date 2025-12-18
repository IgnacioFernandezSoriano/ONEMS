-- Drop existing function
DROP FUNCTION IF EXISTS rpc_balance_node_load_by_period(uuid, date, date, boolean);

-- Create improved aliquot balancing function
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
  v_max_iterations INTEGER := 100;
  v_shipment_id UUID;
  v_moved_count INTEGER;
  
  -- Cell tracking
  v_cell RECORD;
  v_from_cell RECORD;
  v_to_cells RECORD[];
  v_to_cell_idx INTEGER;
  v_distribute_count INTEGER;
  v_remaining INTEGER;
BEGIN
  -- Calculate total shipments and cells
  SELECT 
    COUNT(DISTINCT apd.id),
    COUNT(DISTINCT n.id) * COUNT(DISTINCT DATE_TRUNC('week', apd.fecha_programada))
  INTO v_total_shipments, v_total_cells
  FROM allocation_plan_details apd
  JOIN nodes n ON (n.id = apd.origin_node_id OR n.id = apd.destination_node_id)
  WHERE n.city_id = p_city_id
    AND apd.fecha_programada >= p_start_date
    AND apd.fecha_programada <= p_end_date;
  
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
  
  -- Calculate initial stddev
  WITH cell_loads AS (
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
  SELECT COALESCE(STDDEV(load_count), 0)
  INTO v_stddev_before
  FROM cell_loads;
  
  -- Balancing loop: distribute from overloaded cells to ALL underloaded cells
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
    HAVING COUNT(DISTINCT apd.id) > v_target_avg * 1.1  -- 10% above target
    ORDER BY (COUNT(DISTINCT apd.id) - v_target_avg) DESC
    LIMIT 1;
    
    -- If no overloaded cell found, we're done
    EXIT WHEN v_from_cell.node_id IS NULL;
    
    -- Find ALL underloaded cells and calculate how much each needs
    v_to_cells := ARRAY(
      SELECT ROW(
        n.id,
        n.auto_id,
        w.week_num,
        ws.week_start,
        w.week_end,
        COUNT(DISTINCT apd.id),
        v_target_avg - COUNT(DISTINCT apd.id)
      )::RECORD
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
      HAVING COUNT(DISTINCT apd.id) < v_target_avg * 0.9  -- 10% below target
      ORDER BY (v_target_avg - COUNT(DISTINCT apd.id)) DESC
    );
    
    -- If no underloaded cells found, we're done
    EXIT WHEN array_length(v_to_cells, 1) IS NULL;
    
    -- Calculate how many shipments to move from the overloaded cell
    v_remaining := LEAST(
      FLOOR(v_from_cell.excess)::INTEGER,
      FLOOR(v_from_cell.load_count - v_target_avg)::INTEGER
    );
    
    EXIT WHEN v_remaining <= 0;
    
    -- Distribute shipments proportionally to ALL underloaded cells
    v_to_cell_idx := 1;
    WHILE v_to_cell_idx <= array_length(v_to_cells, 1) AND v_remaining > 0 LOOP
      v_cell := v_to_cells[v_to_cell_idx];
      
      -- Calculate how many to move to this cell (proportional to its deficit)
      v_distribute_count := LEAST(
        v_remaining,
        CEIL((v_cell.f7)::NUMERIC / array_length(v_to_cells, 1))::INTEGER,
        FLOOR(v_target_avg - (v_cell.f6)::NUMERIC)::INTEGER
      );
      
      IF v_distribute_count > 0 THEN
        -- Get shipments to move
        IF p_apply_changes THEN
          FOR v_shipment_id IN (
            SELECT apd.id
            FROM allocation_plan_details apd
            WHERE (apd.origin_node_id = v_from_cell.node_id OR apd.destination_node_id = v_from_cell.node_id)
              AND apd.fecha_programada >= v_from_cell.week_start
              AND apd.fecha_programada <= v_from_cell.week_end
            ORDER BY apd.fecha_programada
            LIMIT v_distribute_count
          )
          LOOP
            -- Update the shipment
            UPDATE allocation_plan_details
            SET 
              origin_node_id = CASE 
                WHEN origin_node_id = v_from_cell.node_id THEN (v_cell.f1)::UUID
                ELSE origin_node_id 
              END,
              destination_node_id = CASE 
                WHEN destination_node_id = v_from_cell.node_id THEN (v_cell.f1)::UUID
                ELSE destination_node_id 
              END,
              fecha_programada = (v_cell.f4)::DATE + (fecha_programada - v_from_cell.week_start),
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
          'to_node_id', v_cell.f1,
          'to_node_code', v_cell.f2,
          'to_week', v_cell.f3,
          'count', v_distribute_count
        );
        
        v_movements_count := v_movements_count + v_distribute_count;
        v_remaining := v_remaining - v_distribute_count;
      END IF;
      
      v_to_cell_idx := v_to_cell_idx + 1;
    END LOOP;
  END LOOP;
  
  -- Calculate final stddev
  WITH cell_loads AS (
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
  SELECT COALESCE(STDDEV(load_count), 0)
  INTO v_stddev_after
  FROM cell_loads;
  
  -- Calculate improvement
  IF v_stddev_before > 0 THEN
    v_improvement := ((v_stddev_before - v_stddev_after) / v_stddev_before * 100);
  ELSE
    v_improvement := 0;
  END IF;
  
  -- Return result
  RETURN jsonb_build_object(
    'success', true,
    'message', CASE 
      WHEN v_movements_count = 0 THEN 'Load is already well balanced'
      WHEN p_apply_changes THEN format('Successfully balanced %s shipments across %s movements', v_moved_count, v_movements_count)
      ELSE format('Preview: would balance %s shipments across %s movements', v_movements_count, v_movements_count)
    END,
    'movements_count', v_movements_count,
    'stddev_before', ROUND(v_stddev_before, 2),
    'stddev_after', ROUND(v_stddev_after, 2),
    'improvement_percentage', ROUND(v_improvement, 2),
    'target_avg', ROUND(v_target_avg, 2),
    'total_cells', v_total_cells,
    'movements', v_movements
  );
END;
$$;
