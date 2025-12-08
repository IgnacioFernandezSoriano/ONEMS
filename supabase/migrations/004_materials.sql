-- ============================================
-- MATERIALS TABLE
-- ============================================

-- Materials table (third level: Carrier → Product → Material)
CREATE TABLE materials (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  unit_measure TEXT,
  description TEXT,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(product_id, code)
);

-- Indexes
CREATE INDEX materials_account_id_idx ON materials(account_id);
CREATE INDEX materials_product_id_idx ON materials(product_id);

-- ============================================
-- TRIGGERS
-- ============================================

-- Auto-assign account_id for materials
CREATE TRIGGER set_materials_account_id
  BEFORE INSERT ON materials
  FOR EACH ROW
  EXECUTE FUNCTION set_account_id();

-- Prevent account_id changes for materials
CREATE TRIGGER prevent_materials_account_change
  BEFORE UPDATE ON materials
  FOR EACH ROW
  EXECUTE FUNCTION prevent_account_id_change();

-- Updated_at trigger
CREATE TRIGGER update_materials_updated_at
  BEFORE UPDATE ON materials
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- ============================================
-- RLS POLICIES
-- ============================================

ALTER TABLE materials ENABLE ROW LEVEL SECURITY;

-- Materials policies
CREATE POLICY "materials_select"
  ON materials FOR SELECT
  USING (
    current_user_role() = 'superadmin' OR
    account_id = current_user_account_id()
  );

CREATE POLICY "materials_insert"
  ON materials FOR INSERT
  WITH CHECK (
    current_user_role() IN ('superadmin', 'admin')
  );

CREATE POLICY "materials_update"
  ON materials FOR UPDATE
  USING (
    current_user_role() = 'superadmin' OR
    (current_user_role() = 'admin' AND account_id = current_user_account_id())
  );

CREATE POLICY "materials_delete"
  ON materials FOR DELETE
  USING (
    current_user_role() = 'superadmin' OR
    (current_user_role() = 'admin' AND account_id = current_user_account_id())
  );

-- Verify
SELECT 'Materials table created successfully' as status;
