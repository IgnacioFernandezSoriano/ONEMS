-- Carrier Link fase 2, tarea 1: ensayo de lote desde la web (cl_dry_run_batch).
-- Envuelve cl_ingest_batch(..., true) para authenticated: feed de su cuenta + Edit en cl_connectors (o superadmin).
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid text, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  PERFORM set_config('request.jwt.claim.role', coalesce(p_role, ''), true);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.raises(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE || ':' || SQLERRM; END $$;

CREATE OR REPLACE FUNCTION pg_temp.rd(p_trk text, p_ts text, p_office text, p_evt text) RETURNS jsonb
LANGUAGE sql AS $$
  SELECT jsonb_build_object('trk', p_trk, 'svc', 'EXP', 'ts', p_ts, 'office', p_office, 'evt', p_evt)
$$;

CREATE OR REPLACE FUNCTION pg_temp.payload() RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('demand_id', current_setting('t.demand'), 'batch_id', 'B-UI',
           'strata', jsonb_build_array(jsonb_build_object(
              'stratum_id', '91000000-0000-0000-0000-0000000000b1', 'population_size', 48,
              'selection_method', 'uniform_random_within_stratum',
              'rows', jsonb_build_array(
                pg_temp.rd('A1', '20/10/2026 09:14', 'NBO', 'ADM'),
                pg_temp.rd('A1', '21/10/2026 10:00', 'MBA', 'DLV'),
                pg_temp.rd('A2', '21/10/2026 08:00', 'NBO', 'ADM'),
                pg_temp.rd('A3', '21/10/2026 08:00', 'XYZ', 'ADM')))))
$$;

BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

UPDATE public.accounts SET timezone = 'Africa/Nairobi' WHERE id = 'a0000000-0000-0000-0000-000000000001';
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001'),
  ('d2000000-0000-0000-0000-0000000000c2','a0000000-0000-0000-0000-000000000001','PC2','Center 2','City2','c2000000-0000-0000-0000-000000000002');
INSERT INTO public.readers (id, account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role) VALUES
  ('ad000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','NBO ADM','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','NBO','ADM','origin'),
  ('ad000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-0000000000c2','MBA any','Exit','carrier_scan','ca000000-0000-0000-0000-000000000001','MBA',NULL,'destination');
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status) VALUES
  ('f0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed A1','active');
INSERT INTO public.cl_field_mappings (account_id, carrier_id, standard_field, carrier_field, format, timezone) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','item_id','trk',NULL,NULL),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','product','svc',NULL,NULL),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','scan_at','ts','DD/MM/YYYY HH24:MI','Africa/Nairobi'),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','place_ref','office',NULL,NULL),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','mode_ref','evt',NULL,NULL);
INSERT INTO public.cl_value_mappings (account_id, carrier_id, kind, carrier_value, onems_value) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','product','EXP','PR');
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','P1','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',2,'2026-10-19','2026-10-25','active','f0000000-0000-0000-0000-0000000000a1');
INSERT INTO public.cl_plan_quotas (id, account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned) VALUES
  ('91000000-0000-0000-0000-0000000000b1','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,43,'2026-10-19','2026-10-25',2);
SELECT set_config('t.demand', public.cl_build_demand('90000000-0000-0000-0000-0000000000a1',
  ARRAY['91000000-0000-0000-0000-0000000000b1']::uuid[])::text, true);

-- Feed de A2 (para el usuario de otra cuenta y el superadmin).
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','CB','Carrier2');
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status) VALUES
  ('f0000000-0000-0000-0000-0000000000b2','a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','Feed A2','active');

-- 93 AM de A1 (Edit en cl_connectors), 94 APM de A1 con cl_connectors solo View, 92 UPU AM de A2, 97 superadmin.
INSERT INTO auth.users (id, email) VALUES
  ('93000000-0000-0000-0000-000000000093','am@t.l'),
  ('94000000-0000-0000-0000-000000000094','apm@t.l'),
  ('92000000-0000-0000-0000-000000000092','upu2@t.l'),
  ('97000000-0000-0000-0000-000000000097','super@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('93000000-0000-0000-0000-000000000093','am@t.l','AM','user','a0000000-0000-0000-0000-000000000001'),
  ('94000000-0000-0000-0000-000000000094','apm@t.l','APM','user','a0000000-0000-0000-0000-000000000001'),
  ('92000000-0000-0000-0000-000000000092','upu2@t.l','UPU2','user','a0000000-0000-0000-0000-000000000002'),
  ('97000000-0000-0000-0000-000000000097','super@t.l','Super','superadmin',NULL);
INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000093','account_manager'),
  ('a0000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000094','allocation_plan_manager'),
  ('a0000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000092','upu_account_manager');
INSERT INTO public.account_access (account_id, role, option, level) VALUES
  ('a0000000-0000-0000-0000-000000000001','allocation_plan_manager','cl_connectors','view')
ON CONFLICT (account_id, role, option) DO UPDATE SET level = EXCLUDED.level;

-- Referencia: el ensayo directo (como postgres).
SELECT set_config('t.expected', public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.payload(), true)::text, true);
SELECT set_config('t.n_batches', (SELECT count(*) FROM public.cl_batches)::text, true);
SELECT set_config('t.n_scans', (SELECT count(*) FROM public.cl_batch_scans)::text, true);
SELECT set_config('t.n_alerts', (SELECT count(*) FROM public.cl_alerts)::text, true);

-- 1. Permisos de la función.
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT prosecdef FROM pg_proc WHERE oid = 'public.cl_dry_run_batch(uuid,jsonb)'::regprocedure), 'SECURITY DEFINER');
  PERFORM pg_temp.ok((SELECT proconfig @> ARRAY['search_path=public, extensions'] FROM pg_proc WHERE oid = 'public.cl_dry_run_batch(uuid,jsonb)'::regprocedure), 'search_path fijado');
  PERFORM pg_temp.ok(NOT has_function_privilege('anon', 'public.cl_dry_run_batch(uuid,jsonb)', 'EXECUTE'), 'anon sin EXECUTE');
  PERFORM pg_temp.ok(has_function_privilege('authenticated', 'public.cl_dry_run_batch(uuid,jsonb)', 'EXECUTE'), 'authenticated EXECUTE');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', 'public.cl_ingest_batch(uuid,jsonb,boolean)', 'EXECUTE'), 'cl_ingest_batch sigue cerrada a authenticated');
END $$;

-- 2. AM de A1: obtiene el mismo resumen que el ensayo directo y no escribe nada.
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE r jsonb; e jsonb := current_setting('t.expected')::jsonb;
BEGIN
  r := public.cl_dry_run_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.payload());
  PERFORM pg_temp.ok((r->>'dry_run')::boolean IS TRUE, 'dry_run = true: ' || r::text);
  PERFORM pg_temp.ok(r->'strata' = e->'strata', 'mismo strata que cl_ingest_batch(...,true): ' || r::text);
  PERFORM pg_temp.ok((r->'strata'->0->>'rows')::int = 4, 'resumen calculado (4 filas)');
  PERFORM pg_temp.ok(NOT (r ? 'replayed'), 'ensayo normal sin replayed');
END $$;
RESET ROLE;
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_batches)::text = current_setting('t.n_batches'), 'sin lotes nuevos');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_batch_scans)::text = current_setting('t.n_scans'), 'sin lecturas nuevas');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts)::text = current_setting('t.n_alerts'), 'sin alertas nuevas');
END $$;

-- 3. AM de A1 sobre un feed de A2 o inexistente: 42501, mismo mensaje (sin oráculo de existencia).
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE v_foreign text; v_missing text;
BEGIN
  v_foreign := pg_temp.raises($q$SELECT public.cl_dry_run_batch('f0000000-0000-0000-0000-0000000000b2', pg_temp.payload())$q$);
  v_missing := pg_temp.raises($q$SELECT public.cl_dry_run_batch('f0000000-0000-0000-0000-00000000dead', pg_temp.payload())$q$);
  PERFORM pg_temp.ok(v_foreign LIKE '42501:CL_FORBIDDEN%', 'feed ajeno: 42501 CL_FORBIDDEN (' || coalesce(v_foreign, 'null') || ')');
  PERFORM pg_temp.ok(v_missing LIKE '42501:%', 'feed inexistente: 42501 (' || coalesce(v_missing, 'null') || ')');
  PERFORM pg_temp.ok(v_foreign = v_missing, 'mismo error ajeno/inexistente');
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT public.cl_dry_run_batch(NULL, pg_temp.payload())$q$) LIKE '42501:%', 'feed NULL: 42501');
END $$;
RESET ROLE;

-- 4. Usuario de A2 sobre el feed de A1: 42501.
SET ROLE authenticated;
SELECT pg_temp.as_user('92000000-0000-0000-0000-000000000092', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT public.cl_dry_run_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.payload())$q$) LIKE '42501:CL_FORBIDDEN%', 'otra cuenta: 42501');
END $$;
RESET ROLE;

-- 5. APM de A1 con cl_connectors solo View: 42501.
SET ROLE authenticated;
SELECT pg_temp.as_user('94000000-0000-0000-0000-000000000094', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok(public.has_any_access('a0000000-0000-0000-0000-000000000001', 'view', 'cl_connectors'), 'fixture: APM ve conectores');
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT public.cl_dry_run_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.payload())$q$) LIKE '42501:CL_FORBIDDEN%', 'solo view: 42501');
END $$;
RESET ROLE;

-- 6. Superadmin: puede ensayar en cualquier cuenta.
SET ROLE authenticated;
SELECT pg_temp.as_user('97000000-0000-0000-0000-000000000097', 'authenticated');
DO $$
DECLARE r jsonb;
BEGIN
  r := public.cl_dry_run_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.payload());
  PERFORM pg_temp.ok((r->>'dry_run')::boolean IS TRUE AND r->'strata' = current_setting('t.expected')::jsonb->'strata', 'superadmin ensaya');
END $$;
RESET ROLE;
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_batches)::text = current_setting('t.n_batches'), 'superadmin: sin lotes nuevos');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_batch_scans)::text = current_setting('t.n_scans'), 'superadmin: sin lecturas nuevas');
END $$;

-- 7. Lote de más de 5 MB: CL_BAD_PAYLOAD (mismo tope que la Edge Function).
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE v_big jsonb; m text;
BEGIN
  v_big := pg_temp.payload() || jsonb_build_object('pad', (SELECT string_agg(md5(i::text), '') FROM generate_series(1, 200000) i));
  PERFORM pg_temp.ok(pg_column_size(v_big) > 5 * 1024 * 1024, 'fixture: payload > 5 MB');
  m := pg_temp.raises(format('SELECT public.cl_dry_run_batch(%L, %L::jsonb)', 'f0000000-0000-0000-0000-0000000000a1', v_big));
  PERFORM pg_temp.ok(m LIKE '22023:CL_BAD_PAYLOAD%', 'lote > 5 MB: ' || coalesce(left(m, 200), 'null'));
END $$;
RESET ROLE;

-- 8. batch_id ya cargado de verdad: cl_ingest_batch devuelve el resumen guardado; el ensayo lo marca dry_run + replayed.
SELECT set_config('t.real', public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.payload())::text, true);
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE r jsonb; v_real jsonb := current_setting('t.real')::jsonb;
BEGIN
  PERFORM pg_temp.ok(v_real->>'batch' IS NOT NULL AND NOT (v_real ? 'dry_run'), 'fixture: carga real');
  r := public.cl_dry_run_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.payload());
  PERFORM pg_temp.ok(r->'dry_run' = 'true'::jsonb AND r->'replayed' = 'true'::jsonb, 'repetido: dry_run y replayed: ' || r::text);
  PERFORM pg_temp.ok(r - 'dry_run' - 'replayed' = v_real, 'repetido: resumen guardado intacto');
END $$;
RESET ROLE;

\echo cl_ui_dry_run: OK
ROLLBACK;
