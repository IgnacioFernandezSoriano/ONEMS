-- ============================================
-- FIX CRÍTICO: ACTUALIZAR POLÍTICAS RLS
-- ============================================
-- Fecha: 2026-01-16
-- Descripción: Las políticas RLS de carriers, products, materials y material_catalog
--              usan current_user_role() y current_user_account_id() sin el prefijo public.
--              Esto causa que NO filtren correctamente y todos los usuarios vean todos los datos.
-- ============================================

-- ============================================
-- CARRIERS: ACTUALIZAR POLÍTICAS
-- ============================================

DROP POLICY IF EXISTS "carriers_select" ON carriers;
DROP POLICY IF EXISTS "carriers_insert" ON carriers;
DROP POLICY IF EXISTS "carriers_update" ON carriers;
DROP POLICY IF EXISTS "carriers_delete" ON carriers;

CREATE POLICY "carriers_select"
  ON carriers FOR SELECT
  USING (
    public.current_user_role() = 'superadmin' OR
    account_id = public.current_user_account_id()
  );

CREATE POLICY "carriers_insert"
  ON carriers FOR INSERT
  WITH CHECK (
    public.current_user_role() IN ('superadmin', 'admin')
  );

CREATE POLICY "carriers_update"
  ON carriers FOR UPDATE
  USING (
    public.current_user_role() = 'superadmin' OR
    (public.current_user_role() = 'admin' AND account_id = public.current_user_account_id())
  );

CREATE POLICY "carriers_delete"
  ON carriers FOR DELETE
  USING (
    public.current_user_role() = 'superadmin' OR
    (public.current_user_role() = 'admin' AND account_id = public.current_user_account_id())
  );

-- ============================================
-- PRODUCTS: ACTUALIZAR POLÍTICAS
-- ============================================

DROP POLICY IF EXISTS "products_select" ON products;
DROP POLICY IF EXISTS "products_insert" ON products;
DROP POLICY IF EXISTS "products_update" ON products;
DROP POLICY IF EXISTS "products_delete" ON products;

CREATE POLICY "products_select"
  ON products FOR SELECT
  USING (
    public.current_user_role() = 'superadmin' OR
    account_id = public.current_user_account_id()
  );

CREATE POLICY "products_insert"
  ON products FOR INSERT
  WITH CHECK (
    public.current_user_role() IN ('superadmin', 'admin')
  );

CREATE POLICY "products_update"
  ON products FOR UPDATE
  USING (
    public.current_user_role() = 'superadmin' OR
    (public.current_user_role() = 'admin' AND account_id = public.current_user_account_id())
  );

CREATE POLICY "products_delete"
  ON products FOR DELETE
  USING (
    public.current_user_role() = 'superadmin' OR
    (public.current_user_role() = 'admin' AND account_id = public.current_user_account_id())
  );

-- ============================================
-- MATERIALS: ACTUALIZAR POLÍTICAS
-- ============================================

DROP POLICY IF EXISTS "materials_select" ON materials;
DROP POLICY IF EXISTS "materials_insert" ON materials;
DROP POLICY IF EXISTS "materials_update" ON materials;
DROP POLICY IF EXISTS "materials_delete" ON materials;

CREATE POLICY "materials_select"
  ON materials FOR SELECT
  USING (
    public.current_user_role() = 'superadmin' OR
    account_id = public.current_user_account_id()
  );

CREATE POLICY "materials_insert"
  ON materials FOR INSERT
  WITH CHECK (
    public.current_user_role() IN ('superadmin', 'admin')
  );

CREATE POLICY "materials_update"
  ON materials FOR UPDATE
  USING (
    public.current_user_role() = 'superadmin' OR
    (public.current_user_role() = 'admin' AND account_id = public.current_user_account_id())
  );

CREATE POLICY "materials_delete"
  ON materials FOR DELETE
  USING (
    public.current_user_role() = 'superadmin' OR
    (public.current_user_role() = 'admin' AND account_id = public.current_user_account_id())
  );

-- ============================================
-- MATERIAL_CATALOG: ACTUALIZAR POLÍTICAS
-- ============================================

DROP POLICY IF EXISTS "material_catalog_select" ON material_catalog;
DROP POLICY IF EXISTS "material_catalog_insert" ON material_catalog;
DROP POLICY IF EXISTS "material_catalog_update" ON material_catalog;
DROP POLICY IF EXISTS "material_catalog_delete" ON material_catalog;

CREATE POLICY "material_catalog_select"
  ON material_catalog FOR SELECT
  USING (
    public.current_user_role() = 'superadmin' OR
    account_id = public.current_user_account_id()
  );

CREATE POLICY "material_catalog_insert"
  ON material_catalog FOR INSERT
  WITH CHECK (
    public.current_user_role() IN ('superadmin', 'admin')
  );

CREATE POLICY "material_catalog_update"
  ON material_catalog FOR UPDATE
  USING (
    public.current_user_role() = 'superadmin' OR
    (public.current_user_role() = 'admin' AND account_id = public.current_user_account_id())
  );

CREATE POLICY "material_catalog_delete"
  ON material_catalog FOR DELETE
  USING (
    public.current_user_role() = 'superadmin' OR
    (public.current_user_role() = 'admin' AND account_id = public.current_user_account_id())
  );

-- ============================================
-- PRODUCT_MATERIALS: ACTUALIZAR POLÍTICAS
-- ============================================

DROP POLICY IF EXISTS "product_materials_select" ON product_materials;
DROP POLICY IF EXISTS "product_materials_insert" ON product_materials;
DROP POLICY IF EXISTS "product_materials_update" ON product_materials;
DROP POLICY IF EXISTS "product_materials_delete" ON product_materials;

CREATE POLICY "product_materials_select"
  ON product_materials FOR SELECT
  USING (
    public.current_user_role() = 'superadmin' OR
    account_id = public.current_user_account_id()
  );

CREATE POLICY "product_materials_insert"
  ON product_materials FOR INSERT
  WITH CHECK (
    public.current_user_role() IN ('superadmin', 'admin')
  );

CREATE POLICY "product_materials_update"
  ON product_materials FOR UPDATE
  USING (
    public.current_user_role() = 'superadmin' OR
    (public.current_user_role() = 'admin' AND account_id = public.current_user_account_id())
  );

CREATE POLICY "product_materials_delete"
  ON product_materials FOR DELETE
  USING (
    public.current_user_role() = 'superadmin' OR
    (public.current_user_role() = 'admin' AND account_id = public.current_user_account_id())
  );

-- ============================================
-- VERIFICACIÓN
-- ============================================

SELECT 'RLS policies updated successfully for carriers, products, materials, material_catalog, and product_materials' as status;
