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
--    receipt_mgr_check pasa de rol legacy 'admin' a receipts:view (+ receipts:edit en las que escriben).
-- 5. Sin EXECUTE para authenticated en funciones de mantenimiento entre cuentas sin llamador web.
-- 6. Comprobación final: no queda ninguna política de escritura no prevista en esas tablas.
--
-- Fuera de esta migración (cuerpo vivo por verificar, ver informe de la tarea 9):
--   reprocess_transfer_errors, consolidate_rfid_events, reconstruct_journeys.
-- rpc_balance_city_v2 va en 20261119100210_account_access_writes_balance.sql (cuerpo muy largo).

-- ------------------------------------------------------------------------------------------------ 1. huella
DO $$
DECLARE r record; v_oid regprocedure; v_bad text := '';
BEGIN
  FOR r IN SELECT * FROM (VALUES
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

-- profiles (Users): las reglas de rol legacy 'admin' pasan a users:edit en la cuenta activa, con las mismas
-- restricciones (nunca tocar ni crear superadmin; solo roles admin/user). Siguen profiles_update_own
-- (idioma, etc.) y las de superadmin. El alta/baja real va por las edge create-user/delete-user (service_role).
CREATE POLICY profiles_insert_users_edit ON public.profiles
  FOR INSERT TO authenticated
  WITH CHECK (account_id = (SELECT public.current_user_account_id())
              AND role = ANY (ARRAY['admin','user'])
              AND (SELECT public.has_any_access(public.current_user_account_id(), 'edit', 'users')));
CREATE POLICY profiles_update_users_edit ON public.profiles
  FOR UPDATE TO authenticated
  USING (account_id = (SELECT public.current_user_account_id())
         AND role <> 'superadmin'
         AND (SELECT public.has_any_access(public.current_user_account_id(), 'edit', 'users')))
  WITH CHECK (account_id = (SELECT public.current_user_account_id())
              AND role = ANY (ARRAY['admin','user'])
              AND (SELECT public.has_any_access(public.current_user_account_id(), 'edit', 'users')));
CREATE POLICY profiles_delete_users_edit ON public.profiles
  FOR DELETE TO authenticated
  USING (account_id = (SELECT public.current_user_account_id())
         AND role <> 'superadmin'
         AND (SELECT public.has_any_access(public.current_user_account_id(), 'edit', 'users')));

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

-- request_case_analysis(text,uuid): PERFORM public.require_edit(v_account, 'reported_incidents', 'panelist_availability', 'receipts');
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
  PERFORM public.require_edit(v_account, 'reported_incidents', 'panelist_availability', 'receipts');  -- fase 3: derecho Edit/View de la matriz
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

-- send_case_message(text,uuid,uuid,text,text): PERFORM public.require_edit(v_account, 'reported_incidents', 'panelist_availability', 'receipts');
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
  PERFORM public.require_edit(v_account, 'reported_incidents', 'panelist_availability', 'receipts');  -- fase 3: derecho Edit/View de la matriz
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
