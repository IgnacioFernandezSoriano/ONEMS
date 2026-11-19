-- Carrier Link fase 1, tarea 9: cuota no cubierta (reparto del deficit) y deshacer un lote.
-- Escenarios construidos con las funciones reales (cuotas, activacion, emision, entrada, sorteo y cierre del lote).
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.sqlstate_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE; END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid text, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  PERFORM set_config('request.jwt.claim.role', coalesce(p_role, ''), true);
END $$;

-- Cuota City1 -> City2 de la semana ISO 2026-Wn.
CREATE OR REPLACE FUNCTION pg_temp.qw(p_week int) RETURNS uuid LANGUAGE sql AS $$
  SELECT q.id FROM public.cl_plan_quotas q
   WHERE q.plan_id = '90000000-0000-0000-0000-0000000000a1' AND q.iso_year = 2026 AND q.iso_week = p_week
$$;

CREATE OR REPLACE FUNCTION pg_temp.qcol(p_week int) RETURNS public.cl_plan_quotas LANGUAGE sql AS $$
  SELECT q.* FROM public.cl_plan_quotas q WHERE q.id = pg_temp.qw(p_week)
$$;

-- Maestros, conector y plan activo con cuotas City1 -> City2 (semanas y muestras por posicion). close_lag_days = 0.
CREATE OR REPLACE FUNCTION pg_temp.setup(p_weeks int[], p_samples int[], p_end date DEFAULT '2026-12-13') RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
    ('d1000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001'),
    ('d2000000-0000-0000-0000-0000000000c2','a0000000-0000-0000-0000-000000000001','PC2','Center 2','City2','c2000000-0000-0000-0000-000000000002');
  INSERT INTO public.readers (id, account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role) VALUES
    ('ad000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','NBO ADM','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','NBO','ADM','origin'),
    ('ad000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-0000000000c2','MBA any','Exit','carrier_scan','ca000000-0000-0000-0000-000000000001','MBA',NULL,'destination');
  INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status) VALUES
    ('f0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed A1','active');
  INSERT INTO public.cl_field_mappings (account_id, carrier_id, standard_field, carrier_field) VALUES
    ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','item_id','trk'),
    ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','scan_at','ts'),
    ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','place_ref','office'),
    ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','mode_ref','evt');
  INSERT INTO public.delivery_standards (account_id, carrier_id, product_id, origin_city_id, destination_city_id, standard_time, time_unit, cl_first_mile_time, cl_last_mile_time)
  VALUES ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',
          'c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002', 48, 'hours', 0, 12);
  INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, feed_id, close_lag_days) VALUES
    ('90000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','CL Q4','ca000000-0000-0000-0000-000000000001',
     'cb000000-0000-0000-0000-000000000001', 100, '2026-10-05', p_end, 'f0000000-0000-0000-0000-0000000000a1', 0);
  PERFORM public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a1',
    (SELECT jsonb_agg(jsonb_build_object('origin_city_id','c1000000-0000-0000-0000-000000000001',
                                         'destination_city_id','c2000000-0000-0000-0000-000000000002',
                                         'iso_year',2026,'iso_week',w,'samples',s))
       FROM unnest(p_weeks, p_samples) u(w, s)));
  PERFORM public.cl_plan_activate('90000000-0000-0000-0000-0000000000a1');
END $$;

-- Emite (lunes 03:00 UTC) y devuelve la demanda nueva.
CREATE OR REPLACE FUNCTION pg_temp.emit(p_now timestamptz) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.ok(public.cl_emit_due_demands(p_now) = 1, 'una demanda emitida en ' || p_now);
  RETURN (SELECT id FROM public.cl_demands WHERE requested_at = p_now);
END $$;

-- Un estrato del lote: p_items envios con inicio (NBO ADM) el lunes de la semana y fin (MBA) el martes.
CREATE OR REPLACE FUNCTION pg_temp.stratum(p_week int, p_pop int, p_items text[]) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('stratum_id', pg_temp.qw(p_week), 'population_size', p_pop,
                            'selection_method', 'uniform_random_within_stratum',
                            'rows', COALESCE((SELECT jsonb_agg(r ORDER BY o) FROM (
                               SELECT 2 * i AS o, jsonb_build_object('trk', it, 'office', 'NBO', 'evt', 'ADM',
                                        'ts', to_char((SELECT period_start FROM public.cl_plan_quotas WHERE id = pg_temp.qw(p_week)), 'YYYY-MM-DD') || 'T08:00:00Z') AS r
                                 FROM unnest(p_items) WITH ORDINALITY u(it, i)
                               UNION ALL
                               SELECT 2 * i + 1, jsonb_build_object('trk', it, 'office', 'MBA', 'evt', 'DLV',
                                        'ts', to_char((SELECT period_start FROM public.cl_plan_quotas WHERE id = pg_temp.qw(p_week)) + 1, 'YYYY-MM-DD') || 'T08:00:00Z')
                                 FROM unnest(p_items) WITH ORDINALITY u(it, i)) s), '[]'::jsonb))
$$;

-- Entrada + sorteo de cada estrato (+ cierre si p_finish). Devuelve el id del lote.
CREATE OR REPLACE FUNCTION pg_temp.batch(p_demand uuid, p_cbid text, p_strata jsonb, p_finish boolean DEFAULT true) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_b uuid; e jsonb;
BEGIN
  v_b := (public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1',
           jsonb_build_object('demand_id', p_demand, 'batch_id', p_cbid, 'strata', p_strata))->>'batch')::uuid;
  PERFORM pg_temp.ok(v_b IS NOT NULL, 'lote creado ' || p_cbid);
  FOR e IN SELECT * FROM jsonb_array_elements(p_strata) LOOP
    PERFORM public.cl_sample_stratum(v_b, (e->>'stratum_id')::uuid);
  END LOOP;
  IF p_finish THEN
    PERFORM pg_temp.ok(public.cl_finish_batch(v_b)->>'status' = 'sampled', 'lote cerrado ' || p_cbid);
  END IF;
  RETURN v_b;
END $$;

-- Usuarios: 93 AM de A1 (Edit en cl_monitor), 95 APM de A1 (View en cl_monitor), 92 UPU AM de A2, 97 superadmin.
CREATE OR REPLACE FUNCTION pg_temp.users() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, email) VALUES
    ('93000000-0000-0000-0000-000000000093','am@t.l'),
    ('95000000-0000-0000-0000-000000000095','apm@t.l'),
    ('92000000-0000-0000-0000-000000000092','upu2@t.l'),
    ('97000000-0000-0000-0000-000000000097','super@t.l');
  INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
    ('93000000-0000-0000-0000-000000000093','am@t.l','AM','user','a0000000-0000-0000-0000-000000000001'),
    ('95000000-0000-0000-0000-000000000095','apm@t.l','APM','user','a0000000-0000-0000-0000-000000000001'),
    ('92000000-0000-0000-0000-000000000092','upu2@t.l','UPU2','user','a0000000-0000-0000-0000-000000000002'),
    ('97000000-0000-0000-0000-000000000097','super@t.l','Super','superadmin',NULL);
  INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
    ('a0000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000093','account_manager'),
    ('a0000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000095','allocation_plan_manager'),
    ('a0000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000092','upu_account_manager');
END $$;

-- ===================================================================== 0. Permisos de las funciones
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT prosecdef FROM pg_proc WHERE oid = 'public.cl_undo_batch(uuid)'::regprocedure), 'undo SECURITY DEFINER');
  PERFORM pg_temp.ok((SELECT 'search_path=public, extensions' = ANY (proconfig) FROM pg_proc WHERE oid = 'public.cl_undo_batch(uuid)'::regprocedure), 'undo search_path');
  PERFORM pg_temp.ok(has_function_privilege('authenticated','public.cl_undo_batch(uuid)','EXECUTE'), 'authenticated deshace (con permiso)');
  PERFORM pg_temp.ok(has_function_privilege('service_role','public.cl_undo_batch(uuid)','EXECUTE'), 'service_role deshace');
  PERFORM pg_temp.ok(NOT has_function_privilege('anon','public.cl_undo_batch(uuid)','EXECUTE'), 'anon no deshace');
  PERFORM pg_temp.ok((SELECT prosecdef FROM pg_proc WHERE oid = 'public.cl_settle_quota(uuid)'::regprocedure), 'settle SECURITY DEFINER');
  PERFORM pg_temp.ok((SELECT 'search_path=public, extensions' = ANY (proconfig) FROM pg_proc WHERE oid = 'public.cl_settle_quota(uuid)'::regprocedure), 'settle search_path');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated','public.cl_settle_quota(uuid)','EXECUTE')
                     AND NOT has_function_privilege('anon','public.cl_settle_quota(uuid)','EXECUTE')
                     AND NOT has_function_privilege('service_role','public.cl_settle_quota(uuid)','EXECUTE'), 'settle interna');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated','public.cl_finish_batch(uuid)','EXECUTE')
                     AND has_function_privilege('service_role','public.cl_finish_batch(uuid)','EXECUTE'), 'finish: solo service_role');
END $$;
ROLLBACK;

-- ===================================================================== 1. Cuota 6, obtenidas 2, poblacion 2 -> carried; +2 y +2 en el mes
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
SELECT pg_temp.setup(ARRAY[42,43,44,45], ARRAY[6,3,3,2]);
DO $$
DECLARE v_d uuid; v_b uuid;
BEGIN
  v_d := pg_temp.emit('2026-10-19 03:00+00');            -- solo vence W42
  v_b := pg_temp.batch(v_d, 'B1', jsonb_build_array(pg_temp.stratum(42, 2, ARRAY['P1','P2'])));
  PERFORM pg_temp.ok((pg_temp.qcol(42)).status = 'carried' AND (pg_temp.qcol(42)).samples_obtained = 2, 'W42 carried con 2: ' || row_to_json(pg_temp.qcol(42))::text);
  PERFORM pg_temp.ok((pg_temp.qcol(43)).samples_carried_in = 2 AND (pg_temp.qcol(43)).status = 'pending', 'W43 +2');
  PERFORM pg_temp.ok((pg_temp.qcol(44)).samples_carried_in = 2 AND (pg_temp.qcol(44)).status = 'pending', 'W44 (empieza en octubre) +2');
  PERFORM pg_temp.ok((pg_temp.qcol(45)).samples_carried_in = 0, 'W45 (noviembre) no recibe');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_demands WHERE id = v_d) = 'partial', 'demanda partial');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_alerts WHERE alert_type = 'quota_unfilled'), 'sin quota_unfilled');
  -- liquidar otra vez una cuota ya repartida no cambia nada
  PERFORM pg_temp.ok(public.cl_settle_quota(pg_temp.qw(42)) = 'carried', 'settle idempotente');
  PERFORM pg_temp.ok((pg_temp.qcol(43)).samples_carried_in = 2 AND (pg_temp.qcol(44)).samples_carried_in = 2, 'sin doble reparto');
  -- la siguiente emision pide lo previsto + lo arrastrado
  v_d := pg_temp.emit('2026-10-26 03:00+00');
  PERFORM pg_temp.ok((SELECT (s->>'samples_required')::int FROM public.cl_demands d, jsonb_array_elements(d.payload->'strata') s
                       WHERE d.id = v_d AND s->>'stratum_id' = pg_temp.qw(43)::text) = 5, 'W43 pide 3 + 2');
END $$;
ROLLBACK;

-- ===================================================================== 2. Deficit 5 entre 2 semanas -> +3 y +2
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
SELECT pg_temp.setup(ARRAY[42,43,44,45], ARRAY[7,3,3,2]);
DO $$
DECLARE v_d uuid;
BEGIN
  v_d := pg_temp.emit('2026-10-19 03:00+00');
  PERFORM pg_temp.batch(v_d, 'B1', jsonb_build_array(pg_temp.stratum(42, 2, ARRAY['P1','P2'])));
  PERFORM pg_temp.ok((pg_temp.qcol(42)).status = 'carried', 'W42 carried');
  PERFORM pg_temp.ok((pg_temp.qcol(43)).samples_carried_in = 3, 'la primera semana recibe el resto: 3');
  PERFORM pg_temp.ok((pg_temp.qcol(44)).samples_carried_in = 2, 'la segunda 2');
  PERFORM pg_temp.ok((pg_temp.qcol(45)).samples_carried_in = 0, 'W45 nada');
END $$;
ROLLBACK;

-- ===================================================================== 3. Ultima semana del mes -> mes siguiente (solo el primero con cuotas)
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
SELECT pg_temp.setup(ARRAY[44,45,46,50], ARRAY[4,2,2,2]);
DO $$
DECLARE v_d uuid;
BEGIN
  v_d := pg_temp.emit('2026-11-02 03:00+00');            -- vence W44 (26/10 - 01/11)
  PERFORM pg_temp.batch(v_d, 'B1', jsonb_build_array(pg_temp.stratum(44, 1, ARRAY['P1'])));
  PERFORM pg_temp.ok((pg_temp.qcol(44)).status = 'carried' AND (pg_temp.qcol(44)).samples_obtained = 1, 'W44 carried');
  PERFORM pg_temp.ok((pg_temp.qcol(45)).samples_carried_in = 2 AND (pg_temp.qcol(46)).samples_carried_in = 1, 'noviembre: +2 y +1');
  PERFORM pg_temp.ok((pg_temp.qcol(50)).samples_carried_in = 0, 'diciembre no recibe');
END $$;
ROLLBACK;

-- ===================================================================== 4. Ultima cuota del plan -> unfilled con alerta
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
SELECT pg_temp.setup(ARRAY[43,44], ARRAY[2,4], '2026-11-01');
DO $$
DECLARE v_d uuid;
BEGIN
  v_d := pg_temp.emit('2026-11-02 03:00+00');            -- vencen W43 y W44
  PERFORM pg_temp.batch(v_d, 'B1', jsonb_build_array(pg_temp.stratum(43, 2, ARRAY['P1','P2']), pg_temp.stratum(44, 1, ARRAY['P3'])));
  PERFORM pg_temp.ok((pg_temp.qcol(43)).status = 'fulfilled', 'W43 fulfilled');
  PERFORM pg_temp.ok((pg_temp.qcol(44)).status = 'unfilled', 'W44 unfilled: ' || row_to_json(pg_temp.qcol(44))::text);
  PERFORM pg_temp.ok((pg_temp.qcol(43)).samples_carried_in = 0, 'una cuota anterior no recibe deficit');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE alert_type = 'quota_unfilled' AND quota_id = pg_temp.qw(44)
                        AND (details->>'missing')::int = 3) = 1, 'alerta quota_unfilled con lo que falta');
  PERFORM pg_temp.ok(public.cl_settle_quota(pg_temp.qw(44)) = 'unfilled', 'settle de unfilled idempotente');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE alert_type = 'quota_unfilled') = 1, 'una sola alerta');
END $$;
ROLLBACK;

-- ===================================================================== 5. Poblacion 40, recibidos 30, demands_count 1 -> pending; nueva demanda pide lo que falta
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
SELECT pg_temp.setup(ARRAY[42,43], ARRAY[35,3]);
DO $$
DECLARE v_d uuid;
BEGIN
  v_d := pg_temp.emit('2026-10-19 03:00+00');
  PERFORM pg_temp.batch(v_d, 'B1', jsonb_build_array(pg_temp.stratum(42, 40,
            ARRAY(SELECT 'R' || lpad(g::text, 2, '0') FROM generate_series(1, 30) g))));
  PERFORM pg_temp.ok((pg_temp.qcol(42)).status = 'pending' AND (pg_temp.qcol(42)).samples_obtained = 30
                     AND (pg_temp.qcol(42)).demands_count = 1, 'W42 vuelve a pending: ' || row_to_json(pg_temp.qcol(42))::text);
  PERFORM pg_temp.ok((pg_temp.qcol(43)).samples_carried_in = 0, 'sin reparto');
  -- siguiente hueco del calendario: pide solo lo que falta (5) para W42
  v_d := pg_temp.emit('2026-10-26 03:00+00');
  PERFORM pg_temp.ok((SELECT (s->>'samples_required')::int FROM public.cl_demands d, jsonb_array_elements(d.payload->'strata') s
                       WHERE d.id = v_d AND s->>'stratum_id' = pg_temp.qw(42)::text) = 5, 'W42 pide 5');
  PERFORM pg_temp.ok((pg_temp.qcol(42)).demands_count = 2 AND (pg_temp.qcol(42)).status = 'open', 'segunda demanda');
END $$;
ROLLBACK;

-- ===================================================================== 6. Igual con demands_count = 3 -> carried
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
SELECT pg_temp.setup(ARRAY[42,43], ARRAY[35,3]);
DO $$
DECLARE v_d uuid; v_b uuid;
BEGIN
  v_d := pg_temp.emit('2026-10-19 03:00+00');
  v_b := pg_temp.batch(v_d, 'B1', jsonb_build_array(pg_temp.stratum(42, 40,
            ARRAY(SELECT 'R' || lpad(g::text, 2, '0') FROM generate_series(1, 30) g))), false);
  UPDATE public.cl_plan_quotas SET demands_count = 3 WHERE id = pg_temp.qw(42);
  PERFORM public.cl_finish_batch(v_b);
  PERFORM pg_temp.ok((pg_temp.qcol(42)).status = 'carried', 'tercera demanda: carried');
  PERFORM pg_temp.ok((pg_temp.qcol(43)).samples_carried_in = 5, 'W43 +5');
END $$;
ROLLBACK;

-- ===================================================================== 7. Deshacer un lote
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
SELECT pg_temp.users();
SELECT pg_temp.setup(ARRAY[42,43], ARRAY[2,3]);
SELECT set_config('t.d1', pg_temp.emit('2026-10-19 03:00+00')::text, true);
SELECT set_config('t.b1', pg_temp.batch(current_setting('t.d1')::uuid, 'B1', jsonb_build_array(pg_temp.stratum(42, 2, ARRAY['U1','U2'])))::text, true);
SELECT pg_temp.ok((pg_temp.qcol(42)).status = 'fulfilled' AND (SELECT count(*) FROM public.one_db) = 2, 'antes: W42 fulfilled, 2 filas one_db');

-- sin Edit en cl_monitor / otra cuenta / lote inexistente: el mismo 42501
SET ROLE authenticated;
SELECT pg_temp.as_user('95000000-0000-0000-0000-000000000095', 'authenticated');
SELECT pg_temp.ok(pg_temp.sqlstate_of(format('SELECT public.cl_undo_batch(%L)', current_setting('t.b1'))) = '42501', 'APM (View en cl_monitor): 42501');
SELECT pg_temp.as_user('92000000-0000-0000-0000-000000000092', 'authenticated');
SELECT pg_temp.ok(pg_temp.sqlstate_of(format('SELECT public.cl_undo_batch(%L)', current_setting('t.b1'))) = '42501', 'otra cuenta: 42501');
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
SELECT pg_temp.ok(pg_temp.sqlstate_of(format('SELECT public.cl_undo_batch(%L)', gen_random_uuid())) = '42501', 'lote inexistente: 42501');
SELECT pg_temp.ok((public.cl_undo_batch(current_setting('t.b1')::uuid)->>'status') = 'undone', 'AM deshace');
SELECT pg_temp.ok(pg_temp.sqlstate_of(format('SELECT public.cl_undo_batch(%L)', current_setting('t.b1'))) = '22023', 'deshacer dos veces: 22023');
RESET ROLE;

DO $$
DECLARE v_b uuid := current_setting('t.b1')::uuid;
BEGIN
  PERFORM pg_temp.ok((SELECT count(*) FROM public.one_db o JOIN public.cl_samples s ON s.id = o.cl_sample_id WHERE s.batch_id = v_b) = 0
                     AND (SELECT count(*) FROM public.one_db) = 0, '0 filas one_db del lote');
  PERFORM pg_temp.ok((SELECT count(*) FILTER (WHERE status = 'voided') = 2 AND count(*) = 2 FROM public.cl_samples WHERE batch_id = v_b), 'muestras voided');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_sample_scans x JOIN public.cl_samples s ON s.id = x.sample_id WHERE s.batch_id = v_b) = 4, 'lecturas de la muestra se conservan');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_sampling_runs WHERE batch_id = v_b), 'sin cl_sampling_runs del lote');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_batches WHERE id = v_b) = 'undone', 'lote undone');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_demands WHERE id = current_setting('t.d1')::uuid) = 'failed', 'demanda failed');
  PERFORM pg_temp.ok((pg_temp.qcol(42)).status = 'pending' AND (pg_temp.qcol(42)).samples_obtained = 0, 'W42 pending con 0');
  PERFORM pg_temp.ok((pg_temp.qcol(43)).status = 'pending', 'W43 sigue pending');
END $$;

-- el mismo item_id puede volver a ser muestra (siguiente hueco del calendario)
SELECT set_config('t.d2', pg_temp.emit('2026-10-26 03:00+00')::text, true);
SELECT set_config('t.b2', pg_temp.batch(current_setting('t.d2')::uuid, 'B2', jsonb_build_array(pg_temp.stratum(42, 2, ARRAY['U1','U2'])), false)::text, true);
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_samples WHERE item_id = 'U1' AND status = 'active' AND batch_id = current_setting('t.b2')::uuid) = 1,
                     'U1 vuelve a ser muestra');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_samples WHERE item_id = 'U1') = 2, 'U1: una voided y una activa');
  PERFORM pg_temp.ok((pg_temp.qcol(42)).samples_obtained = 2, 'W42 obtiene 2 de nuevo');
END $$;

-- superadmin deshace un lote sin cerrar (validated): la cuota abierta de esa demanda vuelve a pending
SET ROLE authenticated;
SELECT pg_temp.as_user('97000000-0000-0000-0000-000000000097', 'authenticated');
SELECT pg_temp.ok((public.cl_undo_batch(current_setting('t.b2')::uuid)->>'status') = 'undone', 'superadmin deshace');
RESET ROLE;
DO $$
BEGIN
  PERFORM pg_temp.ok((pg_temp.qcol(42)).status = 'pending' AND (pg_temp.qcol(42)).samples_obtained = 0, 'W42 pending otra vez');
  PERFORM pg_temp.ok((pg_temp.qcol(43)).status = 'pending', 'W43 (en la demanda, sin estrato en el lote) vuelve a pending');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_samples WHERE item_id = 'U1' AND status = 'active') = 0, 'U1 sin muestra activa');
END $$;
ROLLBACK;

-- ===================================================================== 8. Deshacer despues de repartir: la cuota carried se queda, alerta
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
SELECT pg_temp.setup(ARRAY[42,43], ARRAY[6,3]);
DO $$
DECLARE v_d uuid; v_b uuid; r jsonb;
BEGIN
  v_d := pg_temp.emit('2026-10-19 03:00+00');
  v_b := pg_temp.batch(v_d, 'B1', jsonb_build_array(pg_temp.stratum(42, 2, ARRAY['P1','P2'])));
  PERFORM pg_temp.ok((pg_temp.qcol(42)).status = 'carried' AND (pg_temp.qcol(43)).samples_carried_in = 4, 'W42 carried, W43 +4');
  r := public.cl_undo_batch(v_b);   -- backend (sin usuario)
  PERFORM pg_temp.ok((pg_temp.qcol(42)).status = 'carried' AND (pg_temp.qcol(42)).samples_obtained = 0, 'W42 sigue carried, obtenidas 0');
  PERFORM pg_temp.ok((pg_temp.qcol(43)).samples_carried_in = 4, 'el reparto no se toca');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE alert_type = 'undo_after_carry' AND quota_id = pg_temp.qw(42)
                        AND details->>'batch_id' = v_b::text) = 1, 'alerta undo_after_carry');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_samples WHERE status = 'voided') = 2 AND (SELECT count(*) FROM public.one_db) = 0, 'muestras anuladas');
END $$;
ROLLBACK;
