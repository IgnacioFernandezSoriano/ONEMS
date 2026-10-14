-- Activar RLS por account_id en las tablas de stock (subsistema "falta material en tratamiento").
-- Estas tablas se crearon con RLS deshabilitada en el baseline; este cambio las alinea con el
-- patron ya usado en el resto del esquema (ver panelist_incident, panelist_unavailability, etc.):
--   using/with check (account_id = current_user_account_id() OR is_superadmin())
-- service_role bypassa RLS por defecto en Postgres, por lo que n8n y las RPC SECURITY DEFINER
-- (create-user, weekly-aggregation, receive_material_shipment, etc.) siguen funcionando igual.

-- ---------- material_stocks ----------
ALTER TABLE public.material_stocks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS material_stocks_select ON public.material_stocks;
DROP POLICY IF EXISTS material_stocks_insert ON public.material_stocks;
DROP POLICY IF EXISTS material_stocks_update ON public.material_stocks;
DROP POLICY IF EXISTS material_stocks_delete ON public.material_stocks;
CREATE POLICY material_stocks_select ON public.material_stocks
  FOR SELECT USING (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY material_stocks_insert ON public.material_stocks
  FOR INSERT WITH CHECK (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY material_stocks_update ON public.material_stocks
  FOR UPDATE USING (account_id = current_user_account_id() OR is_superadmin())
  WITH CHECK (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY material_stocks_delete ON public.material_stocks
  FOR DELETE USING (account_id = current_user_account_id() OR is_superadmin());

-- ---------- panelist_material_stocks ----------
ALTER TABLE public.panelist_material_stocks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS panelist_material_stocks_select ON public.panelist_material_stocks;
DROP POLICY IF EXISTS panelist_material_stocks_insert ON public.panelist_material_stocks;
DROP POLICY IF EXISTS panelist_material_stocks_update ON public.panelist_material_stocks;
DROP POLICY IF EXISTS panelist_material_stocks_delete ON public.panelist_material_stocks;
CREATE POLICY panelist_material_stocks_select ON public.panelist_material_stocks
  FOR SELECT USING (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY panelist_material_stocks_insert ON public.panelist_material_stocks
  FOR INSERT WITH CHECK (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY panelist_material_stocks_update ON public.panelist_material_stocks
  FOR UPDATE USING (account_id = current_user_account_id() OR is_superadmin())
  WITH CHECK (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY panelist_material_stocks_delete ON public.panelist_material_stocks
  FOR DELETE USING (account_id = current_user_account_id() OR is_superadmin());

-- ---------- material_movements ----------
ALTER TABLE public.material_movements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS material_movements_select ON public.material_movements;
DROP POLICY IF EXISTS material_movements_insert ON public.material_movements;
DROP POLICY IF EXISTS material_movements_update ON public.material_movements;
DROP POLICY IF EXISTS material_movements_delete ON public.material_movements;
CREATE POLICY material_movements_select ON public.material_movements
  FOR SELECT USING (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY material_movements_insert ON public.material_movements
  FOR INSERT WITH CHECK (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY material_movements_update ON public.material_movements
  FOR UPDATE USING (account_id = current_user_account_id() OR is_superadmin())
  WITH CHECK (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY material_movements_delete ON public.material_movements
  FOR DELETE USING (account_id = current_user_account_id() OR is_superadmin());

-- ---------- material_shipments ----------
ALTER TABLE public.material_shipments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS material_shipments_select ON public.material_shipments;
DROP POLICY IF EXISTS material_shipments_insert ON public.material_shipments;
DROP POLICY IF EXISTS material_shipments_update ON public.material_shipments;
DROP POLICY IF EXISTS material_shipments_delete ON public.material_shipments;
CREATE POLICY material_shipments_select ON public.material_shipments
  FOR SELECT USING (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY material_shipments_insert ON public.material_shipments
  FOR INSERT WITH CHECK (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY material_shipments_update ON public.material_shipments
  FOR UPDATE USING (account_id = current_user_account_id() OR is_superadmin())
  WITH CHECK (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY material_shipments_delete ON public.material_shipments
  FOR DELETE USING (account_id = current_user_account_id() OR is_superadmin());

-- ---------- material_shipment_items ----------
ALTER TABLE public.material_shipment_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS material_shipment_items_select ON public.material_shipment_items;
DROP POLICY IF EXISTS material_shipment_items_insert ON public.material_shipment_items;
DROP POLICY IF EXISTS material_shipment_items_update ON public.material_shipment_items;
DROP POLICY IF EXISTS material_shipment_items_delete ON public.material_shipment_items;
CREATE POLICY material_shipment_items_select ON public.material_shipment_items
  FOR SELECT USING (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY material_shipment_items_insert ON public.material_shipment_items
  FOR INSERT WITH CHECK (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY material_shipment_items_update ON public.material_shipment_items
  FOR UPDATE USING (account_id = current_user_account_id() OR is_superadmin())
  WITH CHECK (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY material_shipment_items_delete ON public.material_shipment_items
  FOR DELETE USING (account_id = current_user_account_id() OR is_superadmin());

-- ---------- stock_settings ----------
ALTER TABLE public.stock_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS stock_settings_select ON public.stock_settings;
DROP POLICY IF EXISTS stock_settings_insert ON public.stock_settings;
DROP POLICY IF EXISTS stock_settings_update ON public.stock_settings;
DROP POLICY IF EXISTS stock_settings_delete ON public.stock_settings;
CREATE POLICY stock_settings_select ON public.stock_settings
  FOR SELECT USING (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY stock_settings_insert ON public.stock_settings
  FOR INSERT WITH CHECK (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY stock_settings_update ON public.stock_settings
  FOR UPDATE USING (account_id = current_user_account_id() OR is_superadmin())
  WITH CHECK (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY stock_settings_delete ON public.stock_settings
  FOR DELETE USING (account_id = current_user_account_id() OR is_superadmin());

-- ---------- material_requirements_periods ----------
ALTER TABLE public.material_requirements_periods ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS material_requirements_periods_select ON public.material_requirements_periods;
DROP POLICY IF EXISTS material_requirements_periods_insert ON public.material_requirements_periods;
DROP POLICY IF EXISTS material_requirements_periods_update ON public.material_requirements_periods;
DROP POLICY IF EXISTS material_requirements_periods_delete ON public.material_requirements_periods;
CREATE POLICY material_requirements_periods_select ON public.material_requirements_periods
  FOR SELECT USING (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY material_requirements_periods_insert ON public.material_requirements_periods
  FOR INSERT WITH CHECK (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY material_requirements_periods_update ON public.material_requirements_periods
  FOR UPDATE USING (account_id = current_user_account_id() OR is_superadmin())
  WITH CHECK (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY material_requirements_periods_delete ON public.material_requirements_periods
  FOR DELETE USING (account_id = current_user_account_id() OR is_superadmin());

-- ---------- stock_alerts ----------
ALTER TABLE public.stock_alerts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS stock_alerts_select ON public.stock_alerts;
DROP POLICY IF EXISTS stock_alerts_insert ON public.stock_alerts;
DROP POLICY IF EXISTS stock_alerts_update ON public.stock_alerts;
DROP POLICY IF EXISTS stock_alerts_delete ON public.stock_alerts;
CREATE POLICY stock_alerts_select ON public.stock_alerts
  FOR SELECT USING (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY stock_alerts_insert ON public.stock_alerts
  FOR INSERT WITH CHECK (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY stock_alerts_update ON public.stock_alerts
  FOR UPDATE USING (account_id = current_user_account_id() OR is_superadmin())
  WITH CHECK (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY stock_alerts_delete ON public.stock_alerts
  FOR DELETE USING (account_id = current_user_account_id() OR is_superadmin());

-- ---------- material_catalog / product_materials: SKIPPED ----------
-- Ambas tablas YA tienen RLS activada en el baseline (00000000000000_baseline_prod_schema.sql,
-- lineas ~8136 y ~8145) con politicas propias mas estrictas que el patron de este ticket:
-- el INSERT exige rol admin/superadmin (no solo account_id = current_user_account_id()).
-- Sobrescribirlas con el patron generico de esta migracion DEBILITARIA la seguridad existente,
-- asi que se dejan intactas. Confirmado en local: relrowsecurity = true para ambas antes de
-- aplicar esta migracion.

-- ---------- ROLLBACK (manual, no aplicar salvo incidente) ----------
-- ALTER TABLE public.material_stocks DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.panelist_material_stocks DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.material_movements DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.material_shipments DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.material_shipment_items DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.stock_settings DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.material_requirements_periods DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE public.stock_alerts DISABLE ROW LEVEL SECURITY;
-- (material_catalog y product_materials no se tocan en esta migracion; ya tenian RLS propia)
