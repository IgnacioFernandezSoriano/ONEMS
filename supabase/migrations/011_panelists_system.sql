-- Migration 011: Panelists System
-- Creates panelists table, unavailability tracking, and adds fields to allocation_plan_details

-- ============================================================================
-- 1. CREATE TABLE: panelists
-- ============================================================================

CREATE TABLE IF NOT EXISTS panelists (
  -- Identification
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  panelist_code VARCHAR(50) NOT NULL,
  
  -- Personal Information
  name VARCHAR(255) NOT NULL,
  email VARCHAR(255) NOT NULL,
  mobile VARCHAR(50) NOT NULL,
  
  -- Node Assignment (1:1 relationship)
  node_id UUID NOT NULL REFERENCES nodes(id) ON DELETE RESTRICT,
  
  -- Status
  status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  
  -- Multi-tenancy
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  
  -- Audit
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID REFERENCES auth.users(id),
  updated_by UUID REFERENCES auth.users(id)
);

-- Indexes
CREATE INDEX idx_panelists_node_id ON panelists(node_id);
CREATE INDEX idx_panelists_account_id ON panelists(account_id);
CREATE INDEX idx_panelists_status ON panelists(status);
CREATE INDEX idx_panelists_email ON panelists(email);

-- Unique constraint: Code unique per account
CREATE UNIQUE INDEX idx_panelists_code_account ON panelists(panelist_code, account_id);

-- Unique constraint: One active panelist per node (1:1)
CREATE UNIQUE INDEX idx_panelists_node_unique ON panelists(node_id) WHERE status = 'active';

-- ============================================================================
-- 2. CREATE TABLE: panelist_unavailability
-- ============================================================================

CREATE TABLE IF NOT EXISTS panelist_unavailability (
  -- Identification
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Panelist
  panelist_id UUID NOT NULL REFERENCES panelists(id) ON DELETE CASCADE,
  
  -- Unavailability Period
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  
  -- Reason
  reason VARCHAR(50) NOT NULL CHECK (reason IN (
    'vacation',
    'sick_leave',
    'personal',
    'training',
    'other'
  )),
  notes TEXT,
  
  -- Status
  status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'cancelled')),
  
  -- Multi-tenancy
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  
  -- Audit
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID REFERENCES auth.users(id),
  updated_by UUID REFERENCES auth.users(id),
  
  -- Validation: end_date must be >= start_date
  CONSTRAINT check_dates CHECK (end_date >= start_date)
);

-- Indexes
CREATE INDEX idx_unavailability_panelist_id ON panelist_unavailability(panelist_id);
CREATE INDEX idx_unavailability_account_id ON panelist_unavailability(account_id);
CREATE INDEX idx_unavailability_dates ON panelist_unavailability(start_date, end_date);
CREATE INDEX idx_unavailability_status ON panelist_unavailability(status);

-- ============================================================================
-- 3. ALTER TABLE: allocation_plan_details (add new fields)
-- ============================================================================

-- Tag ID
ALTER TABLE allocation_plan_details 
ADD COLUMN IF NOT EXISTS tag_id VARCHAR(100);

-- Assigned Panelists (references)
ALTER TABLE allocation_plan_details 
ADD COLUMN IF NOT EXISTS origin_panelist_id UUID REFERENCES panelists(id) ON DELETE SET NULL;

ALTER TABLE allocation_plan_details 
ADD COLUMN IF NOT EXISTS destination_panelist_id UUID REFERENCES panelists(id) ON DELETE SET NULL;

-- Snapshot of panelist names (historical)
ALTER TABLE allocation_plan_details 
ADD COLUMN IF NOT EXISTS origin_panelist_name VARCHAR(255);

ALTER TABLE allocation_plan_details 
ADD COLUMN IF NOT EXISTS destination_panelist_name VARCHAR(255);

-- Operation timestamps
ALTER TABLE allocation_plan_details 
ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ;

ALTER TABLE allocation_plan_details 
ADD COLUMN IF NOT EXISTS sent_at TIMESTAMPTZ;

ALTER TABLE allocation_plan_details 
ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ;

-- Indexes for new fields
CREATE INDEX IF NOT EXISTS idx_allocation_details_tag_id ON allocation_plan_details(tag_id);
CREATE INDEX IF NOT EXISTS idx_allocation_details_origin_panelist ON allocation_plan_details(origin_panelist_id);
CREATE INDEX IF NOT EXISTS idx_allocation_details_dest_panelist ON allocation_plan_details(destination_panelist_id);
CREATE INDEX IF NOT EXISTS idx_allocation_details_assigned_at ON allocation_plan_details(assigned_at);

-- ============================================================================
-- 4. ROW LEVEL SECURITY: panelists
-- ============================================================================

ALTER TABLE panelists ENABLE ROW LEVEL SECURITY;

-- Policy: SELECT - Only panelists from user's account
CREATE POLICY panelists_select_policy ON panelists
  FOR SELECT
  USING (account_id = current_user_account_id());

-- Policy: INSERT - Can only create in their account
CREATE POLICY panelists_insert_policy ON panelists
  FOR INSERT
  WITH CHECK (account_id = current_user_account_id());

-- Policy: UPDATE - Can only update from their account
CREATE POLICY panelists_update_policy ON panelists
  FOR UPDATE
  USING (account_id = current_user_account_id())
  WITH CHECK (account_id = current_user_account_id());

-- Policy: DELETE - Can only delete from their account
CREATE POLICY panelists_delete_policy ON panelists
  FOR DELETE
  USING (account_id = current_user_account_id());

-- ============================================================================
-- 5. ROW LEVEL SECURITY: panelist_unavailability
-- ============================================================================

ALTER TABLE panelist_unavailability ENABLE ROW LEVEL SECURITY;

-- Policy: SELECT - Only periods from user's account
CREATE POLICY unavailability_select_policy ON panelist_unavailability
  FOR SELECT
  USING (account_id = current_user_account_id());

-- Policy: INSERT - Can only create in their account
CREATE POLICY unavailability_insert_policy ON panelist_unavailability
  FOR INSERT
  WITH CHECK (account_id = current_user_account_id());

-- Policy: UPDATE - Can only update from their account
CREATE POLICY unavailability_update_policy ON panelist_unavailability
  FOR UPDATE
  USING (account_id = current_user_account_id())
  WITH CHECK (account_id = current_user_account_id());

-- Policy: DELETE - Can only delete from their account
CREATE POLICY unavailability_delete_policy ON panelist_unavailability
  FOR DELETE
  USING (account_id = current_user_account_id());

-- ============================================================================
-- 6. HELPER FUNCTIONS
-- ============================================================================

-- Function: Check if panelist is available on a specific date
CREATE OR REPLACE FUNCTION is_panelist_available(
  p_panelist_id UUID,
  p_date DATE
) RETURNS BOOLEAN AS $$
BEGIN
  -- Check if panelist is active
  IF NOT EXISTS (
    SELECT 1 FROM panelists 
    WHERE id = p_panelist_id AND status = 'active'
  ) THEN
    RETURN FALSE;
  END IF;
  
  -- Check if panelist has active unavailability periods on that date
  IF EXISTS (
    SELECT 1 FROM panelist_unavailability
    WHERE panelist_id = p_panelist_id
      AND status = 'active'
      AND p_date BETWEEN start_date AND end_date
  ) THEN
    RETURN FALSE;
  END IF;
  
  RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Get panelist for a node (1:1 relationship)
CREATE OR REPLACE FUNCTION get_panelist_for_node(
  p_node_id UUID,
  p_date DATE DEFAULT CURRENT_DATE
) RETURNS TABLE (
  id UUID,
  panelist_code VARCHAR,
  name VARCHAR,
  email VARCHAR,
  mobile VARCHAR,
  is_available BOOLEAN
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.panelist_code,
    p.name,
    p.email,
    p.mobile,
    is_panelist_available(p.id, p_date) as is_available
  FROM panelists p
  WHERE p.node_id = p_node_id
    AND p.status = 'active'
  LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Check if node is available (has available panelist)
CREATE OR REPLACE FUNCTION is_node_available(
  p_node_id UUID,
  p_date DATE
) RETURNS BOOLEAN AS $$
DECLARE
  v_panelist_id UUID;
BEGIN
  -- Get active panelist for the node
  SELECT id INTO v_panelist_id
  FROM panelists
  WHERE node_id = p_node_id AND status = 'active'
  LIMIT 1;
  
  -- If no panelist, node is not available
  IF v_panelist_id IS NULL THEN
    RETURN FALSE;
  END IF;
  
  -- Check panelist availability
  RETURN is_panelist_available(v_panelist_id, p_date);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 7. VIEWS
-- ============================================================================

-- View: Nodes with panelists and availability status
CREATE OR REPLACE VIEW nodes_with_panelists AS
SELECT 
  n.id as node_id,
  n.auto_id as node_code,
  n.status as node_status,
  c.id as city_id,
  c.name as city_name,
  c.code as city_code,
  r.name as region_name,
  p.id as panelist_id,
  p.panelist_code,
  p.name as panelist_name,
  p.email as panelist_email,
  p.mobile as panelist_mobile,
  p.status as panelist_status,
  -- Current availability
  CASE 
    WHEN p.id IS NULL THEN 'no_panelist'
    WHEN p.status = 'inactive' THEN 'panelist_inactive'
    WHEN EXISTS (
      SELECT 1 FROM panelist_unavailability pu
      WHERE pu.panelist_id = p.id
        AND pu.status = 'active'
        AND CURRENT_DATE BETWEEN pu.start_date AND pu.end_date
    ) THEN 'unavailable'
    ELSE 'available'
  END as availability_status,
  n.account_id
FROM nodes n
JOIN cities c ON n.city_id = c.id
JOIN regions r ON c.region_id = r.id
LEFT JOIN panelists p ON n.id = p.node_id AND p.status = 'active';

-- View: Allocation details with full panelist information
CREATE OR REPLACE VIEW allocation_details_full AS
SELECT 
  ad.*,
  -- Origin panelist (current info)
  op.panelist_code as origin_panelist_code,
  op.email as origin_panelist_email,
  op.mobile as origin_panelist_mobile,
  op.status as origin_panelist_status,
  -- Destination panelist (current info)
  dp.panelist_code as destination_panelist_code,
  dp.email as destination_panelist_email,
  dp.mobile as destination_panelist_mobile,
  dp.status as destination_panelist_status
FROM allocation_plan_details ad
LEFT JOIN panelists op ON ad.origin_panelist_id = op.id
LEFT JOIN panelists dp ON ad.destination_panelist_id = dp.id;

-- View: Panelists with availability status
CREATE OR REPLACE VIEW panelists_availability_status AS
SELECT 
  p.id,
  p.panelist_code,
  p.name,
  p.email,
  p.mobile,
  p.status as panelist_status,
  n.auto_id as node_code,
  c.name as city_name,
  c.code as city_code,
  r.name as region_name,
  -- Current availability
  CASE 
    WHEN p.status = 'inactive' THEN 'inactive'
    WHEN EXISTS (
      SELECT 1 FROM panelist_unavailability pu
      WHERE pu.panelist_id = p.id
        AND pu.status = 'active'
        AND CURRENT_DATE BETWEEN pu.start_date AND pu.end_date
    ) THEN 'unavailable'
    ELSE 'available'
  END as current_availability,
  -- Next unavailability date
  (
    SELECT MIN(pu.start_date)
    FROM panelist_unavailability pu
    WHERE pu.panelist_id = p.id
      AND pu.status = 'active'
      AND pu.start_date > CURRENT_DATE
  ) as next_unavailable_date,
  p.account_id,
  p.created_at,
  p.updated_at
FROM panelists p
JOIN nodes n ON p.node_id = n.id
JOIN cities c ON n.city_id = c.id
JOIN regions r ON c.region_id = r.id;

-- View: Active unavailability periods
CREATE OR REPLACE VIEW active_unavailability_periods AS
SELECT 
  pu.id,
  pu.panelist_id,
  p.panelist_code,
  p.name as panelist_name,
  n.auto_id as node_code,
  c.name as city_name,
  pu.start_date,
  pu.end_date,
  pu.reason,
  pu.notes,
  -- Days remaining
  CASE 
    WHEN pu.end_date < CURRENT_DATE THEN 0
    WHEN pu.start_date > CURRENT_DATE THEN pu.end_date - pu.start_date + 1
    ELSE pu.end_date - CURRENT_DATE + 1
  END as days_remaining,
  pu.account_id,
  pu.created_at
FROM panelist_unavailability pu
JOIN panelists p ON pu.panelist_id = p.id
JOIN nodes n ON p.node_id = n.id
JOIN cities c ON n.city_id = c.id
WHERE pu.status = 'active'
ORDER BY pu.start_date;

-- ============================================================================
-- 8. TRIGGERS
-- ============================================================================

-- Trigger: Update updated_at on panelists
CREATE OR REPLACE FUNCTION update_panelists_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_panelists_updated_at
  BEFORE UPDATE ON panelists
  FOR EACH ROW
  EXECUTE FUNCTION update_panelists_updated_at();

-- Trigger: Update updated_at on panelist_unavailability
CREATE OR REPLACE FUNCTION update_unavailability_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_unavailability_updated_at
  BEFORE UPDATE ON panelist_unavailability
  FOR EACH ROW
  EXECUTE FUNCTION update_unavailability_updated_at();
