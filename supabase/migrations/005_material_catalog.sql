-- ============================================
-- MATERIAL CATALOG SYSTEM
-- ============================================

-- Create material_catalog table (global catalog per account)
CREATE TABLE material_catalog (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  unit_measure TEXT,
  description TEXT,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  -- Unique constraint per account
  CONSTRAINT material_catalog_code_account_unique UNIQUE (account_id, code)
);

-- Create product_materials junction table (many-to-many)
CREATE TABLE product_materials (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  material_catalog_id UUID NOT NULL REFERENCES material_catalog(id) ON DELETE CASCADE,
  quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  -- Unique constraint: one material per product
  CONSTRAINT product_materials_unique UNIQUE (product_id, material_catalog_id)
);

-- Indexes
CREATE INDEX material_catalog_account_id_idx ON material_catalog(account_id);
CREATE INDEX material_catalog_code_idx ON material_catalog(code);
CREATE INDEX product_materials_product_id_idx ON product_materials(product_id);
CREATE INDEX product_materials_material_catalog_id_idx ON product_materials(material_catalog_id);

-- Triggers for account_id
CREATE TRIGGER set_material_catalog_account_id
  BEFORE INSERT ON material_catalog
  FOR EACH ROW
  EXECUTE FUNCTION set_account_id();

CREATE TRIGGER prevent_material_catalog_account_change
  BEFORE UPDATE ON material_catalog
  FOR EACH ROW
  EXECUTE FUNCTION prevent_account_id_change();

CREATE TRIGGER set_product_materials_account_id
  BEFORE INSERT ON product_materials
  FOR EACH ROW
  EXECUTE FUNCTION set_account_id();

CREATE TRIGGER prevent_product_materials_account_change
  BEFORE UPDATE ON product_materials
  FOR EACH ROW
  EXECUTE FUNCTION prevent_account_id_change();

-- Triggers for updated_at
CREATE TRIGGER update_material_catalog_updated_at
  BEFORE UPDATE ON material_catalog
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_product_materials_updated_at
  BEFORE UPDATE ON product_materials
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- ============================================
-- RLS POLICIES
-- ============================================

ALTER TABLE material_catalog ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_materials ENABLE ROW LEVEL SECURITY;

-- Material Catalog Policies
CREATE POLICY "material_catalog_select"
  ON material_catalog FOR SELECT
  USING (
    current_user_role() = 'superadmin' OR
    account_id = current_user_account_id()
  );

CREATE POLICY "material_catalog_insert"
  ON material_catalog FOR INSERT
  WITH CHECK (
    current_user_role() IN ('superadmin', 'admin')
  );

CREATE POLICY "material_catalog_update"
  ON material_catalog FOR UPDATE
  USING (
    current_user_role() = 'superadmin' OR
    (current_user_role() = 'admin' AND account_id = current_user_account_id())
  );

CREATE POLICY "material_catalog_delete"
  ON material_catalog FOR DELETE
  USING (
    current_user_role() = 'superadmin' OR
    (current_user_role() = 'admin' AND account_id = current_user_account_id())
  );

-- Product Materials Policies
CREATE POLICY "product_materials_select"
  ON product_materials FOR SELECT
  USING (
    current_user_role() = 'superadmin' OR
    account_id = current_user_account_id()
  );

CREATE POLICY "product_materials_insert"
  ON product_materials FOR INSERT
  WITH CHECK (
    current_user_role() IN ('superadmin', 'admin')
  );

CREATE POLICY "product_materials_update"
  ON product_materials FOR UPDATE
  USING (
    current_user_role() = 'superadmin' OR
    (current_user_role() = 'admin' AND account_id = current_user_account_id())
  );

CREATE POLICY "product_materials_delete"
  ON product_materials FOR DELETE
  USING (
    current_user_role() = 'superadmin' OR
    (current_user_role() = 'admin' AND account_id = current_user_account_id())
  );

-- Verify tables created
SELECT 'Material catalog system created successfully' as status;
