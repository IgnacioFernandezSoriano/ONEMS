-- ============================================
-- Migration: Demo Reset Extended - UP
-- Date: 2026-01-28
-- Author: Manus AI
-- Description: Extends Demo Reset to delete and reload configuration data
-- ============================================

BEGIN;

-- ============================================
-- STEP 1: Create seed data table
-- ============================================

CREATE TABLE IF NOT EXISTS demo2_seed_data (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  table_name TEXT NOT NULL UNIQUE,
  data JSONB NOT NULL,
  record_count INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_demo2_seed_data_table_name 
  ON demo2_seed_data(table_name);

COMMENT ON TABLE demo2_seed_data IS 
  'Stores DEMO2 seed data for automatic reset';

-- ============================================
-- STEP 2: Backup current function (rename)
-- ============================================

-- Rename current function to keep as backup
DROP FUNCTION IF EXISTS admin_reset_account_data_backup(text);
CREATE OR REPLACE FUNCTION admin_reset_account_data_backup(p_account_identifier text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_account_id UUID;
  v_account_name TEXT;
  v_deleted_counts JSONB := '{}'::JSONB;
  v_count INTEGER;
BEGIN
  SELECT id, name INTO v_account_id, v_account_name
  FROM accounts
  WHERE name = p_account_identifier 
     OR slug = p_account_identifier
  LIMIT 1;
  
  IF v_account_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', format('Account "%s" not found', p_account_identifier)
    );
  END IF;
  
  RAISE NOTICE 'Resetting data for account: % (ID: %)', v_account_name, v_account_id;
  
  DELETE FROM allocation_plan_details
  WHERE plan_id IN (SELECT id FROM allocation_plans WHERE account_id = v_account_id);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('allocation_plan_details', v_count);
  
  DELETE FROM allocation_plans WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('allocation_plans', v_count);
  
  DELETE FROM generated_allocation_plan_details
  WHERE plan_id IN (SELECT id FROM generated_allocation_plans WHERE account_id = v_account_id);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('generated_allocation_plan_details', v_count);
  
  DELETE FROM generated_allocation_plans WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('generated_allocation_plans', v_count);
  
  DELETE FROM material_shipment_items
  WHERE material_shipment_id IN (SELECT id FROM material_shipments WHERE account_id = v_account_id);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_shipment_items', v_count);
  
  DELETE FROM material_shipments WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_shipments', v_count);
  
  DELETE FROM material_movements WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_movements', v_count);
  
  DELETE FROM material_stocks WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_stocks', v_count);
  
  DELETE FROM panelist_material_stocks
  WHERE panelist_id IN (SELECT id FROM panelists WHERE account_id = v_account_id);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('panelist_material_stocks', v_count);
  
  DELETE FROM material_requirements_periods WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_requirements_periods', v_count);
  
  DELETE FROM purchase_order_items
  WHERE purchase_order_id IN (SELECT id FROM purchase_orders WHERE account_id = v_account_id);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('purchase_order_items', v_count);
  
  DELETE FROM purchase_orders WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('purchase_orders', v_count);
  
  DELETE FROM node_balancing_history WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('node_balancing_history', v_count);
  
  DELETE FROM panelist_unavailability
  WHERE panelist_id IN (SELECT id FROM panelists WHERE account_id = v_account_id);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('panelist_unavailability', v_count);
  
  DELETE FROM one_db WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('one_db', v_count);
  
  RETURN jsonb_build_object(
    'success', true,
    'account_id', v_account_id,
    'account_name', v_account_name,
    'message', format('Successfully reset data for account "%s"', v_account_name),
    'deleted_records', v_deleted_counts
  );
  
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', format('Error resetting account data: %s', SQLERRM)
    );
END;
$$;

COMMENT ON FUNCTION admin_reset_account_data_backup(text) IS 
  'Backup of original reset function (operational data only)';

-- ============================================
-- STEP 3: Create new extended function
-- ============================================

CREATE OR REPLACE FUNCTION admin_reset_and_seed_demo2()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_account_id UUID;
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
  
  v_seed_data JSONB;
  v_record JSONB;
  v_new_id UUID;
  v_region_id UUID;
  v_city_id UUID;
  v_node_id UUID;
  v_carrier_id UUID;
  v_material_id UUID;
  v_product_id UUID;
  v_origin_city_id UUID;
  v_dest_city_id UUID;
BEGIN
  SELECT id INTO v_account_id FROM accounts WHERE name = v_account_name;
  
  IF v_account_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', format('Account "%s" not found', v_account_name));
  END IF;
  
  RAISE NOTICE 'Resetting and seeding DEMO2 (ID: %)', v_account_id;
  
  -- STEP 1: Delete operational data (call backup function)
  RAISE NOTICE 'Step 1/3: Deleting operational data...';
  DECLARE
    v_reset_result JSONB;
  BEGIN
    v_reset_result := admin_reset_account_data_backup(v_account_name);
    v_deleted_counts := v_reset_result->'deleted_records';
  END;
  
  -- STEP 2: Delete configuration data
  RAISE NOTICE 'Step 2/3: Deleting configuration data...';
  
  DELETE FROM delivery_standards WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('delivery_standards', v_count);
  
  DELETE FROM product_materials WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('product_materials', v_count);
  
  DELETE FROM panelists WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('panelists', v_count);
  
  DELETE FROM nodes WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('nodes', v_count);
  
  DELETE FROM cities WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('cities', v_count);
  
  DELETE FROM regions WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('regions', v_count);
  
  DELETE FROM products WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('products', v_count);
  
  DELETE FROM carriers WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('carriers', v_count);
  
  DELETE FROM material_catalog WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('material_catalog', v_count);
  
  -- STEP 3: Reload seed data
  RAISE NOTICE 'Step 3/3: Reloading seed data...';
  
  -- 3.1 REGIONS
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'regions';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      INSERT INTO regions (account_id, code, name, description, country_code, status)
      VALUES (v_account_id, v_record->>'code', v_record->>'name', COALESCE(v_record->>'description', ''), 
              v_record->>'country_code', COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_region_map := v_region_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('regions', v_count);
  END IF;
  
  -- 3.2 CITIES
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'cities';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_region_id := (v_region_map->(v_record->>'region_id'))::uuid;
      INSERT INTO cities (account_id, region_id, code, name, latitude, longitude, classification, city_type, region_name, population, status)
      VALUES (v_account_id, v_region_id, v_record->>'code', v_record->>'name', 
              (v_record->>'latitude')::numeric, (v_record->>'longitude')::numeric,
              v_record->>'classification', v_record->>'city_type', v_record->>'region_name',
              (v_record->>'population')::integer, COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_city_map := v_city_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('cities', v_count);
  END IF;
  
  -- 3.3 NODES
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'nodes';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_city_id := (v_city_map->(v_record->>'city_id'))::uuid;
      INSERT INTO nodes (account_id, city_id, auto_id, status)
      VALUES (v_account_id, v_city_id, v_record->>'auto_id', COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_node_map := v_node_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('nodes', v_count);
  END IF;
  
  -- 3.4 CARRIERS
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'carriers';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      INSERT INTO carriers (account_id, code, name, type, status)
      VALUES (v_account_id, v_record->>'code', v_record->>'name', v_record->>'type', COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_carrier_map := v_carrier_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('carriers', v_count);
  END IF;
  
  -- 3.5 MATERIAL_CATALOG
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'material_catalog';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      INSERT INTO material_catalog (account_id, code, name, unit_measure, status)
      VALUES (v_account_id, v_record->>'code', v_record->>'name', v_record->>'unit_measure', COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_material_map := v_material_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('material_catalog', v_count);
  END IF;
  
  -- 3.6 PRODUCTS
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'products';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_carrier_id := (v_carrier_map->(v_record->>'carrier_id'))::uuid;
      INSERT INTO products (account_id, carrier_id, code, description, standard_delivery_hours, time_unit, status)
      VALUES (v_account_id, v_carrier_id, v_record->>'code', v_record->>'description',
              (v_record->>'standard_delivery_hours')::integer, COALESCE(v_record->>'time_unit', 'hours'),
              COALESCE(v_record->>'status', 'active'))
      RETURNING id INTO v_new_id;
      v_product_map := v_product_map || jsonb_build_object(v_record->>'id', v_new_id::text);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('products', v_count);
  END IF;
  
  -- 3.7 PRODUCT_MATERIALS
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'product_materials';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_product_id := (v_product_map->(v_record->>'product_id'))::uuid;
      v_material_id := (v_material_map->(v_record->>'material_id'))::uuid;
      INSERT INTO product_materials (account_id, product_id, material_id, quantity)
      VALUES (v_account_id, v_product_id, v_material_id, (v_record->>'quantity')::numeric);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('product_materials', v_count);
  END IF;
  
  -- 3.8 PANELISTS
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'panelists';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_node_id := (v_node_map->(v_record->>'node_id'))::uuid;
      v_city_id := (v_city_map->(v_record->>'city_id'))::uuid;
      INSERT INTO panelists (account_id, panelist_code, name, email, mobile, telegram_id, address_line1, address_line2, 
                             postal_code, address_city, address_country, node_id, city_id, status)
      VALUES (v_account_id, v_record->>'panelist_code', v_record->>'name', v_record->>'email', v_record->>'mobile',
              v_record->>'telegram_id', v_record->>'address_line1', v_record->>'address_line2',
              v_record->>'postal_code', v_record->>'address_city', v_record->>'address_country',
              v_node_id, v_city_id, COALESCE(v_record->>'status', 'active'));
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('panelists', v_count);
  END IF;
  
  -- 3.9 DELIVERY_STANDARDS
  SELECT data INTO v_seed_data FROM demo2_seed_data WHERE table_name = 'delivery_standards';
  IF v_seed_data IS NOT NULL THEN
    v_count := 0;
    FOR v_record IN SELECT * FROM jsonb_array_elements(v_seed_data) LOOP
      v_origin_city_id := (v_city_map->(v_record->>'origin_city_id'))::uuid;
      v_dest_city_id := (v_city_map->(v_record->>'destination_city_id'))::uuid;
      INSERT INTO delivery_standards (account_id, origin_city_id, destination_city_id, standard_time, success_percentage)
      VALUES (v_account_id, v_origin_city_id, v_dest_city_id, 
              (v_record->>'standard_time')::integer, (v_record->>'success_percentage')::numeric);
      v_count := v_count + 1;
    END LOOP;
    v_inserted_counts := v_inserted_counts || jsonb_build_object('delivery_standards', v_count);
  END IF;
  
  RETURN jsonb_build_object(
    'success', true,
    'account_id', v_account_id,
    'account_name', v_account_name,
    'message', format('Successfully reset and seeded DEMO2'),
    'deleted_records', v_deleted_counts,
    'inserted_records', v_inserted_counts
  );
  
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'message', format('Error resetting and seeding DEMO2: %s', SQLERRM));
END;
$$;

COMMENT ON FUNCTION admin_reset_and_seed_demo2() IS 
  'Extended Demo Reset: deletes operational + configuration data and reloads seed data for DEMO2';

COMMIT;
