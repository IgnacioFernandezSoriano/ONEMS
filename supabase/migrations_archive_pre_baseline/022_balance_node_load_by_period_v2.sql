-- Function to balance node load for a date period
-- V2: Uses allocation_plan_details instead of material_shipments
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
  v_from_node RECORD;
  v_to_node RECORD;
  v_shipments_to_move UUID[];
  v_shipment_id UUID;
BEGIN
  -- Calculate current standard deviation based on allocation_plan_details
  -- Count total shipments per node (both as origin and destination)
  WITH node_loads AS (
    SELECT 
      n.id AS node_id,
      COUNT(DISTINCT apd.id) AS load_count
    FROM nodes n
    LEFT JOIN allocation_plan_details apd ON 
      (apd.origin_node_id = n.id OR apd.destination_node_id = n.id) AND
      apd.fecha_programada BETWEEN p_start_date AND p_end_date
    WHERE n.city_id = p_city_id
    GROUP BY n.id
  )
  SELECT STDDEV(load_count) INTO v_stddev_before
  FROM node_loads;
  
  v_stddev_before := COALESCE(v_stddev_before, 0);
  
  -- If stddev is already low, no need to balance
  IF v_stddev_before < 5 THEN
    RETURN jsonb_build_object(
      'success', true,
      'movements_count', 0,
      'stddev_before', v_stddev_before,
      'stddev_after', v_stddev_before,
      'improvement_percentage', 0,
      'movements', '[]'::jsonb,
      'message', 'Load is already well balanced (stddev < 5)'
    );
  END IF;
  
  -- Find overloaded and underloaded nodes
  FOR v_from_node IN
    WITH node_loads AS (
      SELECT 
        n.id AS node_id,
        n.auto_id AS node_code,
        COUNT(apd.id) AS current_load,
        AVG(COUNT(apd.id)) OVER () AS avg_load
      FROM nodes n
      LEFT JOIN allocation_plan_details apd ON 
        (apd.origin_node_id = n.id OR apd.destination_node_id = n.id) AND
        apd.fecha_programada BETWEEN p_start_date AND p_end_date AND
        apd.status IN ('pending', 'assigned', 'planned')
      WHERE n.city_id = p_city_id
      GROUP BY n.id, n.auto_id
    )
    SELECT 
      node_id,
      node_code,
      current_load,
      avg_load,
      (current_load - avg_load) AS excess
    FROM node_loads
    WHERE current_load > avg_load * 1.2  -- 20% above average
    ORDER BY excess DESC
  LOOP
    -- Find underloaded node to transfer to
    SELECT 
      n.id AS node_id,
      n.auto_id AS node_code,
      COUNT(apd.id) AS current_load
    INTO v_to_node
    FROM nodes n
    LEFT JOIN allocation_plan_details apd ON 
      (apd.origin_node_id = n.id OR apd.destination_node_id = n.id) AND
      apd.fecha_programada BETWEEN p_start_date AND p_end_date AND
      apd.status IN ('pending', 'assigned', 'planned')
    WHERE n.city_id = p_city_id
      AND n.id != v_from_node.node_id
    GROUP BY n.id, n.auto_id
    HAVING COUNT(apd.id) < v_from_node.avg_load * 0.9  -- 10% below average
    ORDER BY COUNT(apd.id) ASC
    LIMIT 1;
    
    IF v_to_node.node_id IS NOT NULL THEN
      -- Get shipments to move (move half of the excess)
      -- Move shipments where the overloaded node is the origin
      SELECT ARRAY_AGG(id) INTO v_shipments_to_move
      FROM (
        SELECT id
        FROM allocation_plan_details
        WHERE origin_node_id = v_from_node.node_id
          AND fecha_programada BETWEEN p_start_date AND p_end_date
          AND status IN ('pending', 'assigned', 'planned')
        ORDER BY fecha_programada
        LIMIT GREATEST(1, FLOOR(v_from_node.excess / 2))
      ) sub;
      
      -- Apply changes if requested
      IF p_apply_changes AND v_shipments_to_move IS NOT NULL THEN
        FOREACH v_shipment_id IN ARRAY v_shipments_to_move
        LOOP
          UPDATE allocation_plan_details
          SET 
            origin_node_id = v_to_node.node_id,
            reassignment_reason = COALESCE(reassignment_reason || '; ', '') || '[Auto-balanced ' || CURRENT_DATE || ']',
            reassigned_at = NOW(),
            updated_at = NOW()
          WHERE id = v_shipment_id;
        END LOOP;
      END IF;
      
      -- Record movement
      v_movement := jsonb_build_object(
        'from_node_id', v_from_node.node_id,
        'from_node_code', v_from_node.node_code,
        'to_node_id', v_to_node.node_id,
        'to_node_code', v_to_node.node_code,
        'shipment_ids', v_shipments_to_move,
        'count', COALESCE(array_length(v_shipments_to_move, 1), 0)
      );
      
      v_movements := array_append(v_movements, v_movement);
      v_movements_count := v_movements_count + COALESCE(array_length(v_shipments_to_move, 1), 0);
    END IF;
  END LOOP;
  
  -- Calculate new standard deviation
  -- Count total shipments per node (both as origin and destination)
  WITH node_loads AS (
    SELECT 
      n.id AS node_id,
      COUNT(DISTINCT apd.id) AS load_count
    FROM nodes n
    LEFT JOIN allocation_plan_details apd ON 
      (apd.origin_node_id = n.id OR apd.destination_node_id = n.id) AND
      apd.fecha_programada BETWEEN p_start_date AND p_end_date
    WHERE n.city_id = p_city_id
    GROUP BY n.id
  )
  SELECT STDDEV(load_count) INTO v_stddev_after
  FROM node_loads;
  
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
    'movements', array_to_json(v_movements)::jsonb,
    'message', format('Balanced %s shipments across nodes. Standard deviation reduced from %s to %s (%.1f%% improvement)',
                      v_movements_count, 
                      ROUND(v_stddev_before, 2), 
                      ROUND(v_stddev_after, 2),
                      ROUND(v_improvement, 1))
  );
  
  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION rpc_balance_node_load_by_period TO authenticated;

COMMENT ON FUNCTION rpc_balance_node_load_by_period IS 
'Balances node load distribution for a custom date period by reassigning pending allocation plan details from overloaded nodes to underloaded nodes within the same city.
V2: Uses allocation_plan_details instead of material_shipments';
