-- ============================================
-- CARRIERS MODULE
-- ============================================

-- Carriers table
CREATE TABLE carriers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  type TEXT,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(account_id, code)
);

-- Products table
CREATE TABLE products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  carrier_id UUID NOT NULL REFERENCES carriers(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  description TEXT NOT NULL,
  standard_delivery_hours INTEGER NOT NULL,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(carrier_id, code)
);

-- Indexes
CREATE INDEX carriers_account_id_idx ON carriers(account_id);
CREATE INDEX products_account_id_idx ON products(account_id);
CREATE INDEX products_carrier_id_idx ON products(carrier_id);

-- ============================================
-- TRIGGERS
-- ============================================

-- Auto-assign account_id for carriers
CREATE TRIGGER set_carriers_account_id
  BEFORE INSERT ON carriers
  FOR EACH ROW
  EXECUTE FUNCTION set_account_id();

-- Auto-assign account_id for products
CREATE TRIGGER set_products_account_id
  BEFORE INSERT ON products
  FOR EACH ROW
  EXECUTE FUNCTION set_account_id();

-- Prevent account_id changes for carriers
CREATE TRIGGER prevent_carriers_account_change
  BEFORE UPDATE ON carriers
  FOR EACH ROW
  EXECUTE FUNCTION prevent_account_id_change();

-- Prevent account_id changes for products
CREATE TRIGGER prevent_products_account_change
  BEFORE UPDATE ON products
  FOR EACH ROW
  EXECUTE FUNCTION prevent_account_id_change();

-- Updated_at triggers
CREATE TRIGGER update_carriers_updated_at
  BEFORE UPDATE ON carriers
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_products_updated_at
  BEFORE UPDATE ON products
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- ============================================
-- RLS POLICIES
-- ============================================

ALTER TABLE carriers ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;

-- Carriers policies
CREATE POLICY "carriers_select"
  ON carriers FOR SELECT
  USING (
    current_user_role() = 'superadmin' OR
    account_id = current_user_account_id()
  );

CREATE POLICY "carriers_insert"
  ON carriers FOR INSERT
  WITH CHECK (
    current_user_role() IN ('superadmin', 'admin')
  );

CREATE POLICY "carriers_update"
  ON carriers FOR UPDATE
  USING (
    current_user_role() = 'superadmin' OR
    (current_user_role() = 'admin' AND account_id = current_user_account_id())
  );

CREATE POLICY "carriers_delete"
  ON carriers FOR DELETE
  USING (
    current_user_role() = 'superadmin' OR
    (current_user_role() = 'admin' AND account_id = current_user_account_id())
  );

-- Products policies
CREATE POLICY "products_select"
  ON products FOR SELECT
  USING (
    current_user_role() = 'superadmin' OR
    account_id = current_user_account_id()
  );

CREATE POLICY "products_insert"
  ON products FOR INSERT
  WITH CHECK (
    current_user_role() IN ('superadmin', 'admin')
  );

CREATE POLICY "products_update"
  ON products FOR UPDATE
  USING (
    current_user_role() = 'superadmin' OR
    (current_user_role() = 'admin' AND account_id = current_user_account_id())
  );

CREATE POLICY "products_delete"
  ON products FOR DELETE
  USING (
    current_user_role() = 'superadmin' OR
    (current_user_role() = 'admin' AND account_id = current_user_account_id())
  );

-- Verify
SELECT 'Carriers and Products tables created successfully' as status;
