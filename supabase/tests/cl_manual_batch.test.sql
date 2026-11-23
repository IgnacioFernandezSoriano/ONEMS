-- Carrier Link: carga manual de un lote desde Conectores (20261123100000_cl_manual_batch.sql).
-- cl_manual_ingest / cl_manual_sample / cl_manual_finish reproducen la Edge Function carrier-link-ingest para un lote
-- real: estado del conector (pausado / en prueba), topes, cl_ingest_batch(..., false), sorteo por estrato, cierre.
-- Todo en BEGIN ... ROLLBACK.
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

CREATE OR REPLACE FUNCTION pg_temp.st(p_sid text, p_pop int, p_rows jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('stratum_id', p_sid, 'population_size', p_pop,
                            'selection_method', 'uniform_random_within_stratum', 'rows', p_rows)
$$;

-- Lote de la demanda 1 (un estrato): A1 completo, A2 sin fin, A3 en un punto desconocido.
CREATE OR REPLACE FUNCTION pg_temp.payload() RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('demand_id', current_setting('t.demand'), 'batch_id', 'B-MAN',
           'strata', jsonb_build_array(pg_temp.st('91000000-0000-0000-0000-0000000000b1', 48, jsonb_build_array(
                pg_temp.rd('A1', '20/10/2026 09:14', 'NBO', 'ADM'),
                pg_temp.rd('A1', '21/10/2026 10:00', 'MBA', 'DLV'),
                pg_temp.rd('A2', '21/10/2026 08:00', 'NBO', 'ADM'),
                pg_temp.rd('A3', '21/10/2026 08:00', 'XYZ', 'ADM')))))
$$;

-- Lote de la demanda 2 (dos estratos, semanas 43 y 44).
CREATE OR REPLACE FUNCTION pg_temp.payload2() RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('demand_id', current_setting('t.demand2'), 'batch_id', 'B-MAN-2',
           'strata', jsonb_build_array(
              pg_temp.st('91000000-0000-0000-0000-0000000000b2', 10, jsonb_build_array(
                pg_temp.rd('C1', '20/10/2026 09:00', 'NBO', 'ADM'),
                pg_temp.rd('C1', '22/10/2026 09:00', 'MBA', 'DLV'))),
              pg_temp.st('91000000-0000-0000-0000-0000000000b3', 10, jsonb_build_array(
                pg_temp.rd('C2', '27/10/2026 09:00', 'NBO', 'ADM'),
                pg_temp.rd('C2', '28/10/2026 09:00', 'MBA', 'DLV')))))
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
-- A1 activo (el de las cargas), A1b activo (otro conector de la cuenta), T en prueba, Z pausado.
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status) VALUES
  ('f0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed A1','active'),
  ('f0000000-0000-0000-0000-0000000000a3','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed A1b','active'),
  ('f0000000-0000-0000-0000-0000000000a4','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed T','testing'),
  ('f0000000-0000-0000-0000-0000000000a5','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed Z','paused');
INSERT INTO public.cl_field_mappings (account_id, carrier_id, standard_field, carrier_field, format, timezone) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','item_id','trk',NULL,NULL),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','product','svc',NULL,NULL),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','scan_at','ts','DD/MM/YYYY HH24:MI','Africa/Nairobi'),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','place_ref','office',NULL,NULL),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','mode_ref','evt',NULL,NULL);
INSERT INTO public.cl_value_mappings (account_id, carrier_id, kind, carrier_value, onems_value) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','product','EXP','PR');
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','P1','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',2,'2026-10-19','2026-10-25','active','f0000000-0000-0000-0000-0000000000a1'),
  ('90000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000001','P2','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',2,'2026-10-19','2026-11-01','active','f0000000-0000-0000-0000-0000000000a1');
INSERT INTO public.cl_plan_quotas (id, account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned) VALUES
  ('91000000-0000-0000-0000-0000000000b1','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,43,'2026-10-19','2026-10-25',2),
  ('91000000-0000-0000-0000-0000000000b2','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a2','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,43,'2026-10-19','2026-10-25',1),
  ('91000000-0000-0000-0000-0000000000b3','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a2','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,44,'2026-10-26','2026-11-01',1);
SELECT set_config('t.demand', public.cl_build_demand('90000000-0000-0000-0000-0000000000a1',
  ARRAY['91000000-0000-0000-0000-0000000000b1']::uuid[])::text, true);
SELECT set_config('t.demand2', public.cl_build_demand('90000000-0000-0000-0000-0000000000a2',
  ARRAY['91000000-0000-0000-0000-0000000000b2','91000000-0000-0000-0000-0000000000b3']::uuid[])::text, true);

-- Feed de A2 (para el usuario de otra cuenta).
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

SELECT set_config('t.n_batches', (SELECT count(*) FROM public.cl_batches)::text, true);

-- 1. Permisos de las funciones.
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.cl_manual_ingest(uuid,jsonb)', 'public.cl_manual_sample(uuid,uuid,uuid)',
                           'public.cl_manual_finish(uuid,uuid)'] LOOP
    PERFORM pg_temp.ok((SELECT prosecdef FROM pg_proc WHERE oid = f::regprocedure), f || ' SECURITY DEFINER');
    PERFORM pg_temp.ok((SELECT proconfig @> ARRAY['search_path=public, extensions'] FROM pg_proc WHERE oid = f::regprocedure), f || ' search_path');
    PERFORM pg_temp.ok(NOT has_function_privilege('anon', f, 'EXECUTE'), f || ' anon sin EXECUTE');
    PERFORM pg_temp.ok(has_function_privilege('authenticated', f, 'EXECUTE'), f || ' authenticated EXECUTE');
  END LOOP;
  FOREACH f IN ARRAY ARRAY['public.cl_manual_authorize(uuid)', 'public.cl_manual_check_status(text)', 'public.cl_manual_batch_status(uuid,uuid)'] LOOP
    PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', f, 'EXECUTE')
                   AND NOT has_function_privilege('anon', f, 'EXECUTE'), f || ' interna');
  END LOOP;
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', 'public.cl_ingest_batch(uuid,jsonb,boolean)', 'EXECUTE'), 'cl_ingest_batch sigue cerrada');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', 'public.cl_sample_stratum(uuid,uuid)', 'EXECUTE'), 'cl_sample_stratum sigue cerrada');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', 'public.cl_finish_batch(uuid)', 'EXECUTE'), 'cl_finish_batch sigue cerrada');
END $$;

-- 2. Sin derecho: feed ajeno, inexistente, NULL, usuario de otra cuenta, solo View: el mismo 42501 CL_FORBIDDEN,
--    en las tres funciones, sin escribir nada.
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE v_foreign text; v_missing text; z uuid := '00000000-0000-0000-0000-000000000000';
BEGIN
  v_foreign := pg_temp.raises($q$SELECT public.cl_manual_ingest('f0000000-0000-0000-0000-0000000000b2', pg_temp.payload())$q$);
  v_missing := pg_temp.raises($q$SELECT public.cl_manual_ingest('f0000000-0000-0000-0000-00000000dead', pg_temp.payload())$q$);
  PERFORM pg_temp.ok(v_foreign = '42501:CL_FORBIDDEN', 'feed ajeno: ' || coalesce(v_foreign, 'null'));
  PERFORM pg_temp.ok(v_missing = v_foreign, 'inexistente = ajeno: ' || coalesce(v_missing, 'null'));
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT public.cl_manual_ingest(NULL, pg_temp.payload())$q$) = v_foreign, 'feed NULL');
  PERFORM pg_temp.ok(pg_temp.raises(format('SELECT public.cl_manual_sample(%L, %L, %L)', 'f0000000-0000-0000-0000-0000000000b2', z, z)) = v_foreign, 'sample ajeno');
  PERFORM pg_temp.ok(pg_temp.raises(format('SELECT public.cl_manual_sample(%L, %L, %L)', 'f0000000-0000-0000-0000-00000000dead', z, z)) = v_foreign, 'sample inexistente');
  PERFORM pg_temp.ok(pg_temp.raises(format('SELECT public.cl_manual_finish(%L, %L)', 'f0000000-0000-0000-0000-0000000000b2', z)) = v_foreign, 'finish ajeno');
  PERFORM pg_temp.ok(pg_temp.raises(format('SELECT public.cl_manual_finish(%L, %L)', 'f0000000-0000-0000-0000-00000000dead', z)) = v_foreign, 'finish inexistente');
END $$;
RESET ROLE;

SET ROLE authenticated;
SELECT pg_temp.as_user('92000000-0000-0000-0000-000000000092', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT public.cl_manual_ingest('f0000000-0000-0000-0000-0000000000a1', pg_temp.payload())$q$) = '42501:CL_FORBIDDEN', 'otra cuenta');
END $$;
RESET ROLE;

SET ROLE authenticated;
SELECT pg_temp.as_user('94000000-0000-0000-0000-000000000094', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok(public.has_any_access('a0000000-0000-0000-0000-000000000001', 'view', 'cl_connectors'), 'fixture: APM ve conectores');
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT public.cl_manual_ingest('f0000000-0000-0000-0000-0000000000a1', pg_temp.payload())$q$) = '42501:CL_FORBIDDEN', 'solo view');
END $$;
RESET ROLE;

-- Sin rol (anon) no puede ni llamarla.
SET ROLE anon;
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT public.cl_manual_ingest('f0000000-0000-0000-0000-0000000000a1', '{}'::jsonb)$q$) LIKE '42501:%', 'anon');
END $$;
RESET ROLE;
SELECT pg_temp.ok((SELECT count(*) FROM public.cl_batches)::text = current_setting('t.n_batches'), 'sin derecho: sin lotes');

-- 3. Conector en prueba o pausado: rechazado como en la Edge Function, sin escribir nada.
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE m text;
BEGIN
  m := pg_temp.raises($q$SELECT public.cl_manual_ingest('f0000000-0000-0000-0000-0000000000a4', pg_temp.payload())$q$);
  PERFORM pg_temp.ok(m LIKE '22023:CL_FEED_TESTING_DRY_RUN_ONLY%', 'en prueba: ' || coalesce(m, 'null'));
  m := pg_temp.raises($q$SELECT public.cl_manual_ingest('f0000000-0000-0000-0000-0000000000a5', pg_temp.payload())$q$);
  PERFORM pg_temp.ok(m LIKE '22023:CL_FEED_PAUSED%', 'pausado: ' || coalesce(m, 'null'));
END $$;
RESET ROLE;
SELECT pg_temp.ok((SELECT count(*) FROM public.cl_batches)::text = current_setting('t.n_batches'), 'prueba/pausado: sin lotes');

-- 4. Topes de la Edge Function: > 5 MB (CL_BODY_TOO_LARGE) y > 5.000 lecturas (CL_TOO_MANY_ROWS).
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE v_big jsonb; v_many jsonb; v_ok jsonb; m text;
BEGIN
  v_big := pg_temp.payload() || jsonb_build_object('pad', (SELECT string_agg(md5(i::text), '') FROM generate_series(1, 200000) i));
  PERFORM pg_temp.ok(pg_column_size(v_big) > 5 * 1024 * 1024, 'fixture: payload > 5 MB');
  m := pg_temp.raises(format('SELECT public.cl_manual_ingest(%L, %L::jsonb)', 'f0000000-0000-0000-0000-0000000000a1', v_big));
  PERFORM pg_temp.ok(m LIKE '22023:CL_BODY_TOO_LARGE%', '> 5 MB: ' || coalesce(left(m, 200), 'null'));

  v_many := jsonb_build_object('demand_id', current_setting('t.demand'), 'batch_id', 'B-MANY',
              'strata', jsonb_build_array(
                 pg_temp.st('91000000-0000-0000-0000-0000000000b1', 9999,
                   (SELECT jsonb_agg(pg_temp.rd('M' || i, '20/10/2026 09:00', 'NBO', 'ADM')) FROM generate_series(1, 3000) i)),
                 'not-an-object',
                 pg_temp.st('91000000-0000-0000-0000-0000000000b9', 9999,
                   (SELECT jsonb_agg(pg_temp.rd('N' || i, '20/10/2026 09:00', 'NBO', 'ADM')) FROM generate_series(1, 2001) i))));
  m := pg_temp.raises(format('SELECT public.cl_manual_ingest(%L, %L::jsonb)', 'f0000000-0000-0000-0000-0000000000a1', v_many));
  PERFORM pg_temp.ok(m LIKE '22023:CL_TOO_MANY_ROWS: 5001 rows%', '5.001 lecturas: ' || coalesce(left(m, 200), 'null'));
  -- 5.000 exactas pasan el tope (las rechaza cl_ingest_batch por otra razon: el estrato b9 no es de la demanda).
  v_ok := jsonb_set(v_many, '{strata,2,rows}', (v_many->'strata'->2->'rows') - 0);
  m := pg_temp.raises(format('SELECT public.cl_manual_ingest(%L, %L::jsonb)', 'f0000000-0000-0000-0000-0000000000a1', v_ok));
  PERFORM pg_temp.ok(m NOT LIKE '%CL_TOO_MANY_ROWS%', '5.000 lecturas no tocan el tope: ' || coalesce(left(m, 200), 'null'));
  -- Un tope de tamano en un feed ajeno sigue siendo 42501 (permisos primero).
  m := pg_temp.raises(format('SELECT public.cl_manual_ingest(%L, %L::jsonb)', 'f0000000-0000-0000-0000-0000000000b2', v_big));
  PERFORM pg_temp.ok(m = '42501:CL_FORBIDDEN', 'ajeno y grande: 42501');
END $$;
RESET ROLE;
SELECT pg_temp.ok((SELECT count(*) FROM public.cl_batches)::text = current_setting('t.n_batches'), 'topes: sin lotes');

-- 5. Extremo a extremo (AM de A1): ingest -> sorteo por estrato -> cierre, como la Edge Function.
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE r jsonb; s jsonb; f jsonb; v_batch uuid;
BEGIN
  r := public.cl_manual_ingest('f0000000-0000-0000-0000-0000000000a1', pg_temp.payload());
  PERFORM pg_temp.ok(r->'needs_sampling' = 'true'::jsonb, 'needs_sampling: ' || r::text);
  PERFORM pg_temp.ok(r->>'batch_status' = 'validated', 'batch_status validated');
  PERFORM pg_temp.ok(r->'ingest'->>'status' = 'validated' AND r->'ingest'->>'batch' IS NOT NULL, 'lote validado y guardado');
  PERFORM pg_temp.ok(NOT (r->'ingest' ? 'dry_run'), 'lote real (sin dry_run)');
  PERFORM pg_temp.ok(jsonb_array_length(r->'ingest'->'strata') = 1, 'un estrato en el resumen');
  v_batch := (r->'ingest'->>'batch')::uuid;
  PERFORM set_config('t.batch', v_batch::text, false);
  PERFORM set_config('t.ingest', (r->'ingest')::text, false);

  s := public.cl_manual_sample('f0000000-0000-0000-0000-0000000000a1', v_batch, '91000000-0000-0000-0000-0000000000b1');
  PERFORM pg_temp.ok((s->>'samples_selected')::int = 1 AND s->'selected_item_ids' = '["A1"]'::jsonb, 'sorteo: A1 ' || s::text);
  PERFORM pg_temp.ok((s->>'samples_required')::int = 2, 'pedidas 2');
  PERFORM set_config('t.sample', s::text, false);

  f := public.cl_manual_finish('f0000000-0000-0000-0000-0000000000a1', v_batch);
  PERFORM pg_temp.ok(f->>'status' = 'sampled' AND f->>'demand_status' = 'partial', 'cierre: ' || f::text);
END $$;
RESET ROLE;
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT status FROM public.cl_batches WHERE id = current_setting('t.batch')::uuid) = 'sampled', 'lote sampled');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_samples WHERE batch_id = current_setting('t.batch')::uuid AND item_id = 'A1' AND status = 'active') = 1, 'muestra A1 creada');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_demands WHERE id = current_setting('t.demand')::uuid) = 'partial', 'demanda partial');
END $$;

-- 6. Repetir el mismo batch_id: devuelve el resumen guardado, sin sorteo pendiente ni escrituras.
--    Sortear / cerrar otra vez es idempotente (mismo resultado).
SELECT set_config('t.n_batches', (SELECT count(*) FROM public.cl_batches)::text, true);
SELECT set_config('t.n_samples', (SELECT count(*) FROM public.cl_samples)::text, true);
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE r jsonb;
BEGIN
  r := public.cl_manual_ingest('f0000000-0000-0000-0000-0000000000a1', pg_temp.payload());
  PERFORM pg_temp.ok(r->'ingest' = current_setting('t.ingest')::jsonb, 'repetido: resumen guardado ' || r::text);
  PERFORM pg_temp.ok(r->'needs_sampling' = 'false'::jsonb, 'repetido: ya sorteado');
  PERFORM pg_temp.ok(r->>'batch_status' = 'sampled', 'repetido: batch_status sampled ' || r::text);
  PERFORM pg_temp.ok(public.cl_manual_sample('f0000000-0000-0000-0000-0000000000a1', current_setting('t.batch')::uuid,
                     '91000000-0000-0000-0000-0000000000b1') = current_setting('t.sample')::jsonb, 'sorteo idempotente');
  PERFORM pg_temp.ok(public.cl_manual_finish('f0000000-0000-0000-0000-0000000000a1', current_setting('t.batch')::uuid)->>'status' = 'sampled', 'cierre idempotente');
END $$;
RESET ROLE;
SELECT pg_temp.ok((SELECT count(*) FROM public.cl_batches)::text = current_setting('t.n_batches')
              AND (SELECT count(*) FROM public.cl_samples)::text = current_setting('t.n_samples'), 'repetido: sin escrituras');

-- 7. Lote de otro conector (aunque sea de la misma cuenta) o inexistente: CL_BATCH_NOT_FOUND.
--    Con el conector del lote pausado se rechaza tambien el lote ya guardado (la Edge Function mira el estado antes).
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE m text;
BEGIN
  m := pg_temp.raises(format('SELECT public.cl_manual_sample(%L, %L, %L)', 'f0000000-0000-0000-0000-0000000000a3',
                             current_setting('t.batch'), '91000000-0000-0000-0000-0000000000b1'));
  PERFORM pg_temp.ok(m LIKE '22023:CL_BATCH_NOT_FOUND%', 'sample con otro conector: ' || coalesce(m, 'null'));
  m := pg_temp.raises(format('SELECT public.cl_manual_finish(%L, %L)', 'f0000000-0000-0000-0000-0000000000a3', current_setting('t.batch')));
  PERFORM pg_temp.ok(m LIKE '22023:CL_BATCH_NOT_FOUND%', 'finish con otro conector: ' || coalesce(m, 'null'));
  m := pg_temp.raises(format('SELECT public.cl_manual_finish(%L, %L)', 'f0000000-0000-0000-0000-0000000000a1', gen_random_uuid()));
  PERFORM pg_temp.ok(m LIKE '22023:CL_BATCH_NOT_FOUND%', 'lote inexistente: ' || coalesce(m, 'null'));
  -- El lote de A1 enviado por el conector A1b: su demanda no es de A1b.
  m := pg_temp.raises($q$SELECT public.cl_manual_ingest('f0000000-0000-0000-0000-0000000000a3', pg_temp.payload())$q$);
  PERFORM pg_temp.ok(m LIKE 'P0001:CL_DEMAND_NOT_OPEN%', 'demanda de otro conector: ' || coalesce(m, 'null'));
END $$;
RESET ROLE;
UPDATE public.cl_feeds SET status = 'paused' WHERE id = 'f0000000-0000-0000-0000-0000000000a1';
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT public.cl_manual_ingest('f0000000-0000-0000-0000-0000000000a1', pg_temp.payload())$q$) LIKE '22023:CL_FEED_PAUSED%', 'repetido en pausado');
  PERFORM pg_temp.ok(pg_temp.raises(format('SELECT public.cl_manual_finish(%L, %L)', 'f0000000-0000-0000-0000-0000000000a1', current_setting('t.batch'))) LIKE '22023:CL_FEED_PAUSED%', 'finish en pausado');
END $$;
RESET ROLE;
UPDATE public.cl_feeds SET status = 'active' WHERE id = 'f0000000-0000-0000-0000-0000000000a1';

-- 8. Fallo a medias y reanudacion (superadmin): se sortea solo el primer estrato (como si fallara el segundo), el
--    cierre queda 'pending'; al volver a cargar el mismo fichero se retoma: needs_sampling, estrato 1 idempotente,
--    estrato 2 sorteado, cierre 'sampled' y demanda fulfilled.
SET ROLE authenticated;
SELECT pg_temp.as_user('97000000-0000-0000-0000-000000000097', 'authenticated');
DO $$
DECLARE r jsonb; r2 jsonb; s1 jsonb; s1b jsonb; s2 jsonb; f jsonb; v_batch uuid;
BEGIN
  r := public.cl_manual_ingest('f0000000-0000-0000-0000-0000000000a1', pg_temp.payload2());
  PERFORM pg_temp.ok(r->'needs_sampling' = 'true'::jsonb AND jsonb_array_length(r->'ingest'->'strata') = 2, 'dos estratos: ' || r::text);
  v_batch := (r->'ingest'->>'batch')::uuid;
  s1 := public.cl_manual_sample('f0000000-0000-0000-0000-0000000000a1', v_batch, '91000000-0000-0000-0000-0000000000b2');
  PERFORM pg_temp.ok((s1->>'samples_selected')::int = 1, 'estrato 1: ' || s1::text);
  f := public.cl_manual_finish('f0000000-0000-0000-0000-0000000000a1', v_batch);
  PERFORM pg_temp.ok(f->>'status' = 'pending' AND f->'strata_pending' = '["91000000-0000-0000-0000-0000000000b3"]'::jsonb, 'a medias: ' || f::text);

  r2 := public.cl_manual_ingest('f0000000-0000-0000-0000-0000000000a1', pg_temp.payload2());
  PERFORM pg_temp.ok(r2->'ingest' = r->'ingest' AND r2->'needs_sampling' = 'true'::jsonb, 'reanudar: ' || r2::text);
  s1b := public.cl_manual_sample('f0000000-0000-0000-0000-0000000000a1', v_batch, '91000000-0000-0000-0000-0000000000b2');
  PERFORM pg_temp.ok(s1b = s1, 'estrato 1 idempotente');
  s2 := public.cl_manual_sample('f0000000-0000-0000-0000-0000000000a1', v_batch, '91000000-0000-0000-0000-0000000000b3');
  PERFORM pg_temp.ok((s2->>'samples_selected')::int = 1 AND s2->'selected_item_ids' = '["C2"]'::jsonb, 'estrato 2: ' || s2::text);
  f := public.cl_manual_finish('f0000000-0000-0000-0000-0000000000a1', v_batch);
  PERFORM pg_temp.ok(f->>'status' = 'sampled' AND f->>'demand_status' = 'fulfilled', 'reanudado: ' || f::text);
  -- Un estrato que no es del lote: el error del sorteador.
  PERFORM pg_temp.ok(pg_temp.raises(format('SELECT public.cl_manual_sample(%L, %L, %L)', 'f0000000-0000-0000-0000-0000000000a1',
                     v_batch, '91000000-0000-0000-0000-0000000000b1')) LIKE '22023:%', 'estrato ajeno al lote');
  PERFORM set_config('t.batch2', v_batch::text, false);
END $$;
RESET ROLE;

-- 9. Lote repetido cuyo estado ya no es sorteable (p. ej. caducado): batch_status lo dice y no se sortea.
UPDATE public.cl_batches SET status = 'expired' WHERE id = current_setting('t.batch2')::uuid;
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE r jsonb;
BEGIN
  r := public.cl_manual_ingest('f0000000-0000-0000-0000-0000000000a1', pg_temp.payload2());
  PERFORM pg_temp.ok(r->>'batch_status' = 'expired' AND r->'needs_sampling' = 'false'::jsonb, 'caducado: ' || r::text);
END $$;
RESET ROLE;

ROLLBACK;
