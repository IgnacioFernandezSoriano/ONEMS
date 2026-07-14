-- =====================================================
-- Migration 012: Panelist Unavailability System
-- =====================================================
-- This migration implements:
-- 1. panelist_unavailability table
-- 2. Additional fields in allocation_plan_details for reassignment history
-- 3. View for real-time availability calculation
-- 4. Functions for automatic reassignment logic
-- 5. Cron job function for daily status updates
-- =====================================================

-- =====================================================
-- 1. Add fields to allocation_plan_details
-- =====================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'allocation_plan_details' AND column_name = 'original_origin_node_id') THEN
    ALTER TABLE allocation_plan_details ADD COLUMN original_origin_node_id UUID REFERENCES nodes(id);
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'allocation_plan_details' AND column_name = 'original_destination_node_id') THEN
    ALTER TABLE allocation_plan_details ADD COLUMN original_destination_node_id UUID REFERENCES nodes(id);
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'allocation_plan_details' AND column_name = 'reassignment_reason') THEN
    ALTER TABLE allocation_plan_details ADD COLUMN reassignment_reason TEXT CHECK (reassignment_reason IN ('panelist_unavailable', 'manual', 'rebalancing'));
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'allocation_plan_details' AND column_name = 'reassigned_at') THEN
    ALTER TABLE allocation_plan_details ADD COLUMN reassigned_at TIMESTAMPTZ;
  END IF;
  
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'allocation_plan_details' AND column_name = 'reassigned_by') THEN
    ALTER TABLE allocation_plan_details ADD COLUMN reassigned_by UUID REFERENCES profiles(id);
  END IF;
END $$;

-- =====================================================
-- 2. Create panelist_unavailability table (if not exists)
-- =====================================================

CREATE TABLE IF NOT EXISTS panelist_unavailability (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  panelist_id UUID NOT NULL REFERENCES panelists(id) ON DELETE CASCADE,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  reason TEXT NOT NULL CHECK (reason IN ('vacation', 'sick', 'training', 'personal', 'other')),
  notes TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'cancelled')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID REFERENCES profiles(id),
  updated_by UUID REFERENCES profiles(id),
  CONSTRAINT valid_date_range CHECK (end_date >= start_date)
);

-- Indexes for panelist_unavailability
CREATE INDEX IF NOT EXISTS idx_panelist_unavailability_panelist_id ON panelist_unavailability(panelist_id);
CREATE INDEX IF NOT EXISTS idx_panelist_unavailability_dates ON panelist_unavailability(start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_panelist_unavailability_account_id ON panelist_unavailability(account_id);
CREATE INDEX IF NOT EXISTS idx_panelist_unavailability_status ON panelist_unavailability(status);

-- RLS for panelist_unavailability
ALTER TABLE panelist_unavailability ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS panelist_unavailability_select_policy ON panelist_unavailability;
CREATE POLICY panelist_unavailability_select_policy ON panelist_unavailability
  FOR SELECT USING (account_id = current_user_account_id());

DROP POLICY IF EXISTS panelist_unavailability_insert_policy ON panelist_unavailability;
CREATE POLICY panelist_unavailability_insert_policy ON panelist_unavailability
  FOR INSERT WITH CHECK (account_id = current_user_account_id());

DROP POLICY IF EXISTS panelist_unavailability_update_policy ON panelist_unavailability;
CREATE POLICY panelist_unavailability_update_policy ON panelist_unavailability
  FOR UPDATE USING (account_id = current_user_account_id());

DROP POLICY IF EXISTS panelist_unavailability_delete_policy ON panelist_unavailability;
CREATE POLICY panelist_unavailability_delete_policy ON panelist_unavailability
  FOR DELETE USING (account_id = current_user_account_id());

-- Trigger for updated_at
DROP TRIGGER IF EXISTS update_panelist_unavailability_updated_at ON panelist_unavailability;
CREATE TRIGGER update_panelist_unavailability_updated_at
  BEFORE UPDATE ON panelist_unavailability
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- 3. Create view for availability calculation
-- =====================================================

DROP VIEW IF EXISTS v_allocation_details_with_availability CASCADE;

CREATE OR REPLACE VIEW v_allocation_details_with_availability AS
SELECT 
  apd.*,
  
  -- Origin node and panelist info
  on_node.city_id as origin_city_id,
  on_city.name as origin_city_name,
  op.status as origin_panelist_status,
  
  -- Origin availability status
  CASE 
    WHEN op.id IS NULL THEN 'unassigned'
    WHEN EXISTS (
      SELECT 1 FROM panelist_unavailability pu 
      WHERE pu.panelist_id = op.id 
      AND pu.status = 'active'
      AND apd.fecha_programada BETWEEN pu.start_date AND pu.end_date
    ) THEN 'unavailable'
    WHEN op.status = 'active' THEN 'available'
    ELSE 'inactive'
  END as origin_availability_status,
  
  -- Origin unavailability reason
  (SELECT reason FROM panelist_unavailability pu 
   WHERE pu.panelist_id = op.id 
   AND pu.status = 'active'
   AND apd.fecha_programada BETWEEN pu.start_date AND pu.end_date
   LIMIT 1
  ) as origin_unavailability_reason,
  
  -- Destination node and panelist info
  dn_node.city_id as destination_city_id,
  dn_city.name as destination_city_name,
  dp.status as destination_panelist_status,
  
  -- Destination availability status
  CASE 
    WHEN dp.id IS NULL THEN 'unassigned'
    WHEN EXISTS (
      SELECT 1 FROM panelist_unavailability pu 
      WHERE pu.panelist_id = dp.id 
      AND pu.status = 'active'
      AND apd.fecha_programada BETWEEN pu.start_date AND pu.end_date
    ) THEN 'unavailable'
    WHEN dp.status = 'active' THEN 'available'
    ELSE 'inactive'
  END as destination_availability_status,
  
  -- Destination unavailability reason
  (SELECT reason FROM panelist_unavailability pu 
   WHERE pu.panelist_id = dp.id 
   AND pu.status = 'active'
   AND apd.fecha_programada BETWEEN pu.start_date AND pu.end_date
   LIMIT 1
  ) as destination_unavailability_reason

FROM allocation_plan_details apd
LEFT JOIN nodes on_node ON apd.origin_node_id = on_node.id
LEFT JOIN cities on_city ON on_node.city_id = on_city.id
LEFT JOIN panelists op ON on_node.id = op.node_id AND op.status IN ('active', 'unavailable_temp')
LEFT JOIN nodes dn_node ON apd.destination_node_id = dn_node.id
LEFT JOIN cities dn_city ON dn_node.city_id = dn_city.id
LEFT JOIN panelists dp ON dn_node.id = dp.node_id AND dp.status IN ('active', 'unavailable_temp');

-- =====================================================
-- 4. Function: Check for overlapping unavailability periods
-- =====================================================

CREATE OR REPLACE FUNCTION check_unavailability_overlap()
RETURNS TRIGGER AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM panelist_unavailability
    WHERE panelist_id = NEW.panelist_id
    AND id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::UUID)
    AND status = 'active'
    AND (
      (NEW.start_date BETWEEN start_date AND end_date) OR
      (NEW.end_date BETWEEN start_date AND end_date) OR
      (start_date BETWEEN NEW.start_date AND NEW.end_date)
    )
  ) THEN
    RAISE EXCEPTION 'Overlapping unavailability period exists for this panelist';
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS check_unavailability_overlap_trigger ON panelist_unavailability;
CREATE TRIGGER check_unavailability_overlap_trigger
  BEFORE INSERT OR UPDATE ON panelist_unavailability
  FOR EACH ROW
  WHEN (NEW.status = 'active')
  EXECUTE FUNCTION check_unavailability_overlap();

-- =====================================================
-- 5. Function: Automatic reassignment on unavailability creation
-- =====================================================

CREATE OR REPLACE FUNCTION reassign_on_unavailability()
RETURNS TRIGGER AS $$
DECLARE
  v_node_id UUID;
  v_city_id UUID;
  v_affected_count INT;
  v_alternative_nodes UUID[];
  v_target_node_id UUID;
  v_samples_per_node INT;
  v_remainder INT;
  v_current_index INT := 0;
BEGIN
  -- Only process if status is active and it's a new period or being activated
  IF NEW.status != 'active' OR (TG_OP = 'UPDATE' AND OLD.status = 'active') THEN
    RETURN NEW;
  END IF;
  
  -- Get the node of the unavailable panelist
  SELECT node_id INTO v_node_id
  FROM panelists
  WHERE id = NEW.panelist_id;
  
  IF v_node_id IS NULL THEN
    RETURN NEW;
  END IF;
  
  -- Get the city of the node
  SELECT city_id INTO v_city_id
  FROM nodes
  WHERE id = v_node_id;
  
  -- Find alternative nodes in the same city with available panelists
  SELECT ARRAY_AGG(n.id)
  INTO v_alternative_nodes
  FROM nodes n
  JOIN panelists p ON n.id = p.node_id
  WHERE n.city_id = v_city_id
  AND n.id != v_node_id
  AND p.status = 'active'
  AND NOT EXISTS (
    SELECT 1 FROM panelist_unavailability pu
    WHERE pu.panelist_id = p.id
    AND pu.status = 'active'
    AND NEW.start_date <= pu.end_date 
    AND NEW.end_date >= pu.start_date
  );
  
  -- If no alternative nodes, log warning and return
  IF v_alternative_nodes IS NULL OR array_length(v_alternative_nodes, 1) = 0 THEN
    RAISE WARNING 'No alternative nodes available for reassignment in city %', v_city_id;
    RETURN NEW;
  END IF;
  
  -- Count affected shipments (origin)
  SELECT COUNT(*) INTO v_affected_count
  FROM allocation_plan_details
  WHERE origin_node_id = v_node_id
  AND fecha_programada BETWEEN NEW.start_date AND NEW.end_date
  AND status NOT IN ('completed', 'cancelled');
  
  -- Reassign origin shipments
  IF v_affected_count > 0 THEN
    v_samples_per_node := v_affected_count / array_length(v_alternative_nodes, 1);
    v_remainder := v_affected_count % array_length(v_alternative_nodes, 1);
    
    FOR v_target_node_id IN SELECT UNNEST(v_alternative_nodes) LOOP
      v_current_index := v_current_index + 1;
      
      UPDATE allocation_plan_details
      SET 
        original_origin_node_id = v_node_id,
        origin_node_id = v_target_node_id,
        reassignment_reason = 'panelist_unavailable',
        reassigned_at = NOW(),
        reassigned_by = NULL
      WHERE id IN (
        SELECT id FROM allocation_plan_details
        WHERE origin_node_id = v_node_id
        AND fecha_programada BETWEEN NEW.start_date AND NEW.end_date
        AND status NOT IN ('completed', 'cancelled')
        AND original_origin_node_id IS NULL
        LIMIT v_samples_per_node + CASE WHEN v_current_index <= v_remainder THEN 1 ELSE 0 END
      );
    END LOOP;
  END IF;
  
  -- Reassign destination shipments (same logic)
  v_current_index := 0;
  SELECT COUNT(*) INTO v_affected_count
  FROM allocation_plan_details
  WHERE destination_node_id = v_node_id
  AND fecha_programada BETWEEN NEW.start_date AND NEW.end_date
  AND status NOT IN ('completed', 'cancelled');
  
  IF v_affected_count > 0 THEN
    v_samples_per_node := v_affected_count / array_length(v_alternative_nodes, 1);
    v_remainder := v_affected_count % array_length(v_alternative_nodes, 1);
    
    FOR v_target_node_id IN SELECT UNNEST(v_alternative_nodes) LOOP
      v_current_index := v_current_index + 1;
      
      UPDATE allocation_plan_details
      SET 
        original_destination_node_id = v_node_id,
        destination_node_id = v_target_node_id,
        reassignment_reason = 'panelist_unavailable',
        reassigned_at = NOW(),
        reassigned_by = NULL
      WHERE id IN (
        SELECT id FROM allocation_plan_details
        WHERE destination_node_id = v_node_id
        AND fecha_programada BETWEEN NEW.start_date AND NEW.end_date
        AND status NOT IN ('completed', 'cancelled')
        AND original_destination_node_id IS NULL
        LIMIT v_samples_per_node + CASE WHEN v_current_index <= v_remainder THEN 1 ELSE 0 END
      );
    END LOOP;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS reassign_on_unavailability_trigger ON panelist_unavailability;
CREATE TRIGGER reassign_on_unavailability_trigger
  AFTER INSERT OR UPDATE ON panelist_unavailability
  FOR EACH ROW
  EXECUTE FUNCTION reassign_on_unavailability();

-- =====================================================
-- 6. Function: Daily cron job to update panelist status
-- =====================================================

CREATE OR REPLACE FUNCTION daily_update_panelist_availability()
RETURNS void AS $$
BEGIN
  -- Mark as unavailable_temp those with active unavailability periods
  UPDATE panelists p
  SET status = 'unavailable_temp'
  WHERE EXISTS (
    SELECT 1 FROM panelist_unavailability pu
    WHERE pu.panelist_id = p.id
    AND pu.status = 'active'
    AND CURRENT_DATE BETWEEN pu.start_date AND pu.end_date
  ) AND p.status = 'active';
  
  -- Mark as active those without active unavailability periods
  UPDATE panelists p
  SET status = 'active'
  WHERE NOT EXISTS (
    SELECT 1 FROM panelist_unavailability pu
    WHERE pu.panelist_id = p.id
    AND pu.status = 'active'
    AND CURRENT_DATE BETWEEN pu.start_date AND pu.end_date
  ) AND p.status = 'unavailable_temp';
  
  RAISE NOTICE 'Panelist availability updated successfully';
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 7. Helper view: Coverage status by city
-- =====================================================

DROP VIEW IF EXISTS v_city_coverage_status CASCADE;

CREATE OR REPLACE VIEW v_city_coverage_status AS
SELECT 
  c.id as city_id,
  c.name as city_name,
  c.code as city_code,
  COUNT(DISTINCT n.id) as total_nodes,
  COUNT(DISTINCT CASE WHEN p.status = 'active' THEN p.id END) as active_panelists,
  COUNT(DISTINCT CASE WHEN p.status = 'unavailable_temp' THEN p.id END) as unavailable_panelists,
  COUNT(DISTINCT CASE WHEN p.id IS NULL THEN n.id END) as unassigned_nodes,
  CASE 
    WHEN COUNT(DISTINCT CASE WHEN p.status = 'active' THEN p.id END) = 0 THEN 'critical'
    WHEN COUNT(DISTINCT CASE WHEN p.status = 'active' THEN p.id END) = 1 THEN 'at_risk'
    ELSE 'ok'
  END as coverage_status
FROM cities c
LEFT JOIN nodes n ON c.id = n.city_id AND n.status = 'active'
LEFT JOIN panelists p ON n.id = p.node_id
WHERE c.status = 'active'
GROUP BY c.id, c.name, c.code;

-- =====================================================
-- Migration completed
-- =====================================================

SELECT 'Migration 012: Unavailability System - Completed' as status;
