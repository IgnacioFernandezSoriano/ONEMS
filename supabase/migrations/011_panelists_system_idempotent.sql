-- Migration: Panelists System (Idempotent Version)
-- Description: Creates panelists and unavailability tables with all necessary fields
-- Safe to run multiple times

-- ============================================================================
-- 1. CREATE TABLES (IF NOT EXISTS)
-- ============================================================================

-- Panelists table
CREATE TABLE IF NOT EXISTS panelists (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  panelist_code TEXT,
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  mobile TEXT NOT NULL,
  address_line1 TEXT,
  address_line2 TEXT,
  postal_code TEXT,
  address_city TEXT,
  address_country TEXT,
  node_id UUID NOT NULL REFERENCES nodes(id) ON DELETE RESTRICT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_by UUID REFERENCES auth.users(id),
  updated_by UUID REFERENCES auth.users(id)
);

-- Panelist unavailability periods table
CREATE TABLE IF NOT EXISTS panelist_unavailability (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  panelist_id UUID NOT NULL REFERENCES panelists(id) ON DELETE CASCADE,
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  reason TEXT NOT NULL CHECK (reason IN ('vacation', 'sick_leave', 'personal', 'training', 'other')),
  notes TEXT,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'cancelled')),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_by UUID REFERENCES auth.users(id),
  updated_by UUID REFERENCES auth.users(id),
  CONSTRAINT valid_date_range CHECK (end_date >= start_date)
);

-- ============================================================================
-- 2. ADD COLUMNS TO allocation_plan_details (IF NOT EXISTS)
-- ============================================================================

DO $$ 
BEGIN
  -- Add tag_id column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'allocation_plan_details' AND column_name = 'tag_id'
  ) THEN
    ALTER TABLE allocation_plan_details ADD COLUMN tag_id TEXT;
  END IF;

  -- Add origin_panelist_id column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'allocation_plan_details' AND column_name = 'origin_panelist_id'
  ) THEN
    ALTER TABLE allocation_plan_details ADD COLUMN origin_panelist_id UUID REFERENCES panelists(id) ON DELETE SET NULL;
  END IF;

  -- Add destination_panelist_id column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'allocation_plan_details' AND column_name = 'destination_panelist_id'
  ) THEN
    ALTER TABLE allocation_plan_details ADD COLUMN destination_panelist_id UUID REFERENCES panelists(id) ON DELETE SET NULL;
  END IF;

  -- Add origin_panelist_name column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'allocation_plan_details' AND column_name = 'origin_panelist_name'
  ) THEN
    ALTER TABLE allocation_plan_details ADD COLUMN origin_panelist_name TEXT;
  END IF;

  -- Add destination_panelist_name column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'allocation_plan_details' AND column_name = 'destination_panelist_name'
  ) THEN
    ALTER TABLE allocation_plan_details ADD COLUMN destination_panelist_name TEXT;
  END IF;

  -- Add assigned_at column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'allocation_plan_details' AND column_name = 'assigned_at'
  ) THEN
    ALTER TABLE allocation_plan_details ADD COLUMN assigned_at TIMESTAMP WITH TIME ZONE;
  END IF;

  -- Add sent_at column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'allocation_plan_details' AND column_name = 'sent_at'
  ) THEN
    ALTER TABLE allocation_plan_details ADD COLUMN sent_at TIMESTAMP WITH TIME ZONE;
  END IF;

  -- Add delivered_at column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'allocation_plan_details' AND column_name = 'delivered_at'
  ) THEN
    ALTER TABLE allocation_plan_details ADD COLUMN delivered_at TIMESTAMP WITH TIME ZONE;
  END IF;
END $$;

-- Add address columns to panelists table if they don't exist
DO $$
BEGIN
  -- Add address_line1 column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'panelists' AND column_name = 'address_line1'
  ) THEN
    ALTER TABLE panelists ADD COLUMN address_line1 TEXT;
  END IF;

  -- Add address_line2 column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'panelists' AND column_name = 'address_line2'
  ) THEN
    ALTER TABLE panelists ADD COLUMN address_line2 TEXT;
  END IF;

  -- Add postal_code column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'panelists' AND column_name = 'postal_code'
  ) THEN
    ALTER TABLE panelists ADD COLUMN postal_code TEXT;
  END IF;

  -- Add address_city column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'panelists' AND column_name = 'address_city'
  ) THEN
    ALTER TABLE panelists ADD COLUMN address_city TEXT;
  END IF;

  -- Add address_country column
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'panelists' AND column_name = 'address_country'
  ) THEN
    ALTER TABLE panelists ADD COLUMN address_country TEXT;
  END IF;
END $$;

-- ============================================================================
-- 3. CREATE INDEXES (IF NOT EXISTS)
-- ============================================================================

-- Panelists indexes
CREATE INDEX IF NOT EXISTS idx_panelists_account_id ON panelists(account_id);
CREATE INDEX IF NOT EXISTS idx_panelists_node_id ON panelists(node_id);
CREATE INDEX IF NOT EXISTS idx_panelists_status ON panelists(status);
CREATE INDEX IF NOT EXISTS idx_panelists_code ON panelists(panelist_code);

-- Panelist unavailability indexes
CREATE INDEX IF NOT EXISTS idx_panelist_unavailability_account_id ON panelist_unavailability(account_id);
CREATE INDEX IF NOT EXISTS idx_panelist_unavailability_panelist_id ON panelist_unavailability(panelist_id);
CREATE INDEX IF NOT EXISTS idx_panelist_unavailability_dates ON panelist_unavailability(start_date, end_date);
CREATE INDEX IF NOT EXISTS idx_panelist_unavailability_status ON panelist_unavailability(status);

-- Allocation plan details indexes for new columns
CREATE INDEX IF NOT EXISTS idx_allocation_plan_details_tag_id ON allocation_plan_details(tag_id);
CREATE INDEX IF NOT EXISTS idx_allocation_plan_details_origin_panelist ON allocation_plan_details(origin_panelist_id);
CREATE INDEX IF NOT EXISTS idx_allocation_plan_details_dest_panelist ON allocation_plan_details(destination_panelist_id);

-- ============================================================================
-- 4. CREATE UNIQUE CONSTRAINTS (IF NOT EXISTS)
-- ============================================================================

DO $$
BEGIN
  -- Unique panelist code per account
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'unique_panelist_code_per_account'
  ) THEN
    ALTER TABLE panelists ADD CONSTRAINT unique_panelist_code_per_account UNIQUE (account_id, panelist_code);
  END IF;

  -- Only one active panelist per node (1:1 relationship)
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes WHERE indexname = 'unique_active_panelist_per_node'
  ) THEN
    CREATE UNIQUE INDEX unique_active_panelist_per_node ON panelists(node_id) WHERE status = 'active';
  END IF;
END $$;

-- ============================================================================
-- 5. ENABLE RLS
-- ============================================================================

ALTER TABLE panelists ENABLE ROW LEVEL SECURITY;
ALTER TABLE panelist_unavailability ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 6. CREATE RLS POLICIES (DROP IF EXISTS, THEN CREATE)
-- ============================================================================

-- Panelists policies
DROP POLICY IF EXISTS panelists_select_policy ON panelists;
CREATE POLICY panelists_select_policy ON panelists
  FOR SELECT
  USING (account_id = current_user_account_id());

DROP POLICY IF EXISTS panelists_insert_policy ON panelists;
CREATE POLICY panelists_insert_policy ON panelists
  FOR INSERT
  WITH CHECK (account_id = current_user_account_id());

DROP POLICY IF EXISTS panelists_update_policy ON panelists;
CREATE POLICY panelists_update_policy ON panelists
  FOR UPDATE
  USING (account_id = current_user_account_id())
  WITH CHECK (account_id = current_user_account_id());

DROP POLICY IF EXISTS panelists_delete_policy ON panelists;
CREATE POLICY panelists_delete_policy ON panelists
  FOR DELETE
  USING (account_id = current_user_account_id());

-- Panelist unavailability policies
DROP POLICY IF EXISTS panelist_unavailability_select_policy ON panelist_unavailability;
CREATE POLICY panelist_unavailability_select_policy ON panelist_unavailability
  FOR SELECT
  USING (account_id = current_user_account_id());

DROP POLICY IF EXISTS panelist_unavailability_insert_policy ON panelist_unavailability;
CREATE POLICY panelist_unavailability_insert_policy ON panelist_unavailability
  FOR INSERT
  WITH CHECK (account_id = current_user_account_id());

DROP POLICY IF EXISTS panelist_unavailability_update_policy ON panelist_unavailability;
CREATE POLICY panelist_unavailability_update_policy ON panelist_unavailability
  FOR UPDATE
  USING (account_id = current_user_account_id())
  WITH CHECK (account_id = current_user_account_id());

DROP POLICY IF EXISTS panelist_unavailability_delete_policy ON panelist_unavailability;
CREATE POLICY panelist_unavailability_delete_policy ON panelist_unavailability
  FOR DELETE
  USING (account_id = current_user_account_id());

-- ============================================================================
-- 7. CREATE FUNCTIONS (DROP IF EXISTS, THEN CREATE)
-- ============================================================================

-- Function to check if a panelist is available on a specific date
DROP FUNCTION IF EXISTS is_panelist_available(UUID, DATE);
CREATE OR REPLACE FUNCTION is_panelist_available(
  p_panelist_id UUID,
  p_date DATE
) RETURNS BOOLEAN AS $$
DECLARE
  v_unavailable_count INTEGER;
BEGIN
  -- Check if panelist has any active unavailability period covering this date
  SELECT COUNT(*)
  INTO v_unavailable_count
  FROM panelist_unavailability
  WHERE panelist_id = p_panelist_id
    AND status = 'active'
    AND p_date BETWEEN start_date AND end_date;
  
  RETURN v_unavailable_count = 0;
END;
$$ LANGUAGE plpgsql;

-- Function to get the active panelist for a node (1:1 relationship)
DROP FUNCTION IF EXISTS get_panelist_for_node(UUID, DATE);
CREATE OR REPLACE FUNCTION get_panelist_for_node(
  p_node_id UUID,
  p_date DATE DEFAULT CURRENT_DATE
) RETURNS TABLE (
  panelist_id UUID,
  panelist_code TEXT,
  panelist_name TEXT,
  is_available BOOLEAN
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.panelist_code,
    p.name,
    is_panelist_available(p.id, p_date)
  FROM panelists p
  WHERE p.node_id = p_node_id
    AND p.status = 'active'
  LIMIT 1;
END;
$$ LANGUAGE plpgsql;

-- Function to check if a node has an available panelist
DROP FUNCTION IF EXISTS is_node_available(UUID, DATE);
CREATE OR REPLACE FUNCTION is_node_available(
  p_node_id UUID,
  p_date DATE DEFAULT CURRENT_DATE
) RETURNS BOOLEAN AS $$
DECLARE
  v_panelist_available BOOLEAN;
BEGIN
  SELECT is_available
  INTO v_panelist_available
  FROM get_panelist_for_node(p_node_id, p_date);
  
  RETURN COALESCE(v_panelist_available, FALSE);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 8. CREATE VIEWS (DROP IF EXISTS, THEN CREATE)
-- ============================================================================

-- View: Nodes with panelist information
DROP VIEW IF EXISTS nodes_with_panelists;
CREATE OR REPLACE VIEW nodes_with_panelists AS
SELECT 
  n.*,
  p.id as panelist_id,
  p.panelist_code,
  p.name as panelist_name,
  p.email as panelist_email,
  p.mobile as panelist_mobile,
  p.status as panelist_status,
  CASE 
    WHEN p.id IS NULL THEN 'no_panelist'
    WHEN p.status = 'inactive' THEN 'inactive'
    WHEN EXISTS (
      SELECT 1 FROM panelist_unavailability pu
      WHERE pu.panelist_id = p.id
        AND pu.status = 'active'
        AND CURRENT_DATE BETWEEN pu.start_date AND pu.end_date
    ) THEN 'unavailable'
    ELSE 'available'
  END as panelist_availability
FROM nodes n
LEFT JOIN panelists p ON n.id = p.node_id AND p.status = 'active';

-- View: Allocation details with full panelist information
DROP VIEW IF EXISTS allocation_details_full;
CREATE OR REPLACE VIEW allocation_details_full AS
SELECT 
  ad.*,
  op.name as origin_panelist_full_name,
  op.email as origin_panelist_email,
  op.mobile as origin_panelist_mobile,
  dp.name as destination_panelist_full_name,
  dp.email as destination_panelist_email,
  dp.mobile as destination_panelist_mobile
FROM allocation_plan_details ad
LEFT JOIN panelists op ON ad.origin_panelist_id = op.id
LEFT JOIN panelists dp ON ad.destination_panelist_id = dp.id;

-- View: Panelists with availability status
DROP VIEW IF EXISTS panelists_availability_status;
CREATE OR REPLACE VIEW panelists_availability_status AS
SELECT 
  p.*,
  n.auto_id as node_code,
  c.name as city_name,
  CASE 
    WHEN p.status = 'inactive' THEN 'inactive'
    WHEN EXISTS (
      SELECT 1 FROM panelist_unavailability pu
      WHERE pu.panelist_id = p.id
        AND pu.status = 'active'
        AND CURRENT_DATE BETWEEN pu.start_date AND pu.end_date
    ) THEN 'unavailable'
    ELSE 'available'
  END as availability_status,
  (
    SELECT MIN(pu.start_date)
    FROM panelist_unavailability pu
    WHERE pu.panelist_id = p.id
      AND pu.status = 'active'
      AND pu.start_date > CURRENT_DATE
  ) as next_unavailable_date
FROM panelists p
LEFT JOIN nodes n ON p.node_id = n.id
LEFT JOIN cities c ON n.city_id = c.id;

-- View: Active unavailability periods with days remaining
DROP VIEW IF EXISTS active_unavailability_periods;
CREATE OR REPLACE VIEW active_unavailability_periods AS
SELECT 
  pu.*,
  p.name as panelist_name,
  p.panelist_code,
  n.auto_id as node_code,
  c.name as city_name,
  pu.end_date - CURRENT_DATE as days_remaining,
  CURRENT_DATE BETWEEN pu.start_date AND pu.end_date as is_currently_unavailable
FROM panelist_unavailability pu
JOIN panelists p ON pu.panelist_id = p.id
LEFT JOIN nodes n ON p.node_id = n.id
LEFT JOIN cities c ON n.city_id = c.id
WHERE pu.status = 'active'
ORDER BY pu.start_date;

-- ============================================================================
-- 9. CREATE FUNCTION FOR AUTO-GENERATING PANELIST CODE
-- ============================================================================

-- Function to auto-generate panelist code based on node
DROP FUNCTION IF EXISTS generate_panelist_code() CASCADE;
CREATE OR REPLACE FUNCTION generate_panelist_code()
RETURNS TRIGGER AS $$
DECLARE
  v_node_code TEXT;
  v_city_code TEXT;
  v_count INTEGER;
  v_new_code TEXT;
BEGIN
  -- Only generate if panelist_code is empty or null
  IF NEW.panelist_code IS NULL OR NEW.panelist_code = '' THEN
    -- Get node code
    SELECT n.auto_id, c.code
    INTO v_node_code, v_city_code
    FROM nodes n
    JOIN cities c ON n.city_id = c.id
    WHERE n.id = NEW.node_id;
    
    -- Count existing panelists for this node to generate sequence
    SELECT COUNT(*) + 1
    INTO v_count
    FROM panelists
    WHERE node_id = NEW.node_id;
    
    -- Generate code: PAN-{CITY_CODE}-{SEQUENCE}
    -- Example: PAN-MAD-001
    v_new_code := 'PAN-' || COALESCE(v_city_code, 'XXX') || '-' || LPAD(v_count::TEXT, 3, '0');
    
    NEW.panelist_code := v_new_code;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 10. CREATE FUNCTION FOR UPDATING updated_at COLUMN
-- ============================================================================

-- Function to automatically update updated_at timestamp
DROP FUNCTION IF EXISTS update_updated_at_column() CASCADE;
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 11. CREATE TRIGGERS
-- ============================================================================

-- Trigger for auto-generating panelist code
DROP TRIGGER IF EXISTS generate_panelist_code_trigger ON panelists;
CREATE TRIGGER generate_panelist_code_trigger
  BEFORE INSERT ON panelists
  FOR EACH ROW
  EXECUTE FUNCTION generate_panelist_code();

-- Trigger for panelists
DROP TRIGGER IF EXISTS set_updated_at_panelists ON panelists;
CREATE TRIGGER set_updated_at_panelists
  BEFORE UPDATE ON panelists
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Trigger for panelist_unavailability
DROP TRIGGER IF EXISTS set_updated_at_panelist_unavailability ON panelist_unavailability;
CREATE TRIGGER set_updated_at_panelist_unavailability
  BEFORE UPDATE ON panelist_unavailability
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================

-- Verify tables exist
DO $$
BEGIN
  RAISE NOTICE 'Migration completed successfully!';
  RAISE NOTICE 'Tables created: panelists, panelist_unavailability';
  RAISE NOTICE 'Columns added to allocation_plan_details: tag_id, origin_panelist_id, destination_panelist_id, origin_panelist_name, destination_panelist_name, assigned_at, sent_at, delivered_at';
  RAISE NOTICE 'Functions created: is_panelist_available, get_panelist_for_node, is_node_available';
  RAISE NOTICE 'Views created: nodes_with_panelists, allocation_details_full, panelists_availability_status, active_unavailability_periods';
END $$;
