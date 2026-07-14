-- =====================================================================
-- CATCH-UP MIGRATION — objetos vivos sin migración en el repo
-- Generada: 2026-07-14  |  Proyecto: onems-dev (sehbnpgzqljrsqimwyuz)
-- =====================================================================
-- CONTEXTO: la BD viva contenía 22 tablas y 24 funciones que NO
-- estaban creadas por ninguna migración del repo (creadas a mano en la
-- consola). Esta migración reconstruye su DDL desde el catálogo (pg_catalog)
-- para que el repo pueda volver a levantar la BD desde cero.
--
-- NO ejecutada contra producción: esos objetos YA existen ahí. Su único
-- propósito es reproducibilidad (entornos nuevos / db reset / recuperación).
-- Todo va guardado con IF NOT EXISTS / idempotente donde es posible.
--
-- ⚠️ REVISAR Y PROBAR con 'supabase db reset' en un entorno de scratch antes
--    de confiar en ella. DDL reconstruido, no un pg_dump oficial.
-- =====================================================================

-- pg_dump-style: no validar cuerpos de funciones (permite crear funciones
-- antes que las tablas a las que referencian).
SET check_function_bodies = false;

-- ---------------------------------------------------------------------
-- 1) TIPOS (enums custom)
-- ---------------------------------------------------------------------

-- ---------------------------------------------------------------------
-- 2) SECUENCIAS
-- ---------------------------------------------------------------------
CREATE SEQUENCE IF NOT EXISTS public.diagnosis_anomalies_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.diagnosis_routes_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.diagnosis_time_metrics_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.n8n_upu_agent_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.n8n_upu_incident_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.n8n_upu_timeoff_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.panelist_context_id_seq;
CREATE SEQUENCE IF NOT EXISTS public.rfid_intermediate_db_id_seq;

-- ---------------------------------------------------------------------
-- 3) FUNCIONES (24) — antes que tablas por defaults que las invocan
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_reset_account_data(p_account_identifier text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_account_id UUID;
  v_account_name TEXT;
  v_deleted_counts JSONB := '{}'::JSONB;
  v_count INTEGER;
BEGIN
  -- Determinar si el identificador es UUID o nombre
  IF p_account_identifier ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    -- Es un UUID
    v_account_id := p_account_identifier::UUID;
    SELECT name INTO v_account_name FROM accounts WHERE id = v_account_id;
  ELSE
    -- Es un nombre de cuenta
    v_account_name := p_account_identifier;
    SELECT id INTO v_account_id FROM accounts WHERE name = v_account_name;
  END IF;

  -- Verificar que la cuenta existe
  IF v_account_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Account not found: ' || p_account_identifier
    );
  END IF;

  -- Borrar SOLO datos operacionales (NO configuraciÃ³n)
  
  DELETE FROM generated_allocation_plan_details WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('generated_allocation_plan_details', v_count);

  DELETE FROM generated_allocation_plans WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('generated_allocation_plans', v_count);

  DELETE FROM allocation_plan_details WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('allocation_plan_details', v_count);

  DELETE FROM allocation_plans WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('allocation_plans', v_count);

  DELETE FROM one_db WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('one_db', v_count);

  DELETE FROM material_shipment_items WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_shipment_items', v_count);

  DELETE FROM material_shipments WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_shipments', v_count);

  DELETE FROM material_movements WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_movements', v_count);

  DELETE FROM panelist_material_stocks WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('panelist_material_stocks', v_count);

  DELETE FROM purchase_order_items WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('purchase_order_items', v_count);

  DELETE FROM purchase_orders WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('purchase_orders', v_count);

  DELETE FROM material_requirements_periods WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_requirements_periods', v_count);

  DELETE FROM node_balancing_history WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('node_balancing_history', v_count);

  DELETE FROM material_stocks WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_stocks', v_count);

  DELETE FROM panelist_unavailability WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('panelist_unavailability', v_count);

  -- Retornar resultado
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Account data reset successfully',
    'account_name', v_account_name,
    'deleted_records', v_deleted_counts
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.admin_reset_demo2()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET row_security TO 'off'
AS $function$
DECLARE
  v_account_id UUID := 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'; -- DEMO2 hardcoded
  v_account_name TEXT := 'DEMO2';
  v_deleted_counts JSONB := '{}'::JSONB;
  v_inserted_counts JSONB := '{}'::JSONB;
  v_count INTEGER;
  
  v_region_map JSONB := '{}'::JSONB;
  v_city_map JSONB := '{}'::JSONB;
  v_node_map JSONB := '{}'::JSONB;
  v_carrier_map JSONB := '{}'::JSONB;
  v_material_map JSONB := '{}'::JSONB;
  v_product_map JSONB := '{}'::JSONB;
  v_panelist_map JSONB := '{}'::JSONB;
  
  v_seed_data JSONB;
  v_record JSONB;
  v_new_id UUID;
  v_region_id UUID;
  v_city_id UUID;
  v_carrier_id UUID;
  v_material_id UUID;
  v_product_id UUID;
  v_node_id UUID;
  v_origin_city_id UUID;
  v_dest_city_id UUID;
BEGIN
  -- Verificar que la cuenta DEMO2 existe
  IF NOT EXISTS (SELECT 1 FROM accounts WHERE id = v_account_id) THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'DEMO2 account not found'
    );
  END IF;

  -- ============================================
  -- PASO 1: Borrar datos operacionales
  -- ============================================
  RAISE NOTICE 'Step 1/3: Deleting operational data...';
  
  DELETE FROM generated_allocation_plan_details WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('generated_allocation_plan_details', v_count);

  DELETE FROM generated_allocation_plans WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('generated_allocation_plans', v_count);

  DELETE FROM allocation_plan_details WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('allocation_plan_details', v_count);

  DELETE FROM allocation_plans WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('allocation_plans', v_count);

  DELETE FROM one_db WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('one_db', v_count);

  DELETE FROM material_shipment_items WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_shipment_items', v_count);

  DELETE FROM material_shipments WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_shipments', v_count);

  DELETE FROM material_movements WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_movements', v_count);

  DELETE FROM panelist_material_stocks WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('panelist_material_stocks', v_count);

  DELETE FROM purchase_order_items WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('purchase_order_items', v_count);

  DELETE FROM purchase_orders WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('purchase_orders', v_count);

  DELETE FROM material_requirements_periods WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_requirements_periods', v_count);

  DELETE FROM node_balancing_history WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('node_balancing_history', v_count);

  DELETE FROM material_stocks WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_stocks', v_count);

  DELETE FROM panelist_unavailability WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('panelist_unavailability', v_count);

  -- ============================================
  -- PASO 2: Borrar datos de configuraciÃ³n
  -- ============================================
  RAISE NOTICE 'Step 2/3: Deleting configuration data...';
  
  DELETE FROM delivery_standards WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('delivery_standards', v_count);

  DELETE FROM product_materials WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('product_materials', v_count);

  DELETE FROM material_catalog WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_catalog', v_count);

  DELETE FROM panelists WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('panelists', v_count);

  DELETE FROM products WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('products', v_count);

  DELETE FROM carriers WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('carriers', v_count);

  DELETE FROM nodes WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('nodes', v_count);

  DELETE FROM cities WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('cities', v_count);

  DELETE FROM regions WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('regions', v_count);

  -- ============================================
  -- PASO 3: Recargar datos semilla
  -- ============================================
  RAISE NOTICE 'Step 3/3: Reloading seed data...';
  
  -- 3.1 REGIONS
  -- Columnas: account_id, code, name, description, country_code, status
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'regions';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      INSERT INTO regions (account_id, code, name, description, country_code, status)
      VALUES (v_account_id, 
              v_record->>'code', 
              v_record->>'name',
              v_record->>'description',
              v_record->>'country_code',
              COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_region_map := v_region_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('regions', v_count);
  END IF;

  -- 3.2 CITIES
  -- Columnas: account_id, region_id, code, name, latitude, longitude, classification, city_type, region_name, population, status
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'cities';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_region_id := (v_region_map->>(v_record->>'region_id'))::uuid;
      INSERT INTO cities (account_id, region_id, code, name, latitude, longitude, classification, city_type, region_name, population, status)
      VALUES (v_account_id, 
              v_region_id, 
              v_record->>'code', 
              v_record->>'name', 
              (v_record->>'latitude')::numeric, 
              (v_record->>'longitude')::numeric,
              v_record->>'classification', 
              v_record->>'city_type', 
              v_record->>'region_name',
              ROUND((v_record->>'population')::numeric)::integer, 
              COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_city_map := v_city_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('cities', v_count);
  END IF;

  -- 3.3 NODES
  -- Columnas: account_id, city_id, auto_id, status
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'nodes';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_city_id := (v_city_map->>(v_record->>'city_id'))::uuid;
      INSERT INTO nodes (account_id, city_id, auto_id, status)
      VALUES (v_account_id, 
              v_city_id, 
              v_record->>'auto_id', 
              COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_node_map := v_node_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('nodes', v_count);
  END IF;

  -- 3.4 CARRIERS
  -- Columnas: account_id, code, name, type, status
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'carriers';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      INSERT INTO carriers (account_id, code, name, type, status)
      VALUES (v_account_id, 
              v_record->>'code', 
              v_record->>'name',
              v_record->>'type',
              COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_carrier_map := v_carrier_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('carriers', v_count);
  END IF;

  -- 3.5 PRODUCTS
  -- Columnas: account_id, carrier_id, code, description, standard_delivery_hours, time_unit, status
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'products';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_carrier_id := (v_carrier_map->>(v_record->>'carrier_id'))::uuid;
      INSERT INTO products (account_id, carrier_id, code, description, standard_delivery_hours, time_unit, status)
      VALUES (v_account_id, 
              v_carrier_id, 
              v_record->>'code', 
              v_record->>'description',
              ROUND((v_record->>'standard_delivery_hours')::numeric)::integer, 
              COALESCE(v_record->>'time_unit', 'hours'),
              COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_product_map := v_product_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('products', v_count);
  END IF;

  -- 3.6 MATERIAL_CATALOG
  -- Columnas: account_id, code, name, description, unit_measure, min_stock, status
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'material_catalog';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      INSERT INTO material_catalog (account_id, code, name, description, unit_measure, min_stock, status)
      VALUES (v_account_id, 
              v_record->>'code', 
              v_record->>'name', 
              v_record->>'description',
              v_record->>'unit_measure', 
              COALESCE((v_record->>'min_stock')::integer, 0), 
              COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_material_map := v_material_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('material_catalog', v_count);
  END IF;

  -- 3.7 PANELISTS
  -- Columnas: account_id, node_id, city_id, panelist_code, name, email, mobile, address_line1, address_line2, postal_code, address_city, address_country, telegram_id, status, created_by, updated_by
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'panelists';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_node_id := (v_node_map->>(v_record->>'node_id'))::uuid;
      v_city_id := (v_city_map->>(v_record->>'city_id'))::uuid;
      INSERT INTO panelists (account_id, node_id, city_id, panelist_code, name, email, mobile, address_line1, address_line2, postal_code, address_city, address_country, telegram_id, status, created_by, updated_by)
      VALUES (v_account_id, 
              v_node_id,
              v_city_id,
              v_record->>'panelist_code', 
              v_record->>'name',
              v_record->>'email',
              v_record->>'mobile',
              v_record->>'address_line1',
              v_record->>'address_line2',
              v_record->>'postal_code',
              v_record->>'address_city',
              v_record->>'address_country',
              v_record->>'telegram_id',
              COALESCE(v_record->>'status', 'active'),
              (v_record->>'created_by')::uuid,
              (v_record->>'updated_by')::uuid)
      RETURNING id INTO v_new_id;
      v_panelist_map := v_panelist_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('panelists', v_count);
  END IF;

  -- 3.8 PRODUCT_MATERIALS
  -- Columnas: account_id, product_id, material_id, quantity
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'product_materials';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_product_id := (v_product_map->>(v_record->>'product_id'))::uuid;
      v_material_id := (v_material_map->>(v_record->>'material_id'))::uuid;
      INSERT INTO product_materials (account_id, product_id, material_id, quantity)
      VALUES (v_account_id, 
              v_product_id, 
              v_material_id,
              (v_record->>'quantity')::integer);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('product_materials', v_count);
  END IF;

  -- 3.9 DELIVERY_STANDARDS
  -- Columnas: account_id, carrier_id, product_id, origin_city_id, destination_city_id, standard_time, success_percentage, time_unit, warning_threshold, critical_threshold, threshold_type
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'delivery_standards';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_carrier_id := (v_carrier_map->>(v_record->>'carrier_id'))::uuid;
      v_product_id := (v_product_map->>(v_record->>'product_id'))::uuid;
      v_origin_city_id := (v_city_map->>(v_record->>'origin_city_id'))::uuid;
      v_dest_city_id := (v_city_map->>(v_record->>'destination_city_id'))::uuid;
      INSERT INTO delivery_standards (account_id, carrier_id, product_id, origin_city_id, destination_city_id, standard_time, success_percentage, time_unit, warning_threshold, critical_threshold, threshold_type)
      VALUES (v_account_id, 
              v_carrier_id,
              v_product_id,
              v_origin_city_id, 
              v_dest_city_id,
              (v_record->>'standard_time')::numeric,
              (v_record->>'success_percentage')::numeric,
              COALESCE(v_record->>'time_unit', 'hours'),
              (v_record->>'warning_threshold')::numeric,
              (v_record->>'critical_threshold')::numeric,
              v_record->>'threshold_type');
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('delivery_standards', v_count);
  END IF;

  -- ============================================
  -- Retornar resultado exitoso
  -- ============================================
  RETURN jsonb_build_object(
    'success', true,
    'message', 'DEMO2 reset successfully',
    'account_name', v_account_name,
    'deleted_records', v_deleted_counts,
    'inserted_records', v_inserted_counts
  );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.auto_resolve_stock_alerts()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- For regulator stock alerts
  IF TG_TABLE_NAME = 'material_stocks' THEN
    UPDATE stock_alerts
    SET resolved_at = now()
    WHERE account_id = NEW.account_id
      AND material_id = NEW.material_id
      AND alert_type = 'regulator_insufficient'
      AND resolved_at IS NULL
      AND NEW.quantity >= 0;
  END IF;
  
  -- For panelist stock alerts
  IF TG_TABLE_NAME = 'panelist_material_stocks' THEN
    UPDATE stock_alerts
    SET resolved_at = now()
    WHERE account_id = NEW.account_id
      AND material_id = NEW.material_id
      AND location_id = NEW.panelist_id
      AND alert_type = 'panelist_negative'
      AND resolved_at IS NULL
      AND NEW.quantity >= 0;
  END IF;
  
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.calculate_compliance_percentage(p_account_id uuid, p_date_from timestamp with time zone DEFAULT NULL::timestamp with time zone, p_date_to timestamp with time zone DEFAULT NULL::timestamp with time zone, p_carrier_name text DEFAULT NULL::text, p_product_name text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_compliance_pct NUMERIC;
BEGIN
  SELECT 
    ROUND(
      (SUM(CASE WHEN on_time_delivery THEN 1 ELSE 0 END)::numeric / COUNT(*)) * 100, 
      2
    )
  INTO v_compliance_pct
  FROM one_db
  WHERE account_id = p_account_id
    AND (p_date_from IS NULL OR sent_at >= p_date_from)
    AND (p_date_to IS NULL OR sent_at <= p_date_to)
    AND (p_carrier_name IS NULL OR carrier_name = p_carrier_name)
    AND (p_product_name IS NULL OR product_name = p_product_name);
  
  RETURN COALESCE(v_compliance_pct, 0);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.calculate_network_health_score(p_account_id uuid, p_start_date timestamp with time zone DEFAULT NULL::timestamp with time zone, p_end_date timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(health_score numeric, on_time_delivery_rate numeric, avg_transit_time_hours numeric, avg_processing_time_hours numeric, total_items integer, total_routes integer, total_centers integer, total_sla_violations bigint)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_on_time_rate NUMERIC;
    v_avg_transit NUMERIC;
    v_avg_processing NUMERIC;
    v_health_score NUMERIC;
    v_total_items INTEGER;
    v_total_routes INTEGER;
    v_total_centers INTEGER;
    v_total_violations BIGINT;
BEGIN
    -- Calculate on-time delivery rate (network-wide)
    SELECT 
        ROUND((COUNT(*) FILTER (WHERE j.total_sla_violations = 0)::numeric / NULLIF(COUNT(*), 0) * 100), 2),
        COUNT(*)::INTEGER,
        SUM(j.total_sla_violations)
    INTO v_on_time_rate, v_total_items, v_total_violations
    FROM journeys j
    WHERE j.account_id = p_account_id
        AND j.journey_status = 'completed'
        AND (p_start_date IS NULL OR j.first_event_timestamp >= p_start_date)
        AND (p_end_date IS NULL OR j.last_event_timestamp <= p_end_date);
    
    -- Calculate average transit time (network-wide, in hours)
    SELECT ROUND(AVG(j.total_operational_time_minutes / 60.0)::numeric, 2)
    INTO v_avg_transit
    FROM journeys j
    WHERE j.account_id = p_account_id
        AND j.journey_status = 'completed'
        AND (p_start_date IS NULL OR j.first_event_timestamp >= p_start_date)
        AND (p_end_date IS NULL OR j.last_event_timestamp <= p_end_date);
    
    -- Calculate average processing time (network-wide, in hours)
    SELECT ROUND(AVG(js.adjusted_time_minutes / 60.0)::numeric, 2)
    INTO v_avg_processing
    FROM journey_segments js
    WHERE js.account_id = p_account_id
        AND js.segment_type = 'processing'
        AND (p_start_date IS NULL OR js.entry_timestamp >= p_start_date)
        AND (p_end_date IS NULL OR js.exit_timestamp <= p_end_date);
    
    -- Count total unique routes
    SELECT COUNT(DISTINCT (
        (j.route_path->0->>'postal_center_id')::UUID,
        (j.route_path->(j.total_centers_visited - 1)->>'postal_center_id')::UUID
    ))::INTEGER
    INTO v_total_routes
    FROM journeys j
    WHERE j.account_id = p_account_id
        AND j.journey_status = 'completed'
        AND j.total_centers_visited >= 2
        AND (p_start_date IS NULL OR j.first_event_timestamp >= p_start_date)
        AND (p_end_date IS NULL OR j.last_event_timestamp <= p_end_date);
    
    -- Count total centers
    SELECT COUNT(DISTINCT postal_center_id)::INTEGER
    INTO v_total_centers
    FROM journey_segments
    WHERE account_id = p_account_id
        AND postal_center_id IS NOT NULL;
    
    -- Calculate health score (weighted average)
    v_health_score := ROUND(
        (COALESCE(v_on_time_rate, 0) * 0.50) +
        (GREATEST(0, 100 - (COALESCE(v_avg_transit, 0) * 2)) * 0.30) +
        (GREATEST(0, 100 - (COALESCE(v_avg_processing, 0) * 10)) * 0.20),
        2
    );
    
    -- Return results
    RETURN QUERY SELECT
        v_health_score,
        COALESCE(v_on_time_rate, 0),
        COALESCE(v_avg_transit, 0),
        COALESCE(v_avg_processing, 0),
        COALESCE(v_total_items, 0),
        COALESCE(v_total_routes, 0),
        COALESCE(v_total_centers, 0),
        COALESCE(v_total_violations, 0);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.calculate_working_minutes(p_start_timestamp timestamp with time zone, p_end_timestamp timestamp with time zone, p_account_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
    v_natural_minutes INTEGER;
    v_working_minutes INTEGER;
    v_current_date DATE;
    v_end_date DATE;
    v_day_of_week INTEGER;
    v_is_non_working BOOLEAN;
    v_minutes_to_subtract INTEGER := 0;
BEGIN
    IF p_start_timestamp IS NULL OR p_end_timestamp IS NULL THEN
        RETURN 0;
    END IF;
    
    IF p_end_timestamp <= p_start_timestamp THEN
        RETURN 0;
    END IF;
    
    v_natural_minutes := EXTRACT(EPOCH FROM (p_end_timestamp - p_start_timestamp))::INTEGER / 60;
    v_working_minutes := v_natural_minutes;
    
    v_current_date := p_start_timestamp::DATE;
    v_end_date := p_end_timestamp::DATE;
    
    WHILE v_current_date <= v_end_date LOOP
        v_day_of_week := EXTRACT(DOW FROM v_current_date);
        
        -- Restar fines de semana
        IF v_day_of_week IN (0, 6) THEN
            IF v_current_date = v_end_date AND v_current_date = p_start_timestamp::DATE THEN
                v_minutes_to_subtract := v_minutes_to_subtract + v_natural_minutes;
            ELSIF v_current_date = p_start_timestamp::DATE THEN
                v_minutes_to_subtract := v_minutes_to_subtract + 
                    EXTRACT(EPOCH FROM ((v_current_date + INTERVAL '1 day')::TIMESTAMPTZ - p_start_timestamp))::INTEGER / 60;
            ELSIF v_current_date = v_end_date THEN
                v_minutes_to_subtract := v_minutes_to_subtract + 
                    EXTRACT(EPOCH FROM (p_end_timestamp - v_current_date::TIMESTAMPTZ))::INTEGER / 60;
            ELSE
                v_minutes_to_subtract := v_minutes_to_subtract + 1440;
            END IF;
        END IF;
        
        -- Restar festivos
        SELECT EXISTS(
            SELECT 1 FROM non_working_days
            WHERE account_id = p_account_id AND date = v_current_date
        ) INTO v_is_non_working;
        
        IF v_is_non_working THEN
            IF v_current_date = v_end_date AND v_current_date = p_start_timestamp::DATE THEN
                v_minutes_to_subtract := v_minutes_to_subtract + v_natural_minutes;
            ELSIF v_current_date = p_start_timestamp::DATE THEN
                v_minutes_to_subtract := v_minutes_to_subtract + 
                    EXTRACT(EPOCH FROM ((v_current_date + INTERVAL '1 day')::TIMESTAMPTZ - p_start_timestamp))::INTEGER / 60;
            ELSIF v_current_date = v_end_date THEN
                v_minutes_to_subtract := v_minutes_to_subtract + 
                    EXTRACT(EPOCH FROM (p_end_timestamp - v_current_date::TIMESTAMPTZ))::INTEGER / 60;
            ELSE
                v_minutes_to_subtract := v_minutes_to_subtract + 1440;
            END IF;
        END IF;
        
        v_current_date := v_current_date + INTERVAL '1 day';
    END LOOP;
    
    v_working_minutes := v_natural_minutes - v_minutes_to_subtract;
    
    IF v_working_minutes < 0 THEN
        v_working_minutes := 0;
    END IF;
    
    RETURN v_working_minutes;
EXCEPTION
    WHEN OTHERS THEN
        RETURN v_natural_minutes;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.calculate_working_minutes_simple(p_start_timestamp timestamp with time zone, p_end_timestamp timestamp with time zone)
 RETURNS integer
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    v_natural_minutes INTEGER;
    v_working_minutes INTEGER;
    v_current_date DATE;
    v_end_date DATE;
    v_day_of_week INTEGER;
    v_minutes_to_subtract INTEGER := 0;
BEGIN
    IF p_start_timestamp IS NULL OR p_end_timestamp IS NULL THEN
        RETURN 0;
    END IF;
    
    IF p_end_timestamp <= p_start_timestamp THEN
        RETURN 0;
    END IF;
    
    v_natural_minutes := EXTRACT(EPOCH FROM (p_end_timestamp - p_start_timestamp))::INTEGER / 60;
    v_working_minutes := v_natural_minutes;
    
    v_current_date := p_start_timestamp::DATE;
    v_end_date := p_end_timestamp::DATE;
    
    WHILE v_current_date <= v_end_date LOOP
        v_day_of_week := EXTRACT(DOW FROM v_current_date);
        
        IF v_day_of_week IN (0, 6) THEN
            IF v_current_date = v_end_date AND v_current_date = p_start_timestamp::DATE THEN
                v_minutes_to_subtract := v_minutes_to_subtract + v_natural_minutes;
            ELSIF v_current_date = p_start_timestamp::DATE THEN
                v_minutes_to_subtract := v_minutes_to_subtract + 
                    EXTRACT(EPOCH FROM ((v_current_date + INTERVAL '1 day')::TIMESTAMPTZ - p_start_timestamp))::INTEGER / 60;
            ELSIF v_current_date = v_end_date THEN
                v_minutes_to_subtract := v_minutes_to_subtract + 
                    EXTRACT(EPOCH FROM (p_end_timestamp - v_current_date::TIMESTAMPTZ))::INTEGER / 60;
            ELSE
                v_minutes_to_subtract := v_minutes_to_subtract + 1440;
            END IF;
        END IF;
        
        v_current_date := v_current_date + INTERVAL '1 day';
    END LOOP;
    
    v_working_minutes := v_natural_minutes - v_minutes_to_subtract;
    
    IF v_working_minutes < 0 THEN
        v_working_minutes := 0;
    END IF;
    
    RETURN v_working_minutes;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.classify_route(p_origin_city_id uuid, p_destination_city_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  v_origin_type TEXT;
  v_destination_type TEXT;
BEGIN
  -- Get origin city type
  SELECT city_type INTO v_origin_type
  FROM cities
  WHERE id = p_origin_city_id;
  
  -- Get destination city type
  SELECT city_type INTO v_destination_type
  FROM cities
  WHERE id = p_destination_city_id;
  
  -- Handle NULL cases
  IF v_origin_type IS NULL OR v_destination_type IS NULL THEN
    RETURN 'unclassified';
  END IF;
  
  -- Return classification
  RETURN v_origin_type || '-' || v_destination_type;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.cleanup_processed_rfid_events(p_account_id uuid DEFAULT NULL::uuid, p_older_than_hours integer DEFAULT 24)
 RETURNS TABLE(deleted_count integer, target_account_id uuid, oldest_processed_at timestamp with time zone, newest_processed_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_deleted_count INTEGER;
  v_oldest_processed TIMESTAMPTZ;
  v_newest_processed TIMESTAMPTZ;
  v_cutoff_time TIMESTAMPTZ;
BEGIN
  -- Calculate cutoff time (only delete events processed more than X hours ago)
  v_cutoff_time := NOW() - (p_older_than_hours || ' hours')::INTERVAL;

  -- Get statistics before deletion
  SELECT 
    MIN(r.processed_at),
    MAX(r.processed_at)
  INTO 
    v_oldest_processed,
    v_newest_processed
  FROM rfid_intermediate_db r
  WHERE r.processed_at IS NOT NULL
    AND r.processed_at < v_cutoff_time
    AND (p_account_id IS NULL OR r.account_id = p_account_id);

  -- Delete processed events
  WITH deleted AS (
    DELETE FROM rfid_intermediate_db r
    WHERE r.processed_at IS NOT NULL
      AND r.processed_at < v_cutoff_time
      AND (p_account_id IS NULL OR r.account_id = p_account_id)
    RETURNING *
  )
  SELECT COUNT(*)::INTEGER INTO v_deleted_count FROM deleted;

  -- Return results
  RETURN QUERY SELECT 
    v_deleted_count,
    p_account_id,
    v_oldest_processed,
    v_newest_processed;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_postal_center_config(p_postal_center_id uuid)
 RETURNS TABLE(calculation_mode text, mixed_reader_gap_minutes integer, opening_hour time without time zone, cutoff_time time without time zone)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    COALESCE(pc.calculation_mode, ac.calculation_mode) AS calculation_mode,
    COALESCE(pc.mixed_reader_gap_minutes, ac.mixed_reader_gap_minutes) AS mixed_reader_gap_minutes,
    pc.opening_hour,
    pc.cutoff_time
  FROM postal_centers pc
  JOIN account_config ac ON ac.account_id = pc.account_id
  WHERE pc.id = p_postal_center_id;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_sla_for_segment(p_account_id uuid, p_from_center_id uuid, p_to_center_id uuid)
 RETURNS TABLE(expected_duration_hours numeric, warning_threshold_multiplier numeric, critical_threshold_multiplier numeric)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
  RETURN QUERY
  SELECT 
    sla.expected_duration_hours,
    sla.warning_threshold_multiplier,
    sla.critical_threshold_multiplier
  FROM sla_definitions sla
  WHERE sla.account_id = p_account_id
    AND sla.from_postal_center_id = p_from_center_id
    AND sla.to_postal_center_id = p_to_center_id
    AND sla.is_active = true
  LIMIT 1;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_top_bottom_centers(p_account_id uuid, p_limit integer DEFAULT 5)
 RETURNS TABLE(rank_type text, center_name text, total_items bigint, avg_processing_hours numeric, outbound_on_time_rate numeric)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
  RETURN QUERY
  WITH center_stats AS (
    SELECT
      pc.name as center_name,
      COUNT(DISTINCT js.tag_id) as total_items,
      AVG(js.actual_time_minutes / 60.0) as avg_processing_hours,
      (SUM(CASE WHEN js.sla_compliance = 'on_time' THEN 1 ELSE 0 END)::NUMERIC / NULLIF(COUNT(*), 0)::NUMERIC * 100) as outbound_on_time_rate
    FROM journey_segments js
    JOIN postal_centers pc ON js.postal_center_id = pc.id
    WHERE js.account_id = p_account_id
      AND js.segment_type = 'processing'
      AND pc.account_id = p_account_id
    GROUP BY pc.name
    HAVING COUNT(DISTINCT js.tag_id) >= 3
  ),
  ranked_centers AS (
    SELECT
      cs.center_name,
      cs.total_items,
      cs.avg_processing_hours,
      cs.outbound_on_time_rate,
      ROW_NUMBER() OVER (ORDER BY cs.outbound_on_time_rate DESC, cs.avg_processing_hours ASC) as top_rank,
      ROW_NUMBER() OVER (ORDER BY cs.outbound_on_time_rate ASC, cs.avg_processing_hours DESC) as bottom_rank
    FROM center_stats cs
  )
  SELECT
    'top'::TEXT,
    rc.center_name,
    rc.total_items,
    ROUND(rc.avg_processing_hours, 2),
    ROUND(rc.outbound_on_time_rate, 2)
  FROM ranked_centers rc
  WHERE rc.top_rank <= p_limit
  
  UNION ALL
  
  SELECT
    'bottom'::TEXT,
    rc.center_name,
    rc.total_items,
    ROUND(rc.avg_processing_hours, 2),
    ROUND(rc.outbound_on_time_rate, 2)
  FROM ranked_centers rc
  WHERE rc.bottom_rank <= p_limit
  
  ORDER BY 1 DESC, 5 DESC;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.get_top_bottom_routes(p_account_id uuid, p_limit integer DEFAULT 5)
 RETURNS TABLE(rank_type text, origin_city_name text, destination_city_name text, total_journeys bigint, on_time_rate numeric, avg_transit_hours numeric)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
  RETURN QUERY
  WITH route_stats AS (
    SELECT
      j.origin_city_name,
      j.destination_city_name,
      COUNT(*) as total_journeys,
      (SUM(CASE WHEN j.total_sla_violations = 0 THEN 1 ELSE 0 END)::NUMERIC / NULLIF(COUNT(*), 0)::NUMERIC * 100) as on_time_rate,
      AVG(j.total_actual_time_minutes / 60.0) as avg_transit_hours
    FROM journeys j
    WHERE j.account_id = p_account_id
      AND j.journey_status = 'completed'
      AND j.origin_city_name IS NOT NULL
      AND j.destination_city_name IS NOT NULL
    GROUP BY j.origin_city_name, j.destination_city_name
    HAVING COUNT(*) >= 3
  ),
  ranked_routes AS (
    SELECT
      rs.origin_city_name,
      rs.destination_city_name,
      rs.total_journeys,
      rs.on_time_rate,
      rs.avg_transit_hours,
      ROW_NUMBER() OVER (ORDER BY rs.on_time_rate DESC, rs.avg_transit_hours ASC) as top_rank,
      ROW_NUMBER() OVER (ORDER BY rs.on_time_rate ASC, rs.avg_transit_hours DESC) as bottom_rank
    FROM route_stats rs
  )
  SELECT
    'top'::TEXT,
    rr.origin_city_name,
    rr.destination_city_name,
    rr.total_journeys,
    ROUND(rr.on_time_rate, 2),
    ROUND(rr.avg_transit_hours, 2)
  FROM ranked_routes rr
  WHERE rr.top_rank <= p_limit
  
  UNION ALL
  
  SELECT
    'bottom'::TEXT,
    rr.origin_city_name,
    rr.destination_city_name,
    rr.total_journeys,
    ROUND(rr.on_time_rate, 2),
    ROUND(rr.avg_transit_hours, 2)
  FROM ranked_routes rr
  WHERE rr.bottom_rank <= p_limit
  
  ORDER BY 1 DESC, 5 DESC;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.is_superadmin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = auth.uid() AND role = 'superadmin'
  )
$function$
;

CREATE OR REPLACE FUNCTION public.is_working_day(p_account_id uuid, p_postal_center_id uuid, p_date date)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_day_of_week INTEGER;
  v_is_non_working BOOLEAN;
  v_is_working_in_schedule BOOLEAN;
BEGIN
  -- Verificar si es dÃ­a no laborable (festivo)
  SELECT EXISTS(
    SELECT 1 FROM non_working_days
    WHERE account_id = p_account_id
      AND (postal_center_id = p_postal_center_id OR postal_center_id IS NULL)
      AND date = p_date
  ) INTO v_is_non_working;
  
  IF v_is_non_working THEN
    RETURN false;
  END IF;
  
  -- Verificar horario semanal
  v_day_of_week := EXTRACT(DOW FROM p_date);
  
  SELECT COALESCE(is_working_day, true) INTO v_is_working_in_schedule
  FROM weekly_schedule
  WHERE account_id = p_account_id
    AND (postal_center_id = p_postal_center_id OR postal_center_id IS NULL)
    AND day_of_week = v_day_of_week
  ORDER BY postal_center_id NULLS LAST
  LIMIT 1;
  
  RETURN COALESCE(v_is_working_in_schedule, true);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.prune_tool_messages_chat_memory()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.message->>'type' = 'tool'
     OR (NEW.message->>'type' = 'ai'
         AND (
              (jsonb_typeof(NEW.message->'tool_calls') = 'array'
               AND jsonb_array_length(NEW.message->'tool_calls') > 0)
           OR (jsonb_typeof(NEW.message->'additional_kwargs'->'tool_calls') = 'array'
               AND jsonb_array_length(NEW.message->'additional_kwargs'->'tool_calls') > 0)
         ))
  THEN
    EXECUTE format('DELETE FROM %I.%I WHERE id = $1', TG_TABLE_SCHEMA, TG_TABLE_NAME) USING NEW.id;
  END IF;
  RETURN NULL;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.recalculate_on_time_delivery_on_sla_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- Recalcular on_time_delivery para todos los shipments afectados
  UPDATE one_db
  SET on_time_delivery = (
    CASE 
      WHEN business_transit_days <= (
        SELECT CASE 
          WHEN ds.time_unit = 'days' THEN ds.standard_time
          ELSE ds.standard_time / 24
        END
        FROM delivery_standards ds
        JOIN carriers c ON c.id = ds.carrier_id AND c.name = one_db.carrier_name
        JOIN products p ON p.id = ds.product_id AND p.code = one_db.product_name
        JOIN cities oc ON oc.id = ds.origin_city_id AND oc.name = one_db.origin_city_name
        JOIN cities dc ON dc.id = ds.destination_city_id AND dc.name = one_db.destination_city_name
        WHERE ds.account_id = one_db.account_id
        LIMIT 1
      ) THEN true
      ELSE false
    END
  )
  WHERE carrier_name IN (SELECT name FROM carriers WHERE id = NEW.carrier_id)
    AND product_name IN (SELECT code FROM products WHERE id = NEW.product_id)
    AND origin_city_name IN (SELECT name FROM cities WHERE id = NEW.origin_city_id)
    AND destination_city_name IN (SELECT name FROM cities WHERE id = NEW.destination_city_id);
    
  RETURN NEW;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.reprocess_failed_events(p_account_id uuid)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_result JSON;
BEGIN
    SELECT consolidate_rfid_events(p_account_id) INTO v_result;
    RETURN v_result;
END;
$function$
;

CREATE OR REPLACE FUNCTION public.rpc_execute_pipeline_phase(p_phase text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_account_id uuid;
    v_result jsonb;
    v_consolidation_result json;
    v_segments_result json;
    v_aggregation_result json;
BEGIN
    -- Obtener account_id del usuario autenticado
    SELECT 
        COALESCE(
            (SELECT (raw_user_meta_data->>'account_id')::uuid FROM auth.users WHERE id = auth.uid()),
            (SELECT (auth.jwt()->>'account_id')::uuid),
            'f4d823d2-93e6-4755-9a89-9da87e7fa86e'::uuid
        )
    INTO v_account_id;

    IF v_account_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'No account_id found');
    END IF;

    IF p_phase IS NULL OR p_phase NOT IN ('consolidation', 'segments', 'aggregation', 'all') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid phase');
    END IF;

    IF p_phase = 'consolidation' OR p_phase = 'all' THEN
        v_consolidation_result := consolidate_rfid_events(v_account_id);
    END IF;

    IF p_phase = 'segments' OR p_phase = 'all' THEN
        v_segments_result := build_journey_segments(v_account_id);
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
END;
$function$
;

CREATE OR REPLACE FUNCTION public.rpc_get_pipeline_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_account_id uuid;
    v_raw_events_count integer;
    v_raw_events_pending integer;
    v_processed_events_count integer;
    v_segments_count integer;
    v_paths_count integer;
    v_last_consolidation timestamp with time zone;
    v_last_segment_build timestamp with time zone;
    v_last_aggregation timestamp with time zone;
BEGIN
    SELECT 
        COALESCE(
            (SELECT (raw_user_meta_data->>'account_id')::uuid FROM auth.users WHERE id = auth.uid()),
            (SELECT (auth.jwt()->>'account_id')::uuid),
            'f4d823d2-93e6-4755-9a89-9da87e7fa86e'::uuid
        )
    INTO v_account_id;

    IF v_account_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'No account_id found');
    END IF;

    SELECT 
        COUNT(*),
        COUNT(*) FILTER (WHERE is_processed = FALSE OR is_processed IS NULL)
    INTO v_raw_events_count, v_raw_events_pending
    FROM rfid_events_raw
    WHERE account_id = v_account_id;

    SELECT COUNT(*) INTO v_processed_events_count FROM processed_events WHERE account_id = v_account_id;
    SELECT COUNT(*) INTO v_segments_count FROM journey_segments WHERE account_id = v_account_id;
    SELECT COUNT(*) INTO v_paths_count FROM journey_paths WHERE account_id = v_account_id;

    SELECT MAX(created_at) INTO v_last_consolidation FROM processed_events WHERE account_id = v_account_id;
    SELECT MAX(created_at) INTO v_last_segment_build FROM journey_segments WHERE account_id = v_account_id;
    SELECT MAX(created_at) INTO v_last_aggregation FROM journey_paths WHERE account_id = v_account_id;

    RETURN jsonb_build_object(
        'success', true,
        'account_id', v_account_id,
        'raw_events', jsonb_build_object(
            'total', v_raw_events_count,
            'pending', v_raw_events_pending,
            'processed', v_raw_events_count - v_raw_events_pending
        ),
        'processed_events', jsonb_build_object(
            'total', v_processed_events_count
        ),
        'segments', jsonb_build_object(
            'total', v_segments_count
        ),
        'paths', jsonb_build_object(
            'total', v_paths_count
        ),
        'last_run', jsonb_build_object(
            'consolidation', v_last_consolidation,
            'segment_building', v_last_segment_build,
            'aggregation', v_last_aggregation
        )
    );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.rpc_get_recent_incidents(p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_account_id uuid;
BEGIN
    SELECT 
        COALESCE(
            (SELECT (raw_user_meta_data->>'account_id')::uuid FROM auth.users WHERE id = auth.uid()),
            (SELECT (auth.jwt()->>'account_id')::uuid),
            'f4d823d2-93e6-4755-9a89-9da87e7fa86e'::uuid
        )
    INTO v_account_id;

    RETURN jsonb_build_object(
        'success', true,
        'account_id', v_account_id,
        'incidents', '[]'::jsonb,
        'total', 0,
        'limit', p_limit
    );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.rpc_ingest_epcis_events(p_events jsonb)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_account_id UUID;
    v_event JSONB;
    v_inserted INTEGER := 0;
    v_failed INTEGER := 0;
BEGIN
    v_account_id := auth.uid()::UUID;
    
    -- Insert each event
    FOR v_event IN SELECT * FROM jsonb_array_elements(p_events)
    LOOP
        BEGIN
            INSERT INTO rfid_events_raw (
                account_id,
                tag_id,
                reader_id,  -- LPI
                event_timestamp,
                is_processed
            ) VALUES (
                v_account_id,
                v_event->>'TagId',
                v_event->>'ReaderId',
                (v_event->>'ReadLocalDateTime')::TIMESTAMPTZ,
                FALSE
            );
            
            v_inserted := v_inserted + 1;
            
        EXCEPTION
            WHEN OTHERS THEN
                v_failed := v_failed + 1;
        END;
    END LOOP;
    
    RETURN json_build_object(
        'success', TRUE,
        'inserted', v_inserted,
        'failed', v_failed
    );
    
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'success', FALSE,
            'error', SQLERRM
        );
END;
$function$
;

CREATE OR REPLACE FUNCTION public.rpc_query_journey_paths(p_carrier_id uuid DEFAULT NULL::uuid, p_product_id uuid DEFAULT NULL::uuid, p_origin_city text DEFAULT NULL::text, p_destination_city text DEFAULT NULL::text, p_min_tags integer DEFAULT NULL::integer, p_limit integer DEFAULT 100)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_account_id UUID;
    v_paths JSON;
BEGIN
    v_account_id := auth.uid()::UUID;
    
    SELECT json_agg(
        json_build_object(
            'id', id,
            'carrier_id', carrier_id,
            'product_id', product_id,
            'origin_city', origin_city_name,
            'destination_city', destination_city_name,
            'path_signature', path_signature,
            'path_segments', path_segments,
            'total_tags', total_tags,
            'avg_natural_time_minutes', avg_natural_time_minutes,
            'avg_working_time_minutes', avg_working_time_minutes,
            'compliance_rate', compliance_rate,
            'segment_details', segment_details,
            'last_updated', last_updated
        )
    ) INTO v_paths
    FROM journey_paths
    WHERE account_id = v_account_id
      AND (p_carrier_id IS NULL OR carrier_id = p_carrier_id)
      AND (p_product_id IS NULL OR product_id = p_product_id)
      AND (p_origin_city IS NULL OR origin_city_name = p_origin_city)
      AND (p_destination_city IS NULL OR destination_city_name = p_destination_city)
      AND (p_min_tags IS NULL OR total_tags >= p_min_tags)
    ORDER BY total_tags DESC
    LIMIT p_limit;
    
    RETURN COALESCE(v_paths, '[]'::JSON);
END;
$function$
;

CREATE OR REPLACE FUNCTION public.user_account_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT account_id FROM profiles WHERE id = auth.uid()
$function$
;

-- ---------------------------------------------------------------------
-- 4) TABLAS (22)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.account_config (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  calculation_mode text NOT NULL DEFAULT 'natural_days'::text,
  mixed_reader_gap_minutes integer NOT NULL DEFAULT 10,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  created_by uuid,
  updated_by uuid
);

CREATE TABLE IF NOT EXISTS public.diagnosis_anomalies (
  id bigint NOT NULL DEFAULT nextval('diagnosis_anomalies_id_seq'::regclass),
  account_id uuid NOT NULL,
  route_id bigint,
  tag_id text NOT NULL,
  anomaly_type text NOT NULL,
  severity text NOT NULL,
  description text NOT NULL,
  reader_id text,
  detected_at timestamp with time zone NOT NULL,
  metadata jsonb,
  resolved boolean DEFAULT false,
  resolved_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  postal_center_id uuid,
  expected_duration_hours numeric(10,2),
  actual_duration_hours numeric(10,2)
);

CREATE TABLE IF NOT EXISTS public.diagnosis_routes (
  id bigint NOT NULL DEFAULT nextval('diagnosis_routes_id_seq'::regclass),
  account_id uuid NOT NULL,
  tag_id text NOT NULL,
  route_start_time timestamp with time zone NOT NULL,
  route_end_time timestamp with time zone NOT NULL,
  total_duration_hours numeric(10,2) NOT NULL,
  reader_sequence text[] NOT NULL,
  event_count integer NOT NULL,
  is_complete boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.diagnosis_time_metrics (
  id bigint NOT NULL DEFAULT nextval('diagnosis_time_metrics_id_seq'::regclass),
  account_id uuid NOT NULL,
  route_id bigint NOT NULL,
  tag_id text NOT NULL,
  from_reader_id text NOT NULL,
  to_reader_id text NOT NULL,
  segment_duration_hours numeric(10,2) NOT NULL,
  segment_start_time timestamp with time zone NOT NULL,
  segment_end_time timestamp with time zone NOT NULL,
  expected_duration_hours numeric(10,2),
  is_delayed boolean DEFAULT false,
  delay_hours numeric(10,2),
  created_at timestamp with time zone DEFAULT now(),
  from_postal_center_id uuid,
  to_postal_center_id uuid,
  actual_duration_hours numeric(10,2),
  adjusted_duration_hours numeric(10,2),
  sla_status text,
  analysis_datetime_local timestamp without time zone,
  cutoff_adjusted boolean DEFAULT false
);

CREATE TABLE IF NOT EXISTS public.material_movements (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  material_id uuid NOT NULL,
  movement_type text NOT NULL,
  quantity numeric(10,2) NOT NULL,
  from_location text,
  to_location text,
  reference_id uuid,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  from_location_type text,
  from_location_id uuid,
  to_location_type text,
  to_location_id uuid,
  reference_type text
);

CREATE TABLE IF NOT EXISTS public.material_requirements_periods (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  period_start date NOT NULL,
  period_end date NOT NULL,
  material_id uuid NOT NULL,
  quantity_needed numeric NOT NULL DEFAULT 0,
  quantity_ordered numeric NOT NULL DEFAULT 0,
  quantity_received numeric NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending'::text,
  plans_count integer NOT NULL DEFAULT 0,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.material_shipment_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  material_shipment_id uuid NOT NULL,
  material_id uuid NOT NULL,
  quantity_sent numeric(10,2) NOT NULL,
  quantity_received numeric(10,2) DEFAULT 0,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.material_shipments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  shipment_number text,
  panelist_id uuid NOT NULL,
  status text DEFAULT 'pending'::text,
  shipment_date date,
  expected_date date,
  received_date date,
  tracking_number text,
  total_items integer DEFAULT 0,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.material_stocks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  material_id uuid NOT NULL,
  quantity numeric(10,2) NOT NULL DEFAULT 0,
  min_stock numeric(10,2) DEFAULT 0,
  max_stock numeric(10,2) DEFAULT 0,
  last_updated timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  location_type text,
  location_id uuid
);

CREATE TABLE IF NOT EXISTS public.n8n_upu_agent (
  id integer NOT NULL DEFAULT nextval('n8n_upu_agent_id_seq'::regclass),
  session_id character varying(255) NOT NULL,
  message jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.n8n_upu_incident (
  id integer NOT NULL DEFAULT nextval('n8n_upu_incident_id_seq'::regclass),
  session_id character varying(255) NOT NULL,
  message jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.n8n_upu_timeoff (
  id integer NOT NULL DEFAULT nextval('n8n_upu_timeoff_id_seq'::regclass),
  session_id character varying(255) NOT NULL,
  message jsonb NOT NULL
);

CREATE TABLE IF NOT EXISTS public.panelist_context (
  id bigint NOT NULL DEFAULT nextval('panelist_context_id_seq'::regclass),
  telegram_id text NOT NULL,
  context_type text NOT NULL,
  context_data jsonb,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.panelist_material_stocks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  panelist_id uuid NOT NULL,
  material_id uuid NOT NULL,
  quantity numeric(10,2) NOT NULL DEFAULT 0,
  last_updated timestamp with time zone DEFAULT now(),
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.purchase_order_items (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  purchase_order_id uuid NOT NULL,
  material_id uuid NOT NULL,
  quantity_ordered numeric(10,2) NOT NULL,
  quantity_received numeric(10,2) DEFAULT 0,
  unit_price numeric(10,2),
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.purchase_orders (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  po_number text,
  status text DEFAULT 'draft'::text,
  order_date date,
  expected_date date,
  received_date date,
  supplier text,
  total_items integer DEFAULT 0,
  notes text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.reporting_config (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  compliance_threshold_warning integer DEFAULT 85,
  compliance_threshold_critical integer DEFAULT 75,
  default_report_period text DEFAULT 'month'::text,
  use_regional_grouping boolean DEFAULT true,
  preferred_map_alternative text DEFAULT 'treemap'::text,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_by uuid
);

CREATE TABLE IF NOT EXISTS public.rfid_intermediate_db (
  id bigint NOT NULL DEFAULT nextval('rfid_intermediate_db_id_seq'::regclass),
  event_id uuid NOT NULL,
  read_local_date_time timestamp with time zone NOT NULL,
  reader_id text NOT NULL,
  tag_id text NOT NULL,
  account_id uuid NOT NULL,
  ingested_at timestamp with time zone DEFAULT now(),
  processed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.shipment_incident (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  parcel_id uuid NOT NULL,
  panelist_id uuid,
  account_id uuid,
  telegram_id text NOT NULL,
  description text NOT NULL,
  panelist_language text,
  reported_at timestamp with time zone NOT NULL DEFAULT now(),
  email_sent_to text,
  email_sent_at timestamp with time zone,
  status text DEFAULT 'reported'::text
);

CREATE TABLE IF NOT EXISTS public.sla_definitions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  from_postal_center_id uuid NOT NULL,
  to_postal_center_id uuid NOT NULL,
  expected_duration_hours numeric(10,2) NOT NULL,
  warning_threshold_multiplier numeric(5,2) NOT NULL DEFAULT 1.5,
  critical_threshold_multiplier numeric(5,2) NOT NULL DEFAULT 2.0,
  is_active boolean DEFAULT true,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  created_by uuid,
  updated_by uuid
);

CREATE TABLE IF NOT EXISTS public.stock_alerts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  material_id uuid NOT NULL,
  alert_type text NOT NULL,
  location_id uuid,
  current_quantity numeric NOT NULL,
  expected_quantity numeric,
  reference_id uuid,
  reference_type text,
  notes text,
  created_at timestamp with time zone DEFAULT now(),
  resolved_at timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.stock_settings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  stock_control_enabled boolean DEFAULT false,
  auto_generate_purchase_orders boolean DEFAULT false,
  auto_generate_shipments boolean DEFAULT false,
  purchase_lead_time_days integer DEFAULT 7,
  shipment_lead_time_days integer DEFAULT 3,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 5) CONSTRAINTS (PK, unique, check, FK)
-- ---------------------------------------------------------------------
ALTER TABLE public.account_config ADD CONSTRAINT account_config_pkey PRIMARY KEY (id);
ALTER TABLE public.diagnosis_anomalies ADD CONSTRAINT diagnosis_anomalies_pkey PRIMARY KEY (id);
ALTER TABLE public.diagnosis_routes ADD CONSTRAINT diagnosis_routes_pkey PRIMARY KEY (id);
ALTER TABLE public.diagnosis_time_metrics ADD CONSTRAINT diagnosis_time_metrics_pkey PRIMARY KEY (id);
ALTER TABLE public.material_movements ADD CONSTRAINT material_movements_pkey PRIMARY KEY (id);
ALTER TABLE public.material_requirements_periods ADD CONSTRAINT material_requirements_periods_pkey PRIMARY KEY (id);
ALTER TABLE public.material_shipment_items ADD CONSTRAINT material_shipment_items_pkey PRIMARY KEY (id);
ALTER TABLE public.material_shipments ADD CONSTRAINT material_shipments_pkey PRIMARY KEY (id);
ALTER TABLE public.material_stocks ADD CONSTRAINT material_stocks_pkey PRIMARY KEY (id);
ALTER TABLE public.n8n_upu_agent ADD CONSTRAINT n8n_upu_agent_pkey PRIMARY KEY (id);
ALTER TABLE public.n8n_upu_incident ADD CONSTRAINT n8n_upu_incident_pkey PRIMARY KEY (id);
ALTER TABLE public.n8n_upu_timeoff ADD CONSTRAINT n8n_upu_timeoff_pkey PRIMARY KEY (id);
ALTER TABLE public.panelist_context ADD CONSTRAINT panelist_context_pkey PRIMARY KEY (id);
ALTER TABLE public.panelist_material_stocks ADD CONSTRAINT panelist_material_stocks_pkey PRIMARY KEY (id);
ALTER TABLE public.purchase_order_items ADD CONSTRAINT purchase_order_items_pkey PRIMARY KEY (id);
ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_pkey PRIMARY KEY (id);
ALTER TABLE public.reporting_config ADD CONSTRAINT reporting_config_pkey PRIMARY KEY (id);
ALTER TABLE public.rfid_intermediate_db ADD CONSTRAINT rfid_intermediate_db_pkey PRIMARY KEY (id);
ALTER TABLE public.shipment_incident ADD CONSTRAINT shipment_incident_pkey PRIMARY KEY (id);
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_pkey PRIMARY KEY (id);
ALTER TABLE public.stock_alerts ADD CONSTRAINT stock_alerts_pkey PRIMARY KEY (id);
ALTER TABLE public.stock_settings ADD CONSTRAINT stock_settings_pkey PRIMARY KEY (id);
ALTER TABLE public.account_config ADD CONSTRAINT account_config_account_id_key UNIQUE (account_id);
ALTER TABLE public.material_requirements_periods ADD CONSTRAINT unique_account_period_material UNIQUE (account_id, period_start, period_end, material_id);
ALTER TABLE public.material_shipments ADD CONSTRAINT material_shipments_shipment_number_key UNIQUE (shipment_number);
ALTER TABLE public.material_stocks ADD CONSTRAINT material_stocks_account_id_material_id_key UNIQUE (account_id, material_id);
ALTER TABLE public.panelist_material_stocks ADD CONSTRAINT panelist_material_stocks_account_id_panelist_id_material_id_key UNIQUE (account_id, panelist_id, material_id);
ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_po_number_key UNIQUE (po_number);
ALTER TABLE public.reporting_config ADD CONSTRAINT reporting_config_unique_account UNIQUE (account_id);
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_account_id_from_postal_center_id_to_postal__key UNIQUE (account_id, from_postal_center_id, to_postal_center_id);
ALTER TABLE public.stock_alerts ADD CONSTRAINT stock_alerts_account_id_material_id_alert_type_location_id__key UNIQUE (account_id, material_id, alert_type, location_id, created_at);
ALTER TABLE public.stock_settings ADD CONSTRAINT stock_settings_account_id_key UNIQUE (account_id);
ALTER TABLE public.account_config ADD CONSTRAINT account_config_calculation_mode_check CHECK ((calculation_mode = ANY (ARRAY['natural_days'::text, 'working_days'::text])));
ALTER TABLE public.account_config ADD CONSTRAINT account_config_mixed_reader_gap_minutes_check CHECK ((mixed_reader_gap_minutes > 0));
ALTER TABLE public.diagnosis_time_metrics ADD CONSTRAINT diagnosis_time_metrics_sla_status_check CHECK ((sla_status = ANY (ARRAY['on_time'::text, 'warning'::text, 'critical'::text])));
ALTER TABLE public.material_requirements_periods ADD CONSTRAINT material_requirements_periods_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'ordered'::text, 'received'::text])));
ALTER TABLE public.reporting_config ADD CONSTRAINT reporting_config_compliance_threshold_critical_check CHECK (((compliance_threshold_critical >= 0) AND (compliance_threshold_critical <= 100)));
ALTER TABLE public.reporting_config ADD CONSTRAINT reporting_config_compliance_threshold_warning_check CHECK (((compliance_threshold_warning >= 0) AND (compliance_threshold_warning <= 100)));
ALTER TABLE public.reporting_config ADD CONSTRAINT reporting_config_default_report_period_check CHECK ((default_report_period = ANY (ARRAY['week'::text, 'month'::text, 'quarter'::text])));
ALTER TABLE public.reporting_config ADD CONSTRAINT reporting_config_preferred_map_alternative_check CHECK ((preferred_map_alternative = ANY (ARRAY['treemap'::text, 'heatmap'::text])));
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_check CHECK ((critical_threshold_multiplier > warning_threshold_multiplier));
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_check1 CHECK ((from_postal_center_id <> to_postal_center_id));
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_expected_duration_hours_check CHECK ((expected_duration_hours > (0)::numeric));
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_warning_threshold_multiplier_check CHECK ((warning_threshold_multiplier > 1.0));
ALTER TABLE public.stock_alerts ADD CONSTRAINT stock_alerts_alert_type_check CHECK ((alert_type = ANY (ARRAY['regulator_insufficient'::text, 'panelist_negative'::text])));
ALTER TABLE public.account_config ADD CONSTRAINT account_config_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.account_config ADD CONSTRAINT account_config_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
ALTER TABLE public.account_config ADD CONSTRAINT account_config_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);
ALTER TABLE public.diagnosis_anomalies ADD CONSTRAINT diagnosis_anomalies_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.diagnosis_anomalies ADD CONSTRAINT diagnosis_anomalies_postal_center_id_fkey FOREIGN KEY (postal_center_id) REFERENCES postal_centers(id);
ALTER TABLE public.diagnosis_anomalies ADD CONSTRAINT diagnosis_anomalies_route_id_fkey FOREIGN KEY (route_id) REFERENCES diagnosis_routes(id) ON DELETE CASCADE;
ALTER TABLE public.diagnosis_routes ADD CONSTRAINT diagnosis_routes_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.diagnosis_time_metrics ADD CONSTRAINT diagnosis_time_metrics_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.diagnosis_time_metrics ADD CONSTRAINT diagnosis_time_metrics_from_postal_center_id_fkey FOREIGN KEY (from_postal_center_id) REFERENCES postal_centers(id);
ALTER TABLE public.diagnosis_time_metrics ADD CONSTRAINT diagnosis_time_metrics_route_id_fkey FOREIGN KEY (route_id) REFERENCES diagnosis_routes(id) ON DELETE CASCADE;
ALTER TABLE public.diagnosis_time_metrics ADD CONSTRAINT diagnosis_time_metrics_to_postal_center_id_fkey FOREIGN KEY (to_postal_center_id) REFERENCES postal_centers(id);
ALTER TABLE public.material_movements ADD CONSTRAINT material_movements_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.material_movements ADD CONSTRAINT material_movements_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
ALTER TABLE public.material_movements ADD CONSTRAINT material_movements_material_id_fkey FOREIGN KEY (material_id) REFERENCES material_catalog(id) ON DELETE CASCADE;
ALTER TABLE public.material_requirements_periods ADD CONSTRAINT material_requirements_periods_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.material_requirements_periods ADD CONSTRAINT material_requirements_periods_material_id_fkey FOREIGN KEY (material_id) REFERENCES material_catalog(id) ON DELETE CASCADE;
ALTER TABLE public.material_shipment_items ADD CONSTRAINT material_shipment_items_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.material_shipment_items ADD CONSTRAINT material_shipment_items_material_id_fkey FOREIGN KEY (material_id) REFERENCES material_catalog(id) ON DELETE CASCADE;
ALTER TABLE public.material_shipment_items ADD CONSTRAINT material_shipment_items_material_shipment_id_fkey FOREIGN KEY (material_shipment_id) REFERENCES material_shipments(id) ON DELETE CASCADE;
ALTER TABLE public.material_shipments ADD CONSTRAINT material_shipments_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.material_shipments ADD CONSTRAINT material_shipments_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
ALTER TABLE public.material_shipments ADD CONSTRAINT material_shipments_panelist_id_fkey FOREIGN KEY (panelist_id) REFERENCES panelists(id) ON DELETE CASCADE;
ALTER TABLE public.material_stocks ADD CONSTRAINT material_stocks_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.material_stocks ADD CONSTRAINT material_stocks_material_id_fkey FOREIGN KEY (material_id) REFERENCES material_catalog(id) ON DELETE CASCADE;
ALTER TABLE public.panelist_material_stocks ADD CONSTRAINT panelist_material_stocks_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.panelist_material_stocks ADD CONSTRAINT panelist_material_stocks_material_id_fkey FOREIGN KEY (material_id) REFERENCES material_catalog(id) ON DELETE CASCADE;
ALTER TABLE public.panelist_material_stocks ADD CONSTRAINT panelist_material_stocks_panelist_id_fkey FOREIGN KEY (panelist_id) REFERENCES panelists(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_order_items ADD CONSTRAINT purchase_order_items_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_order_items ADD CONSTRAINT purchase_order_items_material_id_fkey FOREIGN KEY (material_id) REFERENCES material_catalog(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_order_items ADD CONSTRAINT purchase_order_items_purchase_order_id_fkey FOREIGN KEY (purchase_order_id) REFERENCES purchase_orders(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.purchase_orders ADD CONSTRAINT purchase_orders_created_by_fkey FOREIGN KEY (created_by) REFERENCES profiles(id);
ALTER TABLE public.reporting_config ADD CONSTRAINT reporting_config_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.reporting_config ADD CONSTRAINT reporting_config_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);
ALTER TABLE public.rfid_intermediate_db ADD CONSTRAINT rfid_intermediate_db_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.shipment_incident ADD CONSTRAINT shipment_incident_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.shipment_incident ADD CONSTRAINT shipment_incident_panelist_id_fkey FOREIGN KEY (panelist_id) REFERENCES panelists(id) ON DELETE SET NULL;
ALTER TABLE public.shipment_incident ADD CONSTRAINT shipment_incident_parcel_id_fkey FOREIGN KEY (parcel_id) REFERENCES allocation_plan_details(id) ON DELETE CASCADE;
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_created_by_fkey FOREIGN KEY (created_by) REFERENCES auth.users(id);
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_from_postal_center_id_fkey FOREIGN KEY (from_postal_center_id) REFERENCES postal_centers(id) ON DELETE CASCADE;
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_to_postal_center_id_fkey FOREIGN KEY (to_postal_center_id) REFERENCES postal_centers(id) ON DELETE CASCADE;
ALTER TABLE public.sla_definitions ADD CONSTRAINT sla_definitions_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES auth.users(id);
ALTER TABLE public.stock_alerts ADD CONSTRAINT stock_alerts_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;
ALTER TABLE public.stock_alerts ADD CONSTRAINT stock_alerts_material_id_fkey FOREIGN KEY (material_id) REFERENCES material_catalog(id) ON DELETE CASCADE;
ALTER TABLE public.stock_settings ADD CONSTRAINT stock_settings_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE;

-- ---------------------------------------------------------------------
-- 6) ÍNDICES
-- ---------------------------------------------------------------------
CREATE INDEX diagnosis_anomalies_account_id_idx ON public.diagnosis_anomalies USING btree (account_id);
CREATE INDEX diagnosis_anomalies_resolved_idx ON public.diagnosis_anomalies USING btree (resolved);
CREATE INDEX diagnosis_anomalies_route_id_idx ON public.diagnosis_anomalies USING btree (route_id);
CREATE INDEX diagnosis_anomalies_severity_idx ON public.diagnosis_anomalies USING btree (severity);
CREATE INDEX diagnosis_anomalies_tag_id_idx ON public.diagnosis_anomalies USING btree (tag_id);
CREATE INDEX diagnosis_anomalies_type_idx ON public.diagnosis_anomalies USING btree (anomaly_type);
CREATE INDEX diagnosis_routes_account_id_idx ON public.diagnosis_routes USING btree (account_id);
CREATE INDEX diagnosis_routes_end_time_idx ON public.diagnosis_routes USING btree (route_end_time);
CREATE INDEX diagnosis_routes_start_time_idx ON public.diagnosis_routes USING btree (route_start_time);
CREATE INDEX diagnosis_routes_tag_id_idx ON public.diagnosis_routes USING btree (tag_id);
CREATE INDEX diagnosis_time_metrics_account_id_idx ON public.diagnosis_time_metrics USING btree (account_id);
CREATE INDEX diagnosis_time_metrics_readers_idx ON public.diagnosis_time_metrics USING btree (from_reader_id, to_reader_id);
CREATE INDEX diagnosis_time_metrics_route_id_idx ON public.diagnosis_time_metrics USING btree (route_id);
CREATE INDEX diagnosis_time_metrics_tag_id_idx ON public.diagnosis_time_metrics USING btree (tag_id);
CREATE INDEX idx_account_config_account ON public.account_config USING btree (account_id);
CREATE INDEX idx_diagnosis_anomalies_postal_center ON public.diagnosis_anomalies USING btree (postal_center_id);
CREATE INDEX idx_diagnosis_time_metrics_from_center ON public.diagnosis_time_metrics USING btree (from_postal_center_id);
CREATE INDEX idx_diagnosis_time_metrics_sla_status ON public.diagnosis_time_metrics USING btree (sla_status);
CREATE INDEX idx_diagnosis_time_metrics_to_center ON public.diagnosis_time_metrics USING btree (to_postal_center_id);
CREATE INDEX idx_material_movements_account ON public.material_movements USING btree (account_id);
CREATE INDEX idx_material_movements_created ON public.material_movements USING btree (created_at DESC);
CREATE INDEX idx_material_movements_from_location ON public.material_movements USING btree (from_location_type, from_location_id);
CREATE INDEX idx_material_movements_material ON public.material_movements USING btree (material_id);
CREATE INDEX idx_material_movements_to_location ON public.material_movements USING btree (to_location_type, to_location_id);
CREATE INDEX idx_material_movements_type ON public.material_movements USING btree (movement_type);
CREATE INDEX idx_material_requirements_periods_account ON public.material_requirements_periods USING btree (account_id);
CREATE INDEX idx_material_requirements_periods_material ON public.material_requirements_periods USING btree (material_id);
CREATE INDEX idx_material_requirements_periods_period ON public.material_requirements_periods USING btree (period_start, period_end);
CREATE INDEX idx_material_requirements_periods_status ON public.material_requirements_periods USING btree (status);
CREATE INDEX idx_material_shipments_account ON public.material_shipments USING btree (account_id);
CREATE INDEX idx_material_shipments_created ON public.material_shipments USING btree (created_at DESC);
CREATE INDEX idx_material_shipments_panelist ON public.material_shipments USING btree (panelist_id);
CREATE INDEX idx_material_shipments_status ON public.material_shipments USING btree (status);
CREATE INDEX idx_material_stocks_account ON public.material_stocks USING btree (account_id);
CREATE INDEX idx_material_stocks_location ON public.material_stocks USING btree (location_type, location_id);
CREATE INDEX idx_material_stocks_material ON public.material_stocks USING btree (material_id);
CREATE INDEX idx_panelist_context_lookup ON public.panelist_context USING btree (telegram_id, context_type);
CREATE INDEX idx_panelist_stocks_account ON public.panelist_material_stocks USING btree (account_id);
CREATE INDEX idx_panelist_stocks_material ON public.panelist_material_stocks USING btree (material_id);
CREATE INDEX idx_panelist_stocks_panelist ON public.panelist_material_stocks USING btree (panelist_id);
CREATE INDEX idx_po_items_material ON public.purchase_order_items USING btree (material_id);
CREATE INDEX idx_po_items_po ON public.purchase_order_items USING btree (purchase_order_id);
CREATE INDEX idx_purchase_orders_account ON public.purchase_orders USING btree (account_id);
CREATE INDEX idx_purchase_orders_created ON public.purchase_orders USING btree (created_at DESC);
CREATE INDEX idx_purchase_orders_status ON public.purchase_orders USING btree (status);
CREATE INDEX idx_reporting_config_account ON public.reporting_config USING btree (account_id);
CREATE INDEX idx_shipment_incident_account ON public.shipment_incident USING btree (account_id);
CREATE INDEX idx_shipment_incident_panelist ON public.shipment_incident USING btree (panelist_id);
CREATE INDEX idx_shipment_incident_parcel ON public.shipment_incident USING btree (parcel_id);
CREATE INDEX idx_shipment_items_material ON public.material_shipment_items USING btree (material_id);
CREATE INDEX idx_shipment_items_shipment ON public.material_shipment_items USING btree (material_shipment_id);
CREATE INDEX idx_sla_definitions_account ON public.sla_definitions USING btree (account_id);
CREATE INDEX idx_sla_definitions_active ON public.sla_definitions USING btree (is_active) WHERE (is_active = true);
CREATE INDEX idx_sla_definitions_from_center ON public.sla_definitions USING btree (from_postal_center_id);
CREATE INDEX idx_sla_definitions_to_center ON public.sla_definitions USING btree (to_postal_center_id);
CREATE INDEX idx_stock_alerts_account ON public.stock_alerts USING btree (account_id);
CREATE INDEX idx_stock_alerts_created ON public.stock_alerts USING btree (created_at DESC);
CREATE INDEX idx_stock_alerts_location ON public.stock_alerts USING btree (location_id);
CREATE INDEX idx_stock_alerts_material ON public.stock_alerts USING btree (material_id);
CREATE INDEX idx_stock_alerts_resolved ON public.stock_alerts USING btree (resolved_at);
CREATE INDEX idx_stock_alerts_type ON public.stock_alerts USING btree (alert_type);
CREATE INDEX rfid_intermediate_db_account_id_idx ON public.rfid_intermediate_db USING btree (account_id);
CREATE INDEX rfid_intermediate_db_event_id_idx ON public.rfid_intermediate_db USING btree (event_id);
CREATE INDEX rfid_intermediate_db_processed_at_idx ON public.rfid_intermediate_db USING btree (processed_at);
CREATE INDEX rfid_intermediate_db_tag_id_idx ON public.rfid_intermediate_db USING btree (tag_id);

-- ---------------------------------------------------------------------
-- 7) TRIGGERS
-- ---------------------------------------------------------------------
CREATE TRIGGER update_account_config_updated_at BEFORE UPDATE ON public.account_config FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER prevent_diagnosis_anomalies_account_change BEFORE UPDATE ON public.diagnosis_anomalies FOR EACH ROW EXECUTE FUNCTION prevent_account_id_change();
CREATE TRIGGER set_diagnosis_anomalies_account_id BEFORE INSERT ON public.diagnosis_anomalies FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER prevent_diagnosis_routes_account_change BEFORE UPDATE ON public.diagnosis_routes FOR EACH ROW EXECUTE FUNCTION prevent_account_id_change();
CREATE TRIGGER set_diagnosis_routes_account_id BEFORE INSERT ON public.diagnosis_routes FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER prevent_diagnosis_time_metrics_account_change BEFORE UPDATE ON public.diagnosis_time_metrics FOR EACH ROW EXECUTE FUNCTION prevent_account_id_change();
CREATE TRIGGER set_diagnosis_time_metrics_account_id BEFORE INSERT ON public.diagnosis_time_metrics FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER update_material_shipment_items_updated_at BEFORE UPDATE ON public.material_shipment_items FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_material_shipments_updated_at BEFORE UPDATE ON public.material_shipments FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trigger_auto_resolve_regulator_alerts AFTER UPDATE OF quantity ON public.material_stocks FOR EACH ROW EXECUTE FUNCTION auto_resolve_stock_alerts();
CREATE TRIGGER update_material_stocks_updated_at BEFORE UPDATE ON public.material_stocks FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trg_prune_tool_messages AFTER INSERT ON public.n8n_upu_agent FOR EACH ROW EXECUTE FUNCTION prune_tool_messages_chat_memory();
CREATE TRIGGER trg_prune_tool_messages AFTER INSERT ON public.n8n_upu_incident FOR EACH ROW EXECUTE FUNCTION prune_tool_messages_chat_memory();
CREATE TRIGGER trg_prune_tool_messages AFTER INSERT ON public.n8n_upu_timeoff FOR EACH ROW EXECUTE FUNCTION prune_tool_messages_chat_memory();
CREATE TRIGGER trigger_auto_resolve_panelist_alerts AFTER UPDATE OF quantity ON public.panelist_material_stocks FOR EACH ROW EXECUTE FUNCTION auto_resolve_stock_alerts();
CREATE TRIGGER update_panelist_material_stocks_updated_at BEFORE UPDATE ON public.panelist_material_stocks FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_purchase_order_items_updated_at BEFORE UPDATE ON public.purchase_order_items FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_purchase_orders_updated_at BEFORE UPDATE ON public.purchase_orders FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER prevent_rfid_intermediate_db_account_change BEFORE UPDATE ON public.rfid_intermediate_db FOR EACH ROW EXECUTE FUNCTION prevent_account_id_change();
CREATE TRIGGER set_rfid_intermediate_db_account_id BEFORE INSERT ON public.rfid_intermediate_db FOR EACH ROW EXECUTE FUNCTION set_account_id();
CREATE TRIGGER update_sla_definitions_updated_at BEFORE UPDATE ON public.sla_definitions FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_stock_settings_updated_at BEFORE UPDATE ON public.stock_settings FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ---------------------------------------------------------------------
-- 8) RLS + POLICIES
-- ---------------------------------------------------------------------
ALTER TABLE public.account_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diagnosis_anomalies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diagnosis_routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.diagnosis_time_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reporting_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rfid_intermediate_db ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shipment_incident ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sla_definitions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Admins can manage account_config of their account" ON public.account_config AS PERMISSIVE FOR ALL TO public USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superuser'::text]))))));
CREATE POLICY "Users can view account_config of their account" ON public.account_config AS PERMISSIVE FOR SELECT TO public USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
CREATE POLICY account_config_select_own_account ON public.account_config AS PERMISSIVE FOR SELECT TO authenticated USING ((account_id = current_user_account_id()));
CREATE POLICY account_config_update_own_account ON public.account_config AS PERMISSIVE FOR UPDATE TO authenticated USING ((account_id = current_user_account_id()));
CREATE POLICY diagnosis_anomalies_delete ON public.diagnosis_anomalies AS PERMISSIVE FOR DELETE TO public USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY diagnosis_anomalies_insert ON public.diagnosis_anomalies AS PERMISSIVE FOR INSERT TO public WITH CHECK ((current_user_role() = ANY (ARRAY['superadmin'::text, 'admin'::text])));
CREATE POLICY diagnosis_anomalies_select ON public.diagnosis_anomalies AS PERMISSIVE FOR SELECT TO public USING (((current_user_role() = 'superadmin'::text) OR (account_id = current_user_account_id())));
CREATE POLICY diagnosis_anomalies_update ON public.diagnosis_anomalies AS PERMISSIVE FOR UPDATE TO public USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY diagnosis_routes_delete ON public.diagnosis_routes AS PERMISSIVE FOR DELETE TO public USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY diagnosis_routes_insert ON public.diagnosis_routes AS PERMISSIVE FOR INSERT TO public WITH CHECK ((current_user_role() = ANY (ARRAY['superadmin'::text, 'admin'::text])));
CREATE POLICY diagnosis_routes_select ON public.diagnosis_routes AS PERMISSIVE FOR SELECT TO public USING (((current_user_role() = 'superadmin'::text) OR (account_id = current_user_account_id())));
CREATE POLICY diagnosis_routes_update ON public.diagnosis_routes AS PERMISSIVE FOR UPDATE TO public USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY diagnosis_time_metrics_delete ON public.diagnosis_time_metrics AS PERMISSIVE FOR DELETE TO public USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY diagnosis_time_metrics_insert ON public.diagnosis_time_metrics AS PERMISSIVE FOR INSERT TO public WITH CHECK ((current_user_role() = ANY (ARRAY['superadmin'::text, 'admin'::text])));
CREATE POLICY diagnosis_time_metrics_select ON public.diagnosis_time_metrics AS PERMISSIVE FOR SELECT TO public USING (((current_user_role() = 'superadmin'::text) OR (account_id = current_user_account_id())));
CREATE POLICY diagnosis_time_metrics_update ON public.diagnosis_time_metrics AS PERMISSIVE FOR UPDATE TO public USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY superadmin_delete_material_shipment_items ON public.material_shipment_items AS PERMISSIVE FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY superadmin_insert_material_shipment_items ON public.material_shipment_items AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY superadmin_update_material_shipment_items ON public.material_shipment_items AS PERMISSIVE FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY superadmin_delete_material_shipments ON public.material_shipments AS PERMISSIVE FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY superadmin_insert_material_shipments ON public.material_shipments AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY superadmin_update_material_shipments ON public.material_shipments AS PERMISSIVE FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY superadmin_delete_panelist_material_stocks ON public.panelist_material_stocks AS PERMISSIVE FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY superadmin_insert_panelist_material_stocks ON public.panelist_material_stocks AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY superadmin_update_panelist_material_stocks ON public.panelist_material_stocks AS PERMISSIVE FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY superadmin_delete_purchase_order_items ON public.purchase_order_items AS PERMISSIVE FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY superadmin_insert_purchase_order_items ON public.purchase_order_items AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY superadmin_update_purchase_order_items ON public.purchase_order_items AS PERMISSIVE FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY superadmin_delete_purchase_orders ON public.purchase_orders AS PERMISSIVE FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY superadmin_insert_purchase_orders ON public.purchase_orders AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY superadmin_update_purchase_orders ON public.purchase_orders AS PERMISSIVE FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY reporting_config_select_policy ON public.reporting_config AS PERMISSIVE FOR SELECT TO public USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
CREATE POLICY reporting_config_update_policy ON public.reporting_config AS PERMISSIVE FOR UPDATE TO public USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY superadmin_delete_reporting_config ON public.reporting_config AS PERMISSIVE FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY superadmin_insert_reporting_config ON public.reporting_config AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY superadmin_update_reporting_config ON public.reporting_config AS PERMISSIVE FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY rfid_intermediate_db_delete ON public.rfid_intermediate_db AS PERMISSIVE FOR DELETE TO public USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY rfid_intermediate_db_insert ON public.rfid_intermediate_db AS PERMISSIVE FOR INSERT TO public WITH CHECK ((current_user_role() = ANY (ARRAY['superadmin'::text, 'admin'::text])));
CREATE POLICY rfid_intermediate_db_select ON public.rfid_intermediate_db AS PERMISSIVE FOR SELECT TO public USING (((current_user_role() = 'superadmin'::text) OR (account_id = current_user_account_id())));
CREATE POLICY rfid_intermediate_db_update ON public.rfid_intermediate_db AS PERMISSIVE FOR UPDATE TO public USING (((current_user_role() = 'superadmin'::text) OR ((current_user_role() = 'admin'::text) AND (account_id = current_user_account_id()))));
CREATE POLICY managers_select_own_account_incidents ON public.shipment_incident AS PERMISSIVE FOR SELECT TO public USING ((account_id IN ( SELECT a.id
   FROM accounts a
  WHERE (a.email_panelist_manager = auth.email()))));
CREATE POLICY service_role_full_access ON public.shipment_incident AS PERMISSIVE FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "Admins can manage sla_definitions of their account" ON public.sla_definitions AS PERMISSIVE FOR ALL TO public USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = ANY (ARRAY['admin'::text, 'superuser'::text]))))));
CREATE POLICY "Users can view sla_definitions of their account" ON public.sla_definitions AS PERMISSIVE FOR SELECT TO public USING ((account_id IN ( SELECT profiles.account_id
   FROM profiles
  WHERE (profiles.id = auth.uid()))));
CREATE POLICY superadmin_delete_stock_settings ON public.stock_settings AS PERMISSIVE FOR DELETE TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY superadmin_insert_stock_settings ON public.stock_settings AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));
CREATE POLICY superadmin_update_stock_settings ON public.stock_settings AS PERMISSIVE FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'superadmin'::text)))));

RESET check_function_bodies;
