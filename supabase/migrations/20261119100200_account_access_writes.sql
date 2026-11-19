-- Roles y derechos por cuenta, fase 3: la base exige Edit (matriz account_access) para escribir.
-- Spec: docs/superpowers/specs/2026-11-18-roles-derechos-cuenta-design.md
-- Inventario: docs/superpowers/specs/2026-11-18-roles-inventario-escrituras.md
--
-- Se aplica DESPUÉS de desplegar el frontend nuevo (con confirmación expresa, onems-dev sehbnpgzqljrsqimwyuz).
--
-- 1. Comprobación previa: si el cuerpo vivo de alguna función que se reescribe no coincide con el del repo,
--    la migración se detiene sin tocar nada (la BD viva puede ir por delante del repo).
-- 2. Helpers: has_any_access (políticas), require_access / require_edit (funciones SECURITY DEFINER).
--    require_* dejan pasar auth.uid() NULL (n8n por Postgres, pg_cron, ops_*, service_role).
-- 3. Políticas de escritura (INSERT/UPDATE/DELETE) de las tablas que escribe la web: se BORRAN las antiguas
--    (rol legacy 'admin'/'superuser', solo cuenta, duplicadas, superadmin_*) y se crean
--      superadmin  OR  (account_id = cuenta activa AND Edit en alguna opción del inventario).
--    Las políticas SELECT no se tocan (salvo api_keys, cuyo ALL incluía la lectura: se separa en un SELECT
--    equivalente). Se conservan las ALL de superadmin y las de service_role.
-- 4. Funciones SECURITY DEFINER llamadas desde la web: una línea require_edit/require_access tras su guarda
--    de cuenta. plan_undo_authorize (plan_action_*, plan_undo_last) exige allocation_plans:edit;
--    receipt_mgr_check pasa de rol legacy 'admin' a receipts:view (+ receipts:edit en las que escriben;
--    request_case_analysis / send_case_message de tipo 'receipt' exigen receipts:edit).
--    Lecturas de recepciones (receipt_case, incident_message y case_analysis_request de tipo 'receipt'):
--    de rol legacy 'admin' a receipts:view.
-- 5. Sin EXECUTE para authenticated en funciones de mantenimiento entre cuentas sin llamador web.
-- 6. Comprobación final: no queda ninguna política de escritura no prevista en esas tablas.
-- 7. reconstruct_journeys y reprocess_transfer_errors (SECURITY DEFINER sin guarda de cuenta): NO se reescriben
--    (su cuerpo vivo no está verificado contra el repo). Se crean envoltorios con guarda
--    (reconstruct_journeys_for_account, reprocess_transfer_errors_for_account) que la web llama, y se quita
--    EXECUTE a authenticated en los originales. Los llaman también process_rfid_pipeline y
--    rpc_execute_pipeline_phase (SECURITY DEFINER, dueño postgres) y service_role: siguen funcionando.
--
-- Fuera de esta migración (cuerpo vivo por verificar, ver informe de la tarea 9): consolidate_rfid_events.
-- Todo en una sola transacción (incluido rpc_balance_city_v2, al final de la sección 4): no hay un momento con
-- las tablas cerradas y alguna función sin guarda.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '120s';

-- ------------------------------------------------------------------------------------------------ 1. huella
DO $$
DECLARE r record; v_oid regprocedure; v_bad text := '';
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('rpc_balance_city_v2(uuid,date,date,boolean,date)', '6546986e6a04ba8353b8349b64ed9e94'),
    ('rpc_set_account_balance_policy(uuid,text,boolean)', '58d6c5fcca72fc20781ced2ac47013b5'),
    ('rpc_set_pobox_product_shares(uuid,jsonb)', 'aa23a3b244c69ea0b3238d157f0ca332'),
    ('rpc_set_city_balance_policy(uuid,boolean,text,boolean,boolean)', '29e3276f58d4a5cafb3f75f2240e9b27'),
    ('rpc_set_working_day(uuid,integer,boolean)', 'c2871ad4451fe0b31bb3b7d1b1a4a2fc'),
    ('generate_delivery_standards(uuid[],uuid[],uuid[],uuid[])', '33357664bad333996587660b796943bf'),
    ('send_material_shipment(uuid)', '6ab2cf0c1ab0eba69a3a7aa5ffec0e78'),
    ('receive_material_shipment(uuid)', '472f4cf684db5cda84eab970f07a9912'),
    ('resolve_panelist_incident(uuid,text,text,text)', 'ce1c1e09c673d35ee68030d5355240c4'),
    ('cancel_detail(uuid)', 'a61d88668ef7ea98d8eaf3b0373dcd4e'),
    ('create_unavailability_from_incident(uuid,date,date,text)', 'c1057f8ada38943b3dc8b5ea7ed9caeb'),
    ('reroute_returned_sample(uuid,uuid,date)', '589980d364b9f5e4c2659b2c34084083'),
    ('apply_sample_move(uuid,uuid,uuid,date,numeric,numeric)', '7e1e2972ca68699907fa04cfb6f4a635'),
    ('set_incident_resolution(uuid,text)', 'e7dd8946cf608cd784d8c6ff583be357'),
    ('rpc_receipt_case_fix(uuid,uuid)', '3aef2f723a598781963b179d3fa03236'),
    ('rpc_receipt_case_close(uuid,text)', '5d5eaca62d01a182ea33eeed856bf3b8'),
    ('rpc_send_panelist_notice(uuid,text)', '342c8211c124633282e120d909b87155'),
    ('rpc_broadcast_notice(uuid,jsonb)', '713d1ef182c9d33fe7f8a19af3a1ab38'),
    ('send_manager_message(text,uuid,text)', 'c2977eec3a71994638550c57bffd6904'),
    ('request_case_analysis(text,uuid)', '93ab77e752a1be3b8d3a0f1aa67cdafe'),
    ('send_case_message(text,uuid,uuid,text,text)', 'f93d7750012f0e41234468cbed73f061'),
    ('mark_incident_conversation_read(text,uuid)', '21c08bc22a41d091df23c3557e6802df'),
    ('mark_panelist_incident_seen(uuid)', '135b39a66d6a5e1fa33cf2847e59fbfc'),
    ('case_analysis_status(uuid)', 'e922c3bff9af200cf96d16b1662f3003'),
    ('rpc_execute_pipeline_phase(text,uuid)', '87117a9036bc60afd4631560c5f247b4'),
    ('plan_undo_authorize(uuid)', 'a9437b5479c56c1ed40fbd91d4c7d4e0'),
    ('receipt_mgr_check(uuid)', '417e2492ec09392fe8205b52cfc880b8')
  ) h(sig, md5) LOOP
    v_oid := to_regprocedure('public.' || r.sig);
    IF v_oid IS NULL THEN
      v_bad := v_bad || ' ' || r.sig || ' (no existe)';
    ELSIF (SELECT md5(regexp_replace(p.prosrc, '\s', '', 'g')) FROM pg_proc p WHERE p.oid = v_oid) <> r.md5 THEN
      v_bad := v_bad || ' ' || r.sig;
    END IF;
  END LOOP;
  IF v_bad <> '' THEN
    RAISE EXCEPTION 'El cuerpo vivo difiere del repo, revisar antes de aplicar:%', v_bad;
  END IF;
END $$;

-- ------------------------------------------------------------------------------------------------ 2. helpers
-- true si el usuario conectado tiene p_level ('edit' o 'view') en ALGUNA de las opciones en p_account_id.
-- Una sola llamada a my_access (superadmin: todo edit; sin sesión: false).
CREATE OR REPLACE FUNCTION public.has_any_access(p_account_id uuid, p_level text, VARIADIC p_options text[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.my_access(p_account_id) m
     WHERE m.option = ANY (p_options)
       AND (m.level = 'edit' OR (p_level = 'view' AND m.level = 'view'))
  )
$$;

-- Guarda para funciones SECURITY DEFINER. auth.uid() NULL pasa (n8n, cron, ops_*, service_role).
CREATE OR REPLACE FUNCTION public.require_access(p_account_id uuid, p_level text, VARIADIC p_options text[])
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN;
  END IF;
  IF NOT public.has_any_access(p_account_id, p_level, VARIADIC p_options) THEN
    RAISE EXCEPTION 'Forbidden: % right required (%)', p_level, array_to_string(p_options, ' or ')
      USING ERRCODE = '42501';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.require_edit(p_account_id uuid, VARIADIC p_options text[])
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public
AS $$
BEGIN
  PERFORM public.require_access(p_account_id, 'edit', VARIADIC p_options);
END $$;

REVOKE ALL ON FUNCTION public.has_any_access(uuid, text, text[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.require_access(uuid, text, text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.require_edit(uuid, text[]) FROM PUBLIC, anon, authenticated;
-- has_any_access: la evalúan las políticas RLS con el rol del que consulta.
GRANT EXECUTE ON FUNCTION public.has_any_access(uuid, text, text[]) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.require_access(uuid, text, text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.require_edit(uuid, text[]) TO service_role;

-- ------------------------------------------------------------------------------------------------ 3. políticas
-- 3a. Borrar las políticas de escritura antiguas (estado final del repo; IF EXISTS por si la viva no las tiene).
--     Se conservan: las SELECT, las ALL de superadmin (*_superadmin_all), "Service role bypass RLS" (api_keys),
--     superadmin_update_one_db y en profiles las de superadmin y profiles_update_own.
DROP POLICY IF EXISTS "Admins can manage account_config of their account" ON public.account_config;  -- ALL
DROP POLICY IF EXISTS account_config_update_own_account ON public.account_config;  -- UPDATE
DROP POLICY IF EXISTS allocation_plan_details_delete ON public.allocation_plan_details;  -- DELETE
DROP POLICY IF EXISTS superadmin_delete_allocation_plan_details ON public.allocation_plan_details;  -- DELETE
DROP POLICY IF EXISTS allocation_plan_details_insert ON public.allocation_plan_details;  -- INSERT
DROP POLICY IF EXISTS superadmin_insert_allocation_plan_details ON public.allocation_plan_details;  -- INSERT
DROP POLICY IF EXISTS allocation_plan_details_update ON public.allocation_plan_details;  -- UPDATE
DROP POLICY IF EXISTS superadmin_update_allocation_plan_details ON public.allocation_plan_details;  -- UPDATE
DROP POLICY IF EXISTS allocation_plans_delete ON public.allocation_plans;  -- DELETE
DROP POLICY IF EXISTS superadmin_delete_allocation_plans ON public.allocation_plans;  -- DELETE
DROP POLICY IF EXISTS allocation_plans_insert ON public.allocation_plans;  -- INSERT
DROP POLICY IF EXISTS superadmin_insert_allocation_plans ON public.allocation_plans;  -- INSERT
DROP POLICY IF EXISTS allocation_plans_update ON public.allocation_plans;  -- UPDATE
DROP POLICY IF EXISTS superadmin_update_allocation_plans ON public.allocation_plans;  -- UPDATE
DROP POLICY IF EXISTS "Users can manage their account's API keys" ON public.api_keys;  -- ALL
DROP POLICY IF EXISTS carriers_delete ON public.carriers;  -- DELETE
DROP POLICY IF EXISTS superadmin_delete_carriers ON public.carriers;  -- DELETE
DROP POLICY IF EXISTS carriers_insert ON public.carriers;  -- INSERT
DROP POLICY IF EXISTS superadmin_insert_carriers ON public.carriers;  -- INSERT
DROP POLICY IF EXISTS carriers_update ON public.carriers;  -- UPDATE
DROP POLICY IF EXISTS superadmin_update_carriers ON public.carriers;  -- UPDATE
DROP POLICY IF EXISTS cities_delete ON public.cities;  -- DELETE
DROP POLICY IF EXISTS superadmin_delete_cities ON public.cities;  -- DELETE
DROP POLICY IF EXISTS cities_insert ON public.cities;  -- INSERT
DROP POLICY IF EXISTS superadmin_insert_cities ON public.cities;  -- INSERT
DROP POLICY IF EXISTS cities_update ON public.cities;  -- UPDATE
DROP POLICY IF EXISTS superadmin_update_cities ON public.cities;  -- UPDATE
DROP POLICY IF EXISTS delivery_standards_delete ON public.delivery_standards;  -- DELETE
DROP POLICY IF EXISTS superadmin_delete_delivery_standards ON public.delivery_standards;  -- DELETE
DROP POLICY IF EXISTS delivery_standards_insert ON public.delivery_standards;  -- INSERT
DROP POLICY IF EXISTS superadmin_insert_delivery_standards ON public.delivery_standards;  -- INSERT
DROP POLICY IF EXISTS delivery_standards_update ON public.delivery_standards;  -- UPDATE
DROP POLICY IF EXISTS superadmin_update_delivery_standards ON public.delivery_standards;  -- UPDATE
DROP POLICY IF EXISTS generated_allocation_plan_details_delete ON public.generated_allocation_plan_details;  -- DELETE
DROP POLICY IF EXISTS superadmin_delete_generated_allocation_plan_details ON public.generated_allocation_plan_details;  -- DELETE
DROP POLICY IF EXISTS generated_allocation_plan_details_insert ON public.generated_allocation_plan_details;  -- INSERT
DROP POLICY IF EXISTS superadmin_insert_generated_allocation_plan_details ON public.generated_allocation_plan_details;  -- INSERT
DROP POLICY IF EXISTS generated_allocation_plan_details_update ON public.generated_allocation_plan_details;  -- UPDATE
DROP POLICY IF EXISTS superadmin_update_generated_allocation_plan_details ON public.generated_allocation_plan_details;  -- UPDATE
DROP POLICY IF EXISTS generated_allocation_plans_delete ON public.generated_allocation_plans;  -- DELETE
DROP POLICY IF EXISTS superadmin_delete_generated_allocation_plans ON public.generated_allocation_plans;  -- DELETE
DROP POLICY IF EXISTS generated_allocation_plans_insert ON public.generated_allocation_plans;  -- INSERT
DROP POLICY IF EXISTS superadmin_insert_generated_allocation_plans ON public.generated_allocation_plans;  -- INSERT
DROP POLICY IF EXISTS generated_allocation_plans_update ON public.generated_allocation_plans;  -- UPDATE
DROP POLICY IF EXISTS superadmin_update_generated_allocation_plans ON public.generated_allocation_plans;  -- UPDATE
DROP POLICY IF EXISTS incidents_delete_policy ON public.incidents;  -- DELETE
DROP POLICY IF EXISTS incidents_insert_policy ON public.incidents;  -- INSERT
DROP POLICY IF EXISTS incidents_update_policy ON public.incidents;  -- UPDATE
DROP POLICY IF EXISTS journey_segments_delete_policy ON public.journey_segments;  -- DELETE
DROP POLICY IF EXISTS journey_segments_insert_policy ON public.journey_segments;  -- INSERT
DROP POLICY IF EXISTS journey_segments_update_policy ON public.journey_segments;  -- UPDATE
DROP POLICY IF EXISTS journeys_delete_policy ON public.journeys;  -- DELETE
DROP POLICY IF EXISTS journeys_insert_policy ON public.journeys;  -- INSERT
DROP POLICY IF EXISTS journeys_update_policy ON public.journeys;  -- UPDATE
DROP POLICY IF EXISTS material_catalog_delete ON public.material_catalog;  -- DELETE
DROP POLICY IF EXISTS superadmin_delete_material_catalog ON public.material_catalog;  -- DELETE
DROP POLICY IF EXISTS material_catalog_insert ON public.material_catalog;  -- INSERT
DROP POLICY IF EXISTS superadmin_insert_material_catalog ON public.material_catalog;  -- INSERT
DROP POLICY IF EXISTS material_catalog_update ON public.material_catalog;  -- UPDATE
DROP POLICY IF EXISTS superadmin_update_material_catalog ON public.material_catalog;  -- UPDATE
DROP POLICY IF EXISTS material_movements_delete ON public.material_movements;  -- DELETE
DROP POLICY IF EXISTS material_movements_insert ON public.material_movements;  -- INSERT
DROP POLICY IF EXISTS material_movements_update ON public.material_movements;  -- UPDATE
DROP POLICY IF EXISTS material_requirements_periods_delete ON public.material_requirements_periods;  -- DELETE
DROP POLICY IF EXISTS material_requirements_periods_insert ON public.material_requirements_periods;  -- INSERT
DROP POLICY IF EXISTS material_requirements_periods_update ON public.material_requirements_periods;  -- UPDATE
DROP POLICY IF EXISTS material_shipment_items_delete ON public.material_shipment_items;  -- DELETE
DROP POLICY IF EXISTS superadmin_delete_material_shipment_items ON public.material_shipment_items;  -- DELETE
DROP POLICY IF EXISTS material_shipment_items_insert ON public.material_shipment_items;  -- INSERT
DROP POLICY IF EXISTS superadmin_insert_material_shipment_items ON public.material_shipment_items;  -- INSERT
DROP POLICY IF EXISTS material_shipment_items_update ON public.material_shipment_items;  -- UPDATE
DROP POLICY IF EXISTS superadmin_update_material_shipment_items ON public.material_shipment_items;  -- UPDATE
DROP POLICY IF EXISTS material_shipments_delete ON public.material_shipments;  -- DELETE
DROP POLICY IF EXISTS superadmin_delete_material_shipments ON public.material_shipments;  -- DELETE
DROP POLICY IF EXISTS material_shipments_insert ON public.material_shipments;  -- INSERT
DROP POLICY IF EXISTS superadmin_insert_material_shipments ON public.material_shipments;  -- INSERT
DROP POLICY IF EXISTS material_shipments_update ON public.material_shipments;  -- UPDATE
DROP POLICY IF EXISTS superadmin_update_material_shipments ON public.material_shipments;  -- UPDATE
DROP POLICY IF EXISTS material_stocks_delete ON public.material_stocks;  -- DELETE
DROP POLICY IF EXISTS material_stocks_insert ON public.material_stocks;  -- INSERT
DROP POLICY IF EXISTS material_stocks_update ON public.material_stocks;  -- UPDATE
DROP POLICY IF EXISTS nodes_delete ON public.nodes;  -- DELETE
DROP POLICY IF EXISTS superadmin_delete_nodes ON public.nodes;  -- DELETE
DROP POLICY IF EXISTS nodes_insert ON public.nodes;  -- INSERT
DROP POLICY IF EXISTS superadmin_insert_nodes ON public.nodes;  -- INSERT
DROP POLICY IF EXISTS nodes_update ON public.nodes;  -- UPDATE
DROP POLICY IF EXISTS superadmin_update_nodes ON public.nodes;  -- UPDATE
DROP POLICY IF EXISTS "Admins can manage non_working_days of their account" ON public.non_working_days;  -- ALL
DROP POLICY IF EXISTS non_working_days_delete_own_account ON public.non_working_days;  -- DELETE
DROP POLICY IF EXISTS non_working_days_insert_own_account ON public.non_working_days;  -- INSERT
DROP POLICY IF EXISTS non_working_days_update_own_account ON public.non_working_days;  -- UPDATE
DROP POLICY IF EXISTS "Enable delete for authenticated users on own account" ON public.one_db;  -- DELETE
DROP POLICY IF EXISTS superadmin_delete_one_db ON public.one_db;  -- DELETE
DROP POLICY IF EXISTS one_db_insert_policy ON public.one_db;  -- INSERT
DROP POLICY IF EXISTS superadmin_insert_one_db ON public.one_db;  -- INSERT
DROP POLICY IF EXISTS pi_insert ON public.panelist_incident;  -- INSERT
DROP POLICY IF EXISTS pi_update ON public.panelist_incident;  -- UPDATE
DROP POLICY IF EXISTS panelist_material_stocks_delete ON public.panelist_material_stocks;  -- DELETE
DROP POLICY IF EXISTS superadmin_delete_panelist_material_stocks ON public.panelist_material_stocks;  -- DELETE
DROP POLICY IF EXISTS panelist_material_stocks_insert ON public.panelist_material_stocks;  -- INSERT
DROP POLICY IF EXISTS superadmin_insert_panelist_material_stocks ON public.panelist_material_stocks;  -- INSERT
DROP POLICY IF EXISTS panelist_material_stocks_update ON public.panelist_material_stocks;  -- UPDATE
DROP POLICY IF EXISTS superadmin_update_panelist_material_stocks ON public.panelist_material_stocks;  -- UPDATE
DROP POLICY IF EXISTS panelist_unavailability_delete_policy ON public.panelist_unavailability;  -- DELETE
DROP POLICY IF EXISTS superadmin_delete_panelist_unavailability ON public.panelist_unavailability;  -- DELETE
DROP POLICY IF EXISTS unavailability_delete_policy ON public.panelist_unavailability;  -- DELETE
DROP POLICY IF EXISTS panelist_unavailability_insert_policy ON public.panelist_unavailability;  -- INSERT
DROP POLICY IF EXISTS superadmin_insert_panelist_unavailability ON public.panelist_unavailability;  -- INSERT
DROP POLICY IF EXISTS unavailability_insert_policy ON public.panelist_unavailability;  -- INSERT
DROP POLICY IF EXISTS panelist_unavailability_update_policy ON public.panelist_unavailability;  -- UPDATE
DROP POLICY IF EXISTS superadmin_update_panelist_unavailability ON public.panelist_unavailability;  -- UPDATE
DROP POLICY IF EXISTS unavailability_update_policy ON public.panelist_unavailability;  -- UPDATE
DROP POLICY IF EXISTS panelists_delete_policy ON public.panelists;  -- DELETE
DROP POLICY IF EXISTS superadmin_delete_panelists ON public.panelists;  -- DELETE
DROP POLICY IF EXISTS panelists_insert_policy ON public.panelists;  -- INSERT
DROP POLICY IF EXISTS superadmin_insert_panelists ON public.panelists;  -- INSERT
DROP POLICY IF EXISTS panelists_update_policy ON public.panelists;  -- UPDATE
DROP POLICY IF EXISTS superadmin_update_panelists ON public.panelists;  -- UPDATE
DROP POLICY IF EXISTS "Admins can manage postal_centers of their account" ON public.postal_centers;  -- ALL
DROP POLICY IF EXISTS postal_centers_delete_own_account ON public.postal_centers;  -- DELETE
DROP POLICY IF EXISTS postal_centers_insert_own_account ON public.postal_centers;  -- INSERT
DROP POLICY IF EXISTS postal_centers_update_own_account ON public.postal_centers;  -- UPDATE
DROP POLICY IF EXISTS processed_events_delete_policy ON public.processed_events;  -- DELETE
DROP POLICY IF EXISTS processed_events_insert_policy ON public.processed_events;  -- INSERT
DROP POLICY IF EXISTS processed_events_update_policy ON public.processed_events;  -- UPDATE
DROP POLICY IF EXISTS product_materials_delete ON public.product_materials;  -- DELETE
DROP POLICY IF EXISTS product_materials_insert ON public.product_materials;  -- INSERT
DROP POLICY IF EXISTS product_materials_update ON public.product_materials;  -- UPDATE
DROP POLICY IF EXISTS products_delete ON public.products;  -- DELETE
DROP POLICY IF EXISTS superadmin_delete_products ON public.products;  -- DELETE
DROP POLICY IF EXISTS products_insert ON public.products;  -- INSERT
DROP POLICY IF EXISTS superadmin_insert_products ON public.products;  -- INSERT
DROP POLICY IF EXISTS products_update ON public.products;  -- UPDATE
DROP POLICY IF EXISTS superadmin_update_products ON public.products;  -- UPDATE
DROP POLICY IF EXISTS admin_delete_users ON public.profiles;  -- DELETE
DROP POLICY IF EXISTS profile_delete_admin ON public.profiles;  -- DELETE
DROP POLICY IF EXISTS admin_create_users ON public.profiles;  -- INSERT
DROP POLICY IF EXISTS profile_insert_admin ON public.profiles;  -- INSERT
DROP POLICY IF EXISTS profiles_update_admin ON public.profiles;  -- UPDATE
DROP POLICY IF EXISTS "Users can insert reader location history for their account" ON public.reader_location_history;  -- INSERT
DROP POLICY IF EXISTS "Users can update reader location history for their account" ON public.reader_location_history;  -- UPDATE
DROP POLICY IF EXISTS "Admins can manage readers of their account" ON public.readers;  -- ALL
DROP POLICY IF EXISTS readers_delete_own_account ON public.readers;  -- DELETE
DROP POLICY IF EXISTS readers_delete_superadmin ON public.readers;  -- DELETE
DROP POLICY IF EXISTS readers_insert_own_account ON public.readers;  -- INSERT
DROP POLICY IF EXISTS readers_insert_superadmin ON public.readers;  -- INSERT
DROP POLICY IF EXISTS readers_update_own_account ON public.readers;  -- UPDATE
DROP POLICY IF EXISTS readers_update_superadmin ON public.readers;  -- UPDATE
DROP POLICY IF EXISTS regions_delete ON public.regions;  -- DELETE
DROP POLICY IF EXISTS superadmin_delete_regions ON public.regions;  -- DELETE
DROP POLICY IF EXISTS regions_insert ON public.regions;  -- INSERT
DROP POLICY IF EXISTS superadmin_insert_regions ON public.regions;  -- INSERT
DROP POLICY IF EXISTS regions_update ON public.regions;  -- UPDATE
DROP POLICY IF EXISTS superadmin_update_regions ON public.regions;  -- UPDATE
DROP POLICY IF EXISTS rfid_events_raw_delete_policy ON public.rfid_events_raw;  -- DELETE
DROP POLICY IF EXISTS rfid_events_raw_insert_policy ON public.rfid_events_raw;  -- INSERT
DROP POLICY IF EXISTS rfid_events_raw_update_policy ON public.rfid_events_raw;  -- UPDATE
DROP POLICY IF EXISTS slas_delete_policy ON public.slas;  -- DELETE
DROP POLICY IF EXISTS slas_insert_policy ON public.slas;  -- INSERT
DROP POLICY IF EXISTS slas_update_policy ON public.slas;  -- UPDATE
DROP POLICY IF EXISTS stock_alerts_delete ON public.stock_alerts;  -- DELETE
DROP POLICY IF EXISTS stock_alerts_insert ON public.stock_alerts;  -- INSERT
DROP POLICY IF EXISTS stock_alerts_update ON public.stock_alerts;  -- UPDATE
DROP POLICY IF EXISTS stock_settings_delete ON public.stock_settings;  -- DELETE
DROP POLICY IF EXISTS superadmin_delete_stock_settings ON public.stock_settings;  -- DELETE
DROP POLICY IF EXISTS stock_settings_insert ON public.stock_settings;  -- INSERT
DROP POLICY IF EXISTS superadmin_insert_stock_settings ON public.stock_settings;  -- INSERT
DROP POLICY IF EXISTS stock_settings_update ON public.stock_settings;  -- UPDATE
DROP POLICY IF EXISTS superadmin_update_stock_settings ON public.stock_settings;  -- UPDATE
DROP POLICY IF EXISTS "Admins can manage weekly_schedule of their account" ON public.weekly_schedule;  -- ALL
DROP POLICY IF EXISTS weekly_schedule_delete_own_account ON public.weekly_schedule;  -- DELETE
DROP POLICY IF EXISTS weekly_schedule_insert_own_account ON public.weekly_schedule;  -- INSERT
DROP POLICY IF EXISTS weekly_schedule_update_own_account ON public.weekly_schedule;  -- UPDATE

-- api_keys: su ALL de cuenta era también la lectura; se mantiene la lectura igual (cuenta activa).
CREATE POLICY api_keys_select_own_account ON public.api_keys
  FOR SELECT TO authenticated
  USING (account_id = (SELECT public.current_user_account_id()));

-- 3b. Nuevas políticas: superadmin OR (cuenta activa AND Edit en alguna opción).
--     has_any_access(current_user_account_id(), ...) no depende de la fila (la fila ya se exige de la cuenta
--     activa), así que va en (SELECT ...) y se calcula una vez por sentencia.
DO $$
DECLARE r record; v_opts text; v_expr text; c text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    -- E2E Setup
    ('regions',                           ARRAY['topology'],                                        ARRAY['INSERT','UPDATE','DELETE']),
    ('cities',                            ARRAY['topology'],                                        ARRAY['INSERT','UPDATE','DELETE']),
    ('nodes',                             ARRAY['topology'],                                        ARRAY['INSERT','UPDATE','DELETE']),
    ('panelists',                         ARRAY['panelists','topology'],                            ARRAY['INSERT','UPDATE','DELETE']),
    ('panelist_unavailability',           ARRAY['panelists'],                                       ARRAY['INSERT','UPDATE','DELETE']),
    ('carriers',                          ARRAY['carriers'],                                        ARRAY['INSERT','UPDATE','DELETE']),
    ('products',                          ARRAY['carriers'],                                        ARRAY['INSERT','UPDATE','DELETE']),
    ('product_materials',                 ARRAY['carriers'],                                        ARRAY['INSERT','UPDATE','DELETE']),
    ('material_catalog',                  ARRAY['material_catalog','carriers'],                     ARRAY['INSERT','UPDATE','DELETE']),
    ('delivery_standards',                ARRAY['e2e_sla'],                                         ARRAY['INSERT','UPDATE','DELETE']),
    -- E2E Allocation
    ('generated_allocation_plans',        ARRAY['allocation_generator'],                            ARRAY['INSERT','UPDATE','DELETE']),
    ('generated_allocation_plan_details', ARRAY['allocation_generator'],                            ARRAY['INSERT','UPDATE','DELETE']),
    ('allocation_plans',                  ARRAY['allocation_generator'],                            ARRAY['INSERT','UPDATE','DELETE']),
    ('allocation_plan_details',           ARRAY['allocation_generator','allocation_plans'],         ARRAY['INSERT','UPDATE','DELETE']),
    -- E2E Materials (stock_alerts: también lo actualiza el trigger auto_resolve_stock_alerts, INVOKER,
    -- al escribir material_stocks / panelist_material_stocks)
    ('panelist_material_stocks',          ARRAY['allocation_plans','stock_management','reported_incidents'], ARRAY['INSERT','UPDATE','DELETE']),
    ('material_movements',                ARRAY['allocation_plans','stock_management','reported_incidents'], ARRAY['INSERT','UPDATE','DELETE']),
    ('stock_alerts',                      ARRAY['allocation_plans','stock_management','reported_incidents'], ARRAY['INSERT','UPDATE','DELETE']),
    ('material_requirements_periods',     ARRAY['stock_management','reported_incidents'],           ARRAY['INSERT','UPDATE','DELETE']),
    ('material_stocks',                   ARRAY['stock_management'],                                ARRAY['INSERT','UPDATE','DELETE']),
    ('material_shipments',                ARRAY['stock_management','reported_incidents'],           ARRAY['INSERT','UPDATE','DELETE']),
    ('material_shipment_items',           ARRAY['stock_management','reported_incidents'],           ARRAY['INSERT','UPDATE','DELETE']),
    ('stock_settings',                    ARRAY['stock_management'],                                ARRAY['INSERT','UPDATE','DELETE']),
    -- E2E Database
    ('one_db',                            ARRAY['account_working_days'],                            ARRAY['INSERT']),
    ('one_db',                            ARRAY['e2e_db'],                                          ARRAY['DELETE']),
    ('api_keys',                          ARRAY['e2e_db_api'],                                      ARRAY['INSERT','UPDATE','DELETE']),
    -- RFID (consolidate_rfid_events y assemble_journeys son INVOKER: la RLS aplica)
    ('postal_centers',                    ARRAY['postal_centers'],                                  ARRAY['INSERT','UPDATE','DELETE']),
    ('readers',                           ARRAY['postal_centers','readers_management'],             ARRAY['INSERT','UPDATE','DELETE']),
    ('slas',                              ARRAY['segment_sla'],                                     ARRAY['INSERT','UPDATE','DELETE']),
    ('incidents',                         ARRAY['epcis_api'],                                       ARRAY['INSERT','UPDATE','DELETE']),
    ('rfid_events_raw',                   ARRAY['epcis_api'],                                       ARRAY['INSERT','UPDATE','DELETE']),
    ('processed_events',                  ARRAY['epcis_api','route_analysis'],                      ARRAY['INSERT','UPDATE','DELETE']),
    ('journey_segments',                  ARRAY['epcis_api','route_analysis'],                      ARRAY['INSERT','UPDATE','DELETE']),
    ('journeys',                          ARRAY['epcis_api','route_analysis'],                      ARRAY['INSERT','UPDATE','DELETE']),
    -- Incidencias (el resto de escrituras va por funciones SECURITY DEFINER); sin DELETE, como antes
    ('panelist_incident',                 ARRAY['reported_incidents'],                              ARRAY['INSERT','UPDATE']),
    -- Administración / calendario (rpc_set_working_day de Load Balancing escribe weekly_schedule)
    ('account_config',                    ARRAY['account_working_days'],                            ARRAY['INSERT','UPDATE','DELETE']),
    ('weekly_schedule',                   ARRAY['account_working_days','postal_centers','load_balancing'], ARRAY['INSERT','UPDATE','DELETE']),
    ('non_working_days',                  ARRAY['account_working_days','postal_centers'],           ARRAY['INSERT','UPDATE','DELETE'])
  ) t(tbl, opts, cmds) LOOP
    SELECT string_agg(quote_literal(o), ', ') INTO v_opts FROM unnest(r.opts) o;
    v_expr := format('(SELECT public.is_superadmin()) OR (account_id = (SELECT public.current_user_account_id()) '
                     'AND (SELECT public.has_any_access(public.current_user_account_id(), ''edit'', %s)))', v_opts);
    FOREACH c IN ARRAY r.cmds LOOP
      IF c = 'INSERT' THEN
        EXECUTE format('CREATE POLICY %I ON public.%I FOR INSERT TO authenticated WITH CHECK (%s)',
                       r.tbl || '_insert_edit', r.tbl, v_expr);
      ELSIF c = 'UPDATE' THEN
        EXECUTE format('CREATE POLICY %I ON public.%I FOR UPDATE TO authenticated USING (%s) WITH CHECK (%s)',
                       r.tbl || '_update_edit', r.tbl, v_expr, v_expr);
      ELSE
        EXECUTE format('CREATE POLICY %I ON public.%I FOR DELETE TO authenticated USING (%s)',
                       r.tbl || '_delete_edit', r.tbl, v_expr);
      END IF;
    END LOOP;
  END LOOP;
END $$;

-- reader_location_history no tiene account_id: cuenta por el lector (como antes). La escriben
-- assign_reader_to_center (INVOKER, Readers Management) y el trigger log_reader_location_change al mover un
-- lector (Postal Centers o Readers Management). Sin DELETE, como antes.
CREATE POLICY reader_location_history_insert_edit ON public.reader_location_history
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT public.is_superadmin())
    OR (EXISTS (SELECT 1 FROM public.readers r
                 WHERE r.id = reader_location_history.reader_id
                   AND r.account_id = (SELECT public.current_user_account_id()))
        AND (SELECT public.has_any_access(public.current_user_account_id(), 'edit',
                                          'readers_management', 'postal_centers'))));
CREATE POLICY reader_location_history_update_edit ON public.reader_location_history
  FOR UPDATE TO authenticated
  USING ((SELECT public.is_superadmin())
    OR (EXISTS (SELECT 1 FROM public.readers r
                 WHERE r.id = reader_location_history.reader_id
                   AND r.account_id = (SELECT public.current_user_account_id()))
        AND (SELECT public.has_any_access(public.current_user_account_id(), 'edit',
                                          'readers_management', 'postal_centers'))))
  WITH CHECK ((SELECT public.is_superadmin())
    OR (EXISTS (SELECT 1 FROM public.readers r
                 WHERE r.id = reader_location_history.reader_id
                   AND r.account_id = (SELECT public.current_user_account_id()))
        AND (SELECT public.has_any_access(public.current_user_account_id(), 'edit',
                                          'readers_management', 'postal_centers'))));

-- profiles (Users): las reglas de rol legacy 'admin' pasan a users:edit en la cuenta activa. Con users:edit NO se
-- sube a nadie (ni a uno mismo) a 'admin' ni 'superadmin': se crea solo con rol 'user' y al editar, el rol queda
-- 'user' o como estaba (profile_stored_role lee la fila antes del UPDATE). Solo el superadmin cambia el rol de
-- 'user' a otro. Siguen profiles_update_own (idioma, etc.; no puede cambiar su rol) y las de superadmin.
-- El alta/baja real va por las edge create-user/delete-user (service_role).
CREATE OR REPLACE FUNCTION public.profile_stored_role(p_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public
AS $$
  SELECT p.role FROM public.profiles p WHERE p.id = p_id
$$;
REVOKE ALL ON FUNCTION public.profile_stored_role(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.profile_stored_role(uuid) TO authenticated, service_role;

CREATE POLICY profiles_insert_users_edit ON public.profiles
  FOR INSERT TO authenticated
  WITH CHECK (account_id = (SELECT public.current_user_account_id())
              AND role = 'user'
              AND (SELECT public.has_any_access(public.current_user_account_id(), 'edit', 'users')));
CREATE POLICY profiles_update_users_edit ON public.profiles
  FOR UPDATE TO authenticated
  USING (account_id = (SELECT public.current_user_account_id())
         AND role <> 'superadmin'
         AND (SELECT public.has_any_access(public.current_user_account_id(), 'edit', 'users')))
  WITH CHECK (account_id = (SELECT public.current_user_account_id())
              AND (role = 'user' OR (role = 'admin' AND role = public.profile_stored_role(id)))
              AND (SELECT public.has_any_access(public.current_user_account_id(), 'edit', 'users')));
CREATE POLICY profiles_delete_users_edit ON public.profiles
  FOR DELETE TO authenticated
  USING (account_id = (SELECT public.current_user_account_id())
         AND role <> 'superadmin'
         AND (SELECT public.has_any_access(public.current_user_account_id(), 'edit', 'users')));

-- 3c. Lecturas de recepciones: del rol legacy 'admin' a receipts:view en la cuenta activa. Las ramas que no son de
--     recepción de incident_message y case_analysis_request quedan exactamente igual.
--     Rendimiento: aquí has_access(account_id, ...) recibe la cuenta DE LA FILA, así que no se puede sacar a un
--     (SELECT ...) de una vez por sentencia como en 3b; se evalúa por fila (función STABLE, barata). Igual en
--     profile_select_users_access (20261119100160, ya aplicada). Sin cambio de semántica.
DROP POLICY IF EXISTS receipt_case_select ON public.receipt_case;
CREATE POLICY receipt_case_select ON public.receipt_case
  FOR SELECT TO authenticated
  USING (public.is_superadmin()
         OR (account_id = public.current_user_account_id() AND public.has_access(account_id, 'receipts', 'view')));

DROP POLICY IF EXISTS incident_message_select ON public.incident_message;
CREATE POLICY incident_message_select ON public.incident_message
  FOR SELECT TO authenticated
  USING (
    is_superadmin()
    OR (incident_kind <> 'receipt' AND account_id = current_user_account_id())
    OR (incident_kind = 'receipt' AND account_id = current_user_account_id()
        AND public.has_access(account_id, 'receipts', 'view'))
  );

DROP POLICY IF EXISTS case_analysis_request_select ON public.case_analysis_request;
CREATE POLICY case_analysis_request_select ON public.case_analysis_request
  FOR SELECT TO authenticated
  USING (public.is_superadmin()
          OR (incident_kind <> 'receipt' AND account_id = public.current_user_account_id())
          OR (incident_kind = 'receipt' AND account_id = public.current_user_account_id()
              AND public.has_access(account_id, 'receipts', 'view')));

-- ------------------------------------------------------------------------------------------------ 4. funciones
-- 4a. A mano: plan_undo_authorize (guarda común de plan_action_create/update/delete y plan_undo_last).
CREATE OR REPLACE FUNCTION public.plan_undo_authorize(p_account_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;
  IF p_account_id IS NULL
     OR NOT (p_account_id = public.current_user_account_id() OR public.is_superadmin()) THEN
    RAISE EXCEPTION 'Sin permiso sobre la cuenta %', p_account_id USING ERRCODE = 'insufficient_privilege';
  END IF;
  PERFORM public.require_edit(p_account_id, 'allocation_plans');  -- fase 3: derecho Edit/View de la matriz
END $function$;

-- 4b. receipt_mgr_check: antes exigía profiles.role = 'admin'. Ahora receipts:view en la cuenta activa
--     (la usan también lecturas y marcas de leído); las funciones que escriben añaden receipts:edit.
CREATE OR REPLACE FUNCTION public.receipt_mgr_check(p_account_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_superadmin() THEN
    IF p_account_id IS DISTINCT FROM public.current_user_account_id()
       OR NOT public.has_access(p_account_id, 'receipts', 'view') THEN
      RAISE EXCEPTION 'No autorizado para esta cuenta' USING ERRCODE = '42501';
    END IF;
  END IF;
END;
$function$;

-- 4c. Cuerpo actual del repo + una línea de guarda (marcada "fase 3").

-- rpc_set_account_balance_policy(uuid,text,boolean): PERFORM public.require_edit(p_account_id, 'load_balancing');
CREATE OR REPLACE FUNCTION public.rpc_set_account_balance_policy(p_account_id uuid, p_date_policy text DEFAULT NULL::text, p_pobox_enabled boolean DEFAULT NULL::boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_row public.account_config%ROWTYPE;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_superadmin()
     AND p_account_id IS DISTINCT FROM (SELECT p.account_id FROM public.profiles p WHERE p.id = auth.uid()) THEN
    RAISE EXCEPTION 'No autorizado para esta cuenta' USING ERRCODE = '42501';
  END IF;
  PERFORM public.require_edit(p_account_id, 'load_balancing');  -- fase 3: derecho Edit/View de la matriz
  IF p_date_policy IS NOT NULL AND p_date_policy NOT IN ('weekly', 'daily') THEN
    RAISE EXCEPTION 'date_policy invalida: %', p_date_policy USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.id = p_account_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Account not found');
  END IF;

  INSERT INTO public.account_config AS ac (account_id, calculation_mode, date_policy, pobox_enabled, created_by, updated_by)
  VALUES (p_account_id, 'natural_days', COALESCE(p_date_policy, 'daily'), COALESCE(p_pobox_enabled, false),
          auth.uid(), auth.uid())
  ON CONFLICT (account_id) DO UPDATE
     SET date_policy   = COALESCE(p_date_policy, ac.date_policy),
         pobox_enabled = COALESCE(p_pobox_enabled, ac.pobox_enabled),
         updated_at    = now(),
         updated_by    = auth.uid()
  RETURNING ac.* INTO v_row;

  RETURN jsonb_build_object('success', true, 'date_policy', v_row.date_policy, 'pobox_enabled', v_row.pobox_enabled);
END;
$function$;

-- rpc_set_pobox_product_shares(uuid,jsonb): PERFORM public.require_edit(p_account_id, 'load_balancing');
CREATE OR REPLACE FUNCTION public.rpc_set_pobox_product_shares(p_account_id uuid, p_shares jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_clean jsonb;
  v_sum   integer;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_superadmin()
     AND p_account_id IS DISTINCT FROM (SELECT p.account_id FROM public.profiles p WHERE p.id = auth.uid()) THEN
    RAISE EXCEPTION 'No autorizado para esta cuenta' USING ERRCODE = '42501';
  END IF;
  PERFORM public.require_edit(p_account_id, 'load_balancing');  -- fase 3: derecho Edit/View de la matriz
  IF NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.id = p_account_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Account not found');
  END IF;
  IF p_shares IS NULL OR jsonb_typeof(p_shares) <> 'array' THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_shares');
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_shares) s
              WHERE jsonb_typeof(s->'pct') IS DISTINCT FROM 'number'
                 OR (s->>'pct')::numeric <> floor((s->>'pct')::numeric)
                 OR (s->>'pct')::numeric < 0 OR (s->>'pct')::numeric > 100
                 OR NOT EXISTS (SELECT 1 FROM public.products pr
                                 WHERE pr.id::text = s->>'product_id' AND pr.account_id = p_account_id)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'invalid_shares');
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object('product_id', d.pid, 'pct', d.pct) ORDER BY d.pid), '[]'::jsonb),
         COALESCE(sum(d.pct), 0)
    INTO v_clean, v_sum
    FROM (SELECT DISTINCT ON (s->>'product_id') (s->>'product_id')::uuid AS pid, (s->>'pct')::int AS pct
            FROM jsonb_array_elements(p_shares) s
           WHERE (s->>'pct')::int > 0
           ORDER BY s->>'product_id') d;
  IF v_sum <> 0 AND v_sum <> 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'shares_must_sum_100');
  END IF;

  INSERT INTO public.account_config AS ac (account_id, calculation_mode, pobox_product_shares, created_by, updated_by)
  VALUES (p_account_id, 'natural_days', v_clean, auth.uid(), auth.uid())
  ON CONFLICT (account_id) DO UPDATE
     SET pobox_product_shares = v_clean, updated_at = now(), updated_by = auth.uid();
  RETURN jsonb_build_object('success', true, 'shares', v_clean);
END;
$function$;

-- rpc_set_city_balance_policy(uuid,boolean,text,boolean,boolean): PERFORM public.require_edit(v_account_id, 'load_balancing');
CREATE OR REPLACE FUNCTION public.rpc_set_city_balance_policy(p_city_id uuid, p_set_date_policy boolean, p_date_policy text, p_set_pobox boolean, p_pobox_enabled boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_account_id uuid;
  v_date_policy text;
  v_pobox boolean;
BEGIN
  SELECT c.account_id INTO v_account_id FROM public.cities c WHERE c.id = p_city_id;
  IF v_account_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'City not found');
  END IF;
  IF auth.uid() IS NOT NULL AND NOT public.is_superadmin()
     AND v_account_id IS DISTINCT FROM (SELECT p.account_id FROM public.profiles p WHERE p.id = auth.uid()) THEN
    RAISE EXCEPTION 'No autorizado para esta cuenta' USING ERRCODE = '42501';
  END IF;
  PERFORM public.require_edit(v_account_id, 'load_balancing');  -- fase 3: derecho Edit/View de la matriz
  IF COALESCE(p_set_date_policy, false) AND p_date_policy IS NOT NULL AND p_date_policy NOT IN ('weekly', 'daily') THEN
    RAISE EXCEPTION 'date_policy invalida: %', p_date_policy USING ERRCODE = '22023';
  END IF;

  UPDATE public.cities c
     SET date_policy   = CASE WHEN COALESCE(p_set_date_policy, false) THEN p_date_policy ELSE c.date_policy END,
         pobox_enabled = CASE WHEN COALESCE(p_set_pobox, false) THEN p_pobox_enabled ELSE c.pobox_enabled END
   WHERE c.id = p_city_id
  RETURNING c.date_policy, c.pobox_enabled INTO v_date_policy, v_pobox;

  RETURN jsonb_build_object('success', true, 'date_policy', v_date_policy, 'pobox_enabled', v_pobox);
END;
$function$;

-- rpc_set_working_day(uuid,integer,boolean): PERFORM public.require_edit(p_account_id, 'load_balancing', 'account_working_days');
CREATE OR REPLACE FUNCTION public.rpc_set_working_day(p_account_id uuid, p_day_of_week integer, p_is_working boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_superadmin()
     AND p_account_id IS DISTINCT FROM (SELECT p.account_id FROM public.profiles p WHERE p.id = auth.uid()) THEN
    RAISE EXCEPTION 'No autorizado para esta cuenta' USING ERRCODE = '42501';
  END IF;
  PERFORM public.require_edit(p_account_id, 'load_balancing', 'account_working_days');  -- fase 3: derecho Edit/View de la matriz
  IF p_day_of_week IS NULL OR p_day_of_week NOT BETWEEN 0 AND 6 OR p_is_working IS NULL THEN
    RAISE EXCEPTION 'Dia de la semana invalido: %', p_day_of_week USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.accounts a WHERE a.id = p_account_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Account not found');
  END IF;

  -- Serializa la siembra (el UNIQUE no protege con postal_center_id NULL).
  PERFORM pg_advisory_xact_lock(hashtext('weekly_schedule:' || p_account_id::text));

  INSERT INTO public.weekly_schedule (account_id, postal_center_id, day_of_week, is_working_day, opening_hour, cutoff_time,
                                      created_by, updated_by)
  SELECT p_account_id, NULL, d, d BETWEEN 1 AND 5,
         CASE WHEN d BETWEEN 1 AND 5 THEN '08:00'::time END, CASE WHEN d BETWEEN 1 AND 5 THEN '18:00'::time END,
         auth.uid(), auth.uid()
    FROM generate_series(0, 6) d
   WHERE NOT EXISTS (SELECT 1 FROM public.weekly_schedule w
                      WHERE w.account_id = p_account_id AND w.postal_center_id IS NULL AND w.day_of_week = d);

  UPDATE public.weekly_schedule w
     SET is_working_day = p_is_working,
         opening_hour = CASE WHEN p_is_working AND (w.opening_hour IS NULL OR w.cutoff_time IS NULL)
                             THEN '08:00'::time ELSE w.opening_hour END,
         cutoff_time  = CASE WHEN p_is_working AND (w.opening_hour IS NULL OR w.cutoff_time IS NULL)
                             THEN '18:00'::time ELSE w.cutoff_time END,
         updated_at = now(),
         updated_by = auth.uid()
   WHERE w.account_id = p_account_id AND w.postal_center_id IS NULL AND w.day_of_week = p_day_of_week;

  RETURN jsonb_build_object('success', true);
END;
$function$;

-- generate_delivery_standards(uuid[],uuid[],uuid[],uuid[]): PERFORM public.require_edit(v_account_id, 'e2e_sla');
CREATE OR REPLACE FUNCTION public.generate_delivery_standards(p_carrier_ids uuid[] DEFAULT NULL::uuid[], p_product_ids uuid[] DEFAULT NULL::uuid[], p_origin_city_ids uuid[] DEFAULT NULL::uuid[], p_destination_city_ids uuid[] DEFAULT NULL::uuid[])
 RETURNS TABLE(inserted_count integer, skipped_count integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$

DECLARE

  v_account_id UUID;

  v_carrier_id UUID;

  v_product_id UUID;

  v_origin_city_id UUID;

  v_destination_city_id UUID;

  v_inserted INTEGER := 0;

  v_skipped INTEGER := 0;

  v_carriers UUID[];

  v_products UUID[];

  v_origin_cities UUID[];

  v_destination_cities UUID[];

  v_carrier_products UUID[];

BEGIN

  -- Get current user's account_id

  v_account_id := current_user_account_id();

  PERFORM public.require_edit(v_account_id, 'e2e_sla');  -- fase 3: derecho Edit/View de la matriz
  

  -- If no carriers specified, get ALL carriers for the account

  IF p_carrier_ids IS NULL OR array_length(p_carrier_ids, 1) IS NULL THEN

    SELECT ARRAY_AGG(id) INTO v_carriers

    FROM carriers

    WHERE account_id = v_account_id AND status = 'active';

  ELSE

    v_carriers := p_carrier_ids;

  END IF;

  

  -- If no origin cities specified, get ALL cities for the account

  IF p_origin_city_ids IS NULL OR array_length(p_origin_city_ids, 1) IS NULL THEN

    SELECT ARRAY_AGG(id) INTO v_origin_cities

    FROM cities

    WHERE account_id = v_account_id AND status = 'active';

  ELSE

    v_origin_cities := p_origin_city_ids;

  END IF;

  

  -- If no destination cities specified, get ALL cities for the account

  IF p_destination_city_ids IS NULL OR array_length(p_destination_city_ids, 1) IS NULL THEN

    SELECT ARRAY_AGG(id) INTO v_destination_cities

    FROM cities

    WHERE account_id = v_account_id AND status = 'active';

  ELSE

    v_destination_cities := p_destination_city_ids;

  END IF;

  

  -- Loop through carriers

  FOREACH v_carrier_id IN ARRAY v_carriers

  LOOP

    -- Get products for this carrier

    -- If products were specified, filter to only those that belong to this carrier

    -- If no products specified, get ALL products for this carrier

    IF p_product_ids IS NULL OR array_length(p_product_ids, 1) IS NULL THEN

      -- Get ALL products for this carrier

      SELECT ARRAY_AGG(id) INTO v_carrier_products

      FROM products

      WHERE carrier_id = v_carrier_id AND status = 'active';

    ELSE

      -- Get only specified products that belong to this carrier

      SELECT ARRAY_AGG(id) INTO v_carrier_products

      FROM products

      WHERE carrier_id = v_carrier_id 

        AND id = ANY(p_product_ids)

        AND status = 'active';

    END IF;

    

    -- Skip if no products found for this carrier

    IF v_carrier_products IS NULL OR array_length(v_carrier_products, 1) IS NULL THEN

      CONTINUE;

    END IF;

    

    -- Loop through products of this carrier

    FOREACH v_product_id IN ARRAY v_carrier_products

    LOOP

      -- Loop through origin cities

      FOREACH v_origin_city_id IN ARRAY v_origin_cities

      LOOP

        -- Loop through destination cities

        FOREACH v_destination_city_id IN ARRAY v_destination_cities

        LOOP

          -- Skip if same city

          IF v_origin_city_id != v_destination_city_id THEN

            -- Try to insert, skip if already exists

            BEGIN

              INSERT INTO delivery_standards (

                carrier_id,

                product_id,

                origin_city_id,

                destination_city_id

              ) VALUES (

                v_carrier_id,

                v_product_id,

                v_origin_city_id,

                v_destination_city_id

              );

              v_inserted := v_inserted + 1;

            EXCEPTION WHEN unique_violation THEN

              v_skipped := v_skipped + 1;

            END;

          END IF;

        END LOOP;

      END LOOP;

    END LOOP;

  END LOOP;

  

  RETURN QUERY SELECT v_inserted, v_skipped;

END;

$function$;

-- send_material_shipment(uuid): PERFORM public.require_edit(v_ship.account_id, 'stock_management');
CREATE OR REPLACE FUNCTION public.send_material_shipment(p_shipment_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ship   public.material_shipments%rowtype;
  v_item   record;
BEGIN
  SELECT * INTO v_ship FROM public.material_shipments WHERE id = p_shipment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'shipment % not found', p_shipment_id; END IF;
  PERFORM public.assert_same_account(v_ship.account_id);
  PERFORM public.require_edit(v_ship.account_id, 'stock_management');  -- fase 3: derecho Edit/View de la matriz

  IF v_ship.status <> 'pending' THEN
    RETURN; -- idempotente: ya enviado/recibido/cancelado
  END IF;

  FOR v_item IN
    SELECT material_id, quantity_sent
      FROM public.material_shipment_items
     WHERE material_shipment_id = p_shipment_id
  LOOP
    IF v_ship.source_panelist_id IS NULL THEN
      -- Origen: almacen central del regulador.
      UPDATE public.material_stocks
         SET quantity = greatest(0, quantity - v_item.quantity_sent),
             last_updated = now()
       WHERE account_id = v_ship.account_id
         AND material_id = v_item.material_id;
    ELSE
      -- Origen: panelista donante.
      UPDATE public.panelist_material_stocks
         SET quantity = greatest(0, quantity - v_item.quantity_sent),
             last_updated = now()
       WHERE account_id = v_ship.account_id
         AND panelist_id = v_ship.source_panelist_id
         AND material_id = v_item.material_id;
    END IF;

    INSERT INTO public.material_movements
      (account_id, material_id, movement_type, quantity, reference_id, notes, created_by)
    VALUES
      (v_ship.account_id, v_item.material_id, 'dispatch', v_item.quantity_sent,
       p_shipment_id,
       CASE WHEN v_ship.source_panelist_id IS NULL
            THEN 'Dispatch central -> panelista'
            ELSE 'Dispatch donante -> panelista' END,
       auth.uid());
  END LOOP;

  UPDATE public.material_shipments
     SET status = 'sent', shipment_date = coalesce(shipment_date, now()),
         ask_count = 0,
         next_ask_at = CASE WHEN v_ship.source_panelist_id IS NULL
                            THEN COALESCE(v_ship.expected_date::timestamptz, now() + interval '2 days')
                            ELSE now() + interval '2 days' END
   WHERE id = p_shipment_id;
END;
$function$;

-- receive_material_shipment(uuid): PERFORM public.require_edit(v_ship.account_id, 'stock_management');
CREATE OR REPLACE FUNCTION public.receive_material_shipment(p_shipment_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_ship  public.material_shipments%rowtype;
  v_items jsonb;
BEGIN
  SELECT * INTO v_ship FROM public.material_shipments WHERE id = p_shipment_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'shipment % not found', p_shipment_id; END IF;
  PERFORM public.assert_same_account(v_ship.account_id);
  PERFORM public.require_edit(v_ship.account_id, 'stock_management');  -- fase 3: derecho Edit/View de la matriz
  IF v_ship.status = 'received' THEN RETURN; END IF;
  IF v_ship.status NOT IN ('sent','partially_received') THEN
    RAISE EXCEPTION 'shipment % in status % cannot be received', p_shipment_id, v_ship.status;
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'material_id', material_id,
           'quantity', quantity_sent - coalesce(quantity_received, 0))), '[]'::jsonb)
    INTO v_items
    FROM public.material_shipment_items
   WHERE material_shipment_id = p_shipment_id;

  PERFORM public.receive_material_shipment_items(p_shipment_id, v_items);
END;
$function$;

-- resolve_panelist_incident(uuid,text,text,text): PERFORM public.require_edit(v_account, 'reported_incidents');
CREATE OR REPLACE FUNCTION public.resolve_panelist_incident(p_incident_id uuid, p_status text, p_resolution_note text DEFAULT NULL::text, p_reply_text text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_account uuid; v_old text; v_panelist uuid; v_cat text;
BEGIN
  SELECT account_id, status, panelist_id, category INTO v_account, v_old, v_panelist, v_cat
    FROM panelist_incident WHERE id = p_incident_id;
  PERFORM assert_same_account(v_account);
  PERFORM public.require_edit(v_account, 'reported_incidents');  -- fase 3: derecho Edit/View de la matriz
  IF p_status NOT IN ('open','in_progress','resolved','dismissed') THEN
    RAISE EXCEPTION 'invalid status %', p_status; END IF;
  UPDATE panelist_incident SET
    status = p_status,
    resolution_note = COALESCE(p_resolution_note, resolution_note),
    reply_to_panelist = COALESCE(p_reply_text, reply_to_panelist),
    reply_status = CASE WHEN p_reply_text IS NOT NULL THEN 'pending_send' ELSE reply_status END,
    resolved_by = CASE WHEN p_status IN ('resolved','dismissed') THEN auth.uid() ELSE resolved_by END,
    resolved_at = CASE WHEN p_status IN ('resolved','dismissed') THEN now() ELSE resolved_at END,
    updated_at = now()
  WHERE id = p_incident_id;
  -- Efecto central (sin WARNING): al cerrar una incidencia de material, se liberan los envios retenidos.
  IF v_cat = 'missing_materials' AND p_status IN ('resolved','dismissed') THEN
    PERFORM public.refresh_material_hold(v_panelist);
  END IF;
  IF v_old IS DISTINCT FROM p_status THEN
    BEGIN
      PERFORM public.log_incident_message('reported', p_incident_id, 'internal', 'system',
        'Estado: ' || p_status || COALESCE(' - ' || p_resolution_note, ''),
        jsonb_build_object('status', p_status), 'sent');
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'resolve_panelist_incident: estado de la incidencia % no registrado: %', p_incident_id, SQLERRM;
    END;
  END IF;
END; $function$;

-- cancel_detail(uuid): PERFORM public.require_edit(v_account, 'reported_incidents');
CREATE OR REPLACE FUNCTION public.cancel_detail(p_detail_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_account uuid;
BEGIN
  SELECT account_id INTO v_account FROM allocation_plan_details WHERE id = p_detail_id;
  PERFORM assert_same_account(v_account);
  PERFORM public.require_edit(v_account, 'reported_incidents');  -- fase 3: derecho Edit/View de la matriz
  UPDATE allocation_plan_details SET status = 'cancelled', updated_at = now() WHERE id = p_detail_id;
END; $function$;

-- create_unavailability_from_incident(uuid,date,date,text): PERFORM public.require_edit(v_account, 'reported_incidents');
CREATE OR REPLACE FUNCTION public.create_unavailability_from_incident(p_incident_id uuid, p_start date, p_end date, p_reason text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_account uuid; v_panelist uuid; v_new uuid;
BEGIN
  SELECT account_id, panelist_id INTO v_account, v_panelist
    FROM panelist_incident WHERE id = p_incident_id;
  PERFORM assert_same_account(v_account);
  PERFORM public.require_edit(v_account, 'reported_incidents');  -- fase 3: derecho Edit/View de la matriz
  IF p_start IS NULL OR p_end IS NULL OR p_end < p_start THEN
    RAISE EXCEPTION 'invalid date range'; END IF;
  -- panelist_unavailability.reason es NOT NULL con CHECK IN
  -- ('vacation','sick_leave','personal','training','other','materials'); si el llamador no
  -- pasa un valor valido, usamos 'other' para no romper la constraint.
  INSERT INTO panelist_unavailability (account_id, panelist_id, start_date, end_date, reason, status)
  VALUES (
    v_account, v_panelist, p_start, p_end,
    CASE WHEN p_reason IN ('vacation','sick_leave','personal','training','other','materials')
         THEN p_reason ELSE 'other' END,
    'active')
  RETURNING id INTO v_new;  -- el trigger generate_proposals_on_unavailability_trigger dispara el motor
  UPDATE panelist_incident SET linked_unavailability_id = v_new, status = 'in_progress', updated_at = now()
  WHERE id = p_incident_id;
  RETURN v_new;
END; $function$;

-- reroute_returned_sample(uuid,uuid,date): PERFORM public.require_edit(v_d.account_id, 'reported_incidents');
CREATE OR REPLACE FUNCTION public.reroute_returned_sample(p_detail_id uuid, p_to_node_id uuid, p_week_start date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_d allocation_plan_details;
BEGIN
  SELECT * INTO v_d FROM allocation_plan_details WHERE id = p_detail_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sample % not found', p_detail_id; END IF;

  -- Guarda multi-tenant (igual que apply_sample_move).
  IF auth.uid() IS NOT NULL AND NOT is_superadmin()
     AND v_d.account_id IS DISTINCT FROM (SELECT pr.account_id FROM profiles pr WHERE pr.id = auth.uid()) THEN
    RAISE EXCEPTION 'Cross-tenant access denied';
  END IF;
  PERFORM public.require_edit(v_d.account_id, 'reported_incidents');  -- fase 3: derecho Edit/View de la matriz

  IF v_d.status NOT IN ('sent','incident') THEN
    RAISE EXCEPTION 'Sample is not returned-eligible';
  END IF;

  UPDATE allocation_plan_details
     SET status = 'pending', sent_at = NULL, sent_date = NULL, updated_at = now()
   WHERE id = v_d.id;

  RETURN public.apply_sample_move(p_detail_id, v_d.destination_node_id, p_to_node_id, p_week_start);
END; $function$;

-- apply_sample_move(uuid,uuid,uuid,date,numeric,numeric): PERFORM public.require_edit(v_d.account_id, 'panelist_availability');
CREATE OR REPLACE FUNCTION public.apply_sample_move(p_detail_id uuid, p_from_node_id uuid, p_to_node_id uuid, p_week_start date, p_reference_load numeric DEFAULT 6, p_deviation_percent numeric DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_actor uuid := auth.uid();
  v_d record;
  v_s jsonb;
  v_date date;
  v_same boolean;
  v_side text;
  v_date_changed boolean;
  v_new_origin boolean;
  v_new_dest boolean;
  v_pan_id uuid;
  v_pan_name text;
BEGIN
  IF p_from_node_id IS NULL OR p_to_node_id IS NULL OR p_week_start IS NULL THEN
    RAISE EXCEPTION 'Nodes and week required';
  END IF;

  -- Bloquea la muestra: dos soltadas simultaneas se serializan.
  SELECT * INTO v_d FROM allocation_plan_details WHERE id = p_detail_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Sample % not found', p_detail_id; END IF;

  -- Guarda multi-tenant antes de revelar nada del estado.
  IF v_actor IS NOT NULL AND NOT is_superadmin()
     AND v_d.account_id IS DISTINCT FROM (SELECT pr.account_id FROM profiles pr WHERE pr.id = v_actor) THEN
    RAISE EXCEPTION 'Cross-tenant access denied';
  END IF;
  PERFORM public.require_edit(v_d.account_id, 'panelist_availability');  -- fase 3: derecho Edit/View de la matriz

  v_s := incident_suggest_sample_move(p_detail_id, p_from_node_id, p_to_node_id, p_week_start,
                                      p_reference_load, p_deviation_percent);
  IF NOT COALESCE((v_s->>'found')::boolean, false) THEN
    RAISE EXCEPTION 'Cannot move: %', v_s->>'reason';
  END IF;
  v_date := (v_s->>'date')::date;
  v_same := (v_s->>'same_node')::boolean;
  v_side := v_s->>'side';
  v_date_changed := v_date IS DISTINCT FROM v_d.fecha_programada;
  IF v_same AND NOT v_date_changed THEN RAISE EXCEPTION 'Nothing to change'; END IF;

  v_new_origin := NOT v_same AND v_side = 'origin';
  v_new_dest := NOT v_same AND v_side = 'destination';
  IF NOT v_same THEN
    SELECT p.id, p.name INTO v_pan_id, v_pan_name FROM panelists p
     WHERE p.id = incident_node_panelist(p_to_node_id, v_d.account_id) AND p.account_id = v_d.account_id;
  END IF;

  UPDATE allocation_plan_details
     SET original_origin_node_id = CASE WHEN v_new_origin
           THEN COALESCE(original_origin_node_id, origin_node_id) ELSE original_origin_node_id END,
         origin_node_id = CASE WHEN v_new_origin THEN p_to_node_id ELSE origin_node_id END,
         origin_panelist_name = CASE WHEN v_new_origin THEN v_pan_name ELSE origin_panelist_name END,
         origin_panelist_id = CASE WHEN v_new_origin AND origin_panelist_id IS NOT NULL
           THEN v_pan_id ELSE origin_panelist_id END,
         original_destination_node_id = CASE WHEN v_new_dest
           THEN COALESCE(original_destination_node_id, destination_node_id) ELSE original_destination_node_id END,
         destination_node_id = CASE WHEN v_new_dest THEN p_to_node_id ELSE destination_node_id END,
         destination_panelist_name = CASE WHEN v_new_dest THEN v_pan_name ELSE destination_panelist_name END,
         destination_panelist_id = CASE WHEN v_new_dest AND destination_panelist_id IS NOT NULL
           THEN v_pan_id ELSE destination_panelist_id END,
         original_fecha_programada = CASE WHEN v_date_changed
           THEN COALESCE(original_fecha_programada, fecha_programada) ELSE original_fecha_programada END,
         fecha_programada = v_date,
         status = CASE WHEN status = 'notified' THEN 'pending' ELSE status END,
         -- Una muestra ya movida por una baja conserva ese motivo.
         reassignment_reason = CASE WHEN reassignment_reason = 'panelist_unavailable'
           THEN reassignment_reason ELSE 'rebalancing' END,
         reassigned_at = now(),
         reassigned_by = v_actor,
         updated_at = now()
   WHERE id = v_d.id;

  -- Avisos a los panelistas de antes y despues (incluido el que deja la muestra: former_sender/former_receiver).
  -- v_d conserva el estado previo al UPDATE.
  PERFORM incident_enqueue_change_full(
    v_d.id,
    CASE WHEN v_same THEN 'shift_date' WHEN v_side = 'origin' THEN 'reroute_origin' ELSE 'reroute_destination' END,
    v_d.fecha_programada, v_d.origin_node_id, v_d.destination_node_id);

  RETURN jsonb_build_object('ok', true, 'date', v_date, 'node_id', p_to_node_id, 'side', v_side);
END;
$function$;

-- set_incident_resolution(uuid,text): PERFORM public.require_edit(v_account, 'panelist_availability');
CREATE OR REPLACE FUNCTION public.set_incident_resolution(p_unavailability_id uuid, p_text text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_account uuid;
BEGIN
  SELECT account_id INTO v_account FROM panelist_unavailability WHERE id = p_unavailability_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unavailability % not found', p_unavailability_id; END IF;
  IF auth.uid() IS NOT NULL AND NOT is_superadmin()
     AND v_account IS DISTINCT FROM (SELECT pr.account_id FROM profiles pr WHERE pr.id = auth.uid()) THEN
    RAISE EXCEPTION 'Cross-tenant access denied';
  END IF;
  PERFORM public.require_edit(v_account, 'panelist_availability');  -- fase 3: derecho Edit/View de la matriz

  UPDATE panelist_unavailability
     SET final_resolution = p_text,
         updated_by = auth.uid(),
         updated_at = now()
   WHERE id = p_unavailability_id;
END;
$function$;

-- rpc_receipt_case_fix(uuid,uuid): PERFORM public.require_edit(c.account_id, 'receipts');
CREATE OR REPLACE FUNCTION public.rpc_receipt_case_fix(p_case_id uuid, p_detail_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  c public.receipt_case%ROWTYPE;
  d public.allocation_plan_details%ROWTYPE;
  v_recv_node uuid;
  v_recv_name text;
  v_recv_city uuid;
  v_dest_city uuid;
  v_typo boolean := false;
  v_moved boolean := false;
  v_orig_tag text;
  v_res text;
  v_outcome text;
  v_role text;
  v_culprit uuid;
BEGIN
  SELECT * INTO c FROM public.receipt_case WHERE id = p_case_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Caso no encontrado' USING ERRCODE = '22023';
  END IF;
  PERFORM public.receipt_mgr_check(c.account_id);
  PERFORM public.require_edit(c.account_id, 'receipts');  -- fase 3: derecho Edit/View de la matriz
  IF c.status NOT IN ('needs_decision', 'pending') THEN
    RAISE EXCEPTION 'El caso ya esta cerrado (%)', c.status USING ERRCODE = '22023';
  END IF;

  SELECT * INTO d FROM public.allocation_plan_details x
   WHERE x.id = p_detail_id AND x.account_id = c.account_id FOR UPDATE;
  IF NOT FOUND OR d.status <> 'sent' THEN
    RAISE EXCEPTION 'El envio no existe en esta cuenta o no esta en estado sent' USING ERRCODE = '22023';
  END IF;
  -- Un envio declarado despues del primer intento no puede ser la carta recibida: arreglar nunca anula.
  IF d.sent_at IS NOT NULL AND d.sent_at > c.first_attempt_at THEN
    RAISE EXCEPTION 'El envio se declaro despues de la recepcion (%)', d.sent_at USING ERRCODE = '22023';
  END IF;

  SELECT pa.node_id, pa.name INTO v_recv_node, v_recv_name
    FROM public.panelists pa WHERE pa.id = c.panelist_id AND pa.account_id = c.account_id;
  IF c.panelist_id IS NULL OR v_recv_node IS NULL THEN
    RAISE EXCEPTION 'El caso no tiene un panelista receptor con nodo' USING ERRCODE = '22023';
  END IF;

  SELECT n.city_id INTO v_recv_city FROM public.nodes n WHERE n.id = v_recv_node;
  SELECT n.city_id INTO v_dest_city FROM public.nodes n WHERE n.id = d.destination_node_id;
  IF v_recv_city IS DISTINCT FROM v_dest_city THEN
    RAISE EXCEPTION 'El destino del envio es de otra ciudad que la del receptor' USING ERRCODE = '22023';
  END IF;

  -- Etiqueta: la que declaro el panelista pasa a ser la del envio.
  IF c.tag_norm IS NOT NULL AND d.tag_id IS DISTINCT FROM c.tag_norm THEN
    IF EXISTS (SELECT 1 FROM public.allocation_plan_details x
                WHERE x.account_id = c.account_id AND x.tag_id = c.tag_norm AND x.id <> d.id) THEN
      RAISE EXCEPTION 'Otro envio de la cuenta ya tiene la etiqueta %', c.tag_norm USING ERRCODE = '22023';
    END IF;
    UPDATE public.allocation_plan_details
       SET tag_id = c.tag_norm, idtag = COALESCE(NULLIF(btrim(COALESCE(c.tag_raw, '')), ''), c.tag_norm)
     WHERE id = d.id AND status = 'sent';
    v_typo := true;
    v_orig_tag := d.tag_id;   -- la etiqueta que declaro el remitente
  END IF;
  -- Misma ciudad, otro nodo: el destino pasa al nodo del receptor.
  IF d.destination_node_id <> v_recv_node THEN
    UPDATE public.allocation_plan_details
       SET original_destination_node_id = COALESCE(original_destination_node_id, destination_node_id),
           destination_node_id = v_recv_node,
           destination_panelist_id = c.panelist_id,
           destination_panelist_name = v_recv_name
     WHERE id = d.id AND status = 'sent';
    v_moved := true;
  END IF;

  -- La recepcion cuenta desde el primer intento (y la regla POBOX se evalua con esa fecha).
  v_res := public.register_receipt_with_rules(d.id, c.first_attempt_at, c.panelist_id);
  v_outcome := CASE WHEN v_res <> 'ok' THEN v_res
                    WHEN v_typo THEN 'ok_typo_fixed'
                    WHEN v_moved THEN 'ok_same_city'
                    ELSE 'ok' END;

  SELECT k.culprit_role, k.culprit_panelist_id INTO v_role, v_culprit
    FROM public.receipt_outcome_culprit(v_outcome, d.id, c.panelist_id) k;

  UPDATE public.receipt_case
     SET reason = v_outcome,
         status = public.receipt_outcome_status(v_outcome),
         detail_id = d.id,
         culprit_role = v_role,
         culprit_panelist_id = v_culprit,
         original_tag = COALESCE(v_orig_tag, original_tag),
         resolved_at = now(),
         resolved_by = auth.uid()
   WHERE id = c.id;

  BEGIN
    PERFORM public.enqueue_receipt_reminder(c.id);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'rpc_receipt_case_fix: no se pudo encolar el recordatorio del caso %: %', c.id, SQLERRM;
  END;

  RETURN v_outcome;
END;
$function$;

-- rpc_receipt_case_close(uuid,text): PERFORM public.require_edit(c.account_id, 'receipts');
CREATE OR REPLACE FUNCTION public.rpc_receipt_case_close(p_case_id uuid, p_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  c public.receipt_case%ROWTYPE;
  v_dstatus text;
  v_status text := 'discarded';
BEGIN
  SELECT * INTO c FROM public.receipt_case WHERE id = p_case_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Caso no encontrado' USING ERRCODE = '22023';
  END IF;
  PERFORM public.receipt_mgr_check(c.account_id);
  PERFORM public.require_edit(c.account_id, 'receipts');  -- fase 3: derecho Edit/View de la matriz
  IF c.status NOT IN ('needs_decision', 'pending') THEN
    RAISE EXCEPTION 'El caso ya esta cerrado (%)', c.status USING ERRCODE = '22023';
  END IF;

  IF c.detail_id IS NOT NULL THEN
    SELECT x.status INTO v_dstatus FROM public.allocation_plan_details x
     WHERE x.id = c.detail_id AND x.account_id = c.account_id;
    IF v_dstatus IN ('sent', 'pending', 'notified') THEN
      IF public.cancel_detail_for_compensation(c.detail_id, 'receipt_before_sent') THEN
        v_status := 'compensated';
      END IF;
    END IF;
  END IF;

  UPDATE public.receipt_case
     SET status = v_status,
         resolution_note = p_note,
         resolved_at = now(),
         resolved_by = auth.uid()
   WHERE id = c.id;
END;
$function$;

-- rpc_send_panelist_notice(uuid,text): PERFORM public.require_edit(v_account, 'receipts');
CREATE OR REPLACE FUNCTION public.rpc_send_panelist_notice(p_panelist_id uuid, p_body text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_account uuid;
  v_status text;
  v_tg text;
  v_id uuid;
BEGIN
  SELECT pa.account_id, pa.status, pa.telegram_id INTO v_account, v_status, v_tg
    FROM public.panelists pa WHERE pa.id = p_panelist_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Panelista no encontrado' USING ERRCODE = '22023';
  END IF;
  PERFORM public.receipt_mgr_check(v_account);
  PERFORM public.require_edit(v_account, 'receipts');  -- fase 3: derecho Edit/View de la matriz
  IF v_status IS DISTINCT FROM 'active' OR btrim(COALESCE(v_tg, '')) !~ '^[0-9]+$' THEN
    RAISE EXCEPTION 'El panelista no esta activo o no tiene Telegram' USING ERRCODE = '22023';
  END IF;
  IF p_body IS NULL OR length(btrim(p_body)) < 1 OR length(p_body) > 3000 THEN
    RAISE EXCEPTION 'El texto del aviso debe tener entre 1 y 3000 caracteres' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.panelist_notification (account_id, panelist_id, kind, payload, send_after)
  VALUES (v_account, p_panelist_id, 'manager_notice',
          jsonb_build_object('body', p_body, 'author_user_id', auth.uid()), NULL)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;

-- rpc_broadcast_notice(uuid,jsonb): PERFORM public.require_edit(p_account_id, 'receipts');
CREATE OR REPLACE FUNCTION public.rpc_broadcast_notice(p_account_id uuid, p_bodies jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_bid uuid := gen_random_uuid();
  v_n int;
  k text;
BEGIN
  PERFORM public.receipt_mgr_check(p_account_id);
  PERFORM public.require_edit(p_account_id, 'receipts');  -- fase 3: derecho Edit/View de la matriz
  IF p_bodies IS NULL OR jsonb_typeof(p_bodies) <> 'object'
     OR COALESCE(length(btrim(p_bodies->>'en')), 0) < 1 THEN
    RAISE EXCEPTION 'Falta el texto en ingles (en)' USING ERRCODE = '22023';
  END IF;
  FOR k IN SELECT jsonb_object_keys(p_bodies) LOOP
    IF jsonb_typeof(p_bodies->k) <> 'string' OR length(p_bodies->>k) > 3000 THEN
      RAISE EXCEPTION 'El texto "%" debe ser una cadena de hasta 3000 caracteres', k USING ERRCODE = '22023';
    END IF;
  END LOOP;

  INSERT INTO public.panelist_notification (account_id, panelist_id, kind, payload, send_after)
  SELECT p.account_id, p.id, 'broadcast',
         jsonb_build_object('body', COALESCE(NULLIF(btrim(p_bodies->>COALESCE(p.language, 'en')), ''), p_bodies->>'en'),
                            'broadcast_id', v_bid, 'body_en', p_bodies->>'en', 'author_user_id', auth.uid()),
         NULL
    FROM public.panelists p
   WHERE p.account_id = p_account_id AND p.status = 'active' AND btrim(p.telegram_id) ~ '^[0-9]+$';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$;

-- send_manager_message(text,uuid,text): PERFORM public.require_edit(v_account, 'reported_incidents', 'panelist_availability', 'receipts');
CREATE OR REPLACE FUNCTION public.send_manager_message(p_incident_kind text, p_incident_id uuid, p_body text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_account uuid; v_panelist uuid; v_new uuid;
BEGIN
  IF p_incident_kind = 'reported' THEN
    SELECT account_id, panelist_id INTO v_account, v_panelist
      FROM panelist_incident WHERE id = p_incident_id;
  ELSIF p_incident_kind = 'unavailability' THEN
    SELECT account_id, panelist_id INTO v_account, v_panelist
      FROM panelist_unavailability WHERE id = p_incident_id;
  ELSE
    RAISE EXCEPTION 'invalid incident kind';
  END IF;
  IF v_account IS NULL THEN RAISE EXCEPTION 'incident not found'; END IF;
  PERFORM assert_same_account(v_account);
  PERFORM public.require_edit(v_account, 'reported_incidents', 'panelist_availability', 'receipts');  -- fase 3: derecho Edit/View de la matriz
  IF NOT EXISTS (SELECT 1 FROM panelists WHERE id = v_panelist AND account_id = v_account) THEN
    RAISE EXCEPTION 'Cross-tenant access denied'; END IF;
  IF NULLIF(btrim(p_body), '') IS NULL THEN RAISE EXCEPTION 'empty message'; END IF;
  IF NOT EXISTS (SELECT 1 FROM panelists WHERE id = v_panelist AND NULLIF(btrim(telegram_id), '') IS NOT NULL) THEN
    RAISE EXCEPTION 'panelist has no telegram'; END IF;
  INSERT INTO incident_message (account_id, panelist_id, incident_kind, incident_id,
                                direction, author, body, meta, status)
  VALUES (v_account, v_panelist, p_incident_kind, p_incident_id,
          'outbound', 'manager', btrim(p_body),
          jsonb_build_object('manager_user_id', auth.uid()), 'pending_send')
  RETURNING id INTO v_new;
  RETURN v_new;
END; $function$;

-- request_case_analysis(text,uuid): receipts:edit si es de recepción; si no, Edit en alguna de las 3 de incidencias
CREATE OR REPLACE FUNCTION public.request_case_analysis(p_incident_kind text, p_incident_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_account uuid; v_id uuid;
BEGIN
  IF p_incident_kind IS NULL OR p_incident_kind NOT IN ('reported','unavailability','receipt') THEN
    RAISE EXCEPTION 'invalid incident kind'; END IF;
  SELECT o.account_id INTO v_account FROM public.incident_owner(p_incident_kind, p_incident_id) o;
  IF v_account IS NULL THEN RAISE EXCEPTION 'incident not found'; END IF;
  PERFORM public.assert_same_account(v_account);
  IF p_incident_kind = 'receipt' THEN  -- fase 3: derecho Edit/View de la matriz
    PERFORM public.require_edit(v_account, 'receipts');
  ELSE
    PERFORM public.require_edit(v_account, 'reported_incidents', 'panelist_availability', 'receipts');
  END IF;
  IF p_incident_kind = 'receipt' THEN PERFORM public.receipt_mgr_check(v_account); END IF;
  IF NOT public.case_analysis_allowed(v_account) THEN
    RAISE EXCEPTION 'case analysis not enabled for this account' USING ERRCODE = '42501'; END IF;
  -- evita dos peticiones a la vez para la misma incidencia
  PERFORM pg_advisory_xact_lock(hashtextextended(p_incident_kind || ':' || p_incident_id::text, 0));
  SELECT r.id INTO v_id FROM public.case_analysis_request r
   WHERE r.incident_kind = p_incident_kind AND r.incident_id = p_incident_id
     AND r.status IN ('queued','running') AND r.created_at > now() - interval '10 minutes'
   ORDER BY r.created_at DESC LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  INSERT INTO public.case_analysis_request (account_id, requested_by, incident_kind, incident_id)
  VALUES (v_account, auth.uid(), p_incident_kind, p_incident_id) RETURNING id INTO v_id;
  RETURN v_id;
END $function$;

-- send_case_message(text,uuid,uuid,text,text): receipts:edit si es de recepción; si no, Edit en alguna de las 3 de incidencias
CREATE OR REPLACE FUNCTION public.send_case_message(p_incident_kind text, p_incident_id uuid, p_panelist_id uuid, p_body text, p_draft_key text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_account uuid; v_new uuid;
BEGIN
  IF p_incident_kind NOT IN ('reported','unavailability','receipt') THEN
    RAISE EXCEPTION 'invalid incident kind'; END IF;
  SELECT o.account_id INTO v_account FROM public.incident_owner(p_incident_kind, p_incident_id) o;
  IF v_account IS NULL THEN RAISE EXCEPTION 'incident not found'; END IF;
  PERFORM assert_same_account(v_account);
  IF p_incident_kind = 'receipt' THEN  -- fase 3: derecho Edit/View de la matriz
    PERFORM public.require_edit(v_account, 'receipts');
  ELSE
    PERFORM public.require_edit(v_account, 'reported_incidents', 'panelist_availability', 'receipts');
  END IF;
  -- la pantalla de errores de recepcion es solo para admins de la cuenta
  IF p_incident_kind = 'receipt' THEN PERFORM public.receipt_mgr_check(v_account); END IF;
  IF NOT public.case_analysis_allowed(v_account) THEN
    RAISE EXCEPTION 'case analysis not enabled for this account' USING ERRCODE = '42501'; END IF;
  IF p_panelist_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM panelists WHERE id = p_panelist_id AND account_id = v_account) THEN
    RAISE EXCEPTION 'Cross-tenant access denied'; END IF;
  IF NULLIF(btrim(p_body), '') IS NULL THEN RAISE EXCEPTION 'empty message'; END IF;
  -- mismo limite que rpc_send_manager_notice y el textarea
  IF length(p_body) > 3000 THEN RAISE EXCEPTION 'message too long'; END IF;
  -- misma regla que ops_case_send: panelista activo con id de Telegram numerico
  IF NOT EXISTS (SELECT 1 FROM panelists WHERE id = p_panelist_id AND status = 'active') THEN
    RAISE EXCEPTION 'panelist not active'; END IF;
  IF NOT EXISTS (SELECT 1 FROM panelists WHERE id = p_panelist_id AND btrim(COALESCE(telegram_id, '')) ~ '^[0-9]+$') THEN
    RAISE EXCEPTION 'panelist has no telegram'; END IF;
  INSERT INTO incident_message (account_id, panelist_id, incident_kind, incident_id,
                                direction, author, body, meta, status)
  VALUES (v_account, p_panelist_id, p_incident_kind, p_incident_id,
          'outbound', 'manager', btrim(p_body),
          jsonb_build_object('manager_user_id', auth.uid(), 'case_draft_key', p_draft_key), 'pending_send')
  RETURNING id INTO v_new;
  RETURN v_new;
END; $function$;

-- mark_incident_conversation_read(text,uuid): PERFORM public.require_access(v_account, 'view', 'reported_incidents', 'panelist_availability', 'receipts');
CREATE OR REPLACE FUNCTION public.mark_incident_conversation_read(p_incident_kind text, p_incident_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_account uuid; v_n int;
BEGIN
  IF p_incident_kind NOT IN ('reported','unavailability','receipt') THEN
    RAISE EXCEPTION 'invalid incident kind'; END IF;
  SELECT o.account_id INTO v_account FROM public.incident_owner(p_incident_kind, p_incident_id) o;
  IF v_account IS NULL THEN RAISE EXCEPTION 'incident not found'; END IF;
  PERFORM assert_same_account(v_account);
  PERFORM public.require_access(v_account, 'view', 'reported_incidents', 'panelist_availability', 'receipts');  -- fase 3: derecho Edit/View de la matriz
  -- los casos de recepcion son solo para admins de la cuenta (paridad con send_case_message y la RLS)
  IF p_incident_kind = 'receipt' THEN PERFORM public.receipt_mgr_check(v_account); END IF;
  UPDATE incident_message
     SET read_at = now()
   WHERE incident_kind = p_incident_kind AND incident_id = p_incident_id
     AND account_id = v_account AND direction = 'inbound' AND read_at IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END; $function$;

-- mark_panelist_incident_seen(uuid): PERFORM public.require_access(v_account, 'view', 'reported_incidents');
CREATE OR REPLACE FUNCTION public.mark_panelist_incident_seen(p_incident_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_account uuid; v_n int;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT account_id INTO v_account FROM panelist_incident WHERE id = p_incident_id;
  IF v_account IS NULL THEN RAISE EXCEPTION 'incident not found'; END IF;
  PERFORM assert_same_account(v_account);
  PERFORM public.require_access(v_account, 'view', 'reported_incidents');  -- fase 3: derecho Edit/View de la matriz
  UPDATE panelist_incident SET manager_seen_at = now()
   WHERE id = p_incident_id AND manager_seen_at IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n > 0;
END; $function$;

-- case_analysis_status(uuid): PERFORM public.require_access(r.account_id, 'view', 'reported_incidents', 'panelist_availability', 'receipts');
CREATE OR REPLACE FUNCTION public.case_analysis_status(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE r public.case_analysis_request;
BEGIN
  SELECT * INTO r FROM public.case_analysis_request WHERE id = p_request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'request not found'; END IF;
  PERFORM public.assert_same_account(r.account_id);
  PERFORM public.require_access(r.account_id, 'view', 'reported_incidents', 'panelist_availability', 'receipts');  -- fase 3: derecho Edit/View de la matriz
  IF r.incident_kind = 'receipt' THEN PERFORM public.receipt_mgr_check(r.account_id); END IF;
  -- UPDATE condicionado: nunca pisa una peticion que acaba de terminar
  UPDATE public.case_analysis_request SET status = 'failed', error = 'agent_timeout', finished_at = now()
   WHERE id = r.id AND status IN ('queued','running') AND created_at < now() - interval '10 minutes';
  SELECT * INTO r FROM public.case_analysis_request WHERE id = p_request_id;
  RETURN jsonb_build_object('status', r.status, 'result', r.result, 'error', r.error);
END $function$;

-- rpc_execute_pipeline_phase(text,uuid): PERFORM public.require_edit(v_account_id, 'epcis_api');
CREATE OR REPLACE FUNCTION public.rpc_execute_pipeline_phase(p_phase text, p_account_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
    v_res record;
    v_account_id uuid;
    v_consolidation_result json;
    v_segments_result json;
    v_aggregation_result json;
    v_rj RECORD;
    v_aj RECORD;
BEGIN
    v_res := public.pipeline_resolve_account(p_account_id);
    IF v_res.error IS NOT NULL THEN
        RETURN jsonb_build_object('success', false, 'error', v_res.error);
    END IF;
    v_account_id := v_res.account_id;
    PERFORM public.require_edit(v_account_id, 'epcis_api');  -- fase 3: derecho Edit/View de la matriz

    IF p_phase IS NULL OR p_phase NOT IN ('consolidation', 'segments', 'aggregation', 'all') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid phase');
    END IF;

    IF p_phase = 'consolidation' OR p_phase = 'all' THEN
        v_consolidation_result := consolidate_rfid_events(v_account_id);
        PERFORM reenrich_processed_events(v_account_id);
    END IF;

    IF p_phase = 'segments' OR p_phase = 'all' THEN
        SELECT * INTO v_rj FROM reconstruct_journeys(v_account_id);
        SELECT * INTO v_aj FROM assemble_journeys(v_account_id);
        PERFORM * FROM propagate_journey_enrichment(v_account_id);
        v_segments_result := json_build_object(
            'success', true,
            'segments_created', v_rj.segments_created,
            'events_processed', v_rj.events_processed,
            'journeys_created', v_aj.journeys_created,
            'journeys_updated', v_aj.journeys_updated);
    END IF;

    IF p_phase = 'aggregation' OR p_phase = 'all' THEN
        v_aggregation_result := aggregate_journey_paths(v_account_id);
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'account_id', v_account_id,
        'phase', p_phase,
        'consolidation', v_consolidation_result,
        'segments', v_segments_result,
        'aggregation', v_aggregation_result
    );
END $function$;

-- 4d. rpc_balance_city_v2: cuerpo actual del repo (20261102072347_pobox_receipt_after_absence.sql) + require_edit
--     tras su guarda de cuenta. auth.uid() NULL (ops_fix_r3_apply, service_role) sigue pasando.
-- rpc_balance_city_v2(uuid,date,date,boolean,date): PERFORM public.require_edit(v_account_id, 'load_balancing');
CREATE OR REPLACE FUNCTION public.rpc_balance_city_v2(p_city_id uuid, p_start_date date, p_end_date date, p_apply_changes boolean DEFAULT false, p_fence_until date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_account_id    uuid;
  v_tz            text;
  v_today         date;
  v_from          date;
  v_fence         date;   -- ultimo dia congelado (NULL = sin fence)
  v_pb_replaced   integer := 0;   -- filas 'pobox' convertidas en 'compensation'
  v_pb_conv       integer := 0;
  v_offset        integer;
  v_date_policy   text;
  v_pobox         boolean;
  v_n_nodes       integer;
  v_had_remainder boolean := false;
  v_total         integer;
  v_stddev_before numeric := 0;
  v_stddev_after  numeric := 0;
  v_improvement   numeric := 0;
  v_movements     jsonb;
  v_movements_count integer := 0;
  v_matrix_before jsonb;
  v_matrix_after  jsonb;
  v_warnings      jsonb;
  v_conf          record;
  v_cur           record;
  v_other         record;
  -- POBOX
  v_day           date;
  v_wk            date;
  v_mv_id         uuid;
  v_mv_cell       integer;
  v_plan          uuid;
  v_org_node      uuid;
  v_org_cell      integer;
  v_dst_node      uuid;
  v_new_id        uuid;
  v_fb_cell       integer;
  v_pb_missing    integer := 0;
  v_pb_moved      integer := 0;
  v_pb_created    integer := 0;
  v_pb_uncovered  integer := 0;
  v_pb_unc_dates  text[] := '{}';
  -- Muestras por compensar (fase 0)
  v_def_removed    integer := 0;
  v_def_origin     integer := 0;
  v_def_dest       integer := 0;
  v_def_day        integer := 0;
  v_def_reassigned integer := 0;
  v_def_waiting    integer := 0;
  v_def_ins        integer := 0;
  v_def_del        integer := 0;
  v_def_blocked    integer := 0;
  v_def_bad        text;
  -- Reintroduccion (fase R y POBOX)
  v_rc             record;
  v_rc_any         boolean := false;   -- la ciudad tiene anotaciones pendientes (existe lb2_rcand)
  v_r_onode        uuid;
  v_r_dnode        uuid;
  v_r_day          date;
  v_r_cell         integer;
  v_reint          integer := 0;
  v_reint_ins      integer := 0;
  v_reint_upd      integer := 0;
  v_pb_reint       integer := 0;
  v_wait_by        jsonb;
BEGIN
  SELECT c.account_id, COALESCE(a.timezone, 'UTC'), c.balance_rotation_offset
    INTO v_account_id, v_tz, v_offset
    FROM public.cities c JOIN public.accounts a ON a.id = c.account_id
   WHERE c.id = p_city_id;

  IF v_account_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'City not found', 'message', 'City not found',
      'movements_count', 0, 'stddev_before', 0, 'stddev_after', 0, 'improvement_percentage', 0,
      'movements', '[]'::jsonb, 'matrix_before', '[]'::jsonb, 'matrix_after', '[]'::jsonb, 'warnings', '[]'::jsonb,
      'policy', jsonb_build_object('date_policy', NULL, 'pobox_enabled', NULL),
      'pobox', jsonb_build_object('days_missing', 0, 'days_moved', 0, 'days_created', 0, 'days_uncovered', 0,
                                  'days_reintroduced', 0),
      'fence_until', NULL,
      'deferred', jsonb_build_object('removed', 0, 'reassigned_dest', 0, 'reintroduced', 0, 'replaced_pobox', 0,
                                     'waiting', 0, 'blocked', 0,
                                     'by_reason', jsonb_build_object('origin_no_panelist', 0, 'dest_no_panelist', 0,
                                                                     'no_valid_day', 0),
                                     'waiting_by_reason', jsonb_build_object('no_origin_panelist', 0, 'no_dest_panelist', 0,
                                                                             'no_capacity', 0, 'plan_inactive', 0,
                                                                             'outside_period', 0)));
  END IF;

  -- Guarda de cuenta (igual que rpc_get_node_load_by_day): con sesion de usuario solo miembros de la cuenta
  -- de la ciudad o superadmin; auth.uid() NULL = llamada interna / service_role.
  IF auth.uid() IS NOT NULL AND NOT public.is_superadmin()
     AND v_account_id IS DISTINCT FROM (SELECT p.account_id FROM public.profiles p WHERE p.id = auth.uid()) THEN
    RAISE EXCEPTION 'No autorizado para esta cuenta' USING ERRCODE = '42501';
  END IF;
  PERFORM public.require_edit(v_account_id, 'load_balancing');  -- fase 3: derecho Edit/View de la matriz

  -- Dos aplicaciones concurrentes sobre la misma ciudad se serializan (la segunda calcula sobre lo que dejo la
  -- primera). La vista previa no bloquea. El offset se relee tras el bloqueo.
  IF p_apply_changes THEN
    PERFORM pg_advisory_xact_lock(hashtext(p_city_id::text));
    SELECT c.balance_rotation_offset INTO v_offset FROM public.cities c WHERE c.id = p_city_id;
  END IF;

  SELECT ep.date_policy, ep.pobox_enabled INTO v_date_policy, v_pobox
    FROM public.effective_city_policy(p_city_id) ep;
  v_today := (now() AT TIME ZONE v_tz)::date;
  -- Fence: de hoy a p_fence_until (incluidos) no se toca nada; se reparte desde el dia siguiente.
  v_fence := CASE WHEN p_fence_until >= v_today THEN p_fence_until END;
  v_from  := GREATEST(p_start_date, v_today, COALESCE(v_fence + 1, v_today));   -- nunca en el pasado ni en el fence

  DROP TABLE IF EXISTS pg_temp.lb2_nodes, pg_temp.lb2_days, pg_temp.lb2_absent, pg_temp.lb2_cells, pg_temp.lb2_segs, pg_temp.lb2_ship,
                       pg_temp.lb2_new, pg_temp.lb2_pb, pg_temp.lb2_plans, pg_temp.lb2_routes, pg_temp.lb2_dest,
                       pg_temp.lb2_dabsent, pg_temp.lb2_dload, pg_temp.lb2_sdabs,
                       pg_temp.lb2_alt, pg_temp.lb2_altload, pg_temp.lb2_altabs, pg_temp.lb2_defer, pg_temp.lb2_hz,
                       pg_temp.lb2_reint, pg_temp.lb2_rcand, pg_temp.lb2_rload, pg_temp.lb2_rday,
                       pg_temp.lb2_rdest, pg_temp.lb2_rdslot, pg_temp.lb2_rpb, pg_temp.lb2_pshare;

  -- ===== 1-2. Nodos de la ciudad (todos, para codigos) y validez (activo + panelista activo).
  CREATE TEMP TABLE pg_temp.lb2_nodes (
    node_id uuid PRIMARY KEY, node_code text, all_rank integer, valid boolean, valid_rank integer,
    panelist_id uuid, panelist_name text
  ) ON COMMIT DROP;
  INSERT INTO pg_temp.lb2_nodes (node_id, node_code, all_rank, valid, panelist_id, panelist_name)
  SELECT n.id, n.auto_id, (row_number() OVER (ORDER BY n.auto_id, n.id))::int - 1,
         (n.status = 'active' AND pan.id IS NOT NULL), pan.id, pan.name::text
    FROM public.nodes n
    LEFT JOIN LATERAL (SELECT p.id, p.name FROM public.panelists p
                        WHERE p.node_id = n.id AND p.account_id = v_account_id AND p.status = 'active'
                        ORDER BY p.created_at, p.id LIMIT 1) pan ON true
   WHERE n.city_id = p_city_id AND n.account_id = v_account_id;
  UPDATE pg_temp.lb2_nodes t SET valid_rank = x.r
    FROM (SELECT node_id, (row_number() OVER (ORDER BY all_rank))::int - 1 AS r FROM pg_temp.lb2_nodes WHERE valid) x
   WHERE x.node_id = t.node_id;
  SELECT count(*) INTO v_n_nodes FROM pg_temp.lb2_nodes WHERE valid;

  -- Dias laborables de la cuenta en [v_from, fin].
  CREATE TEMP TABLE pg_temp.lb2_days (d date PRIMARY KEY, week_start date, month_start date) ON COMMIT DROP;
  INSERT INTO pg_temp.lb2_days
  SELECT g::date, date_trunc('week', g)::date, date_trunc('month', g)::date
    FROM generate_series(v_from, p_end_date, interval '1 day') g
   WHERE public.is_account_working_day(v_account_id, g::date);

  -- Ausencias activas (cualquier panelista activo del nodo, como la vista diaria).
  CREATE TEMP TABLE pg_temp.lb2_absent (node_id uuid, d date, PRIMARY KEY (node_id, d)) ON COMMIT DROP;
  INSERT INTO pg_temp.lb2_absent
  SELECT DISTINCT p.node_id, dd.d
    FROM public.panelist_unavailability u
    JOIN public.panelists p ON p.id = u.panelist_id AND p.account_id = v_account_id AND p.status = 'active'
    JOIN pg_temp.lb2_nodes n ON n.node_id = p.node_id AND n.valid
    JOIN pg_temp.lb2_days dd ON dd.d BETWEEN u.start_date AND u.end_date
   WHERE u.account_id = v_account_id AND u.status = 'active';

  -- ===== 4. Celdas. Tramo = (week_start, month_start).
  CREATE TEMP TABLE pg_temp.lb2_cells (
    cell_id serial PRIMARY KEY, node_id uuid, node_code text, valid_rank integer,
    week_start date, month_start date, cell_date date,
    day_idx integer, node_cells integer,
    current_load integer NOT NULL DEFAULT 0, target integer NOT NULL DEFAULT 0,
    kept integer NOT NULL DEFAULT 0, new_load integer NOT NULL DEFAULT 0,
    fixed integer NOT NULL DEFAULT 0,  -- envios congelados (no movibles) que ya estan en la celda
    -- el dia cae dentro de las fechas del plan de algun envio de la ciudad (si no, la celda no recibe objetivo)
    in_plan boolean NOT NULL DEFAULT true
  ) ON COMMIT DROP;
  IF v_date_policy = 'weekly' THEN
    INSERT INTO pg_temp.lb2_cells (node_id, node_code, valid_rank, week_start, month_start, cell_date)
    SELECT n.node_id, n.node_code, n.valid_rank, d.week_start, d.month_start, min(d.d)
      FROM pg_temp.lb2_nodes n CROSS JOIN pg_temp.lb2_days d
     WHERE n.valid AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_absent a WHERE a.node_id = n.node_id AND a.d = d.d)
     GROUP BY n.node_id, n.node_code, n.valid_rank, d.week_start, d.month_start
     ORDER BY n.valid_rank, d.week_start, d.month_start;
  ELSE
    INSERT INTO pg_temp.lb2_cells (node_id, node_code, valid_rank, week_start, month_start, cell_date)
    SELECT n.node_id, n.node_code, n.valid_rank, d.week_start, d.month_start, d.d
      FROM pg_temp.lb2_nodes n CROSS JOIN pg_temp.lb2_days d
     WHERE n.valid AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_absent a WHERE a.node_id = n.node_id AND a.d = d.d)
     ORDER BY n.valid_rank, d.d;
  END IF;
  CREATE INDEX ON pg_temp.lb2_cells (node_id, cell_date);
  -- Posicion del dia dentro del nodo y del tramo (para repartir los +1 en dias distintos).
  UPDATE pg_temp.lb2_cells c SET day_idx = x.i, node_cells = x.k
    FROM (SELECT cell_id,
                 (row_number() OVER (PARTITION BY node_id, week_start, month_start ORDER BY cell_date))::int - 1 AS i,
                 (count(*) OVER (PARTITION BY node_id, week_start, month_start))::int AS k
            FROM pg_temp.lb2_cells) x
   WHERE x.cell_id = c.cell_id;

  -- ===== 3. Envios pendientes de la ciudad en el periodo (origen en cualquier nodo de la ciudad).
  CREATE TEMP TABLE pg_temp.lb2_ship (
    id uuid PRIMARY KEY, cur_node uuid, cur_code text, cur_rank integer, dest_node uuid, fecha date,
    month_key date, cur_cell integer, new_cell integer, keep boolean NOT NULL DEFAULT false,
    od_conflict boolean NOT NULL DEFAULT false, pobox_move boolean NOT NULL DEFAULT false,
    dest_bad boolean NOT NULL DEFAULT false,
    -- congelado: no se puede mover (destino sin panelista activo, origen = destino sin arreglo o sin celda
    -- valida); se queda donde esta y cuenta como carga fija de su celda actual (si la tiene).
    frozen boolean NOT NULL DEFAULT false,
    dest_city uuid,
    -- fechas del plan del envio; NULL = sin restriccion (el envio ya esta fuera de su plan: dato incoherente que
    -- no se castiga borrandolo)
    plan_start date, plan_end date,
    pl_end date,   -- fin real del plan (para el horizonte de R3 cuando el envio esta fuera de su plan)
    def_blocked boolean NOT NULL DEFAULT false,   -- se apartaria pero tiene dependientes (R2): se queda
    -- fase 0: motivo para apartarlo al registro (NULL = se queda en el plan)
    defer_reason text,
    -- fase 0: destino reasignado dentro de la ciudad destino (dest_node ya es el nuevo)
    new_dest boolean NOT NULL DEFAULT false, new_dest_pid uuid, new_dest_pname text,
    -- muestra reintroducida (generation_source = 'compensation'); comp_frozen = fija en su hueco valido (R7)
    comp boolean NOT NULL DEFAULT false, comp_frozen boolean NOT NULL DEFAULT false
  ) ON COMMIT DROP;
  INSERT INTO pg_temp.lb2_ship (id, cur_node, cur_code, cur_rank, dest_node, dest_city, fecha, month_key, dest_bad,
                                plan_start, plan_end, pl_end, comp)
  SELECT a.id, a.origin_node_id, n.node_code, n.all_rank, a.destination_node_id, dn.city_id, a.fecha_programada,
         date_trunc('month', GREATEST(a.fecha_programada, v_from))::date,
         -- destino sin panelista activo: ninguna fecha es valida para el (spec 5.3)
         NOT EXISTS (SELECT 1 FROM public.panelists p
                      WHERE p.node_id = a.destination_node_id AND p.account_id = v_account_id AND p.status = 'active'),
         CASE WHEN a.fecha_programada BETWEEN pl.start_date AND pl.end_date THEN pl.start_date END,
         CASE WHEN a.fecha_programada BETWEEN pl.start_date AND pl.end_date THEN pl.end_date END,
         pl.end_date, a.generation_source = 'compensation'
    FROM public.allocation_plan_details a
    JOIN pg_temp.lb2_nodes n ON n.node_id = a.origin_node_id
    LEFT JOIN public.nodes dn ON dn.id = a.destination_node_id
    LEFT JOIN public.allocation_plans pl ON pl.id = a.plan_id
   WHERE a.account_id = v_account_id
     AND a.status = 'pending'
     AND a.fecha_programada BETWEEN p_start_date AND p_end_date
     -- las del fence se quedan como estan (no entran en el calculo)
     AND (v_fence IS NULL OR a.fecha_programada NOT BETWEEN v_today AND v_fence);
  SELECT count(*) INTO v_total FROM pg_temp.lb2_ship;

  -- ===== 0. Muestras por compensar (spec 2026-10-28, 3.1). Orden de prioridad: origen, destino, dia.
  -- 0a. Ciudad sin ningun nodo valido: el origen no se puede reasignar => todas al registro.
  IF v_n_nodes = 0 THEN
    UPDATE pg_temp.lb2_ship SET defer_reason = 'origin_no_panelist' WHERE TRUE;
  END IF;

  -- 0b. Destino sin panelista activo: otro nodo activo con panelista activo de la MISMA ciudad destino (distinto
  -- del nodo origen), el de menos recepciones en la semana ISO del envio (empate: en el periodo, luego codigo);
  -- se prefieren los no ausentes ese dia. Sin alternativa => al registro.
  IF EXISTS (SELECT 1 FROM pg_temp.lb2_ship WHERE dest_bad AND defer_reason IS NULL) THEN
    CREATE TEMP TABLE pg_temp.lb2_alt (
      node_id uuid PRIMARY KEY, city_id uuid, node_code text, panelist_id uuid, panelist_name text
    ) ON COMMIT DROP;
    INSERT INTO pg_temp.lb2_alt
    SELECT n.id, n.city_id, n.auto_id, pan.id, pan.name::text
      FROM public.nodes n
      JOIN LATERAL (SELECT p.id, p.name FROM public.panelists p
                     WHERE p.node_id = n.id AND p.account_id = v_account_id AND p.status = 'active'
                     ORDER BY p.created_at, p.id LIMIT 1) pan ON true
     WHERE n.account_id = v_account_id AND n.status = 'active'
       AND n.city_id IN (SELECT DISTINCT s.dest_city FROM pg_temp.lb2_ship s WHERE s.dest_bad AND s.defer_reason IS NULL);

    UPDATE pg_temp.lb2_ship s SET defer_reason = 'dest_no_panelist'
     WHERE s.dest_bad AND s.defer_reason IS NULL
       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_alt t WHERE t.city_id = s.dest_city AND t.node_id <> s.cur_node);

    IF EXISTS (SELECT 1 FROM pg_temp.lb2_ship WHERE dest_bad AND defer_reason IS NULL) THEN
      CREATE TEMP TABLE pg_temp.lb2_altload (node_id uuid, d date, n integer) ON COMMIT DROP;
      INSERT INTO pg_temp.lb2_altload
      SELECT a.destination_node_id, a.fecha_programada, count(*)::int
        FROM public.allocation_plan_details a
        JOIN pg_temp.lb2_alt t ON t.node_id = a.destination_node_id
       WHERE a.account_id = v_account_id AND a.status <> 'cancelled'
         AND a.fecha_programada BETWEEN date_trunc('week', p_start_date)::date AND p_end_date + 6
       GROUP BY a.destination_node_id, a.fecha_programada;
      CREATE INDEX ON pg_temp.lb2_altload (node_id, d);
      CREATE TEMP TABLE pg_temp.lb2_altabs (node_id uuid, d date, PRIMARY KEY (node_id, d)) ON COMMIT DROP;
      INSERT INTO pg_temp.lb2_altabs
      SELECT DISTINCT p.node_id, g::date
        FROM public.panelist_unavailability u
        JOIN public.panelists p ON p.id = u.panelist_id AND p.account_id = v_account_id AND p.status = 'active'
        JOIN pg_temp.lb2_alt t ON t.node_id = p.node_id
        CROSS JOIN LATERAL generate_series(GREATEST(u.start_date, p_start_date), LEAST(u.end_date, p_end_date),
                                           interval '1 day') g
       WHERE u.account_id = v_account_id AND u.status = 'active'
         AND u.start_date <= p_end_date AND u.end_date >= p_start_date;

      -- Uno a uno (por fecha) para que la carga de los ya reasignados cuente en los siguientes.
      FOR v_conf IN
        SELECT s.id FROM pg_temp.lb2_ship s WHERE s.dest_bad AND s.defer_reason IS NULL ORDER BY s.fecha, s.id
      LOOP
        SELECT s.fecha, s.cur_node, s.dest_city INTO v_cur FROM pg_temp.lb2_ship s WHERE s.id = v_conf.id;
        v_wk := date_trunc('week', v_cur.fecha)::date;
        SELECT t.node_id, t.panelist_id, t.panelist_name INTO v_other
          FROM pg_temp.lb2_alt t
         WHERE t.city_id = v_cur.dest_city AND t.node_id <> v_cur.cur_node
         ORDER BY EXISTS (SELECT 1 FROM pg_temp.lb2_altabs x WHERE x.node_id = t.node_id AND x.d = v_cur.fecha),
                  (SELECT COALESCE(sum(l.n), 0) FROM pg_temp.lb2_altload l
                    WHERE l.node_id = t.node_id AND l.d BETWEEN v_wk AND v_wk + 6),
                  (SELECT COALESCE(sum(l.n), 0) FROM pg_temp.lb2_altload l
                    WHERE l.node_id = t.node_id AND l.d BETWEEN p_start_date AND p_end_date),
                  t.node_code, t.node_id
         LIMIT 1;
        IF NOT FOUND THEN   -- no deberia ocurrir (filtrado arriba); por seguridad, al registro
          UPDATE pg_temp.lb2_ship SET defer_reason = 'dest_no_panelist' WHERE id = v_conf.id;
          CONTINUE;
        END IF;
        UPDATE pg_temp.lb2_ship
           SET dest_node = v_other.node_id, dest_bad = false, new_dest = true,
               new_dest_pid = v_other.panelist_id, new_dest_pname = v_other.panelist_name
         WHERE id = v_conf.id;
        INSERT INTO pg_temp.lb2_altload VALUES (v_other.node_id, v_cur.fecha, 1);
      END LOOP;
    END IF;
  END IF;
  -- Sin efecto tras 0b (todo destino sin panelista se reasigna o se aparta); se conserva por seguridad.
  UPDATE pg_temp.lb2_ship SET frozen = true WHERE dest_bad AND defer_reason IS NULL;

  -- Ausencias de los nodos DESTINO de esos envios (spec 5.3: no se programa un dia de ausencia ni como origen
  -- ni como destino). Un envio no puede ir a una celda cuya fecha este aqui para su destino.
  CREATE TEMP TABLE pg_temp.lb2_sdabs (node_id uuid, d date, PRIMARY KEY (node_id, d)) ON COMMIT DROP;
  INSERT INTO pg_temp.lb2_sdabs
  SELECT DISTINCT p.node_id, dd.d
    FROM public.panelist_unavailability u
    JOIN public.panelists p ON p.id = u.panelist_id AND p.account_id = v_account_id AND p.status = 'active'
    JOIN (SELECT DISTINCT dest_node FROM pg_temp.lb2_ship) sd ON sd.dest_node = p.node_id
    JOIN pg_temp.lb2_days dd ON dd.d BETWEEN u.start_date AND u.end_date
   WHERE u.account_id = v_account_id AND u.status = 'active';

  -- Atrasados: cuentan en el mes de v_from; si ese mes ya no tiene celdas, en el primer mes siguiente que las tenga.
  UPDATE pg_temp.lb2_ship s SET month_key = m.next_month
    FROM (SELECT min(month_start) AS next_month FROM pg_temp.lb2_cells
           WHERE month_start > date_trunc('month', v_from)::date) m
   WHERE s.fecha < v_from AND m.next_month IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_cells c WHERE c.month_start = s.month_key);

  -- R7. Una reintroducida pendiente ('compensation') que esta en un hueco valido se queda FIJA donde esta: no la
  -- mueven ni el reparto equitativo, ni el paso al primer dia del tramo (politica semanal), ni POBOX. Asi los
  -- topes totales de la fase R (1 compensation por (nodo origen, dia) y por (nodo destino, dia)) se mantienen al
  -- repetir el balanceo. Hueco valido: dia laborable del periodo dentro de su plan, nodo origen valido y no
  -- ausente, nodo destino activo con panelista activo, no ausente y distinto del origen. Cuenta como carga fija
  -- (objetivos, desviaciones, matrices, topes) y no se avisa como no_valid_cell. Si deja de estar en un hueco
  -- valido (baja declarada despues, nodo sin panelista...) se trata como cualquier otra muestra movible.
  -- Politica semanal: por esto la reintroducida conserva para siempre su dia real.
  UPDATE pg_temp.lb2_ship s SET frozen = true, comp_frozen = true
   WHERE s.comp AND s.defer_reason IS NULL AND NOT s.frozen AND NOT s.dest_bad
     AND (s.plan_start IS NOT NULL OR s.fecha > s.pl_end)  -- fecha dentro de su plan o posterior a su fin (spec 3.4 bis)
     AND s.dest_node <> s.cur_node
     AND EXISTS (SELECT 1 FROM pg_temp.lb2_days dd WHERE dd.d = s.fecha)
     AND EXISTS (SELECT 1 FROM pg_temp.lb2_nodes n WHERE n.node_id = s.cur_node AND n.valid)
     AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_absent x WHERE x.node_id = s.cur_node AND x.d = s.fecha)
     AND EXISTS (SELECT 1 FROM public.nodes dn WHERE dn.id = s.dest_node AND dn.status = 'active')
     AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs x WHERE x.node_id = s.dest_node AND x.d = s.fecha);

  -- 0c. Sin dia valido. Celda compatible = de otro nodo que el destino, sin ausencia del destino ese dia y dentro
  -- de las fechas del plan. Si el mes del envio no tiene ninguna, se busca en los demas meses del periodo (la
  -- celda compatible mas cercana decide el mes; el reparto normal elige luego la celda dentro de ese mes). Si no
  -- hay en ningun mes => al registro, salvo que el unico obstaculo sea origen = destino (celdas del propio nodo
  -- destino: se mantiene el aviso origin_equals_destination / no_valid_cell, no se borra). Si el periodo no
  -- tiene ningun dia laborable >= hoy (periodo pasado) no se aparta nada por este motivo.
  IF EXISTS (SELECT 1 FROM pg_temp.lb2_days) THEN
    UPDATE pg_temp.lb2_ship s SET month_key = x.m
      FROM (SELECT s2.id,
                   (SELECT c.month_start FROM pg_temp.lb2_cells c
                     WHERE c.node_id <> s2.dest_node
                       AND (s2.plan_start IS NULL OR c.cell_date BETWEEN s2.plan_start AND s2.plan_end)
                       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs a WHERE a.node_id = s2.dest_node AND a.d = c.cell_date)
                     ORDER BY abs(c.cell_date - GREATEST(s2.fecha, v_from)), c.cell_date, c.valid_rank
                     LIMIT 1) AS m
              FROM pg_temp.lb2_ship s2
             WHERE s2.defer_reason IS NULL AND NOT s2.comp_frozen
               AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_cells c
                                WHERE c.month_start = s2.month_key AND c.node_id <> s2.dest_node
                                  AND (s2.plan_start IS NULL OR c.cell_date BETWEEN s2.plan_start AND s2.plan_end)
                                  AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs a
                                                   WHERE a.node_id = s2.dest_node AND a.d = c.cell_date))) x
     WHERE x.id = s.id AND x.m IS NOT NULL;
    UPDATE pg_temp.lb2_ship s SET defer_reason = 'no_valid_day'
     WHERE s.defer_reason IS NULL AND NOT s.comp_frozen
       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_cells c
                        WHERE c.month_start = s.month_key AND c.node_id <> s.dest_node
                          AND (s.plan_start IS NULL OR c.cell_date BETWEEN s.plan_start AND s.plan_end)
                          AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs a WHERE a.node_id = s.dest_node AND a.d = c.cell_date))
       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_cells c
                        WHERE c.node_id = s.dest_node
                          AND (s.plan_start IS NULL OR c.cell_date BETWEEN s.plan_start AND s.plan_end));
  END IF;

  -- 0c bis (R3). no_valid_day solo borra si no hay NINGUN hueco en el resto del horizonte del plan, no solo en el
  -- periodo de la pantalla: dia laborable en [max(v_from, inicio del plan), fin del plan] con algun nodo valido de
  -- esta ciudad no ausente y algun nodo valido (activo + panelista activo) de la ciudad destino no ausente. Si lo
  -- hay, la muestra se queda donde esta (carga fija, aviso no_valid_cell) para balancear con un periodo mas ancho.
  -- Por combinacion distinta (ciudad destino, horizonte), no por fila.
  IF EXISTS (SELECT 1 FROM pg_temp.lb2_ship WHERE defer_reason = 'no_valid_day') THEN
    CREATE TEMP TABLE pg_temp.lb2_hz (
      dest_city uuid, h_from date, h_to date, has_slot boolean NOT NULL DEFAULT false
    ) ON COMMIT DROP;
    INSERT INTO pg_temp.lb2_hz (dest_city, h_from, h_to)
    SELECT DISTINCT s.dest_city, GREATEST(v_from, COALESCE(s.plan_start, v_from)),
           COALESCE(s.plan_end, GREATEST(s.pl_end, p_end_date))
      FROM pg_temp.lb2_ship s WHERE s.defer_reason = 'no_valid_day';
    UPDATE pg_temp.lb2_hz h
       SET has_slot = EXISTS (
             SELECT 1 FROM generate_series(h.h_from, h.h_to, interval '1 day') g
              WHERE public.is_account_working_day(v_account_id, g::date)
                AND EXISTS (SELECT 1 FROM pg_temp.lb2_nodes n
                             WHERE n.valid
                               AND NOT EXISTS (SELECT 1 FROM public.panelist_unavailability u
                                                 JOIN public.panelists p ON p.id = u.panelist_id
                                                  AND p.account_id = v_account_id AND p.status = 'active'
                                                WHERE p.node_id = n.node_id AND u.account_id = v_account_id
                                                  AND u.status = 'active' AND g::date BETWEEN u.start_date AND u.end_date))
                AND EXISTS (SELECT 1 FROM public.nodes dn
                             WHERE dn.city_id = h.dest_city AND dn.account_id = v_account_id AND dn.status = 'active'
                               AND EXISTS (SELECT 1 FROM public.panelists p
                                            WHERE p.node_id = dn.id AND p.account_id = v_account_id AND p.status = 'active')
                               AND NOT EXISTS (SELECT 1 FROM public.panelist_unavailability u
                                                 JOIN public.panelists p ON p.id = u.panelist_id
                                                  AND p.account_id = v_account_id AND p.status = 'active'
                                                WHERE p.node_id = dn.id AND u.account_id = v_account_id
                                                  AND u.status = 'active' AND g::date BETWEEN u.start_date AND u.end_date)))
     WHERE h.h_from <= h.h_to;
    UPDATE pg_temp.lb2_ship s SET defer_reason = NULL, frozen = true
      FROM pg_temp.lb2_hz h
     WHERE s.defer_reason = 'no_valid_day' AND h.has_slot
       AND h.dest_city = s.dest_city
       AND h.h_from = GREATEST(v_from, COALESCE(s.plan_start, v_from))
       AND h.h_to = COALESCE(s.plan_end, GREATEST(s.pl_end, p_end_date));
  END IF;

  -- 0c ter (R2). Nunca se borra una muestra con dependientes que el borrado arrastraria o desenlazaria:
  -- material_hold.allocation_plan_detail_id (CASCADE), shipment_incident.parcel_id (CASCADE),
  -- panelist_incident.allocation_plan_detail_id y one_db.allocation_detail_id (SET NULL). Se queda donde esta
  -- (congelada, carga fija) y se avisa con deferred_blocked. Las propuestas de panelist_reassignment_proposal SI
  -- caen en cascada: se refieren a una muestra que deja de existir en el plan (la anotacion conserva la fila).
  UPDATE pg_temp.lb2_ship s SET defer_reason = NULL, frozen = true, def_blocked = true
   WHERE s.defer_reason IS NOT NULL
     AND s.id IN (SELECT m.allocation_plan_detail_id FROM public.material_hold m
                   WHERE m.allocation_plan_detail_id IN (SELECT c.id FROM pg_temp.lb2_ship c WHERE c.defer_reason IS NOT NULL)
                  UNION
                  SELECT si.parcel_id FROM public.shipment_incident si
                   WHERE si.parcel_id IN (SELECT c.id FROM pg_temp.lb2_ship c WHERE c.defer_reason IS NOT NULL)
                  UNION
                  SELECT pi.allocation_plan_detail_id FROM public.panelist_incident pi
                   WHERE pi.allocation_plan_detail_id IN (SELECT c.id FROM pg_temp.lb2_ship c WHERE c.defer_reason IS NOT NULL)
                  UNION
                  SELECT o.allocation_detail_id FROM public.one_db o
                   WHERE o.allocation_detail_id IN (SELECT c.id FROM pg_temp.lb2_ship c WHERE c.defer_reason IS NOT NULL));
  SELECT count(*) INTO v_def_blocked FROM pg_temp.lb2_ship WHERE def_blocked;

  -- 0d. Las apartadas salen del calculo: no cuentan en totales del mes, objetivos, desviaciones ni matrices.
  CREATE TEMP TABLE pg_temp.lb2_defer (id uuid PRIMARY KEY, reason text NOT NULL) ON COMMIT DROP;
  INSERT INTO pg_temp.lb2_defer SELECT s.id, s.defer_reason FROM pg_temp.lb2_ship s WHERE s.defer_reason IS NOT NULL;
  SELECT count(*), count(*) FILTER (WHERE reason = 'origin_no_panelist'),
         count(*) FILTER (WHERE reason = 'dest_no_panelist'), count(*) FILTER (WHERE reason = 'no_valid_day')
    INTO v_def_removed, v_def_origin, v_def_dest, v_def_day
    FROM pg_temp.lb2_defer;
  DELETE FROM pg_temp.lb2_ship WHERE defer_reason IS NOT NULL;
  SELECT count(*) INTO v_def_reassigned FROM pg_temp.lb2_ship WHERE new_dest;
  SELECT count(*) INTO v_def_waiting FROM public.deferred_samples d
   WHERE d.account_id = v_account_id AND d.origin_city_id = p_city_id AND d.status = 'pending';
  v_def_waiting := v_def_waiting + v_def_removed;

  -- Filtro por fechas del plan en el reparto normal: una celda fuera de las fechas del plan de todos los envios
  -- de la ciudad no recibe objetivo (sin restricciones de plan no cambia nada).
  UPDATE pg_temp.lb2_cells c
     SET in_plan = EXISTS (SELECT 1 FROM pg_temp.lb2_ship s
                            WHERE s.plan_start IS NULL OR c.cell_date BETWEEN s.plan_start AND s.plan_end)
   WHERE TRUE;

  -- Celda actual de cada envio (si la tiene).
  IF v_date_policy = 'weekly' THEN
    UPDATE pg_temp.lb2_ship s SET cur_cell = c.cell_id
      FROM pg_temp.lb2_cells c
     WHERE c.node_id = s.cur_node
       AND c.week_start = date_trunc('week', s.fecha)::date
       AND c.month_start = date_trunc('month', s.fecha)::date
       AND c.month_start = s.month_key;
  ELSE
    UPDATE pg_temp.lb2_ship s SET cur_cell = c.cell_id
      FROM pg_temp.lb2_cells c
     WHERE c.node_id = s.cur_node AND c.cell_date = s.fecha;
  END IF;
  UPDATE pg_temp.lb2_cells c SET current_load = x.n
    FROM (SELECT cur_cell, count(*)::int AS n FROM pg_temp.lb2_ship WHERE cur_cell IS NOT NULL GROUP BY cur_cell) x
   WHERE x.cur_cell = c.cell_id;

  -- ===== 5. Objetivos. Tramos con al menos una celda; peso = dias laborables del tramo en el periodo.
  CREATE TEMP TABLE pg_temp.lb2_segs (
    week_start date, month_start date, seg_from date, wdays integer, ncells integer,
    share integer NOT NULL DEFAULT 0, base integer NOT NULL DEFAULT 0, rem integer NOT NULL DEFAULT 0,
    g integer NOT NULL DEFAULT 0, PRIMARY KEY (week_start, month_start)
  ) ON COMMIT DROP;
  INSERT INTO pg_temp.lb2_segs (week_start, month_start, seg_from, wdays, ncells)
  SELECT d.week_start, d.month_start, min(d.d), count(*)::int, x.ncells
    FROM pg_temp.lb2_days d
    JOIN (SELECT week_start, month_start, count(*)::int AS ncells FROM pg_temp.lb2_cells WHERE in_plan GROUP BY 1, 2) x
      ON x.week_start = d.week_start AND x.month_start = d.month_start
   WHERE EXISTS (SELECT 1 FROM pg_temp.lb2_ship s
                  WHERE s.plan_start IS NULL OR d.d BETWEEN s.plan_start AND s.plan_end)
   GROUP BY d.week_start, d.month_start, x.ncells;

  -- Envios congelados ANTES de calcular objetivos: destino sin panelista activo (ya marcados) y envios cuyo
  -- mes tiene celdas pero ninguna compatible (todas del nodo destino o en dias de ausencia del destino). Se
  -- quedan donde estan y cuentan como carga fija de su celda actual, si la tienen.
  UPDATE pg_temp.lb2_ship s SET frozen = true
   WHERE NOT s.frozen
     AND EXISTS (SELECT 1 FROM pg_temp.lb2_cells c WHERE c.month_start = s.month_key)
     AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_cells c
                      WHERE c.month_start = s.month_key AND c.node_id <> s.dest_node
                        AND (s.plan_start IS NULL OR c.cell_date BETWEEN s.plan_start AND s.plan_end)
                        AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs x WHERE x.node_id = s.dest_node AND x.d = c.cell_date));
  UPDATE pg_temp.lb2_cells c SET fixed = x.n
    FROM (SELECT cur_cell, count(*)::int AS n FROM pg_temp.lb2_ship WHERE frozen AND cur_cell IS NOT NULL GROUP BY cur_cell) x
   WHERE x.cur_cell = c.cell_id;

  -- 5a. Total del mes -> tramos (suelo + resto mayor; empate -> tramo mas temprano). El total es la carga
  -- final del mes: envios movibles + envios congelados que ya ocupan una celda del mes (carga fija). Los
  -- congelados fuera de toda celda no cuentan.
  WITH mt AS (SELECT month_key, sum(n)::numeric AS t
                FROM (SELECT month_key, count(*) AS n FROM pg_temp.lb2_ship WHERE NOT frozen GROUP BY month_key
                      UNION ALL
                      SELECT month_start, sum(fixed) FROM pg_temp.lb2_cells WHERE fixed > 0 GROUP BY month_start) u
               GROUP BY month_key),
  w AS (SELECT s.week_start, s.month_start, s.seg_from, mt.t,
               s.wdays * mt.t / sum(s.wdays) OVER (PARTITION BY s.month_start) AS raw
          FROM pg_temp.lb2_segs s JOIN mt ON mt.month_key = s.month_start),
  f AS (SELECT w.*, floor(w.raw)::int AS fl FROM w),
  r AS (SELECT f.*, f.t::int - sum(f.fl) OVER (PARTITION BY f.month_start) AS leftover,
               row_number() OVER (PARTITION BY f.month_start ORDER BY f.raw - f.fl DESC, f.seg_from) AS rk
          FROM f)
  UPDATE pg_temp.lb2_segs s SET share = r.fl + CASE WHEN r.rk <= r.leftover THEN 1 ELSE 0 END
    FROM r WHERE r.week_start = s.week_start AND r.month_start = s.month_start;
  UPDATE pg_temp.lb2_segs SET base = share / ncells, rem = share % ncells WHERE ncells > 0;
  v_had_remainder := EXISTS (SELECT 1 FROM pg_temp.lb2_segs WHERE rem > 0);

  -- 5b. Puntero de rotacion por tramo: empieza en balance_rotation_offset mod N y avanza tantos nodos como +1
  -- se repartieron en los tramos anteriores (asi los +1 no caen siempre en los mismos nodos).
  UPDATE pg_temp.lb2_segs s SET g = x.g
    FROM (SELECT week_start, month_start,
                 ((v_offset + COALESCE(sum(rem) OVER (ORDER BY seg_from ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0))
                   % NULLIF(v_n_nodes, 0))::int AS g
            FROM pg_temp.lb2_segs) x
   WHERE x.week_start = s.week_start AND x.month_start = s.month_start;

  -- 5c. Tramo -> celdas: base para todas; los rem +1 van por orden (vuelta, nodo rotado). La "vuelta" de una
  -- celda desplaza el dia segun el nodo, para que los +1 de nodos distintos caigan en dias distintos.
  WITH q AS (
    SELECT c.cell_id, c.week_start, c.month_start, c.cell_date, s.base, s.rem,
           (((c.valid_rank - s.g) % v_n_nodes) + v_n_nodes) % v_n_nodes AS qn, c.day_idx, c.node_cells
      FROM pg_temp.lb2_cells c JOIN pg_temp.lb2_segs s ON s.week_start = c.week_start AND s.month_start = c.month_start
     WHERE c.in_plan),
  o AS (
    SELECT q.cell_id, q.base, q.rem,
           row_number() OVER (PARTITION BY q.week_start, q.month_start
                              ORDER BY (((q.day_idx - q.qn) % q.node_cells) + q.node_cells) % q.node_cells,
                                       q.qn, q.cell_date) AS ord
      FROM q)
  UPDATE pg_temp.lb2_cells c SET target = o.base + CASE WHEN o.ord <= o.rem THEN 1 ELSE 0 END
    FROM o WHERE o.cell_id = c.cell_id;

  -- 5d. Carga fija: el objetivo de cada celda pasa a ser de envios MOVIBLES = objetivo total - fijos (>= 0).
  -- Si una celda tiene mas fijos que su objetivo, sobran huecos en el mes: se quitan los de nivel final
  -- (fijos + k) mas alto, de modo que cada mes tenga exactamente tantos huecos como envios movibles. Sin
  -- congelados no cambia nada.
  IF EXISTS (SELECT 1 FROM pg_temp.lb2_cells WHERE fixed > 0) THEN
    UPDATE pg_temp.lb2_cells SET target = GREATEST(target - fixed, 0)
     WHERE TRUE;
    WITH mm AS (SELECT month_key, count(*)::int AS m FROM pg_temp.lb2_ship WHERE NOT frozen GROUP BY month_key),
    u AS (SELECT c.cell_id, c.month_start,
                 row_number() OVER (PARTITION BY c.month_start ORDER BY c.fixed + k.k, c.cell_date, c.valid_rank, k.k) AS rn
            FROM pg_temp.lb2_cells c CROSS JOIN LATERAL generate_series(1, c.target) k(k)),
    kp AS (SELECT u.cell_id, count(*)::int AS n
             FROM u LEFT JOIN mm ON mm.month_key = u.month_start
            WHERE u.rn <= COALESCE(mm.m, 0) GROUP BY u.cell_id)
    UPDATE pg_temp.lb2_cells c SET target = COALESCE(kp.n, 0)
      FROM pg_temp.lb2_cells c2 LEFT JOIN kp ON kp.cell_id = c2.cell_id
     WHERE c2.cell_id = c.cell_id;
  END IF;

  -- ===== 6. Asignacion con minimos movimientos.
  -- 6a. En cada celda se quedan hasta 'target' envios (los de fecha mas temprana; sale primero el mas lejano).
  -- Un envio cuyo destino esta ausente ese dia (o no tiene panelista activo) no puede quedarse: es excedente.
  WITH k AS (
    SELECT s.id, c.target,
           row_number() OVER (PARTITION BY s.cur_cell ORDER BY s.fecha, s.id) AS rn
      FROM pg_temp.lb2_ship s JOIN pg_temp.lb2_cells c ON c.cell_id = s.cur_cell
     WHERE NOT s.frozen
       AND c.month_start = s.month_key
       AND (s.plan_start IS NULL OR c.cell_date BETWEEN s.plan_start AND s.plan_end)
       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs x WHERE x.node_id = s.dest_node AND x.d = c.cell_date))
  UPDATE pg_temp.lb2_ship s SET keep = true, new_cell = s.cur_cell
    FROM k WHERE k.id = s.id AND k.rn <= k.target;
  UPDATE pg_temp.lb2_cells c SET kept = x.n
    FROM (SELECT cur_cell, count(*)::int AS n FROM pg_temp.lb2_ship WHERE keep GROUP BY cur_cell) x
   WHERE x.cur_cell = c.cell_id;

  -- 6b. Excedentes (sobrantes de celdas por encima del objetivo + envios fuera de toda celda) contra huecos de
  -- celdas deficitarias del MISMO mes. Ambos lados ordenados por fecha: el emparejamiento ordenado minimiza la
  -- distancia total en dias. Por construccion, en cada mes con celdas hay tantos huecos como excedentes.
  WITH ex AS (
    SELECT s.id, s.month_key,
           row_number() OVER (PARTITION BY s.month_key ORDER BY s.fecha, s.cur_rank, s.id) AS rk
      FROM pg_temp.lb2_ship s WHERE NOT s.keep AND NOT s.frozen),
  sl AS (
    SELECT c.cell_id, c.month_start,
           row_number() OVER (PARTITION BY c.month_start ORDER BY c.cell_date, c.valid_rank, k.k) AS rk
      FROM pg_temp.lb2_cells c CROSS JOIN LATERAL generate_series(1, c.target - c.kept) k(k)
     WHERE c.target > c.kept)
  UPDATE pg_temp.lb2_ship s SET new_cell = sl.cell_id
    FROM ex JOIN sl ON sl.month_start = ex.month_key AND sl.rk = ex.rk
   WHERE s.id = ex.id;

  -- 6c. Celda incompatible con el envio: origen = destino (ruta dentro de la ciudad), destino ausente ese dia o
  -- destino sin panelista activo. Se intercambia la celda con otro excedente del mismo mes compatible en ambos
  -- sentidos. Si no hay: origen = destino => el envio se queda donde esta (aviso origin_equals_destination);
  -- destino ausente => celda compatible mas cercana del mismo mes (la menos cargada), y si no existe o el destino
  -- no tiene panelista activo, el envio se queda donde esta (aviso no_valid_cell). Bucle vacio con datos normales.
  FOR v_conf IN
    SELECT s.id FROM pg_temp.lb2_ship s JOIN pg_temp.lb2_cells c ON c.cell_id = s.new_cell
     WHERE NOT s.keep
       AND (c.node_id = s.dest_node OR s.dest_bad
            OR EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs x WHERE x.node_id = s.dest_node AND x.d = c.cell_date)
            OR (s.plan_start IS NOT NULL AND c.cell_date NOT BETWEEN s.plan_start AND s.plan_end))
     ORDER BY s.fecha, s.id
  LOOP
    -- dabs: dia no valido para el envio (destino ausente o fuera de las fechas de su plan)
    SELECT s.new_cell, s.month_key, s.dest_node, s.dest_bad, s.fecha, s.plan_start, s.plan_end, c.node_id, c.cell_date,
           (EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs x WHERE x.node_id = s.dest_node AND x.d = c.cell_date)
            OR (s.plan_start IS NOT NULL AND c.cell_date NOT BETWEEN s.plan_start AND s.plan_end)) AS dabs
      INTO v_cur FROM pg_temp.lb2_ship s JOIN pg_temp.lb2_cells c ON c.cell_id = s.new_cell WHERE s.id = v_conf.id;
    -- ya resuelto por un intercambio previo
    CONTINUE WHEN NOT FOUND OR (v_cur.node_id <> v_cur.dest_node AND NOT v_cur.dest_bad AND NOT v_cur.dabs);
    IF v_cur.dest_bad THEN
      UPDATE pg_temp.lb2_ship SET new_cell = NULL WHERE id = v_conf.id;
      CONTINUE;
    END IF;
    SELECT s2.id, s2.new_cell INTO v_other
      FROM pg_temp.lb2_ship s2 JOIN pg_temp.lb2_cells c2 ON c2.cell_id = s2.new_cell
     WHERE NOT s2.keep AND s2.month_key = v_cur.month_key AND s2.id <> v_conf.id AND NOT s2.dest_bad
       AND c2.node_id <> v_cur.dest_node AND s2.dest_node IS DISTINCT FROM v_cur.node_id
       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs x WHERE x.node_id = v_cur.dest_node AND x.d = c2.cell_date)
       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs x WHERE x.node_id = s2.dest_node AND x.d = v_cur.cell_date)
       AND (v_cur.plan_start IS NULL OR c2.cell_date BETWEEN v_cur.plan_start AND v_cur.plan_end)
       AND (s2.plan_start IS NULL OR v_cur.cell_date BETWEEN s2.plan_start AND s2.plan_end)
     ORDER BY abs(c2.cell_date - v_cur.fecha), c2.cell_date
     LIMIT 1;
    IF FOUND THEN
      UPDATE pg_temp.lb2_ship SET new_cell = v_cur.new_cell WHERE id = v_other.id;
      UPDATE pg_temp.lb2_ship SET new_cell = v_other.new_cell WHERE id = v_conf.id;
    ELSIF NOT v_cur.dabs THEN
      UPDATE pg_temp.lb2_ship SET new_cell = NULL, od_conflict = true WHERE id = v_conf.id;
    ELSE
      v_fb_cell := NULL;
      SELECT c3.cell_id INTO v_fb_cell
        FROM pg_temp.lb2_cells c3
       WHERE c3.month_start = v_cur.month_key AND c3.node_id <> v_cur.dest_node
         AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs x WHERE x.node_id = v_cur.dest_node AND x.d = c3.cell_date)
         AND (v_cur.plan_start IS NULL OR c3.cell_date BETWEEN v_cur.plan_start AND v_cur.plan_end)
       ORDER BY abs(c3.cell_date - v_cur.cell_date),
                (SELECT count(*) FROM pg_temp.lb2_ship x WHERE x.new_cell = c3.cell_id) + c3.fixed, c3.cell_date, c3.valid_rank
       LIMIT 1;
      UPDATE pg_temp.lb2_ship SET new_cell = v_fb_cell WHERE id = v_conf.id;
    END IF;
  END LOOP;

  -- Los que 6c deja sin celda (origen = destino sin intercambio posible; raro, porque tienen celdas
  -- compatibles) se quedan donde estan: tambien cuentan como carga fija en su celda actual para new_load,
  -- matrix_after y stddev_after. No se recalculan los objetivos: repetir la asignacion congelaria en cascada
  -- envios que si se podian mover (su hueco queda libre; ver aviso origin_equals_destination).
  UPDATE pg_temp.lb2_ship SET frozen = true WHERE NOT frozen AND new_cell IS NULL;

  -- ===== 6R. REINTRODUCCION de muestras por compensar (spec 2026-10-28, 3.2). Despues de la equidad y antes de
  -- POBOX. Candidatas: anotaciones 'pending' cuya ciudad origen es esta. Cada una se coloca en un hueco valido:
  --   * dia laborable de la cuenta en [v_from, fin] y desde el inicio de su plan (plan 'active'; el fin del plan no acota);
  --   * nodo origen: el original si es valido y no esta ausente ese dia; si no, el menos cargado de la ciudad;
  --   * nodo destino: el original si es valido y no esta ausente ese dia; si no, el de menos recepciones ese dia
  --     de la ciudad destino de la anotacion (la ruta ciudad->ciudad no cambia); siempre distinto del nodo origen;
  --   * dia con menos envios del nodo origen (empate: menos recepciones del destino ese dia, menos envios de la
  --     ciudad, fecha); topes TOTALES: como maximo 1 fila 'compensation' por (nodo origen, dia) y 1 por (nodo
  --     destino, dia), contando las que ya existen en el plan (repetir el balanceo no las apila).
  -- La fecha de fin del plan NO acota la ventana (solo el inicio del plan, v_from, manana y p_end_date).
  -- Las que no caben esperan con un motivo (plan_inactive, outside_period, no_origin_panelist,
  -- no_dest_panelist, no_capacity) que solo se escribe al aplicar. Las anotaciones apartadas en ESTA ejecucion
  -- (fase 0) aun no estan en el registro: no se reintroducen hasta el siguiente balanceo.
  -- (Sin indices: pocas filas; cada objeto temporal cuesta tiempo de catalogo en cada llamada.)
  CREATE TEMP TABLE pg_temp.lb2_reint (
    id uuid NOT NULL, ds_id uuid NOT NULL, plan_id uuid, o_node uuid, d_node uuid, d date,
    o_pid uuid, o_pname text, d_pid uuid, d_pname text, ds_o_node uuid, ds_d_node uuid, cell_id integer,
    -- sustitucion: id de la fila 'pobox' que se convierte (id = pb_id) y su destino anterior; NULL = fila nueva
    pb_id uuid, pb_old_dest uuid
  ) ON COMMIT DROP;

  -- Al aplicar, las anotaciones de la ciudad se bloquean antes de leerlas (ademas del candado por ciudad).
  IF p_apply_changes THEN
    PERFORM 1 FROM public.deferred_samples d
     WHERE d.account_id = v_account_id AND d.origin_city_id = p_city_id AND d.status = 'pending'
       FOR UPDATE;
  END IF;
  v_rc_any := EXISTS (SELECT 1 FROM public.deferred_samples d
                       WHERE d.account_id = v_account_id AND d.origin_city_id = p_city_id AND d.status = 'pending');
  IF v_rc_any THEN
    CREATE TEMP TABLE pg_temp.lb2_rcand (
      ds_id uuid NOT NULL, ord integer, plan_id uuid, o_node uuid, d_node uuid, dest_city uuid,
      ps date, pe date, plan_ok boolean NOT NULL, placed boolean NOT NULL DEFAULT false, waiting text
    ) ON COMMIT DROP;
    -- Nunca HOY (R9): los avisos del dia (n8n, fecha_programada = hoy) pueden haber salido ya y una muestra
    -- colocada hoy despues quedaria sin notificar y atrasada. La fase R empieza manana (el primer dia laborable
    -- >= manana). La cobertura de HOY por POBOX (mover/crear) no cambia (comportamiento previo).
    INSERT INTO pg_temp.lb2_rcand (ds_id, ord, plan_id, o_node, d_node, dest_city, ps, pe, plan_ok)
    SELECT d.id, (row_number() OVER (ORDER BY d.fecha_programada, d.created_at, d.id))::int, d.plan_id,
           d.origin_node_id, d.destination_node_id, d.dest_city_id,
           GREATEST(pl.start_date, v_from, v_today + 1), p_end_date,
           COALESCE(pl.status = 'active', false)
      FROM public.deferred_samples d
      LEFT JOIN public.allocation_plans pl ON pl.id = d.plan_id AND pl.account_id = v_account_id
     WHERE d.account_id = v_account_id AND d.origin_city_id = p_city_id AND d.status = 'pending';
    UPDATE pg_temp.lb2_rcand SET waiting = 'plan_inactive' WHERE NOT plan_ok;
    UPDATE pg_temp.lb2_rcand c SET waiting = 'outside_period'
     WHERE c.waiting IS NULL
       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_days dd WHERE dd.d BETWEEN c.ps AND c.pe);
    -- Ciudad origen sin ningun nodo valido: esperan sin construir la fase R.
    IF v_n_nodes = 0 THEN
      UPDATE pg_temp.lb2_rcand SET waiting = 'no_origin_panelist' WHERE waiting IS NULL;
    END IF;

    IF EXISTS (SELECT 1 FROM pg_temp.lb2_rcand WHERE waiting IS NULL) THEN
      -- Rejilla (nodo origen valido, dia laborable sin ausencia) con la carga tras la equidad. cell_id = celda de la
      -- matriz donde cuenta (diaria: la del dia; semanal: la del tramo). Politica semanal: la reintroducida
      -- conserva su dia real (no se lleva al primer dia del tramo; la spec no lo fija) y cuenta en su tramo.
      CREATE TEMP TABLE pg_temp.lb2_rload (
        node_id uuid, d date, vrank integer, cell_id integer,
        base integer NOT NULL DEFAULT 0, added integer NOT NULL DEFAULT 0
      ) ON COMMIT DROP;
      IF v_date_policy = 'weekly' THEN
        INSERT INTO pg_temp.lb2_rload (node_id, d, vrank, cell_id)
        SELECT n.node_id, dd.d, n.valid_rank, c.cell_id
          FROM pg_temp.lb2_nodes n
          CROSS JOIN pg_temp.lb2_days dd
          JOIN pg_temp.lb2_cells c ON c.node_id = n.node_id AND c.week_start = dd.week_start AND c.month_start = dd.month_start
         WHERE n.valid
           AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_absent a WHERE a.node_id = n.node_id AND a.d = dd.d);
      ELSE
        -- diaria: las celdas ya son exactamente (nodo valido, dia laborable sin ausencia)
        INSERT INTO pg_temp.lb2_rload (node_id, d, vrank, cell_id)
        SELECT c.node_id, c.cell_date, c.valid_rank, c.cell_id FROM pg_temp.lb2_cells c;
      END IF;
      -- Envios no cancelados con origen en la ciudad tras la equidad: los del periodo en su nueva celda (los
      -- congelados donde estan) y el resto (no pendientes) donde estan; las apartadas no cuentan. Tope TOTAL
      -- (no por ejecucion): 'added' parte de las filas 'compensation' que YA hay en ese (nodo, dia) y 'base' cuenta
      -- el resto; asi repetir el balanceo sobre el mismo periodo no apila mas de 1 compensation por (nodo, dia).
      -- Una sola sentencia: carga por (nodo, dia) en lb2_rload y carga de la ciudad por dia en lb2_rday.
      CREATE TEMP TABLE pg_temp.lb2_rday (d date NOT NULL, n integer NOT NULL DEFAULT 0) ON COMMIT DROP;
      WITH src AS (
        SELECT COALESCE(c.node_id, s.cur_node) AS node_id, COALESCE(c.cell_date, s.fecha) AS d,
               (a.generation_source = 'compensation') AS comp
          FROM pg_temp.lb2_ship s
          JOIN public.allocation_plan_details a ON a.id = s.id
          LEFT JOIN pg_temp.lb2_cells c ON c.cell_id = s.new_cell AND NOT s.frozen
        UNION ALL
        SELECT a.origin_node_id, a.fecha_programada, (a.generation_source = 'compensation')
          FROM public.allocation_plan_details a
          JOIN pg_temp.lb2_nodes n ON n.node_id = a.origin_node_id
         WHERE a.account_id = v_account_id AND a.status <> 'cancelled'
           AND a.fecha_programada BETWEEN v_from AND p_end_date
           AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_ship s WHERE s.id = a.id)
           AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_defer x WHERE x.id = a.id)),
      upd AS (
        UPDATE pg_temp.lb2_rload g SET base = x.nb, added = x.nc
          FROM (SELECT node_id, d, (count(*) FILTER (WHERE NOT comp))::int AS nb,
                       (count(*) FILTER (WHERE comp))::int AS nc
                  FROM src GROUP BY node_id, d) x
         WHERE x.node_id = g.node_id AND x.d = g.d
        RETURNING 1)
      INSERT INTO pg_temp.lb2_rday (d, n)
      SELECT dd.d, COALESCE(x.n, 0)
        FROM pg_temp.lb2_days dd
        LEFT JOIN (SELECT d, count(*)::int AS n FROM src GROUP BY d) x ON x.d = dd.d;

      -- Destinos posibles: nodos activos con panelista activo de las ciudades destino de las candidatas.
      CREATE TEMP TABLE pg_temp.lb2_rdest (
        node_id uuid NOT NULL, city_id uuid, node_code text, panelist_id uuid, panelist_name text
      ) ON COMMIT DROP;
      INSERT INTO pg_temp.lb2_rdest
      SELECT n.id, n.city_id, n.auto_id, pan.id, pan.name::text
        FROM public.nodes n
        JOIN LATERAL (SELECT p.id, p.name FROM public.panelists p
                       WHERE p.node_id = n.id AND p.account_id = v_account_id AND p.status = 'active'
                       ORDER BY p.created_at, p.id LIMIT 1) pan ON true
       WHERE n.account_id = v_account_id AND n.status = 'active'
         AND n.city_id IN (SELECT DISTINCT c.dest_city FROM pg_temp.lb2_rcand c WHERE c.waiting IS NULL);
      -- Huecos de destino: (nodo destino valido, dia laborable del periodo sin ausencia). recv = recepciones no
      -- canceladas ese dia (las de esta ciudad en su dia tras la equidad); comp = de ellas, 'compensation' (de
      -- cualquier ciudad origen). Tope TOTAL de recepcion: como mucho 1 compensation por (nodo destino, dia).
      CREATE TEMP TABLE pg_temp.lb2_rdslot (
        city_id uuid, node_id uuid, node_code text, d date,
        recv integer NOT NULL DEFAULT 0, comp integer NOT NULL DEFAULT 0
      ) ON COMMIT DROP;
      INSERT INTO pg_temp.lb2_rdslot (city_id, node_id, node_code, d)
      SELECT t.city_id, t.node_id, t.node_code, dd.d
        FROM pg_temp.lb2_rdest t CROSS JOIN pg_temp.lb2_days dd
       WHERE NOT EXISTS (SELECT 1 FROM public.panelist_unavailability u
                           JOIN public.panelists p ON p.id = u.panelist_id AND p.account_id = v_account_id AND p.status = 'active'
                          WHERE p.node_id = t.node_id AND u.account_id = v_account_id AND u.status = 'active'
                            AND dd.d BETWEEN u.start_date AND u.end_date);
      WITH rc AS (
        SELECT s.dest_node AS node_id, COALESCE(c.cell_date, s.fecha) AS d, (a.generation_source = 'compensation') AS comp
          FROM pg_temp.lb2_ship s
          JOIN public.allocation_plan_details a ON a.id = s.id
          LEFT JOIN pg_temp.lb2_cells c ON c.cell_id = s.new_cell AND NOT s.frozen
        UNION ALL
        SELECT a.destination_node_id, a.fecha_programada, (a.generation_source = 'compensation')
          FROM public.allocation_plan_details a
         WHERE a.account_id = v_account_id AND a.status <> 'cancelled'
           AND a.destination_node_id IN (SELECT t.node_id FROM pg_temp.lb2_rdest t)
           AND a.fecha_programada BETWEEN v_from AND p_end_date
           AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_ship s WHERE s.id = a.id)
           AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_defer x WHERE x.id = a.id))
      UPDATE pg_temp.lb2_rdslot r SET recv = x.n, comp = x.nc
        FROM (SELECT node_id, d, count(*)::int AS n, (count(*) FILTER (WHERE comp))::int AS nc
                FROM rc GROUP BY node_id, d) x
       WHERE x.node_id = r.node_id AND x.d = r.d;
      -- Estadisticas para que el planificador elija bien las uniones de la busqueda por candidata.
      ANALYZE pg_temp.lb2_rload;
      ANALYZE pg_temp.lb2_rdslot;
      ANALYZE pg_temp.lb2_rday;

      -- Sustitucion (antes que colocar como extra): las anotaciones ocupan el hueco de una fila 'pobox' pendiente
      -- de esta ciudad, en su (nodo origen, dia) tras la equidad. Solo filas sin material, incidencias ni lecturas
      -- enlazadas y en un (nodo, dia) valido de la rejilla (lb2_rload ya excluye hoy-fence, ausencias y no laborables;
      -- el dia >= manana lo pone c.ps). La ruta es la de la anotacion: destino original si es valido ese dia, si no otro
      -- de su ciudad destino. Mismos topes de 1 compensation por (nodo origen, dia) y (nodo destino, dia).
      CREATE TEMP TABLE pg_temp.lb2_rpb (
        id uuid NOT NULL, node_id uuid, d date, dest_node uuid, used boolean NOT NULL DEFAULT false
      ) ON COMMIT DROP;
      INSERT INTO pg_temp.lb2_rpb (id, node_id, d, dest_node)
      SELECT s.id, COALESCE(c.node_id, s.cur_node), COALESCE(c.cell_date, s.fecha), s.dest_node
        FROM pg_temp.lb2_ship s
        JOIN public.allocation_plan_details a ON a.id = s.id AND a.generation_source = 'pobox'
        LEFT JOIN pg_temp.lb2_cells c ON c.cell_id = s.new_cell AND NOT s.frozen
       WHERE NOT EXISTS (SELECT 1 FROM public.material_hold m WHERE m.allocation_plan_detail_id = s.id)
         AND NOT EXISTS (SELECT 1 FROM public.shipment_incident si WHERE si.parcel_id = s.id)
         AND NOT EXISTS (SELECT 1 FROM public.panelist_incident pi WHERE pi.allocation_plan_detail_id = s.id)
         AND NOT EXISTS (SELECT 1 FROM public.one_db o WHERE o.allocation_detail_id = s.id);
      IF EXISTS (SELECT 1 FROM pg_temp.lb2_rpb) THEN
        FOR v_rc IN
          SELECT c.ds_id, c.plan_id, c.o_node, c.d_node, c.dest_city, c.ps, c.pe
            FROM pg_temp.lb2_rcand c WHERE c.waiting IS NULL ORDER BY c.ord
        LOOP
          SELECT p.id, p.node_id, p.d, p.dest_node, t.node_id, g.cell_id
            INTO v_mv_id, v_r_onode, v_r_day, v_dst_node, v_r_dnode, v_r_cell
            FROM pg_temp.lb2_rpb p
            JOIN pg_temp.lb2_rload g ON g.node_id = p.node_id AND g.d = p.d
            JOIN pg_temp.lb2_rdslot t ON t.city_id = v_rc.dest_city AND t.d = p.d AND t.node_id <> p.node_id
            LEFT JOIN pg_temp.lb2_rdslot td ON td.node_id = v_rc.d_node AND td.d = p.d AND td.node_id <> p.node_id
           WHERE NOT p.used
             AND p.d BETWEEN v_rc.ps AND v_rc.pe
             AND g.added = 0
             AND t.comp = 0
             AND (t.node_id = v_rc.d_node OR td.node_id IS NULL)
           ORDER BY p.d, t.recv, t.node_code, t.node_id, p.id
           LIMIT 1;
          CONTINUE WHEN NOT FOUND;
          INSERT INTO pg_temp.lb2_reint (id, ds_id, plan_id, o_node, d_node, d, o_pid, o_pname, d_pid, d_pname,
                                         ds_o_node, ds_d_node, cell_id, pb_id, pb_old_dest)
          SELECT v_mv_id, v_rc.ds_id, v_rc.plan_id, v_r_onode, v_r_dnode, v_r_day, n.panelist_id, n.panelist_name,
                 t.panelist_id, t.panelist_name, v_rc.o_node, v_rc.d_node, NULL, v_mv_id, v_dst_node
            FROM pg_temp.lb2_nodes n, pg_temp.lb2_rdest t
           WHERE n.node_id = v_r_onode AND t.node_id = v_r_dnode;
          UPDATE pg_temp.lb2_rpb SET used = true WHERE id = v_mv_id;
          -- el envio ya contaba en la carga del origen: pasa de 'base' a 'added' (sin envio extra)
          UPDATE pg_temp.lb2_rload SET base = base - 1, added = added + 1 WHERE node_id = v_r_onode AND d = v_r_day;
          UPDATE pg_temp.lb2_rdslot SET recv = recv + 1, comp = comp + 1 WHERE node_id = v_r_dnode AND d = v_r_day;
          UPDATE pg_temp.lb2_rdslot SET recv = recv - 1 WHERE node_id = v_dst_node AND d = v_r_day;
        END LOOP;
      END IF;
      SELECT count(*) INTO v_pb_replaced FROM pg_temp.lb2_reint WHERE pb_id IS NOT NULL;

      -- Una a una (orden: fecha original, alta) para que la carga de las ya colocadas cuente en las siguientes.
      -- Se elige (nodo origen, dia, nodo destino) a la vez:
      --   * origen: el original si ese dia es valido; si no, cualquier nodo valido de la ciudad ese dia;
      --   * destino: el original si ese dia es valido (y distinto del origen); si no, otro de la ciudad destino;
      --   * topes totales: 0 compensation previas en (origen, dia) y en (destino, dia);
      --   * orden: menos envios del nodo origen ese dia, menos recepciones del destino ese dia, menos envios de la
      --     ciudad ese dia (prefiere los dias vacios), fecha.
      FOR v_rc IN
        SELECT c.ds_id, c.plan_id, c.o_node, c.d_node, c.dest_city, c.ps, c.pe
          FROM pg_temp.lb2_rcand c WHERE c.waiting IS NULL
           AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_reint r WHERE r.ds_id = c.ds_id)   -- ya sustituyo a una 'pobox'
         ORDER BY c.ord
      LOOP
        SELECT g.node_id, g.d, g.cell_id, t.node_id INTO v_r_onode, v_r_day, v_r_cell, v_r_dnode
          FROM pg_temp.lb2_rload g
          JOIN pg_temp.lb2_rday y ON y.d = g.d
          JOIN pg_temp.lb2_rdslot t ON t.city_id = v_rc.dest_city AND t.d = g.d AND t.node_id <> g.node_id
          -- el nodo origen / destino original, si ese dia es valido (si lo es, solo se usa el original)
          LEFT JOIN pg_temp.lb2_rload go ON go.node_id = v_rc.o_node AND go.d = g.d
          LEFT JOIN pg_temp.lb2_rdslot td ON td.node_id = v_rc.d_node AND td.d = g.d AND td.node_id <> g.node_id
         WHERE g.d BETWEEN v_rc.ps AND v_rc.pe
           AND g.added = 0                                       -- tope origen: 1 compensation por (nodo, dia)
           AND t.comp = 0                                        -- tope destino: 1 compensation por (nodo, dia)
           AND (g.node_id = v_rc.o_node OR go.node_id IS NULL)
           AND (t.node_id = v_rc.d_node OR td.node_id IS NULL)
         ORDER BY g.base + g.added, t.recv, y.n, g.d, g.vrank, t.node_code, t.node_id
         LIMIT 1;
        IF NOT FOUND THEN
          -- Sin ningun (nodo origen, dia) con hueco: las demas tampoco caben.
          EXIT WHEN NOT EXISTS (SELECT 1 FROM pg_temp.lb2_rload WHERE added = 0);
          CONTINUE;
        END IF;
        INSERT INTO pg_temp.lb2_reint (id, ds_id, plan_id, o_node, d_node, d, o_pid, o_pname, d_pid, d_pname,
                                       ds_o_node, ds_d_node, cell_id)
        SELECT gen_random_uuid(), v_rc.ds_id, v_rc.plan_id, v_r_onode, v_r_dnode, v_r_day, n.panelist_id,
               n.panelist_name, t.panelist_id, t.panelist_name, v_rc.o_node, v_rc.d_node, v_r_cell
          FROM pg_temp.lb2_nodes n, pg_temp.lb2_rdest t
         WHERE n.node_id = v_r_onode AND t.node_id = v_r_dnode;
        UPDATE pg_temp.lb2_rload SET added = added + 1 WHERE node_id = v_r_onode AND d = v_r_day;
        UPDATE pg_temp.lb2_rday SET n = n + 1 WHERE d = v_r_day;
        UPDATE pg_temp.lb2_rdslot SET recv = recv + 1, comp = comp + 1 WHERE node_id = v_r_dnode AND d = v_r_day;
      END LOOP;
      UPDATE pg_temp.lb2_rcand c SET placed = true WHERE c.ds_id IN (SELECT r.ds_id FROM pg_temp.lb2_reint r);

      -- Motivo de espera de las que no se colocaron.
      UPDATE pg_temp.lb2_rcand c
         SET waiting = CASE
               WHEN NOT EXISTS (SELECT 1 FROM pg_temp.lb2_rload g WHERE g.d BETWEEN c.ps AND c.pe)
                 THEN 'no_origin_panelist'
               WHEN NOT EXISTS (SELECT 1 FROM pg_temp.lb2_rload g
                                  JOIN pg_temp.lb2_rdslot t ON t.city_id = c.dest_city AND t.d = g.d
                                                           AND t.node_id <> g.node_id
                                 WHERE g.d BETWEEN c.ps AND c.pe)
                 THEN 'no_dest_panelist'
               ELSE 'no_capacity' END
       WHERE NOT c.placed AND c.waiting IS NULL;
    END IF;
  END IF;   -- v_rc_any

  -- ===== 6P. FASE POBOX (spec seccion 6). Con POBOX efectiva la politica es 'daily': una celda (nodo, dia)
  -- existe si y solo si el nodo es valido y esta disponible ese dia laborable >= v_from.
  CREATE TEMP TABLE pg_temp.lb2_new (
    id uuid PRIMARY KEY, plan_id uuid, origin_node uuid, origin_cell integer, dest_node uuid, d date
  ) ON COMMIT DROP;

  IF v_pobox THEN
    -- Estado tras la equidad: un registro por envio no cancelado con origen en la ciudad. Los pendientes del
    -- periodo (lb2_ship) son movibles y llevan el rango de su plan; el resto es fijo. Ventana: desde el lunes
    -- de la semana de v_from hasta fin + 6 (para contar la carga de semanas completas).
    CREATE TEMP TABLE pg_temp.lb2_pb (
      id uuid PRIMARY KEY, node_id uuid, d date, movable boolean, plan_start date, plan_end date,
      dest_node uuid, dest_bad boolean NOT NULL DEFAULT false,
      reint boolean NOT NULL DEFAULT false,  -- muestra reintroducida en esta ejecucion (fase R)
      comp boolean NOT NULL DEFAULT false    -- fila 'compensation' (ya existente o de esta ejecucion)
    ) ON COMMIT DROP;
    INSERT INTO pg_temp.lb2_pb (id, node_id, d, movable, plan_start, plan_end, dest_node, dest_bad, comp)
    SELECT s.id, COALESCE(c.node_id, s.cur_node), COALESCE(c.cell_date, s.fecha), NOT s.frozen, p.start_date, p.end_date,
           s.dest_node, s.dest_bad, s.comp
      FROM pg_temp.lb2_ship s
      LEFT JOIN pg_temp.lb2_cells c ON c.cell_id = s.new_cell
      JOIN public.allocation_plan_details a ON a.id = s.id
      LEFT JOIN public.allocation_plans p ON p.id = a.plan_id;
    INSERT INTO pg_temp.lb2_pb (id, node_id, d, movable, plan_start, plan_end, dest_node, dest_bad, comp)
    SELECT a.id, a.origin_node_id, a.fecha_programada, false, NULL, NULL, a.destination_node_id,
           -- pendiente/avisada hacia un destino sin panelista activo: no saldra (el bot no la avisa)
           a.status IN ('pending', 'notified')
             AND NOT EXISTS (SELECT 1 FROM public.panelists p WHERE p.node_id = a.destination_node_id
                               AND p.account_id = v_account_id AND p.status = 'active'),
           a.generation_source = 'compensation'
      FROM public.allocation_plan_details a
      JOIN pg_temp.lb2_nodes n ON n.node_id = a.origin_node_id
     WHERE a.account_id = v_account_id
       AND a.status <> 'cancelled'
       AND a.fecha_programada BETWEEN date_trunc('week', v_from)::date AND p_end_date + 6
       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_ship s WHERE s.id = a.id)
       -- las que se apartan al registro ya no cubren su dia
       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_defer d WHERE d.id = a.id);
    CREATE INDEX ON pg_temp.lb2_pb (d);
    CREATE INDEX ON pg_temp.lb2_pb (node_id, d);

    -- Planes activos de la cuenta que tocan el periodo y su avance (no pendientes / total).
    CREATE TEMP TABLE pg_temp.lb2_plans (
      plan_id uuid PRIMARY KEY, start_date date, end_date date, progress numeric, product_id uuid
    ) ON COMMIT DROP;
    INSERT INTO pg_temp.lb2_plans
    SELECT p.id, p.start_date, p.end_date,
           COALESCE((SELECT (count(*) FILTER (WHERE x.status <> 'pending'))::numeric / NULLIF(count(*), 0)
                       FROM public.allocation_plan_details x
                      WHERE x.plan_id = p.id AND x.account_id = v_account_id), 0),
           p.product_id
      FROM public.allocation_plans p
     WHERE p.account_id = v_account_id AND p.status = 'active'
       AND p.start_date <= p_end_date AND p.end_date >= v_from;

    -- Reparto de las 'pobox' por producto (account_config.pobox_product_shares). cnt = 'pobox' no canceladas de la
    -- cuenta por producto; se suman las que se crean en esta ejecucion. Sin reparto la tabla queda vacia.
    CREATE TEMP TABLE pg_temp.lb2_pshare (product_id uuid PRIMARY KEY, pct integer, cnt integer) ON COMMIT DROP;
    INSERT INTO pg_temp.lb2_pshare
    SELECT (s->>'product_id')::uuid, (s->>'pct')::int,
           (SELECT count(*) FROM public.allocation_plan_details a
              JOIN public.allocation_plans ap ON ap.id = a.plan_id
             WHERE a.account_id = v_account_id AND a.generation_source = 'pobox' AND a.status <> 'cancelled'
               AND ap.product_id = (s->>'product_id')::uuid)::int
      FROM public.account_config ac CROSS JOIN LATERAL jsonb_array_elements(ac.pobox_product_shares) s
     WHERE ac.account_id = v_account_id AND (s->>'pct')::int > 0
    ON CONFLICT DO NOTHING;

    -- Ciudades que ya son destino de esta ciudad en cada plan (rutas existentes).
    CREATE TEMP TABLE pg_temp.lb2_routes (plan_id uuid, city_id uuid, PRIMARY KEY (plan_id, city_id)) ON COMMIT DROP;
    INSERT INTO pg_temp.lb2_routes
    SELECT DISTINCT x.plan_id, dn.city_id
      FROM public.allocation_plan_details x
      JOIN pg_temp.lb2_nodes o ON o.node_id = x.origin_node_id
      JOIN public.nodes dn ON dn.id = x.destination_node_id AND dn.account_id = v_account_id
      JOIN pg_temp.lb2_plans pl ON pl.plan_id = x.plan_id
     WHERE x.account_id = v_account_id AND x.status <> 'cancelled' AND dn.city_id <> p_city_id;

    -- Destinos posibles: nodos activos con panelista activo de OTRA ciudad de la cuenta.
    CREATE TEMP TABLE pg_temp.lb2_dest (
      node_id uuid PRIMARY KEY, city_id uuid, node_code text, panelist_id uuid, panelist_name text
    ) ON COMMIT DROP;
    INSERT INTO pg_temp.lb2_dest
    SELECT n.id, n.city_id, n.auto_id, pan.id, pan.name::text
      FROM public.nodes n
      JOIN public.cities c ON c.id = n.city_id AND c.account_id = v_account_id
      JOIN LATERAL (SELECT p.id, p.name FROM public.panelists p
                     WHERE p.node_id = n.id AND p.account_id = v_account_id AND p.status = 'active'
                     ORDER BY p.created_at, p.id LIMIT 1) pan ON true
     WHERE n.account_id = v_account_id AND n.city_id <> p_city_id AND n.status = 'active';
    CREATE TEMP TABLE pg_temp.lb2_dabsent (node_id uuid, d date, PRIMARY KEY (node_id, d)) ON COMMIT DROP;
    INSERT INTO pg_temp.lb2_dabsent
    SELECT DISTINCT p.node_id, dd.d
      FROM public.panelist_unavailability u
      JOIN public.panelists p ON p.id = u.panelist_id AND p.account_id = v_account_id AND p.status = 'active'
      JOIN pg_temp.lb2_dest t ON t.node_id = p.node_id
      JOIN pg_temp.lb2_days dd ON dd.d BETWEEN u.start_date AND u.end_date
     WHERE u.account_id = v_account_id AND u.status = 'active';
    -- Recepciones por nodo destino y dia (no canceladas) en la ventana; los envios creados se suman aqui.
    CREATE TEMP TABLE pg_temp.lb2_dload (node_id uuid, d date, n integer) ON COMMIT DROP;
    INSERT INTO pg_temp.lb2_dload
    SELECT a.destination_node_id, a.fecha_programada, count(*)::int
      FROM public.allocation_plan_details a
      JOIN pg_temp.lb2_dest t ON t.node_id = a.destination_node_id
     WHERE a.account_id = v_account_id AND a.status <> 'cancelled'
       AND a.fecha_programada BETWEEN date_trunc('week', v_from)::date AND p_end_date + 6
       AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_defer d WHERE d.id = a.id)
     GROUP BY a.destination_node_id, a.fecha_programada;
    -- Las reintroducidas por la fase R cubren su dia, cargan su nodo origen y su destino (no son movibles).
    INSERT INTO pg_temp.lb2_pb (id, node_id, d, movable, dest_node, reint, comp)
    SELECT r.id, r.o_node, r.d, false, r.d_node, true, true FROM pg_temp.lb2_reint r WHERE r.pb_id IS NULL;
    -- Las 'pobox' convertidas ya estan (cubren su dia): pasan a 'compensation' fija con el destino nuevo.
    UPDATE pg_temp.lb2_pb b SET movable = false, comp = true, dest_node = r.d_node, dest_bad = false
      FROM pg_temp.lb2_reint r WHERE r.pb_id = b.id;
    INSERT INTO pg_temp.lb2_dload SELECT r.d_node, r.d, 1 FROM pg_temp.lb2_reint r;
    INSERT INTO pg_temp.lb2_dload SELECT r.pb_old_dest, r.d, -1 FROM pg_temp.lb2_reint r WHERE r.pb_id IS NOT NULL;
    CREATE INDEX ON pg_temp.lb2_dload (node_id, d);

    -- Dias sin cubrir tras la equidad (antes de reintroducir), en orden. Mover solo saca de dias con >= 2 y
    -- reintroducir/crear solo cubre el dia tratado, asi que la lista inicial no cambia durante el bucle.
    FOR v_day IN
      SELECT dd.d FROM pg_temp.lb2_days dd
       WHERE NOT EXISTS (SELECT 1 FROM pg_temp.lb2_pb b WHERE b.d = dd.d AND NOT b.reint AND NOT b.dest_bad)
       ORDER BY dd.d
    LOOP
      v_pb_missing := v_pb_missing + 1;
      v_wk := date_trunc('week', v_day)::date;

      -- (0) Ya cubierto por una muestra reintroducida en la fase R (que prefiere los dias vacios de la ciudad):
      -- el dia se cubre compensando la deuda, sin mover ni crear (spec 3.2 bis). Es la unica via por la que POBOX
      -- usa el registro: una anotacion que pudiera servir un dia vacio ya la ha colocado la fase R.
      IF EXISTS (SELECT 1 FROM pg_temp.lb2_pb b WHERE b.d = v_day AND b.reint) THEN
        v_pb_reint := v_pb_reint + 1;
        CONTINUE;
      END IF;

      -- (a) Mover: pendiente del dia mas cercano con >= 2 envios; misma semana primero (atras, luego delante),
      -- despues semanas +-1, +-2...; su nodo debe tener celda ese dia y el dia debe caer en su plan.
      SELECT b.id, cl.cell_id INTO v_mv_id, v_mv_cell
        FROM pg_temp.lb2_pb b
        JOIN (SELECT x.d FROM pg_temp.lb2_pb x WHERE x.d BETWEEN v_from AND p_end_date AND NOT x.dest_bad
               GROUP BY x.d HAVING count(*) >= 2) dc ON dc.d = b.d
        JOIN pg_temp.lb2_cells cl ON cl.node_id = b.node_id AND cl.cell_date = v_day
       WHERE b.movable AND NOT b.dest_bad
         -- una 'compensation' movible no va a un (nodo destino, dia) que ya recibe una (tope R5)
         AND (NOT b.comp
              OR (NOT EXISTS (SELECT 1 FROM pg_temp.lb2_pb x WHERE x.comp AND x.dest_node = b.dest_node AND x.d = v_day)
                  AND NOT EXISTS (SELECT 1 FROM public.allocation_plan_details a
                                   WHERE a.account_id = v_account_id AND a.generation_source = 'compensation'
                                     AND a.status <> 'cancelled' AND a.destination_node_id = b.dest_node
                                     AND a.fecha_programada = v_day
                                     AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_pb y WHERE y.id = a.id))))
         AND NOT EXISTS (SELECT 1 FROM pg_temp.lb2_sdabs x WHERE x.node_id = b.dest_node AND x.d = v_day)
         AND v_day BETWEEN COALESCE(b.plan_start, v_day) AND COALESCE(b.plan_end, v_day)
       ORDER BY abs(date_trunc('week', b.d)::date - v_wk), (b.d > v_day), abs(b.d - v_day), b.id
       LIMIT 1;
      IF FOUND THEN
        UPDATE pg_temp.lb2_pb SET d = v_day WHERE id = v_mv_id;
        UPDATE pg_temp.lb2_ship SET new_cell = v_mv_cell, pobox_move = true WHERE id = v_mv_id;
        v_pb_moved := v_pb_moved + 1;
        CONTINUE;
      END IF;

      -- (b) Crear. Con reparto por producto: el producto mas por debajo de su porcentaje (deficit = pct% del total
      -- tras crear esta - las que ya tiene; empate: mayor pct) con un plan que cubra el dia, y dentro de el el plan
      -- menos avanzado. Sin reparto, o si ningun producto del reparto tiene plan ese dia: plan menos avanzado que
      -- cubre el dia (empate: fin mas lejano).
      v_plan := NULL; v_org_node := NULL; v_org_cell := NULL; v_dst_node := NULL;
      SELECT p.plan_id INTO v_plan FROM pg_temp.lb2_plans p
        JOIN pg_temp.lb2_pshare s ON s.product_id = p.product_id
       WHERE v_day BETWEEN p.start_date AND p.end_date
       ORDER BY s.pct * ((SELECT sum(x.cnt) FROM pg_temp.lb2_pshare x) + 1)::numeric / 100 - s.cnt DESC, s.pct DESC,
                p.progress, p.end_date DESC, p.plan_id
       LIMIT 1;
      IF v_plan IS NULL THEN
        SELECT p.plan_id INTO v_plan FROM pg_temp.lb2_plans p
         WHERE v_day BETWEEN p.start_date AND p.end_date
         ORDER BY p.progress, p.end_date DESC, p.plan_id LIMIT 1;
      END IF;
      -- Origen: nodo de la ciudad disponible ese dia con menos envios en la semana (empate: en el periodo).
      SELECT cl.node_id, cl.cell_id INTO v_org_node, v_org_cell
        FROM pg_temp.lb2_cells cl
       WHERE cl.cell_date = v_day
       ORDER BY (SELECT count(*) FROM pg_temp.lb2_pb b WHERE b.node_id = cl.node_id AND b.d BETWEEN v_wk AND v_wk + 6),
                (SELECT count(*) FROM pg_temp.lb2_pb b WHERE b.node_id = cl.node_id AND b.d BETWEEN v_from AND p_end_date),
                cl.valid_rank
       LIMIT 1;
      -- Destino: nodo valido y disponible de otra ciudad; primero ciudades ya emparejadas en el plan, luego menos
      -- recepciones en la semana, luego en el periodo.
      IF v_plan IS NOT NULL THEN
        SELECT t.node_id INTO v_dst_node
          FROM pg_temp.lb2_dest t
         WHERE NOT EXISTS (SELECT 1 FROM pg_temp.lb2_dabsent x WHERE x.node_id = t.node_id AND x.d = v_day)
         ORDER BY EXISTS (SELECT 1 FROM pg_temp.lb2_routes r WHERE r.plan_id = v_plan AND r.city_id = t.city_id) DESC,
                  (SELECT COALESCE(sum(l.n), 0) FROM pg_temp.lb2_dload l
                    WHERE l.node_id = t.node_id AND l.d BETWEEN v_wk AND v_wk + 6),
                  (SELECT COALESCE(sum(l.n), 0) FROM pg_temp.lb2_dload l
                    WHERE l.node_id = t.node_id AND l.d BETWEEN v_from AND p_end_date),
                  t.node_code, t.node_id
         LIMIT 1;
      END IF;

      IF v_plan IS NULL OR v_org_node IS NULL OR v_dst_node IS NULL THEN
        v_pb_uncovered := v_pb_uncovered + 1;
        v_pb_unc_dates := v_pb_unc_dates || v_day::text;
        CONTINUE;
      END IF;

      v_new_id := gen_random_uuid();
      INSERT INTO pg_temp.lb2_new VALUES (v_new_id, v_plan, v_org_node, v_org_cell, v_dst_node, v_day);
      INSERT INTO pg_temp.lb2_pb VALUES (v_new_id, v_org_node, v_day, false, NULL, NULL, v_dst_node, false);
      INSERT INTO pg_temp.lb2_dload VALUES (v_dst_node, v_day, 1);
      UPDATE pg_temp.lb2_pshare s SET cnt = cnt + 1
        FROM pg_temp.lb2_plans p WHERE p.plan_id = v_plan AND s.product_id = p.product_id;
      v_pb_created := v_pb_created + 1;
    END LOOP;
  END IF;

  UPDATE pg_temp.lb2_cells c SET new_load = x.n
    FROM (SELECT cell, count(*)::int AS n
            FROM (SELECT new_cell AS cell FROM pg_temp.lb2_ship WHERE new_cell IS NOT NULL AND NOT frozen
                  UNION ALL
                  -- carga fija: los congelados cuentan en la celda donde ya estan
                  SELECT cur_cell FROM pg_temp.lb2_ship WHERE frozen AND cur_cell IS NOT NULL
                  UNION ALL
                  SELECT origin_cell FROM pg_temp.lb2_new
                  UNION ALL
                  -- reintroducidas (fase R y POBOX): entran en matrix_after y stddev_after
                  SELECT cell_id FROM pg_temp.lb2_reint WHERE cell_id IS NOT NULL) u
           GROUP BY cell) x
   WHERE x.cell = c.cell_id;
  SELECT count(*) INTO v_reint FROM pg_temp.lb2_reint;

  -- ===== 7. Escritura (solo al aplicar).
  IF p_apply_changes THEN
    -- 7.0 Muestras apartadas: copia completa al registro y borrado del plan, en la misma transaccion y sobre el
    -- mismo conjunto (ids apartados, solo 'pending'). Se bloquean antes las filas; si lo anotado no coincide con
    -- lo calculado o con lo borrado, se aborta TODO el balanceo (nada queda a medias).
    IF v_def_removed > 0 THEN
      PERFORM 1 FROM public.allocation_plan_details a
        JOIN pg_temp.lb2_defer d ON d.id = a.id
       WHERE a.account_id = v_account_id
         FOR UPDATE OF a;
      -- Ya bloqueadas: si alguna dejo de estar pendiente, no tiene nodo destino o gano un dependiente (R2) entre la
      -- lectura y el bloqueo, se aborta nombrando las muestras.
      SELECT string_agg(d.id::text, ', ' ORDER BY d.id) INTO v_def_bad
        FROM pg_temp.lb2_defer d
        LEFT JOIN public.allocation_plan_details a ON a.id = d.id AND a.account_id = v_account_id AND a.status = 'pending'
        LEFT JOIN public.nodes dn ON dn.id = a.destination_node_id
       WHERE dn.id IS NULL;
      IF v_def_bad IS NOT NULL THEN
        RAISE EXCEPTION 'Balanceo abortado: muestras a apartar que ya no estan pendientes o sin nodo destino: %', v_def_bad;
      END IF;
      SELECT string_agg(d.id::text, ', ' ORDER BY d.id) INTO v_def_bad
        FROM pg_temp.lb2_defer d
       WHERE EXISTS (SELECT 1 FROM public.material_hold m WHERE m.allocation_plan_detail_id = d.id)
          OR EXISTS (SELECT 1 FROM public.shipment_incident si WHERE si.parcel_id = d.id)
          OR EXISTS (SELECT 1 FROM public.panelist_incident pi WHERE pi.allocation_plan_detail_id = d.id)
          OR EXISTS (SELECT 1 FROM public.one_db o WHERE o.allocation_detail_id = d.id);
      IF v_def_bad IS NOT NULL THEN
        RAISE EXCEPTION 'Balanceo abortado: muestras a apartar con incidencias, material o lecturas asociadas: %', v_def_bad;
      END IF;
      INSERT INTO public.deferred_samples
        (account_id, plan_id, origin_city_id, dest_city_id, origin_node_id, destination_node_id, fecha_programada,
         reason, row_snapshot, created_by)
      SELECT a.account_id, a.plan_id, p_city_id, dn.city_id, a.origin_node_id, a.destination_node_id,
             a.fecha_programada, d.reason, to_jsonb(a.*), auth.uid()
        FROM pg_temp.lb2_defer d
        JOIN public.allocation_plan_details a ON a.id = d.id
        JOIN public.nodes dn ON dn.id = a.destination_node_id
       WHERE a.account_id = v_account_id AND a.status = 'pending';
      GET DIAGNOSTICS v_def_ins = ROW_COUNT;
      -- OJO: el trigger AFTER DELETE recompute_incidents_on_plan_delete recalcula las bajas activas que tocan
      -- estas filas; borrar la ultima muestra afectada de una baja puede pasar su incidencia a 'auto_resolved'
      -- (los tests desactivan los triggers de incidencias y no lo cubren).
      DELETE FROM public.allocation_plan_details a
       USING pg_temp.lb2_defer d
       WHERE a.id = d.id AND a.account_id = v_account_id AND a.status = 'pending';
      GET DIAGNOSTICS v_def_del = ROW_COUNT;
      IF v_def_ins <> v_def_removed OR v_def_del <> v_def_ins THEN
        RAISE EXCEPTION 'Balanceo abortado: muestras a apartar %, anotadas %, borradas % (reintentar)',
          v_def_removed, v_def_ins, v_def_del;
      END IF;
    END IF;

    -- El panelista origen solo se refresca si cambia el nodo (un cambio solo de fecha lo conserva).
    UPDATE public.allocation_plan_details a
       SET origin_node_id = c.node_id,
           origin_panelist_name = CASE WHEN a.origin_node_id <> c.node_id THEN n.panelist_name
                                       ELSE a.origin_panelist_name END,
           origin_panelist_id = CASE WHEN a.origin_node_id = c.node_id THEN a.origin_panelist_id
                                     WHEN a.origin_panelist_id IS NOT NULL THEN n.panelist_id END,
           fecha_programada = c.cell_date,
           week_number = EXTRACT(week FROM c.cell_date)::int,
           month = EXTRACT(month FROM c.cell_date)::int,
           year = EXTRACT(year FROM c.cell_date)::int,
           original_fecha_programada = COALESCE(a.original_fecha_programada, a.fecha_programada),
           original_origin_node_id = COALESCE(a.original_origin_node_id, a.origin_node_id),
           reassignment_reason = CASE WHEN s.pobox_move THEN 'pobox_move' ELSE 'rebalancing' END,
           reassigned_at = now(),
           reassigned_by = auth.uid(),
           updated_at = now()
      FROM pg_temp.lb2_ship s
      JOIN pg_temp.lb2_cells c ON c.cell_id = s.new_cell
      JOIN pg_temp.lb2_nodes n ON n.node_id = c.node_id
     WHERE a.id = s.id
       AND a.status = 'pending'
       AND (a.origin_node_id <> c.node_id OR a.fecha_programada <> c.cell_date);
    GET DIAGNOSTICS v_movements_count = ROW_COUNT;

    -- 7.1 Destinos reasignados en la fase 0 (dentro de la ciudad destino). La primera vez se guarda el original.
    IF v_def_reassigned > 0 THEN
      UPDATE public.allocation_plan_details a
         SET destination_node_id = s.dest_node,
             original_destination_node_id = COALESCE(a.original_destination_node_id, a.destination_node_id),
             destination_panelist_id = s.new_dest_pid,
             destination_panelist_name = s.new_dest_pname,
             reassignment_reason = CASE WHEN s.pobox_move THEN 'pobox_move' ELSE 'rebalancing' END,
             reassigned_at = now(),
             reassigned_by = auth.uid(),
             updated_at = now()
        FROM pg_temp.lb2_ship s
       WHERE a.id = s.id AND s.new_dest
         AND a.status = 'pending'
         AND a.destination_node_id <> s.dest_node;
    END IF;

    -- Envios creados por POBOX: muestras normales del plan; la unica traza es generation_source = 'pobox'.
    IF v_pb_created > 0 THEN
      INSERT INTO public.allocation_plan_details
        (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year,
         status, origin_panelist_id, origin_panelist_name, destination_panelist_id, destination_panelist_name,
         generation_source)
      SELECT w.id, v_account_id, w.plan_id, w.origin_node, w.dest_node, w.d,
             EXTRACT(week FROM w.d)::int, EXTRACT(month FROM w.d)::int, EXTRACT(year FROM w.d)::int,
             'pending', o.panelist_id, o.panelist_name, t.panelist_id, t.panelist_name, 'pobox'
        FROM pg_temp.lb2_new w
        JOIN pg_temp.lb2_nodes o ON o.node_id = w.origin_node
        JOIN pg_temp.lb2_dest t ON t.node_id = w.dest_node;
    END IF;

    -- 7.2 Reintroducidas: fila nueva 'compensation' en el plan original y la anotacion pasa a 'reintroduced'
    -- enlazada a ella, en la misma transaccion y con recuento exacto (si no cuadra, se aborta TODO el balanceo).
    -- Los nodos originales de la anotacion se guardan en original_* solo si cambian.
    IF v_reint > 0 THEN
      INSERT INTO public.allocation_plan_details
        (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year,
         status, origin_panelist_id, origin_panelist_name, destination_panelist_id, destination_panelist_name,
         original_origin_node_id, original_destination_node_id, generation_source)
      SELECT r.id, v_account_id, r.plan_id, r.o_node, r.d_node, r.d,
             EXTRACT(week FROM r.d)::int, EXTRACT(month FROM r.d)::int, EXTRACT(year FROM r.d)::int,
             'pending', r.o_pid, r.o_pname, r.d_pid, r.d_pname,
             CASE WHEN r.o_node <> r.ds_o_node
                   AND EXISTS (SELECT 1 FROM public.nodes x WHERE x.id = r.ds_o_node) THEN r.ds_o_node END,
             CASE WHEN r.d_node <> r.ds_d_node
                   AND EXISTS (SELECT 1 FROM public.nodes x WHERE x.id = r.ds_d_node) THEN r.ds_d_node END,
             'compensation'
        FROM pg_temp.lb2_reint r
       WHERE r.pb_id IS NULL;
      GET DIAGNOSTICS v_reint_ins = ROW_COUNT;
      -- Sustituciones: la fila 'pobox' (ya en su nodo y dia tras la equidad) pasa a ser la muestra compensada.
      IF v_pb_replaced > 0 THEN
        UPDATE public.allocation_plan_details a
           SET plan_id = r.plan_id,
               destination_node_id = r.d_node,
               destination_panelist_id = r.d_pid,
               destination_panelist_name = r.d_pname,
               original_origin_node_id = CASE WHEN r.o_node <> r.ds_o_node
                     AND EXISTS (SELECT 1 FROM public.nodes x WHERE x.id = r.ds_o_node) THEN r.ds_o_node END,
               original_destination_node_id = CASE WHEN r.d_node <> r.ds_d_node
                     AND EXISTS (SELECT 1 FROM public.nodes x WHERE x.id = r.ds_d_node) THEN r.ds_d_node END,
               generation_source = 'compensation',
               updated_at = now()
          FROM pg_temp.lb2_reint r
         WHERE a.id = r.pb_id AND a.account_id = v_account_id AND a.status = 'pending'
           AND a.generation_source = 'pobox' AND a.origin_node_id = r.o_node AND a.fecha_programada = r.d;
        GET DIAGNOSTICS v_pb_conv = ROW_COUNT;
        IF v_pb_conv <> v_pb_replaced THEN
          RAISE EXCEPTION 'Balanceo abortado: muestras POBOX a sustituir %, convertidas % (reintentar)',
            v_pb_replaced, v_pb_conv;
        END IF;
        v_reint_ins := v_reint_ins + v_pb_conv;
      END IF;
      UPDATE public.deferred_samples d
         SET status = 'reintroduced', reintroduced_at = now(), reintroduced_detail_id = r.id, waiting_reason = NULL
        FROM pg_temp.lb2_reint r
       WHERE d.id = r.ds_id AND d.account_id = v_account_id AND d.status = 'pending';
      GET DIAGNOSTICS v_reint_upd = ROW_COUNT;
      IF v_reint_ins <> v_reint OR v_reint_upd <> v_reint THEN
        RAISE EXCEPTION 'Balanceo abortado: muestras a reintroducir %, insertadas %, anotaciones actualizadas % (reintentar)',
          v_reint, v_reint_ins, v_reint_upd;
      END IF;
    END IF;
    -- Motivo de espera de las anotaciones que no se reintroducen (solo al aplicar).
    IF v_rc_any THEN
      UPDATE public.deferred_samples d
         SET waiting_reason = c.waiting
        FROM pg_temp.lb2_rcand c
       WHERE d.id = c.ds_id AND NOT c.placed AND d.account_id = v_account_id AND d.status = 'pending'
         AND d.waiting_reason IS DISTINCT FROM c.waiting;
    END IF;

    -- Solo si hubo sobrante Y se movio algo: re-aplicar sobre una ciudad ya equilibrada no rota.
    IF v_had_remainder AND v_movements_count > 0 THEN
      UPDATE public.cities SET balance_rotation_offset = balance_rotation_offset + 1 WHERE id = p_city_id;
    END IF;
  ELSE
    SELECT count(*) INTO v_movements_count
      FROM pg_temp.lb2_ship s JOIN pg_temp.lb2_cells c ON c.cell_id = s.new_cell
     WHERE s.cur_node <> c.node_id OR s.fecha <> c.cell_date;
  END IF;

  -- ===== 8. Resultado.
  SELECT COALESCE(stddev(current_load), 0), COALESCE(stddev(new_load), 0)
    INTO v_stddev_before, v_stddev_after FROM pg_temp.lb2_cells;
  v_improvement := CASE WHEN v_stddev_before > 0
                        THEN (v_stddev_before - v_stddev_after) / v_stddev_before * 100 ELSE 0 END;

  IF v_date_policy = 'weekly' THEN
    SELECT jsonb_agg(jsonb_build_object('node_code', node_code, 'week_num', EXTRACT(week FROM week_start)::int,
                                        'week_start', week_start, 'day', NULL, 'load_count', lb)
                     ORDER BY node_code, week_start),
           jsonb_agg(jsonb_build_object('node_code', node_code, 'week_num', EXTRACT(week FROM week_start)::int,
                                        'week_start', week_start, 'day', NULL, 'load_count', la)
                     ORDER BY node_code, week_start)
      INTO v_matrix_before, v_matrix_after
      FROM (SELECT node_code, week_start, sum(current_load)::int AS lb, sum(new_load)::int AS la
              FROM pg_temp.lb2_cells GROUP BY node_code, week_start) x;
  ELSE
    SELECT jsonb_agg(jsonb_build_object('node_code', node_code, 'week_num', EXTRACT(week FROM week_start)::int,
                                        'week_start', week_start, 'day', cell_date, 'load_count', current_load)
                     ORDER BY node_code, cell_date),
           jsonb_agg(jsonb_build_object('node_code', node_code, 'week_num', EXTRACT(week FROM week_start)::int,
                                        'week_start', week_start, 'day', cell_date, 'load_count', new_load)
                     ORDER BY node_code, cell_date)
      INTO v_matrix_before, v_matrix_after
      FROM pg_temp.lb2_cells;
  END IF;

  SELECT jsonb_agg(m ORDER BY m->>'from_date', m->>'to_date', m->>'from_node_code', m->>'to_node_code')
    INTO v_movements
    FROM (SELECT jsonb_build_object('from_node_code', s.cur_code, 'from_date', s.fecha,
                                    'to_node_code', c.node_code, 'to_date', c.cell_date, 'count', count(*)) AS m
            FROM pg_temp.lb2_ship s JOIN pg_temp.lb2_cells c ON c.cell_id = s.new_cell
           WHERE s.cur_node <> c.node_id OR s.fecha <> c.cell_date
           GROUP BY s.cur_code, s.fecha, c.node_code, c.cell_date
           ORDER BY s.fecha, c.cell_date, s.cur_code, c.node_code
           LIMIT 100) sub;

  SELECT jsonb_agg(w) INTO v_warnings
    FROM (SELECT jsonb_build_object('code', 'no_valid_cell', 'count', count(*),
                                    'detail', string_agg(DISTINCT cur_code, ', ' ORDER BY cur_code)) AS w
            FROM pg_temp.lb2_ship WHERE new_cell IS NULL AND NOT od_conflict AND NOT comp_frozen HAVING count(*) > 0
          UNION ALL
          SELECT jsonb_build_object('code', 'origin_equals_destination', 'count', count(*),
                                    'detail', string_agg(DISTINCT cur_code, ', ' ORDER BY cur_code))
            FROM pg_temp.lb2_ship WHERE od_conflict HAVING count(*) > 0
          UNION ALL
          SELECT jsonb_build_object('code', 'pobox_uncovered', 'count', v_pb_uncovered,
                                    'detail', array_to_string(v_pb_unc_dates, ', '))
           WHERE v_pb_uncovered > 0
          UNION ALL
          SELECT jsonb_build_object('code', 'deferred_removed', 'count', v_def_removed,
                                    'detail', concat_ws(', ',
                                      CASE WHEN v_def_origin > 0 THEN 'origin_no_panelist=' || v_def_origin END,
                                      CASE WHEN v_def_dest > 0 THEN 'dest_no_panelist=' || v_def_dest END,
                                      CASE WHEN v_def_day > 0 THEN 'no_valid_day=' || v_def_day END))
           WHERE v_def_removed > 0
          UNION ALL
          SELECT jsonb_build_object('code', 'deferred_blocked', 'count', count(*),
                                    'detail', string_agg(DISTINCT cur_code, ', ' ORDER BY cur_code))
            FROM pg_temp.lb2_ship WHERE def_blocked HAVING count(*) > 0) x;

  IF v_rc_any THEN
    SELECT jsonb_build_object('no_origin_panelist', count(*) FILTER (WHERE waiting = 'no_origin_panelist'),
                              'no_dest_panelist', count(*) FILTER (WHERE waiting = 'no_dest_panelist'),
                              'no_capacity', count(*) FILTER (WHERE waiting = 'no_capacity'),
                              'plan_inactive', count(*) FILTER (WHERE waiting = 'plan_inactive'),
                              'outside_period', count(*) FILTER (WHERE waiting = 'outside_period'))
      INTO v_wait_by
      FROM pg_temp.lb2_rcand WHERE NOT placed;
  ELSE
    v_wait_by := jsonb_build_object('no_origin_panelist', 0, 'no_dest_panelist', 0, 'no_capacity', 0,
                                    'plan_inactive', 0, 'outside_period', 0);
  END IF;

  DROP TABLE IF EXISTS pg_temp.lb2_nodes, pg_temp.lb2_days, pg_temp.lb2_absent, pg_temp.lb2_cells, pg_temp.lb2_segs, pg_temp.lb2_ship,
                       pg_temp.lb2_new, pg_temp.lb2_pb, pg_temp.lb2_plans, pg_temp.lb2_routes, pg_temp.lb2_dest,
                       pg_temp.lb2_dabsent, pg_temp.lb2_dload, pg_temp.lb2_sdabs,
                       pg_temp.lb2_alt, pg_temp.lb2_altload, pg_temp.lb2_altabs, pg_temp.lb2_defer, pg_temp.lb2_hz,
                       pg_temp.lb2_reint, pg_temp.lb2_rcand, pg_temp.lb2_rload, pg_temp.lb2_rday,
                       pg_temp.lb2_rdest, pg_temp.lb2_rdslot, pg_temp.lb2_rpb, pg_temp.lb2_pshare;

  RETURN jsonb_build_object('success', true,
    'movements_count', v_movements_count,
    'stddev_before', v_stddev_before, 'stddev_after', v_stddev_after,
    'improvement_percentage', v_improvement,
    'movements', COALESCE(v_movements, '[]'::jsonb),
    'matrix_before', COALESCE(v_matrix_before, '[]'::jsonb),
    'matrix_after', COALESCE(v_matrix_after, '[]'::jsonb),
    'warnings', COALESCE(v_warnings, '[]'::jsonb),
    'policy', jsonb_build_object('date_policy', v_date_policy, 'pobox_enabled', v_pobox),
    'fence_until', v_fence,
    -- days_missing = dias sin envios tras la equidad; se cubren moviendo (days_moved), reintroduciendo anotadas
    -- (days_reintroduced: cubiertos por la fase R), creando (days_created) o quedan sin cubrir.
    'pobox', jsonb_build_object('days_missing', v_pb_missing, 'days_moved', v_pb_moved,
                                'days_created', v_pb_created, 'days_uncovered', v_pb_uncovered,
                                'days_reintroduced', v_pb_reint),
    -- reintroduced = anotaciones reintroducidas en esta ejecucion (fase R); waiting = anotaciones pendientes
    -- de la ciudad origen tras esta ejecucion (en la vista previa, incluidas las que se apartarian);
    -- waiting_by_reason = motivo de las anotaciones previas que siguen esperando.
    'deferred', jsonb_build_object('removed', v_def_removed, 'reassigned_dest', v_def_reassigned,
                                   'reintroduced', v_reint, 'replaced_pobox', v_pb_replaced,
                                   'waiting', v_def_waiting - v_reint, 'blocked', v_def_blocked,
                                   'by_reason', jsonb_build_object('origin_no_panelist', v_def_origin,
                                                                   'dest_no_panelist', v_def_dest,
                                                                   'no_valid_day', v_def_day),
                                   'waiting_by_reason', v_wait_by),
    'message', CASE WHEN v_total = 0 AND v_pb_created = 0 AND v_reint = 0 THEN 'No shipments found in the specified period'
                    ELSE format('Balanced %s shipments across nodes', v_movements_count) END,
    'error', NULL);
END;
$function$;

-- ------------------------------------------------------------------------------------------------ 5. EXECUTE
-- Mantenimiento entre cuentas, sin llamador con sesión de usuario (web ni edge con JWT de usuario):
--   balance_node_load_matrix ....... solo desde rpc_balance_node_load (SECURITY DEFINER, corre como dueño).
--   cleanup_processed_rfid_events .. sin llamadores.
--   process_all_accounts_pipeline .. edge rfid-provider-poll con service_role.
--   process_rfid_pipeline .......... desde process_all_accounts_pipeline (DEFINER).
--   resolve_provider_reads ......... edge rfid-provider-poll con service_role.
DO $$
DECLARE f regprocedure;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure FROM pg_proc p
     WHERE p.pronamespace = 'public'::regnamespace
       AND p.proname = ANY (ARRAY['balance_node_load_matrix','cleanup_processed_rfid_events',
                                  'process_all_accounts_pipeline','process_rfid_pipeline','resolve_provider_reads'])
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', f);
  END LOOP;
END $$;

-- ------------------------------------------------------------------------------------------------ 6. control
-- Ninguna política de escritura (INSERT/UPDATE/DELETE/ALL) fuera de las previstas en las tablas tocadas.
-- Si la BD viva tiene alguna que el repo no recoge, se aborta todo para revisarla.
DO $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(format('%s.%s (%s)', tablename, policyname, cmd), ', ' ORDER BY tablename, policyname)
    INTO v_bad
    FROM pg_policies
   WHERE schemaname = 'public'
     AND cmd <> 'SELECT'
     AND tablename = ANY (ARRAY['regions','cities','nodes','panelists','panelist_unavailability','carriers','products',
       'product_materials','material_catalog','delivery_standards','slas','generated_allocation_plans',
       'generated_allocation_plan_details','allocation_plans','allocation_plan_details','panelist_material_stocks',
       'material_movements','stock_alerts','material_requirements_periods','material_stocks','material_shipments',
       'material_shipment_items','stock_settings','panelist_incident','account_config','weekly_schedule',
       'non_working_days','postal_centers','readers','reader_location_history','api_keys','one_db','incidents',
       'processed_events','journey_segments','journeys','rfid_events_raw','profiles'])
     AND policyname !~ '_(insert|update|delete)_edit$'
     AND policyname NOT IN ('profiles_insert_users_edit','profiles_update_users_edit','profiles_delete_users_edit',
       'Service role bypass RLS','api_keys_superadmin_all','journey_segments_superadmin_all','journeys_superadmin_all',
       'processed_events_superadmin_all','rfid_events_raw_superadmin_all','superadmin_update_one_db',
       'profile_delete_superadmin','profile_insert_superadmin','profiles_update_own','profiles_update_superadmin');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Políticas de escritura no previstas (revisar antes de aplicar): %', v_bad;
  END IF;
END $$;

-- ------------------------------------------------------------------------------------------------ 7. envoltorios
-- La web (useJourneySegments: ruta /diagnosis/journey-segments -> opción route_analysis) reconstruye viajes de
-- SU cuenta activa con Edit en route_analysis. Sin cuenta (NULL = todas las cuentas) solo el original, que ya
-- no ejecuta authenticated.
CREATE OR REPLACE FUNCTION public.reconstruct_journeys_for_account(p_account_id uuid, p_tag_id text DEFAULT NULL)
 RETURNS TABLE(segments_created bigint, events_processed bigint, execution_time_ms bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
BEGIN
  IF p_account_id IS NULL THEN
    RAISE EXCEPTION 'Account required' USING ERRCODE = '22004';
  END IF;
  IF NOT (public.is_superadmin()
          OR (p_account_id = public.current_user_account_id()
              AND public.has_access(p_account_id, 'route_analysis', 'edit'))) THEN
    RAISE EXCEPTION 'Forbidden: edit right required (route_analysis)' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY SELECT * FROM public.reconstruct_journeys(p_account_id, p_tag_id);
END $$;

-- La web (AllocationPlans, reprocesar envíos con error de traspaso) con Edit en allocation_plans: todos los
-- envíos deben ser de la cuenta activa (superadmin: cualquiera). Los ids inexistentes los trata el original.
CREATE OR REPLACE FUNCTION public.reprocess_transfer_errors_for_account(p_detail_ids uuid[])
 RETURNS TABLE(detail_id uuid, success boolean, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public
AS $$
DECLARE v_account uuid;
BEGIN
  IF NOT public.is_superadmin() THEN
    v_account := public.current_user_account_id();
    IF v_account IS NULL OR NOT public.has_access(v_account, 'allocation_plans', 'edit') THEN
      RAISE EXCEPTION 'Forbidden: edit right required (allocation_plans)' USING ERRCODE = '42501';
    END IF;
    IF EXISTS (SELECT 1 FROM public.allocation_plan_details d
                WHERE d.id = ANY (p_detail_ids) AND d.account_id IS DISTINCT FROM v_account) THEN
      RAISE EXCEPTION 'Forbidden: shipments not in your account' USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN QUERY SELECT * FROM public.reprocess_transfer_errors(p_detail_ids);
END $$;

REVOKE ALL ON FUNCTION public.reconstruct_journeys_for_account(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.reprocess_transfer_errors_for_account(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reconstruct_journeys_for_account(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.reprocess_transfer_errors_for_account(uuid[]) TO authenticated, service_role;

-- Originales: sin EXECUTE para la web (PUBLIC/anon ya revocados en 20261118220000); service_role y los
-- llamadores SECURITY DEFINER (dueño postgres) los siguen ejecutando.
REVOKE EXECUTE ON FUNCTION public.reconstruct_journeys(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.reprocess_transfer_errors(uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reconstruct_journeys(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.reprocess_transfer_errors(uuid[]) TO service_role;
