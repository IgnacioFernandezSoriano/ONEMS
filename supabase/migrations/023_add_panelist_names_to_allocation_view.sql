-- =====================================================
-- Migration 023: Add Panelist Names to Allocation Details View
-- =====================================================
-- This migration updates v_allocation_details_with_availability
-- to include origin_panelist_name and destination_panelist_name
-- =====================================================

DROP VIEW IF EXISTS v_allocation_details_with_availability CASCADE;

CREATE OR REPLACE VIEW v_allocation_details_with_availability AS
SELECT 
  apd.*,
  
  -- Origin node and panelist info
  on_node.city_id as origin_city_id,
  on_city.name as origin_city_name,
  op.id as origin_panelist_id,
  op.name as origin_panelist_name,
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
  dp.id as destination_panelist_id,
  dp.name as destination_panelist_name,
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

-- Grant permissions
GRANT SELECT ON v_allocation_details_with_availability TO authenticated;
