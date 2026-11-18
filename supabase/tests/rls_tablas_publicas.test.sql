-- RLS en tablas que estaban abiertas y sin EXECUTE anónimo en funciones (20261118220000_rls_tablas_y_funciones_publicas.sql).
--   anon: sin acceso a las 14 tablas ni EXECUTE en las funciones de la lista.
--   usuario de A1: ve y escribe solo A1.
--   superadmin: ve todas las cuentas y puede borrar filas de otra cuenta (reseteo DEMO2), gestionar api_keys.
--   service_role: lo ve todo y conserva EXECUTE.
-- Se ejecuta como postgres y cambia de rol (SET ROLE) para que RLS actúe de verdad. Todo en una transacción.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT FALSE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid text, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  PERFORM set_config('request.jwt.claim.role', coalesce(p_role, ''), true);
END $$;

BEGIN;
\ir fixtures/incident_city.sql
-- En Supabase anon/authenticated tienen USAGE en public; el shim local no lo da.
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

INSERT INTO auth.users (id, email) VALUES ('97000000-0000-0000-0000-000000000097','super@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('97000000-0000-0000-0000-000000000097','super@t.l','Super','superadmin',NULL);

INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001');
INSERT INTO public.readers (id, account_id, postal_center_id, reader_id, name, type) VALUES
  ('f1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','LPI1','R1','Mixed');

-- Una fila por cuenta (A1 y A2) en processed_events, journey_segments y api_keys.
INSERT INTO public.processed_events (account_id, tag_id, reader_id, postal_center_id, event_type, timestamp, analysis_datetime,
  postal_center_code_snapshot, postal_center_name_snapshot, reader_id_snapshot, reader_type_snapshot)
SELECT a, '0000000' || n, 'f1000000-0000-0000-0000-000000000001', 'd1000000-0000-0000-0000-000000000001', 'entry',
       '2027-03-01 08:00+00', '2027-03-01 08:00+00', 'PC1', 'Center 1', 'LPI1', 'Mixed'
FROM (VALUES ('a0000000-0000-0000-0000-000000000001'::uuid, 1), ('a0000000-0000-0000-0000-000000000002'::uuid, 2)) v(a, n);

INSERT INTO public.journey_segments (account_id, tag_id, segment_type, postal_center_id, entry_timestamp, exit_timestamp,
  entry_analysis_datetime, exit_analysis_datetime, actual_time_minutes, adjusted_time_minutes)
SELECT a, '0000000' || n, 'operational', 'd1000000-0000-0000-0000-000000000001',
       '2027-03-01 08:00+00', '2027-03-01 10:00+00', '2027-03-01 08:00+00', '2027-03-01 10:00+00', 120, 120
FROM (VALUES ('a0000000-0000-0000-0000-000000000001'::uuid, 1), ('a0000000-0000-0000-0000-000000000002'::uuid, 2)) v(a, n);

INSERT INTO public.api_keys (account_id, api_key, is_active) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'onedb_live_test_a1', true),
  ('a0000000-0000-0000-0000-000000000002', 'onedb_live_test_a2', true);

-- ---------------------------------------------------------------- estado de catálogo
DO $$
DECLARE n int; t text;
  tabs text[] := ARRAY['api_keys','api_usage_log','demo2_seed_data','journey_segments','journeys','n8n_upu_agent',
    'n8n_upu_incident','n8n_upu_timeoff','panelist_context','postal_center_carriers','processed_events',
    'purchase_order_items','purchase_orders','rfid_events_raw'];
  backend text[] := ARRAY['demo2_seed_data','n8n_upu_agent','n8n_upu_incident','n8n_upu_timeoff','panelist_context',
    'postal_center_carriers'];
BEGIN
  SELECT count(*) INTO n FROM pg_class
   WHERE relnamespace = 'public'::regnamespace AND relname = ANY (tabs) AND relrowsecurity;
  PERFORM pg_temp.fail_if(n <> 14, 'tablas con RLS: ' || n);
  FOREACH t IN ARRAY tabs LOOP
    PERFORM pg_temp.fail_if(has_table_privilege('anon', 'public.' || t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),
      'anon conserva privilegios en ' || t);
    PERFORM pg_temp.fail_if(NOT has_table_privilege('service_role', 'public.' || t, 'SELECT,INSERT,UPDATE,DELETE'),
      'service_role sin privilegios en ' || t);
  END LOOP;
  FOREACH t IN ARRAY backend LOOP
    PERFORM pg_temp.fail_if(has_table_privilege('authenticated', 'public.' || t, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE'),
      'authenticated conserva privilegios en tabla de backend ' || t);
  END LOOP;
  PERFORM pg_temp.fail_if(has_table_privilege('anon', 'public.v_segment_details', 'SELECT'), 'anon lee v_segment_details');

  -- Funciones: ninguna sobrecarga ejecutable por anon; service_role sí; authenticated sí salvo las 5 de
  -- mantenimiento entre cuentas y reconstruct_journeys / reprocess_transfer_errors (la web usa sus envoltorios
  -- *_for_account), que desde 20261119100200 (fase 3) solo ejecuta service_role.
  SELECT count(*) INTO n FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND p.proname = ANY (ARRAY['balance_node_load_matrix','cleanup_processed_rfid_events','generate_delivery_standards',
       'process_all_accounts_pipeline','process_rfid_pipeline','recalculate_on_time_delivery_on_sla_change',
       'reconstruct_journeys','reprocess_transfer_errors','resolve_provider_reads','rpc_get_node_load_by_period',
       'set_account_id','transfer_to_one_db','consolidate_rfid_events'])
     AND (has_function_privilege('anon', p.oid, 'EXECUTE')
          OR NOT has_function_privilege('service_role', p.oid, 'EXECUTE')
          OR has_function_privilege('authenticated', p.oid, 'EXECUTE')
             <> NOT (p.proname = ANY (ARRAY['balance_node_load_matrix','cleanup_processed_rfid_events',
                       'process_all_accounts_pipeline','process_rfid_pipeline','resolve_provider_reads',
                       'reconstruct_journeys','reprocess_transfer_errors'])));
  PERFORM pg_temp.fail_if(n <> 0, 'funciones con EXECUTE mal: ' || n);
  SELECT count(DISTINCT proname) INTO n FROM pg_proc
   WHERE pronamespace = 'public'::regnamespace
     AND proname = ANY (ARRAY['balance_node_load_matrix','cleanup_processed_rfid_events','generate_delivery_standards',
       'process_all_accounts_pipeline','process_rfid_pipeline','recalculate_on_time_delivery_on_sla_change',
       'reconstruct_journeys','reprocess_transfer_errors','resolve_provider_reads','rpc_get_node_load_by_period',
       'set_account_id','transfer_to_one_db','consolidate_rfid_events']);
  PERFORM pg_temp.fail_if(n <> 13, 'funciones encontradas: ' || n);
END $$;

-- ---------------------------------------------------------------- anon
SET ROLE anon;
SELECT pg_temp.as_user(NULL, 'anon');
DO $$
DECLARE t text; ok boolean;
BEGIN
  FOREACH t IN ARRAY ARRAY['api_keys','processed_events','journey_segments','panelist_context','rfid_events_raw'] LOOP
    ok := false;
    BEGIN EXECUTE format('SELECT count(*) FROM public.%I', t);
    EXCEPTION WHEN insufficient_privilege THEN ok := true; END;
    PERFORM pg_temp.fail_if(NOT ok, 'anon puede leer ' || t);
  END LOOP;
  ok := false;
  BEGIN INSERT INTO public.api_keys (account_id, api_key) VALUES ('a0000000-0000-0000-0000-000000000001', 'evil');
  EXCEPTION WHEN insufficient_privilege THEN ok := true; END;
  PERFORM pg_temp.fail_if(NOT ok, 'anon inserta api_keys');
  ok := false;
  BEGIN DELETE FROM public.processed_events;
  EXCEPTION WHEN insufficient_privilege THEN ok := true; END;
  PERFORM pg_temp.fail_if(NOT ok, 'anon borra processed_events');
  ok := false;
  BEGIN PERFORM public.cleanup_processed_rfid_events(NULL, 0);
  EXCEPTION WHEN insufficient_privilege THEN ok := true; END;
  PERFORM pg_temp.fail_if(NOT ok, 'anon ejecuta cleanup_processed_rfid_events');
END $$;
RESET ROLE;

-- ---------------------------------------------------------------- usuario de A1
SET ROLE authenticated;
SELECT pg_temp.as_user('99000000-0000-0000-0000-000000000099', 'authenticated');
DO $$
DECLARE n int; ok boolean;
  A1 constant uuid := 'a0000000-0000-0000-0000-000000000001';
  A2 constant uuid := 'a0000000-0000-0000-0000-000000000002';
BEGIN
  SELECT count(*) INTO n FROM public.processed_events;
  PERFORM pg_temp.fail_if(n <> 1, 'A1 processed_events visibles: ' || n);
  SELECT count(*) INTO n FROM public.processed_events WHERE account_id = A2;
  PERFORM pg_temp.fail_if(n <> 0, 'A1 ve processed_events de A2');
  SELECT count(*) INTO n FROM public.journey_segments;
  PERFORM pg_temp.fail_if(n <> 1, 'A1 journey_segments visibles: ' || n);
  SELECT count(*) INTO n FROM public.api_keys;
  PERFORM pg_temp.fail_if(n <> 1, 'A1 api_keys visibles: ' || n);

  -- Escribe en su cuenta: sí. En otra: no.
  UPDATE public.journey_segments SET adjusted_time_minutes = 100 WHERE account_id = A1;
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM pg_temp.fail_if(n <> 1, 'A1 no actualiza su tramo');
  DELETE FROM public.journey_segments WHERE account_id = A2;
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM pg_temp.fail_if(n <> 0, 'A1 borra tramo de A2');
  ok := false;
  BEGIN INSERT INTO public.api_keys (account_id, api_key) VALUES (A2, 'evil_a2');
  EXCEPTION WHEN insufficient_privilege THEN ok := true; END;
  PERFORM pg_temp.fail_if(NOT ok, 'A1 crea api_key en A2');
  INSERT INTO public.api_keys (account_id, api_key) VALUES (A1, 'onedb_live_test_a1_bis');

  -- Tabla de backend: sin acceso.
  ok := false;
  BEGIN PERFORM count(*) FROM public.panelist_context;
  EXCEPTION WHEN insufficient_privilege THEN ok := true; END;
  PERFORM pg_temp.fail_if(NOT ok, 'authenticated lee panelist_context');
END $$;
RESET ROLE;

-- ---------------------------------------------------------------- superadmin (sin cuenta propia)
SET ROLE authenticated;
SELECT pg_temp.as_user('97000000-0000-0000-0000-000000000097', 'authenticated');
DO $$
DECLARE n int;
  A2 constant uuid := 'a0000000-0000-0000-0000-000000000002';
BEGIN
  SELECT count(*) INTO n FROM public.processed_events;
  PERFORM pg_temp.fail_if(n <> 2, 'super processed_events: ' || n);
  SELECT count(*) INTO n FROM public.journey_segments;
  PERFORM pg_temp.fail_if(n <> 2, 'super journey_segments: ' || n);
  SELECT count(*) INTO n FROM public.api_keys WHERE account_id = A2;
  PERFORM pg_temp.fail_if(n <> 1, 'super api_keys de A2: ' || n);
  -- Página OneDB API: genera y desactiva clave de la cuenta elegida.
  INSERT INTO public.api_keys (account_id, api_key, is_active) VALUES (A2, 'onedb_live_test_a2_bis', true);
  UPDATE public.api_keys SET is_active = false WHERE api_key = 'onedb_live_test_a2';
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM pg_temp.fail_if(n <> 1, 'super no desactiva clave de A2');
  -- Reseteo DEMO2 (useAccountManagement.ts): borra tramos y eventos de otra cuenta.
  DELETE FROM public.journey_segments WHERE account_id = A2;
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM pg_temp.fail_if(n <> 1, 'super no borra journey_segments de A2: ' || n);
  DELETE FROM public.processed_events WHERE account_id = A2;
  GET DIAGNOSTICS n = ROW_COUNT;
  PERFORM pg_temp.fail_if(n <> 1, 'super no borra processed_events de A2: ' || n);
END $$;
RESET ROLE;

-- ---------------------------------------------------------------- service_role
SET ROLE service_role;
SELECT pg_temp.as_user(NULL, 'service_role');
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.processed_events;
  PERFORM pg_temp.fail_if(n <> 1, 'service_role processed_events: ' || n);
  SELECT count(*) INTO n FROM public.api_keys;
  PERFORM pg_temp.fail_if(n <> 4, 'service_role api_keys: ' || n);
  SELECT count(*) INTO n FROM public.panelist_context;
  PERFORM count(*) FROM public.cleanup_processed_rfid_events(NULL, 100000);
END $$;
RESET ROLE;

ROLLBACK;
\echo 'PASS rls_tablas_publicas'
