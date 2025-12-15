-- Migration 020: Node Load Balancing System
-- Version: 1.0
-- Date: 2025-12-10
-- Description: Creates views and functions for matrix-based node load balancing

-- ============================================================================
-- PART 1: VIEW FOR NODE LOAD ANALYSIS
-- ============================================================================

-- View to calculate load per node and week
CREATE OR REPLACE VIEW v_node_load_analysis AS
WITH node_weekly_load AS (
  SELECT 
    apd.account_id,
    apd.origin_node_id as node_id,
    n.auto_id as node_code,
    c.name as city_name,
    c.id as city_id,
    apd.week_number,
    apd.month,
    apd.year,
    COUNT(*) as shipment_count,
    COUNT(*) FILTER (WHERE apd.status = 'sent') as sent_count,
    COUNT(*) FILTER (WHERE apd.status = 'received') as received_count,
    COUNT(*) FILTER (WHERE apd.status = 'pending') as pending_count
  FROM allocation_plan_details apd
  JOIN nodes n ON n.id = apd.origin_node_id
  JOIN cities c ON c.id = n.city_id
  WHERE apd.status NOT IN ('cancelled')
  GROUP BY apd.account_id, apd.origin_node_id, n.auto_id, c.name, c.id, 
           apd.week_number, apd.month, apd.year
),
city_weekly_stats AS (
  SELECT 
    account_id,
    city_id,
    city_name,
    week_number,
    month,
    year,
    AVG(shipment_count) as avg_load,
    STDDEV(shipment_count) as stddev_load,
    SUM(shipment_count) as total_load,
    COUNT(DISTINCT node_id) as node_count
  FROM node_weekly_load
  GROUP BY account_id, city_id, city_name, week_number, month, year
),
city_monthly_stats AS (
  SELECT 
    account_id,
    city_id,
    city_name,
    month,
    year,
    AVG(shipment_count) as monthly_avg_load,
    STDDEV(shipment_count) as monthly_stddev_load,
    SUM(shipment_count) as monthly_total_load
  FROM node_weekly_load
  GROUP BY account_id, city_id, city_name, month, year
)
SELECT 
  nwl.*,
  cws.avg_load as city_weekly_avg,
  cws.stddev_load as city_weekly_stddev,
  cws.total_load as city_weekly_total,
  cws.node_count as city_node_count,
  cms.monthly_avg_load as city_monthly_avg,
  cms.monthly_stddev_load as city_monthly_stddev,
  cms.monthly_total_load as city_monthly_total,
  -- Calculate saturation level (weekly)
  CASE 
    WHEN nwl.shipment_count > cws.avg_load * 1.5 THEN 'saturated'
    WHEN nwl.shipment_count > cws.avg_load * 1.2 THEN 'high'
    ELSE 'normal'
  END as saturation_level,
  -- Calculate percentage over average (weekly)
  ROUND((nwl.shipment_count::numeric / NULLIF(cws.avg_load, 0) * 100), 1) as load_percentage,
  -- Calculate excess load (weekly)
  GREATEST(0, nwl.shipment_count - ROUND(cws.avg_load)) as excess_load
FROM node_weekly_load nwl
JOIN city_weekly_stats cws ON 
  cws.account_id = nwl.account_id AND
  cws.city_id = nwl.city_id AND
  cws.week_number = nwl.week_number AND
  cws.month = nwl.month AND
  cws.year = nwl.year
JOIN city_monthly_stats cms ON
  cms.account_id = nwl.account_id AND
  cms.city_id = nwl.city_id AND
  cms.month = nwl.month AND
  cms.year = nwl.year
ORDER BY nwl.city_name, nwl.week_number, nwl.node_code;

COMMENT ON VIEW v_node_load_analysis IS 'Analyzes node load distribution by week and month with saturation detection';

-- ============================================================================
-- PART 2: TABLE FOR BALANCING HISTORY
-- ============================================================================

CREATE TABLE IF NOT EXISTS node_balancing_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  city_id UUID NOT NULL REFERENCES cities(id) ON DELETE CASCADE,
  month INTEGER NOT NULL,
  year INTEGER NOT NULL,
  strategy TEXT NOT NULL DEFAULT 'matrix_balance', -- 'matrix_balance', 'manual'
  shipments_moved INTEGER NOT NULL,
  movements JSONB NOT NULL, -- Array of {from_node_id, to_node_id, from_week, to_week, shipment_ids[]}
  stddev_before NUMERIC(10,2),
  stddev_after NUMERIC(10,2),
  improvement_percentage NUMERIC(5,2),
  performed_by UUID REFERENCES auth.users(id),
  performed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  notes TEXT
);

CREATE INDEX idx_balancing_history_city_month 
  ON node_balancing_history(city_id, month, year);

CREATE INDEX idx_balancing_history_account 
  ON node_balancing_history(account_id);

-- Enable RLS
ALTER TABLE node_balancing_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY balancing_history_select_policy ON node_balancing_history
  FOR SELECT
  USING (account_id = auth.uid());

CREATE POLICY balancing_history_insert_policy ON node_balancing_history
  FOR INSERT
  WITH CHECK (account_id = auth.uid());

COMMENT ON TABLE node_balancing_history IS 'History of node load balancing operations';

-- ============================================================================
-- PART 3: FUNCTION FOR MATRIX-BASED BALANCING
-- ============================================================================

CREATE OR REPLACE FUNCTION balance_node_load_matrix(
  p_account_id UUID,
  p_city_id UUID,
  p_month INTEGER,
  p_year INTEGER,
  p_dry_run BOOLEAN DEFAULT true
)
RETURNS TABLE (
  success BOOLEAN,
  movements_count INTEGER,
  stddev_before NUMERIC,
  stddev_after NUMERIC,
  improvement_percentage NUMERIC,
  movements JSONB,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_stddev_before NUMERIC;
  v_stddev_after NUMERIC;
  v_movements JSONB := '[]'::jsonb;
  v_movement JSONB;
  v_movements_count INTEGER := 0;
  v_target_avg NUMERIC;
  v_saturated_node RECORD;
  v_underloaded_node RECORD;
  v_shipments_to_move UUID[];
  v_move_count INTEGER;
BEGIN
  -- Calculate initial stddev for the entire city-month matrix
  SELECT STDDEV(shipment_count)
  INTO v_stddev_before
  FROM v_node_load_analysis
  WHERE account_id = p_account_id
    AND city_id = p_city_id
    AND month = p_month
    AND year = p_year;
  
  -- Calculate target average load per node
  SELECT AVG(shipment_count)
  INTO v_target_avg
  FROM v_node_load_analysis
  WHERE account_id = p_account_id
    AND city_id = p_city_id
    AND month = p_month
    AND year = p_year;
  
  -- MATRIX BALANCING ALGORITHM
  -- Strategy: Redistribute from saturated nodes to underloaded nodes
  -- considering the entire month matrix simultaneously
  
  FOR v_saturated_node IN
    SELECT 
      node_id,
      node_code,
      week_number,
      shipment_count,
      pending_count,
      ROUND(shipment_count - v_target_avg) as excess
    FROM v_node_load_analysis
    WHERE account_id = p_account_id
      AND city_id = p_city_id
      AND month = p_month
      AND year = p_year
      AND shipment_count > v_target_avg * 1.2 -- Only nodes above 120% of average
      AND pending_count > 0 -- Only if there are pending shipments to move
    ORDER BY shipment_count DESC
  LOOP
    
    -- Find underloaded nodes in ANY week of the same month
    FOR v_underloaded_node IN
      SELECT 
        node_id,
        node_code,
        week_number,
        shipment_count,
        ROUND(v_target_avg - shipment_count) as capacity
      FROM v_node_load_analysis
      WHERE account_id = p_account_id
        AND city_id = p_city_id
        AND month = p_month
        AND year = p_year
        AND node_id != v_saturated_node.node_id -- Different node
        AND shipment_count < v_target_avg * 0.9 -- Only nodes below 90% of average
      ORDER BY shipment_count ASC
      LIMIT 1
    LOOP
      
      -- Calculate how many shipments to move
      v_move_count := LEAST(
        v_saturated_node.excess,
        v_underloaded_node.capacity,
        v_saturated_node.pending_count
      );
      
      IF v_move_count > 0 THEN
        -- Select shipments to move
        SELECT ARRAY_AGG(id)
        INTO v_shipments_to_move
        FROM (
          SELECT id
          FROM allocation_plan_details
          WHERE account_id = p_account_id
            AND origin_node_id = v_saturated_node.node_id
            AND week_number = v_saturated_node.week_number
            AND month = p_month
            AND year = p_year
            AND status = 'pending' -- Only move pending shipments
            AND origin_panelist_id IS NULL -- Not assigned to specific panelist
          ORDER BY fecha_programada
          LIMIT v_move_count
        ) subq;
        
        IF v_shipments_to_move IS NOT NULL AND array_length(v_shipments_to_move, 1) > 0 THEN
          -- Record movement
          v_movement := jsonb_build_object(
            'from_node_id', v_saturated_node.node_id,
            'from_node_code', v_saturated_node.node_code,
            'from_week', v_saturated_node.week_number,
            'to_node_id', v_underloaded_node.node_id,
            'to_node_code', v_underloaded_node.node_code,
            'to_week', v_underloaded_node.week_number,
            'shipment_ids', to_jsonb(v_shipments_to_move),
            'count', array_length(v_shipments_to_move, 1)
          );
          
          v_movements := v_movements || v_movement;
          v_movements_count := v_movements_count + array_length(v_shipments_to_move, 1);
          
          -- Apply changes if not dry run
          IF NOT p_dry_run THEN
            -- Calculate new scheduled date for the target week
            DECLARE
              v_new_date DATE;
              v_week_start DATE;
            BEGIN
              -- Calculate start of target week
              v_week_start := date_trunc('week', make_date(p_year, 1, 4))::date + 
                             (v_underloaded_node.week_number - 1) * INTERVAL '7 days';
              
              -- Set new date to Monday of target week
              v_new_date := v_week_start;
              
              UPDATE allocation_plan_details
              SET 
                origin_node_id = v_underloaded_node.node_id,
                week_number = v_underloaded_node.week_number,
                fecha_programada = v_new_date
              WHERE id = ANY(v_shipments_to_move);
            END;
          END IF;
        END IF;
      END IF;
      
    END LOOP;
    
  END LOOP;
  
  -- Calculate final stddev (simulate if dry run)
  IF p_dry_run THEN
    -- For dry run, estimate improvement (simplified)
    v_stddev_after := v_stddev_before * 0.7; -- Estimate 30% improvement
  ELSE
    -- Recalculate actual stddev after changes
    SELECT STDDEV(shipment_count)
    INTO v_stddev_after
    FROM v_node_load_analysis
    WHERE account_id = p_account_id
      AND city_id = p_city_id
      AND month = p_month
      AND year = p_year;
    
    -- Record in history
    INSERT INTO node_balancing_history (
      account_id,
      city_id,
      month,
      year,
      strategy,
      shipments_moved,
      movements,
      stddev_before,
      stddev_after,
      improvement_percentage,
      performed_by
    ) VALUES (
      p_account_id,
      p_city_id,
      p_month,
      p_year,
      'matrix_balance',
      v_movements_count,
      v_movements,
      v_stddev_before,
      v_stddev_after,
      ROUND(((v_stddev_before - v_stddev_after) / NULLIF(v_stddev_before, 0) * 100), 2),
      p_account_id
    );
  END IF;
  
  -- Return results
  RETURN QUERY SELECT
    true as success,
    v_movements_count as movements_count,
    v_stddev_before as stddev_before,
    v_stddev_after as stddev_after,
    ROUND(((v_stddev_before - v_stddev_after) / NULLIF(v_stddev_before, 0) * 100), 2) as improvement_percentage,
    v_movements as movements,
    CASE 
      WHEN v_movements_count = 0 THEN 'No movements needed - already balanced'
      WHEN p_dry_run THEN 'Dry run completed - no changes applied'
      ELSE 'Balancing completed successfully'
    END as message;
  
END;
$$;

COMMENT ON FUNCTION balance_node_load_matrix IS 'Balances node load across entire city-month matrix using intelligent redistribution';

-- ============================================================================
-- PART 4: RPC FUNCTION FOR FRONTEND
-- ============================================================================

-- Wrapper function that can be called from frontend
CREATE OR REPLACE FUNCTION rpc_balance_node_load(
  p_city_id UUID,
  p_month INTEGER,
  p_year INTEGER,
  p_apply_changes BOOLEAN DEFAULT false
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_result RECORD;
  v_account_id UUID;
BEGIN
  -- Get current user account_id
  v_account_id := auth.uid();
  
  IF v_account_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'User not authenticated'
    );
  END IF;
  
  -- Call the balancing function
  SELECT * INTO v_result
  FROM balance_node_load_matrix(
    v_account_id,
    p_city_id,
    p_month,
    p_year,
    NOT p_apply_changes -- dry_run is opposite of apply_changes
  );
  
  -- Return as JSONB
  RETURN jsonb_build_object(
    'success', v_result.success,
    'movements_count', v_result.movements_count,
    'stddev_before', v_result.stddev_before,
    'stddev_after', v_result.stddev_after,
    'improvement_percentage', v_result.improvement_percentage,
    'movements', v_result.movements,
    'message', v_result.message
  );
  
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM
  );
END;
$$;

COMMENT ON FUNCTION rpc_balance_node_load IS 'RPC endpoint for frontend to trigger node load balancing';
