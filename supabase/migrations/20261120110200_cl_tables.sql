-- Carrier Link fase 0, tarea 3: tablas cl_* (plan, captura y muestra), FK api_keys.feed_id, api_key_issue
-- validado y reset de cuentas que tambien borra los datos de Carrier Link.
-- Spec: docs/superpowers/specs/2026-11-19-carrier-link-design.md 3.3. Forward-only.

-- ---------------------------------------------------------------- tablas
CREATE TABLE public.cl_feeds (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id       uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  carrier_id       uuid NOT NULL REFERENCES public.carriers(id),
  name             text NOT NULL,
  extraction_model text,
  config           jsonb NOT NULL DEFAULT '{}',
  secret_ref       text,
  status           text NOT NULL DEFAULT 'testing' CHECK (status IN ('testing','active','paused')),
  last_batch_at    timestamptz,
  last_error       text,
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.cl_field_mappings (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id     uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  carrier_id     uuid NOT NULL REFERENCES public.carriers(id),
  standard_field text NOT NULL CHECK (standard_field IN ('item_id','product','scan_at','place_ref','mode_ref')),
  carrier_field  text NOT NULL,
  format         text,
  timezone       text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (account_id, carrier_id, standard_field)
);

CREATE TABLE public.cl_value_mappings (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id    uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  carrier_id    uuid NOT NULL REFERENCES public.carriers(id),
  kind          text NOT NULL CHECK (kind = 'product'),
  carrier_value text NOT NULL,
  onems_value   text NOT NULL,  -- products.code
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (account_id, carrier_id, kind, carrier_value)
);

CREATE TABLE public.cl_extra_fields (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id    uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  carrier_id    uuid NOT NULL REFERENCES public.carriers(id),
  carrier_field text NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (account_id, carrier_id, carrier_field)
);

CREATE TABLE public.cl_plans (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id          uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  plan_name           text NOT NULL,
  carrier_id          uuid NOT NULL REFERENCES public.carriers(id),
  product_id          uuid NOT NULL REFERENCES public.products(id),
  total_samples       integer NOT NULL CHECK (total_samples >= 0),
  start_date          date NOT NULL,
  end_date            date NOT NULL,
  status              text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','active','closed')),
  close_lag_days      integer NOT NULL DEFAULT 7,
  oversampling_factor numeric NOT NULL DEFAULT 5,
  feed_id             uuid REFERENCES public.cl_feeds(id),
  feed_diagnosis      boolean NOT NULL DEFAULT false,
  created_by          uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.cl_plan_quotas (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id          uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  plan_id             uuid NOT NULL REFERENCES public.cl_plans(id) ON DELETE CASCADE,
  origin_city_id      uuid NOT NULL REFERENCES public.cities(id),
  destination_city_id uuid NOT NULL REFERENCES public.cities(id),
  iso_year            integer NOT NULL,
  iso_week            integer NOT NULL,
  period_start        date NOT NULL,
  period_end          date NOT NULL,
  samples_planned     integer NOT NULL DEFAULT 0,
  samples_carried_in  integer NOT NULL DEFAULT 0,
  samples_obtained    integer NOT NULL DEFAULT 0,
  demands_count       integer NOT NULL DEFAULT 0,
  status              text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','open','fulfilled','carried','unfilled')),
  created_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (plan_id, origin_city_id, destination_city_id, iso_year, iso_week)
);

CREATE TABLE public.cl_demands (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id   uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  plan_id      uuid NOT NULL REFERENCES public.cl_plans(id),
  feed_id      uuid NOT NULL REFERENCES public.cl_feeds(id),
  status       text NOT NULL DEFAULT 'open' CHECK (status IN ('open','fulfilled','partial','failed')),
  random_seed  text NOT NULL,
  payload      jsonb NOT NULL,
  requested_at timestamptz NOT NULL DEFAULT now(),
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.cl_batches (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id         uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  demand_id          uuid NOT NULL REFERENCES public.cl_demands(id),
  connector_batch_id text NOT NULL,
  status             text NOT NULL DEFAULT 'received' CHECK (status IN ('received','validated','sampled','rejected','undone')),
  summary            jsonb,
  raw_payload        jsonb,
  received_at        timestamptz NOT NULL DEFAULT now(),
  created_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (demand_id, connector_batch_id)
);

CREATE TABLE public.cl_batch_scans (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id    uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  batch_id      uuid NOT NULL REFERENCES public.cl_batches(id) ON DELETE CASCADE,
  stratum_id    uuid,  -- cl_plan_quotas.id (sin FK: el lote conserva su traza)
  item_id       text,
  product_id    uuid,
  scan_at       timestamptz,
  place_ref     text,
  mode_ref      text,
  reader_id     uuid,
  status        text NOT NULL CHECK (status IN ('valid','rejected')),
  reject_reason text,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX cl_batch_scans_batch_stratum_item_idx ON public.cl_batch_scans (batch_id, stratum_id, item_id);

CREATE TABLE public.cl_sampling_runs (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id         uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  demand_id          uuid NOT NULL REFERENCES public.cl_demands(id),
  batch_id           uuid NOT NULL REFERENCES public.cl_batches(id),
  stratum_id         uuid NOT NULL,
  population_size    integer,
  candidates_valid   integer,
  samples_required   integer,
  samples_selected   integer,
  random_seed        text,
  selected_item_ids  text[],
  executed_at        timestamptz NOT NULL DEFAULT now(),
  created_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (batch_id, stratum_id)
);

CREATE TABLE public.cl_alerts (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  plan_id    uuid REFERENCES public.cl_plans(id),
  batch_id   uuid REFERENCES public.cl_batches(id),
  quota_id   uuid REFERENCES public.cl_plan_quotas(id),
  alert_type text NOT NULL,
  severity   text NOT NULL CHECK (severity IN ('low','medium','high')),
  details    jsonb,
  status     text NOT NULL DEFAULT 'open' CHECK (status IN ('open','acknowledged','dismissed')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.cl_samples (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id          uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  plan_id             uuid REFERENCES public.cl_plans(id),
  quota_id            uuid REFERENCES public.cl_plan_quotas(id),
  batch_id            uuid REFERENCES public.cl_batches(id),
  carrier_id          uuid NOT NULL REFERENCES public.carriers(id),
  product_id          uuid REFERENCES public.products(id),
  item_id             text NOT NULL,
  start_reader_id     uuid REFERENCES public.readers(id),
  start_at            timestamptz,
  end_reader_id       uuid REFERENCES public.readers(id),
  end_at              timestamptz,
  origin_city_id      uuid REFERENCES public.cities(id),
  destination_city_id uuid REFERENCES public.cities(id),
  possible_misrouting boolean NOT NULL DEFAULT false,
  extra               jsonb NOT NULL DEFAULT '{}',
  status              text NOT NULL DEFAULT 'active' CHECK (status IN ('active','voided')),
  created_at          timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX cl_samples_active_item_uidx ON public.cl_samples (account_id, carrier_id, item_id) WHERE status = 'active';

CREATE TABLE public.cl_sample_scans (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  sample_id  uuid NOT NULL REFERENCES public.cl_samples(id) ON DELETE CASCADE,
  reader_id  uuid REFERENCES public.readers(id),
  scan_at    timestamptz,
  role       text NOT NULL CHECK (role IN ('start','end','intermediate')),
  place_ref  text,
  mode_ref   text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.one_db
  ADD CONSTRAINT one_db_cl_sample_id_fkey FOREIGN KEY (cl_sample_id) REFERENCES public.cl_samples(id) ON DELETE CASCADE;

-- Indices por clave foranea y cuenta.
CREATE INDEX cl_feeds_account_idx          ON public.cl_feeds (account_id);
CREATE INDEX cl_plans_account_idx          ON public.cl_plans (account_id);
CREATE INDEX cl_plan_quotas_plan_idx       ON public.cl_plan_quotas (plan_id);
CREATE INDEX cl_demands_plan_idx           ON public.cl_demands (plan_id);
CREATE INDEX cl_demands_feed_idx           ON public.cl_demands (feed_id);
CREATE INDEX cl_batches_demand_idx         ON public.cl_batches (demand_id);
CREATE INDEX cl_samples_plan_idx           ON public.cl_samples (plan_id);
CREATE INDEX cl_samples_batch_idx          ON public.cl_samples (batch_id);
CREATE INDEX cl_sample_scans_sample_idx    ON public.cl_sample_scans (sample_id);
CREATE INDEX cl_alerts_plan_idx            ON public.cl_alerts (plan_id);

-- ---------------------------------------------------------------- privilegios y RLS
-- SELECT: superadmin o (cuenta activa y View/Edit en la opcion); escritura: Edit. Sin privilegios para anon.
-- has_any_access(..., 'view') ya acepta tambien Edit.
DO $$
DECLARE r record; v_sel text; v_edit text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('cl_feeds',          'cl_connectors'),
    ('cl_field_mappings', 'cl_connectors'),
    ('cl_value_mappings', 'cl_connectors'),
    ('cl_extra_fields',   'cl_connectors'),
    ('cl_plans',          'cl_plans'),
    ('cl_plan_quotas',    'cl_plans'),
    ('cl_demands',        'cl_monitor'),
    ('cl_batches',        'cl_monitor'),
    ('cl_batch_scans',    'cl_monitor'),
    ('cl_sampling_runs',  'cl_monitor'),
    ('cl_alerts',         'cl_monitor'),
    ('cl_samples',        'cl_samples'),
    ('cl_sample_scans',   'cl_samples')
  ) t(tbl, opt) LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', r.tbl);
    EXECUTE format('REVOKE ALL ON public.%I FROM PUBLIC, anon', r.tbl);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO authenticated', r.tbl);
    EXECUTE format('GRANT ALL ON public.%I TO service_role', r.tbl);
    v_sel  := format('(SELECT public.is_superadmin()) OR (account_id = (SELECT public.current_user_account_id()) '
                     'AND (SELECT public.has_any_access(public.current_user_account_id(), ''view'', %L)))', r.opt);
    v_edit := format('(SELECT public.is_superadmin()) OR (account_id = (SELECT public.current_user_account_id()) '
                     'AND (SELECT public.has_any_access(public.current_user_account_id(), ''edit'', %L)))', r.opt);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (%s)', r.tbl || '_select_access', r.tbl, v_sel);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR INSERT TO authenticated WITH CHECK (%s)', r.tbl || '_insert_edit', r.tbl, v_edit);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR UPDATE TO authenticated USING (%s) WITH CHECK (%s)', r.tbl || '_update_edit', r.tbl, v_edit, v_edit);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR DELETE TO authenticated USING (%s)', r.tbl || '_delete_edit', r.tbl, v_edit);
  END LOOP;
END $$;

-- ---------------------------------------------------------------- api_keys <-> cl_feeds
ALTER TABLE public.api_keys
  ADD CONSTRAINT api_keys_feed_id_fkey FOREIGN KEY (feed_id) REFERENCES public.cl_feeds(id) ON DELETE CASCADE;
ALTER TABLE public.api_keys
  ADD CONSTRAINT api_keys_scope_feed_check CHECK ((scope = 'carrier_feed') = (feed_id IS NOT NULL));

CREATE OR REPLACE FUNCTION public.api_key_issue(
  p_account_id uuid,
  p_name text,
  p_scope text DEFAULT 'onedb_read',
  p_feed_id uuid DEFAULT NULL,
  p_expires_at timestamptz DEFAULT NULL)
 RETURNS TABLE (id uuid, api_key text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_key text;
  v_id  uuid;
BEGIN
  IF NOT (public.is_superadmin() OR public.is_upu_account_manager(p_account_id)) THEN
    RAISE EXCEPTION 'No autorizado para gestionar claves de API en esta cuenta' USING ERRCODE = '42501';
  END IF;
  IF p_name IS NULL OR btrim(p_name) = '' OR length(btrim(p_name)) > 80 THEN
    RAISE EXCEPTION 'El nombre de la clave es obligatorio (máx. 80 caracteres)' USING ERRCODE = '22023';
  END IF;
  IF p_expires_at IS NOT NULL AND p_expires_at <= now() THEN
    RAISE EXCEPTION 'La fecha de caducidad debe ser futura' USING ERRCODE = '22023';
  END IF;
  IF p_scope IS NULL OR p_scope NOT IN ('onedb_read', 'carrier_feed') THEN
    RAISE EXCEPTION 'Ámbito de clave no válido: %', p_scope USING ERRCODE = '22023';
  END IF;
  IF p_scope = 'carrier_feed' THEN
    IF p_feed_id IS NULL OR NOT EXISTS (
         SELECT 1 FROM public.cl_feeds f WHERE f.id = p_feed_id AND f.account_id = p_account_id) THEN
      RAISE EXCEPTION 'Una clave carrier_feed requiere un conector de esta cuenta' USING ERRCODE = '22023';
    END IF;
  ELSIF p_feed_id IS NOT NULL THEN
    RAISE EXCEPTION 'Una clave onedb_read no admite conector' USING ERRCODE = '22023';
  END IF;

  v_key := 'onems_' || encode(gen_random_bytes(24), 'hex');
  INSERT INTO public.api_keys (account_id, key_hash, key_prefix, name, scope, feed_id, expires_at, created_by)
  VALUES (p_account_id, encode(digest(v_key, 'sha256'), 'hex'), left(v_key, 12), btrim(p_name), p_scope,
          p_feed_id, p_expires_at, auth.uid())
  RETURNING public.api_keys.id INTO v_id;

  RETURN QUERY SELECT v_id, v_key;
END $$;
REVOKE ALL ON FUNCTION public.api_key_issue(uuid, text, text, uuid, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.api_key_issue(uuid, text, text, uuid, timestamptz) TO authenticated;

-- ---------------------------------------------------------------- reset de cuentas (cuerpo literal + borrado de cl_*)
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

  -- Borrar SOLO datos operacionales (NO configuración)
  
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

  -- Carrier Link: tablas cl_* de la cuenta (hijos antes que padres) y puntos de lectura de transportista.
  DELETE FROM cl_alerts WHERE account_id = v_account_id;
  DELETE FROM cl_sampling_runs WHERE account_id = v_account_id;
  DELETE FROM cl_sample_scans WHERE account_id = v_account_id;
  DELETE FROM cl_samples WHERE account_id = v_account_id;
  DELETE FROM cl_batch_scans WHERE account_id = v_account_id;
  DELETE FROM cl_batches WHERE account_id = v_account_id;
  DELETE FROM cl_demands WHERE account_id = v_account_id;
  DELETE FROM cl_plan_quotas WHERE account_id = v_account_id;
  DELETE FROM cl_plans WHERE account_id = v_account_id;
  DELETE FROM cl_value_mappings WHERE account_id = v_account_id;
  DELETE FROM cl_field_mappings WHERE account_id = v_account_id;
  DELETE FROM cl_extra_fields WHERE account_id = v_account_id;
  DELETE FROM cl_feeds WHERE account_id = v_account_id;
  DELETE FROM readers WHERE account_id = v_account_id AND capture_source = 'carrier_scan';

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

CREATE OR REPLACE FUNCTION public.admin_reset_and_seed_demo2()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
  
  -- STEP 2: Delete configuration data (IN CORRECT ORDER TO RESPECT FK CONSTRAINTS)
  RAISE NOTICE 'Step 2/3: Deleting configuration data...';
  
  -- 2.1 Delete delivery_standards (has FK to cities, carriers, products)
  DELETE FROM delivery_standards WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('delivery_standards', v_count);
  
  -- 2.2 Delete product_materials (has FK to products, material_catalog)
  DELETE FROM product_materials WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('product_materials', v_count);
  
  -- 2.3 Delete panelists (has FK to nodes, cities)
  DELETE FROM panelists WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('panelists', v_count);
  
  -- 2.3.1 Delete ONE DB data (shipment records)
  DELETE FROM one_db WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('one_db', v_count);

  -- Carrier Link: tablas cl_* de la cuenta (hijos antes que padres) y puntos de lectura de transportista.
  DELETE FROM cl_alerts WHERE account_id = v_account_id;
  DELETE FROM cl_sampling_runs WHERE account_id = v_account_id;
  DELETE FROM cl_sample_scans WHERE account_id = v_account_id;
  DELETE FROM cl_samples WHERE account_id = v_account_id;
  DELETE FROM cl_batch_scans WHERE account_id = v_account_id;
  DELETE FROM cl_batches WHERE account_id = v_account_id;
  DELETE FROM cl_demands WHERE account_id = v_account_id;
  DELETE FROM cl_plan_quotas WHERE account_id = v_account_id;
  DELETE FROM cl_plans WHERE account_id = v_account_id;
  DELETE FROM cl_value_mappings WHERE account_id = v_account_id;
  DELETE FROM cl_field_mappings WHERE account_id = v_account_id;
  DELETE FROM cl_extra_fields WHERE account_id = v_account_id;
  DELETE FROM cl_feeds WHERE account_id = v_account_id;
  DELETE FROM readers WHERE account_id = v_account_id AND capture_source = 'carrier_scan';
  
  -- 2.4 Delete allocation_plan_details (has FK to nodes via plan_id) - CRITICAL FIX
  DELETE FROM allocation_plan_details 
  WHERE plan_id IN (
    SELECT id FROM allocation_plans WHERE account_id = v_account_id
  );
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('allocation_plan_details', v_count);
  
  -- 2.5 Delete generated_allocation_plan_details (has FK to nodes via plan_id) - CRITICAL FIX
  DELETE FROM generated_allocation_plan_details 
  WHERE plan_id IN (
    SELECT id FROM generated_allocation_plans WHERE account_id = v_account_id
  );
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('generated_allocation_plan_details', v_count);
  
  -- 2.6 Now safe to delete nodes
  DELETE FROM nodes WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('nodes', v_count);
  
  -- 2.7 Delete cities (has FK to regions)
  DELETE FROM cities WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('cities', v_count);
  
  -- 2.8 Delete regions
  DELETE FROM regions WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('regions', v_count);
  
  -- 2.9 Delete products (has FK to carriers)
  DELETE FROM products WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('products', v_count);
  
  -- 2.10 Delete carriers
  DELETE FROM carriers WHERE account_id = v_account_id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  v_deleted_counts := v_deleted_counts || jsonb_build_object('carriers', v_count);
  
  -- 2.11 Delete material_catalog
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
      v_region_id := (v_region_map->>(v_record->>'region_id'))::uuid;
      INSERT INTO cities (account_id, region_id, code, name, latitude, longitude, classification, city_type, region_name, population, status)
      VALUES (v_account_id, v_region_id, v_record->>'code', v_record->>'name', 
              (v_record->>'latitude')::numeric, (v_record->>'longitude')::numeric,
              v_record->>'classification', v_record->>'city_type', v_record->>'region_name',
              ROUND((v_record->>'population')::numeric)::integer, COALESCE(v_record->>'status', 'active'))
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
      v_city_id := (v_city_map->>(v_record->>'city_id'))::uuid;
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
      v_carrier_id := (v_carrier_map->>(v_record->>'carrier_id'))::uuid;
      INSERT INTO products (account_id, carrier_id, code, description, standard_delivery_hours, time_unit, status)
      VALUES (v_account_id, v_carrier_id, v_record->>'code', v_record->>'description',
              ROUND((v_record->>'standard_delivery_hours')::numeric)::integer, COALESCE(v_record->>'time_unit', 'hours'),
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
      v_product_id := (v_product_map->>(v_record->>'product_id'))::uuid;
      v_material_id := (v_material_map->>(v_record->>'material_id'))::uuid;
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
      v_node_id := (v_node_map->>(v_record->>'node_id'))::uuid;
      v_city_id := (v_city_map->>(v_record->>'city_id'))::uuid;
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
      v_carrier_id := (v_carrier_map->>(v_record->>'carrier_id'))::uuid;
      v_product_id := (v_product_map->>(v_record->>'product_id'))::uuid;
      v_origin_city_id := (v_city_map->>(v_record->>'origin_city_id'))::uuid;
      v_dest_city_id := (v_city_map->>(v_record->>'destination_city_id'))::uuid;
      INSERT INTO delivery_standards (account_id, carrier_id, product_id, origin_city_id, destination_city_id, 
                                      standard_time, success_percentage, time_unit, warning_threshold, 
                                      critical_threshold, threshold_type)
      VALUES (v_account_id, v_carrier_id, v_product_id, v_origin_city_id, v_dest_city_id, 
              (v_record->>'standard_time')::numeric, (v_record->>'success_percentage')::numeric,
              COALESCE(v_record->>'time_unit', 'hours'),
              COALESCE((v_record->>'warning_threshold')::numeric, 5.0),
              COALESCE((v_record->>'critical_threshold')::numeric, 10.0),
              COALESCE(v_record->>'threshold_type', 'relative'));
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

  -- Carrier Link: tablas cl_* de la cuenta (hijos antes que padres) y puntos de lectura de transportista.
  DELETE FROM cl_alerts WHERE account_id = v_account_id;
  DELETE FROM cl_sampling_runs WHERE account_id = v_account_id;
  DELETE FROM cl_sample_scans WHERE account_id = v_account_id;
  DELETE FROM cl_samples WHERE account_id = v_account_id;
  DELETE FROM cl_batch_scans WHERE account_id = v_account_id;
  DELETE FROM cl_batches WHERE account_id = v_account_id;
  DELETE FROM cl_demands WHERE account_id = v_account_id;
  DELETE FROM cl_plan_quotas WHERE account_id = v_account_id;
  DELETE FROM cl_plans WHERE account_id = v_account_id;
  DELETE FROM cl_value_mappings WHERE account_id = v_account_id;
  DELETE FROM cl_field_mappings WHERE account_id = v_account_id;
  DELETE FROM cl_extra_fields WHERE account_id = v_account_id;
  DELETE FROM cl_feeds WHERE account_id = v_account_id;
  DELETE FROM readers WHERE account_id = v_account_id AND capture_source = 'carrier_scan';

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
  -- PASO 2: Borrar datos de configuración
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
