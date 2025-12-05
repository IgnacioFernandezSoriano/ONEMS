-- ============================================
-- NETWORK TOPOLOGY TABLES
-- ============================================

-- Regions table
CREATE TABLE regions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  code TEXT NOT NULL,
  description TEXT,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(account_id, code)
);

-- Cities table
CREATE TABLE cities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  region_id UUID NOT NULL REFERENCES regions(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  code TEXT NOT NULL,
  latitude DECIMAL(10, 8),
  longitude DECIMAL(11, 8),
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(region_id, code)
);

-- Nodes table
CREATE TABLE nodes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  city_id UUID NOT NULL REFERENCES cities(id) ON DELETE CASCADE,
  auto_id TEXT NOT NULL,
  name TEXT,
  node_type TEXT DEFAULT 'access' CHECK (node_type IN ('core', 'edge', 'access')),
  ip_address INET,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'maintenance')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(account_id, auto_id)
);

-- Indexes
CREATE INDEX regions_account_id_idx ON regions(account_id);
CREATE INDEX cities_account_id_idx ON cities(account_id);
CREATE INDEX cities_region_id_idx ON cities(region_id);
CREATE INDEX nodes_account_id_idx ON nodes(account_id);
CREATE INDEX nodes_city_id_idx ON nodes(city_id);
CREATE INDEX nodes_auto_id_idx ON nodes(auto_id);

-- ============================================
-- TRIGGERS FOR AUTO-ASSIGNMENT
-- ============================================

-- Regions: auto-assign account_id
CREATE TRIGGER set_regions_account_id
  BEFORE INSERT ON regions
  FOR EACH ROW
  EXECUTE FUNCTION set_account_id();

CREATE TRIGGER prevent_regions_account_change
  BEFORE UPDATE ON regions
  FOR EACH ROW
  EXECUTE FUNCTION prevent_account_id_change();

CREATE TRIGGER update_regions_updated_at
  BEFORE UPDATE ON regions
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- Cities: auto-assign account_id
CREATE TRIGGER set_cities_account_id
  BEFORE INSERT ON cities
  FOR EACH ROW
  EXECUTE FUNCTION set_account_id();

CREATE TRIGGER prevent_cities_account_change
  BEFORE UPDATE ON cities
  FOR EACH ROW
  EXECUTE FUNCTION prevent_account_id_change();

CREATE TRIGGER update_cities_updated_at
  BEFORE UPDATE ON cities
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- Nodes: auto-assign account_id
CREATE TRIGGER set_nodes_account_id
  BEFORE INSERT ON nodes
  FOR EACH ROW
  EXECUTE FUNCTION set_account_id();

CREATE TRIGGER prevent_nodes_account_change
  BEFORE UPDATE ON nodes
  FOR EACH ROW
  EXECUTE FUNCTION prevent_account_id_change();

CREATE TRIGGER update_nodes_updated_at
  BEFORE UPDATE ON nodes
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- ============================================
-- RLS POLICIES
-- ============================================

-- Enable RLS
ALTER TABLE regions ENABLE ROW LEVEL SECURITY;
ALTER TABLE cities ENABLE ROW LEVEL SECURITY;
ALTER TABLE nodes ENABLE ROW LEVEL SECURITY;

-- Regions policies
CREATE POLICY "regions_select_own_account"
  ON regions FOR SELECT
  TO authenticated
  USING (account_id = public.current_user_account_id());

CREATE POLICY "regions_select_superadmin"
  ON regions FOR SELECT
  TO authenticated
  USING (public.current_user_role() = 'superadmin');

CREATE POLICY "regions_insert_admin"
  ON regions FOR INSERT
  TO authenticated
  WITH CHECK (
    public.current_user_role() IN ('admin', 'superadmin')
  );

CREATE POLICY "regions_update_admin"
  ON regions FOR UPDATE
  TO authenticated
  USING (
    public.current_user_role() IN ('admin', 'superadmin')
    AND account_id = public.current_user_account_id()
  );

CREATE POLICY "regions_delete_admin"
  ON regions FOR DELETE
  TO authenticated
  USING (
    public.current_user_role() IN ('admin', 'superadmin')
    AND account_id = public.current_user_account_id()
  );

-- Cities policies (same pattern)
CREATE POLICY "cities_select_own_account"
  ON cities FOR SELECT
  TO authenticated
  USING (account_id = public.current_user_account_id());

CREATE POLICY "cities_select_superadmin"
  ON cities FOR SELECT
  TO authenticated
  USING (public.current_user_role() = 'superadmin');

CREATE POLICY "cities_insert_admin"
  ON cities FOR INSERT
  TO authenticated
  WITH CHECK (
    public.current_user_role() IN ('admin', 'superadmin')
  );

CREATE POLICY "cities_update_admin"
  ON cities FOR UPDATE
  TO authenticated
  USING (
    public.current_user_role() IN ('admin', 'superadmin')
    AND account_id = public.current_user_account_id()
  );

CREATE POLICY "cities_delete_admin"
  ON cities FOR DELETE
  TO authenticated
  USING (
    public.current_user_role() IN ('admin', 'superadmin')
    AND account_id = public.current_user_account_id()
  );

-- Nodes policies (same pattern)
CREATE POLICY "nodes_select_own_account"
  ON nodes FOR SELECT
  TO authenticated
  USING (account_id = public.current_user_account_id());

CREATE POLICY "nodes_select_superadmin"
  ON nodes FOR SELECT
  TO authenticated
  USING (public.current_user_role() = 'superadmin');

CREATE POLICY "nodes_insert_admin"
  ON nodes FOR INSERT
  TO authenticated
  WITH CHECK (
    public.current_user_role() IN ('admin', 'superadmin')
  );

CREATE POLICY "nodes_update_admin"
  ON nodes FOR UPDATE
  TO authenticated
  USING (
    public.current_user_role() IN ('admin', 'superadmin')
    AND account_id = public.current_user_account_id()
  );

CREATE POLICY "nodes_delete_admin"
  ON nodes FOR DELETE
  TO authenticated
  USING (
    public.current_user_role() IN ('admin', 'superadmin')
    AND account_id = public.current_user_account_id()
  );

-- ============================================
-- HELPER FUNCTION FOR AUTO_ID GENERATION
-- ============================================

CREATE OR REPLACE FUNCTION generate_node_auto_id(
  p_city_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_region_code TEXT;
  v_city_code TEXT;
  v_node_count INT;
  v_auto_id TEXT;
BEGIN
  -- Get region and city codes
  SELECT r.code, c.code
  INTO v_region_code, v_city_code
  FROM cities c
  JOIN regions r ON c.region_id = r.id
  WHERE c.id = p_city_id;
  
  -- Count existing nodes in this city
  SELECT COUNT(*) + 1
  INTO v_node_count
  FROM nodes
  WHERE city_id = p_city_id;
  
  -- Generate auto_id: REGION-CITY-NNN
  v_auto_id := v_region_code || '-' || v_city_code || '-' || LPAD(v_node_count::TEXT, 3, '0');
  
  RETURN v_auto_id;
END;
$$;
