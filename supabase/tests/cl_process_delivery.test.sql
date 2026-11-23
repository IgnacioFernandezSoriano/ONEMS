-- Carrier Link v4, tarea 2: proceso de una entrega (20261124100100_cl_process_delivery.sql).
-- Carga por el worker (tomar, trozos, arriendo, cursor, sha256, max_rows, lista cerrada de campos), fases de la base
-- (equivalencias, validacion, envios por semana ISO de llegada, cuota por entrega, sorteo determinista, paso a
-- cl_samples / one_db, alertas, liquidacion), vaciado de la zona de paso (M1), reanudar tras caida o fallo, entregas
-- de prueba, retencion de ficheros (M3), arranque del worker y privilegios. Todo en BEGIN ... ROLLBACK.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.raises(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE || ':' || SQLERRM; END $$;

-- Una lectura del fichero (nombres del carrier). p_extra se anade tal cual (campos no permitidos incluidos).
CREATE OR REPLACE FUNCTION pg_temp.r(p_n int, p_trk text, p_ts text, p_office text, p_evt text DEFAULT NULL,
                                     p_svc text DEFAULT 'EXP', p_extra jsonb DEFAULT '{}'::jsonb)
RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('n', p_n, 'r', jsonb_strip_nulls(jsonb_build_object(
           'trk', p_trk, 'ts', p_ts, 'office', p_office, 'evt', p_evt, 'svc', p_svc)) || p_extra)
$$;

-- Crea una entrega 'received' cuyo fichero "es" el texto de p_rows (sha256 y tamano de ese texto).
CREATE OR REPLACE FUNCTION pg_temp.mk(p_id text, p_feed text, p_start text, p_end text, p_rows jsonb,
                                      p_is_test boolean DEFAULT false, p_comp text DEFAULT 'none') RETURNS uuid
LANGUAGE sql AS $$
  INSERT INTO public.cl_deliveries (id, account_id, feed_id, period_start, period_end, source, is_test, format,
                                    compression, file_path, file_bytes, sha256, status, received_at)
  VALUES (p_id::uuid, 'a0000000-0000-0000-0000-000000000001', p_feed::uuid, p_start::date, p_end::date, 'api',
          p_is_test, 'jsonl', p_comp, 'a0000000-0000-0000-0000-000000000001/' || p_feed || '/' || p_id || '.jsonl',
          octet_length(p_rows::text), encode(sha256(convert_to(p_rows::text, 'UTF8')), 'hex'), 'received',
          now() - interval '1 hour')
  RETURNING id
$$;

-- Simula el worker: toma, carga p_rows en trozos de p_per filas y cierra con el sha256 del texto.
CREATE OR REPLACE FUNCTION pg_temp.load(p_rows jsonb, p_per int DEFAULT 1000, p_token text DEFAULT 'token-test-1',
                                        p_sha text DEFAULT NULL) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  c jsonb; v_id uuid; v_off bigint := 0; v_n bigint := 0; v_len bigint; v_total int; v_chunk jsonb; v_res jsonb;
  i int := 0;
BEGIN
  c := public.cl_delivery_worker_claim(p_token);
  IF c->>'action' <> 'load' THEN RETURN c; END IF;
  v_id := (c->>'delivery_id')::uuid;
  v_off := (c->'load'->>'offset')::bigint; v_n := (c->'load'->>'rows')::bigint;
  v_len := (c->>'file_bytes')::bigint;
  v_total := jsonb_array_length(p_rows);
  WHILE v_n < v_total LOOP
    SELECT jsonb_agg(e ORDER BY (e->>'n')::int) INTO v_chunk FROM jsonb_array_elements(p_rows) e
     WHERE (e->>'n')::int > v_n AND (e->>'n')::int <= v_n + p_per;
    v_res := public.cl_delivery_load_rows(v_id, p_token, v_off, v_chunk,
               jsonb_build_object('offset', CASE WHEN v_n + p_per >= v_total THEN v_len ELSE v_off + 1 END,
                                  'rows', LEAST(v_n + p_per, v_total), 'sha', jsonb_build_object('h', '[]'::jsonb),
                                  'sha_offset', v_len, 'header', NULL));
    IF (v_res->>'stop')::boolean THEN RETURN v_res; END IF;
    v_off := CASE WHEN v_n + p_per >= v_total THEN v_len ELSE v_off + 1 END;
    v_n := LEAST(v_n + p_per, v_total);
  END LOOP;
  IF v_total = 0 THEN v_off := v_len; END IF;
  RETURN public.cl_delivery_load_done(v_id, p_token, v_off,
           COALESCE(p_sha, (SELECT d.sha256 FROM public.cl_deliveries d WHERE d.id = v_id)), v_len);
END $$;

-- Pasos de la base hasta que no quede nada (como el bucle de pg_cron, sin COMMIT). Devuelve las fases hechas.
CREATE OR REPLACE FUNCTION pg_temp.run(p_chunk int DEFAULT 100000) RETURNS text[] LANGUAGE plpgsql AS $$
DECLARE v text; acc text[] := ARRAY[]::text[]; i int := 0;
BEGIN
  LOOP
    v := public.cl_process_delivery(NULL, p_chunk);
    acc := acc || v; i := i + 1;
    EXIT WHEN v IN ('idle','load','reset') OR i > 2000;
  END LOOP;
  RETURN acc;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.staging(p_id uuid) RETURNS bigint LANGUAGE sql AS $$
  SELECT (SELECT count(*) FROM public.cl_delivery_rows WHERE delivery_id = p_id)
       + (SELECT count(*) FROM public.cl_delivery_items WHERE delivery_id = p_id)
$$;

BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
-- Fixture independiente de la fecha real.
UPDATE public.accounts SET timezone = 'Africa/Nairobi' WHERE id = 'a0000000-0000-0000-0000-000000000001';
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c3000000-0000-0000-0000-000000000013','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City3','C3');
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001'),
  ('d2000000-0000-0000-0000-0000000000c2','a0000000-0000-0000-0000-000000000001','PC2','Center 2','City2','c2000000-0000-0000-0000-000000000002'),
  ('d3000000-0000-0000-0000-0000000000c3','a0000000-0000-0000-0000-000000000001','PC3','Center 3','City3','c3000000-0000-0000-0000-000000000013');
-- Puntos: NBO/ADM origen (C1), HUB intermedio, MBA (cualquier modo) destino (C2), KSM ambos (C3).
INSERT INTO public.readers (id, account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role) VALUES
  ('ad000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','NBO ADM','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','NBO','ADM','origin'),
  ('ad000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001',NULL,'HUB','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','HUB',NULL,'none'),
  ('ad000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-0000000000c2','MBA any','Exit','carrier_scan','ca000000-0000-0000-0000-000000000001','MBA',NULL,'destination'),
  ('ad000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','d3000000-0000-0000-0000-0000000000c3','KSM','Exit','carrier_scan','ca000000-0000-0000-0000-000000000001','KSM',NULL,'both');
-- Otra cuenta con un punto del mismo nombre (no debe usarse).
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','CB','Carrier2');
INSERT INTO public.regions (id, account_id, name, code) VALUES
  ('e0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','Reg2','R2');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','CityX','CX');
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d9000000-0000-0000-0000-0000000000c9','a0000000-0000-0000-0000-000000000002','PX','Center X','CityX','c3000000-0000-0000-0000-000000000003');
INSERT INTO public.readers (id, account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role) VALUES
  ('ad000000-0000-0000-0000-000000000099','a0000000-0000-0000-0000-000000000002','d9000000-0000-0000-0000-0000000000c9','MBA2','Exit','carrier_scan','ca000000-0000-0000-0000-000000000002','MBA',NULL,'destination');

-- Conectores: F semanal en martes (periodo martes..lunes, cruza la semana ISO), T de prueba, G para gzip.
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status, emit_days, emit_hour, config) VALUES
  ('f0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed F','active','{2}',3,'{"max_rows": 60}'),
  ('f0000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed T','testing','{2}',3,'{}');
INSERT INTO public.cl_field_mappings (account_id, carrier_id, standard_field, carrier_field, format, timezone) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','item_id','trk',NULL,NULL),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','product','svc',NULL,NULL),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','scan_at','ts','YYYY-MM-DD HH24:MI','Africa/Nairobi'),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','place_ref','office',NULL,NULL),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','mode_ref','evt',NULL,NULL);
INSERT INTO public.cl_value_mappings (account_id, carrier_id, kind, carrier_value, onems_value) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','product','EXP','PR');
INSERT INTO public.cl_extra_fields (account_id, carrier_id, carrier_field) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','weight');
INSERT INTO public.delivery_standards (account_id, carrier_id, product_id, origin_city_id, destination_city_id, standard_time, time_unit, cl_first_mile_time, cl_last_mile_time)
VALUES ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002', 96, 'hours', 0, 12);
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','P1','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',11,'2026-11-02','2026-11-29','active','f0000000-0000-0000-0000-0000000000a1'),
  ('90000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000001','PT','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',11,'2026-11-02','2026-11-29','active','f0000000-0000-0000-0000-0000000000a2');
-- Ruta C1 -> C2: W46 (9-15/11) 4, W47 (16-22/11) 5, W48 (23-29/11) 2. Plan de prueba: W46 3.
INSERT INTO public.cl_plan_quotas (id, account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned) VALUES
  ('91000000-0000-0000-0000-000000000046','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,46,'2026-11-09','2026-11-15',4),
  ('91000000-0000-0000-0000-000000000047','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,47,'2026-11-16','2026-11-22',5),
  ('91000000-0000-0000-0000-000000000048','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,48,'2026-11-23','2026-11-29',2),
  ('91000000-0000-0000-0000-0000000000f6','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a2','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,46,'2026-11-09','2026-11-15',3);
-- Una muestra activa previa del envio I15 (otro origen).
INSERT INTO public.cl_samples (account_id, carrier_id, item_id) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','I15');

-- ================================================================ 1. estructura y privilegios
DO $$
DECLARE r record;
BEGIN
  PERFORM pg_temp.ok((SELECT relpersistence = 'u' AND relrowsecurity FROM pg_class
                       WHERE oid = 'public.cl_delivery_items'::regclass), 'cl_delivery_items UNLOGGED con RLS');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM information_schema.role_table_grants
                                  WHERE table_name = 'cl_delivery_items'
                                    AND grantee IN ('anon','authenticated','service_role','PUBLIC')),
                     'cl_delivery_items sin privilegios');
  -- Funciones nuevas: SECURITY DEFINER con search_path (salvo el procedimiento y helpers SQL/IMMUTABLE).
  FOR r IN SELECT p.oid::regprocedure::text AS fn, p.prosecdef, p.proconfig, p.prokind
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public'
              AND p.proname IN ('cl_delivery_worker_claim','cl_delivery_load_rows','cl_delivery_load_done',
                                'cl_delivery_load_fail','cl_delivery_sweep_list','cl_delivery_sweep_done',
                                'cl_process_delivery','cl_delivery_kick_worker','cl_delivery_phase_resolve',
                                'cl_delivery_phase_items','cl_delivery_phase_strata','cl_delivery_phase_draw',
                                'cl_delivery_phase_transfer','cl_delivery_phase_finish','cl_delivery_phase_cleanup',
                                'cl_delivery_alert','cl_delivery_mark_abort','cl_delivery_load_lock',
                                'cl_process_delivery_failed')
  LOOP
    PERFORM pg_temp.ok(r.prosecdef AND 'search_path=public, extensions' = ANY (r.proconfig), r.fn || ' definer + search_path');
  END LOOP;
  -- Worker: solo service_role. Internas y procedimiento: nadie.
  FOR r IN SELECT unnest(ARRAY['public.cl_delivery_worker_claim(text,integer,timestamptz)',
                               'public.cl_delivery_load_rows(uuid,text,bigint,jsonb,jsonb,boolean,integer)',
                               'public.cl_delivery_load_done(uuid,text,bigint,text,bigint)',
                               'public.cl_delivery_load_fail(uuid,text,text,boolean)',
                               'public.cl_delivery_sweep_list(integer,timestamptz)',
                               'public.cl_delivery_sweep_done(text[])']) AS fn LOOP
    PERFORM pg_temp.ok(has_function_privilege('service_role', r.fn, 'EXECUTE'), r.fn || ' service_role');
    PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', r.fn, 'EXECUTE'), r.fn || ' no authenticated');
    PERFORM pg_temp.ok(NOT has_function_privilege('anon', r.fn, 'EXECUTE'), r.fn || ' no anon');
  END LOOP;
  FOR r IN SELECT unnest(ARRAY['public.cl_process_delivery(uuid,integer)',
                               'public.cl_delivery_kick_worker(timestamptz)',
                               'public.cl_delivery_process_run(integer,integer)',
                               'public.cl_delivery_phase_transfer(public.cl_deliveries,public.cl_feeds,integer)',
                               'public.cl_delivery_quota_share(uuid,integer,date,date,date,date)',
                               'public.cl_settle_quota(uuid)']) AS fn LOOP
    PERFORM pg_temp.ok(NOT has_function_privilege('service_role', r.fn, 'EXECUTE')
                       AND NOT has_function_privilege('authenticated', r.fn, 'EXECUTE')
                       AND NOT has_function_privilege('anon', r.fn, 'EXECUTE'), r.fn || ' sin grants');
  END LOOP;
  PERFORM pg_temp.ok((SELECT count(*) FROM cron.job WHERE jobname IN ('cl-delivery-process','cl-delivery-worker-kick')
                       AND schedule = '* * * * *') = 2, 'dos trabajos pg_cron cada minuto');
  PERFORM pg_temp.ok((SELECT command FROM cron.job WHERE jobname = 'cl-delivery-process')
                       = 'CALL public.cl_delivery_process_run();', 'el proceso es un CALL (COMMIT entre pasos)');
END $$;

-- ================================================================ 2. cuota por entrega (D21)
DO $$
DECLARE a uuid := 'a0000000-0000-0000-0000-000000000001';
BEGIN
  -- Semana 16-22/11 (L-V laborables). Entrega del martes 17: 1 de 4 dias restantes (mar..vie) -> 8 * 1/4 = 2.
  PERFORM pg_temp.ok(public.cl_delivery_quota_share(a, 8, '2026-11-17', '2026-11-17', '2026-11-16', '2026-11-22') = 2, 'diaria martes');
  -- Entrega sabado (sin dias laborables, no es el ultimo dia) -> 0; domingo (ultimo dia) -> todo lo que falta.
  PERFORM pg_temp.ok(public.cl_delivery_quota_share(a, 8, '2026-11-21', '2026-11-21', '2026-11-16', '2026-11-22') = 0, 'sabado');
  PERFORM pg_temp.ok(public.cl_delivery_quota_share(a, 3, '2026-11-22', '2026-11-22', '2026-11-16', '2026-11-22') = 3, 'domingo = resto');
  -- Martes..lunes: dentro de la semana del lunes 16 solo ese dia: 5 * 1/5 = 1.
  PERFORM pg_temp.ok(public.cl_delivery_quota_share(a, 5, '2026-11-10', '2026-11-16', '2026-11-16', '2026-11-22') = 1, 'cruza semana: lunes');
  PERFORM pg_temp.ok(public.cl_delivery_quota_share(a, 4, '2026-11-10', '2026-11-16', '2026-11-09', '2026-11-15') = 4, 'cruza semana: cierre');
  -- Festivo de la cuenta el miercoles 18: lunes..martes = 2 de 4 dias laborables -> 6 * 2/4 = 3.
  INSERT INTO public.non_working_days (account_id, date, type) VALUES (a, '2026-11-18', 'holiday');
  PERFORM pg_temp.ok(public.cl_delivery_quota_share(a, 6, '2026-11-16', '2026-11-17', '2026-11-16', '2026-11-22') = 3, 'festivo');
  DELETE FROM public.non_working_days WHERE account_id = a AND date = '2026-11-18';
  PERFORM pg_temp.ok(public.cl_delivery_quota_share(a, 0, '2026-11-16', '2026-11-22', '2026-11-16', '2026-11-22') = 0, 'nada que pedir');
  PERFORM pg_temp.ok(public.cl_delivery_quota_share(a, 5, '2026-11-23', '2026-11-24', '2026-11-16', '2026-11-22') = 0, 'fuera de la semana');
END $$;

-- ================================================================ 3. tomar trabajo, arriendo, cursor, compresion
DO $$
DECLARE c jsonb; e text; v_id uuid := 'de000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM pg_temp.ok(public.cl_delivery_worker_claim('token-test-1')->>'action' = 'idle', 'sin entregas: idle');
  -- gzip -> rejected al tomarla, sin pasar por processing.
  PERFORM pg_temp.mk('de000000-0000-0000-0000-0000000000a0', 'f0000000-0000-0000-0000-0000000000a1', '2026-10-27', '2026-11-02', '[]', false, 'gzip');
  c := public.cl_delivery_worker_claim('token-test-1');
  PERFORM pg_temp.ok(c->>'action' = 'rejected' AND c->>'error' = 'CL_COMPRESSION_UNSUPPORTED', 'gzip rechazada: ' || c::text);
  PERFORM pg_temp.ok((SELECT status = 'rejected' AND error = 'CL_COMPRESSION_UNSUPPORTED' FROM public.cl_deliveries
                       WHERE id = 'de000000-0000-0000-0000-0000000000a0'), 'gzip: estado');

  PERFORM pg_temp.mk(v_id::text, 'f0000000-0000-0000-0000-0000000000a1', '2026-11-03', '2026-11-09',
                     jsonb_build_array(pg_temp.r(1, 'X1', '2026-11-04 08:00', 'NBO', 'ADM')));
  c := public.cl_delivery_worker_claim('token-test-1');
  PERFORM pg_temp.ok(c->>'action' = 'load' AND (c->>'delivery_id')::uuid = v_id, 'toma la recibida');
  PERFORM pg_temp.ok(c->'fields' = '["evt","office","svc","trk","ts","weight"]'::jsonb, 'campos permitidos: ' || (c->'fields')::text);
  PERFORM pg_temp.ok((c->'load'->>'offset')::bigint = 0 AND (c->>'max_rows')::int = 60, 'cursor a cero y max_rows');
  PERFORM pg_temp.ok((SELECT status = 'processing' AND (progress->>'attempts')::int = 1 AND processing_started_at IS NOT NULL
                        FROM public.cl_deliveries WHERE id = v_id), 'processing, intento 1');
  PERFORM pg_temp.ok(public.cl_delivery_worker_claim('token-test-2')->>'action' = 'busy', 'otro worker: busy');
  PERFORM pg_temp.ok(public.cl_delivery_worker_claim('token-test-2', 120, now() + interval '10 minutes')->>'action' = 'load',
                     'arriendo caducado: lo toma otro');
  e := pg_temp.raises(format($q$SELECT public.cl_delivery_load_rows(%L, 'token-test-1', 0, '[]', '{"offset":0,"rows":0,"sha_offset":0}')$q$, v_id));
  PERFORM pg_temp.ok(e LIKE '%CL_LEASE_LOST%', 'arriendo perdido: ' || COALESCE(e, 'null'));
  e := pg_temp.raises(format($q$SELECT public.cl_delivery_load_rows(%L, 'token-test-2', 5, '[]', '{"offset":5,"rows":0,"sha_offset":0}')$q$, v_id));
  PERFORM pg_temp.ok(e LIKE '%CL_CURSOR_MISMATCH%', 'cursor distinto: ' || COALESCE(e, 'null'));
  e := pg_temp.raises(format($q$SELECT public.cl_delivery_load_rows(%L, 'token-test-2', 0, %L, '{"offset":10,"rows":2,"sha_offset":10}')$q$,
                             v_id, jsonb_build_array(pg_temp.r(2, 'X', '2026-11-04 08:00', 'NBO'))));
  PERFORM pg_temp.ok(e LIKE '%CL_BAD_REQUEST%', 'filas no consecutivas: ' || COALESCE(e, 'null'));
  e := pg_temp.raises(format($q$SELECT public.cl_delivery_load_rows(%L, 'token-test-2', 0, '[]', '{"offset":10,"rows":0}')$q$, v_id));
  PERFORM pg_temp.ok(e LIKE '%CL_BAD_REQUEST%', 'cursor sin sha_offset: ' || COALESCE(e, 'null'));
  e := pg_temp.raises(format($q$SELECT public.cl_delivery_load_done(%L, 'token-test-2', 0, 'x', 1)$q$, v_id));
  PERFORM pg_temp.ok(e LIKE '%CL_BAD_REQUEST%', 'fin sin haber leido todo: ' || COALESCE(e, 'null'));
  -- M1: no sale de processing con filas en la zona de paso.
  PERFORM public.cl_delivery_load_rows(v_id, 'token-test-2', 0, jsonb_build_array(pg_temp.r(1, 'X1', '2026-11-04 08:00', 'NBO', 'ADM')),
                                       '{"offset":3,"rows":1,"sha_offset":3}');
  e := pg_temp.raises(format($q$UPDATE public.cl_deliveries SET status = 'failed' WHERE id = %L$q$, v_id));
  PERFORM pg_temp.ok(e LIKE '%CL_STAGING_NOT_EMPTY%', 'M1: ' || COALESCE(e, 'null'));
  -- Fallo definitivo del worker -> abort -> el paso de limpieza vacia y deja rejected.
  e := pg_temp.raises(format($q$SELECT public.cl_delivery_load_fail(%L, 'token-test-2', 'not a code', true)$q$, v_id));
  PERFORM pg_temp.ok(e LIKE '%CL_BAD_REQUEST%', 'codigo libre rechazado');
  PERFORM public.cl_delivery_load_fail(v_id, 'token-test-2', 'CL_RECORD_TOO_LONG', true);
  PERFORM pg_temp.ok(public.cl_delivery_worker_claim('token-test-3')->>'action' = 'sql', 'en abort: trabajo de la base');
  PERFORM pg_temp.ok(pg_temp.run() = ARRAY['cleanup','idle'], 'limpieza');
  PERFORM pg_temp.ok((SELECT status = 'rejected' AND error = 'CL_RECORD_TOO_LONG' AND finished_at IS NOT NULL
                        AND progress->>'phase' = 'rejected' FROM public.cl_deliveries WHERE id = v_id), 'rejected tras abort');
  PERFORM pg_temp.ok(pg_temp.staging(v_id) = 0, 'zona de paso vacia');
END $$;

-- ================================================================ 4. sha256 distinto y max_rows
DO $$
DECLARE r jsonb; v1 uuid := 'de000000-0000-0000-0000-000000000002'; v2 uuid := 'de000000-0000-0000-0000-000000000003';
BEGIN
  PERFORM pg_temp.mk(v1::text, 'f0000000-0000-0000-0000-0000000000a1', '2026-11-03', '2026-11-09',
                     jsonb_build_array(pg_temp.r(1, 'X1', '2026-11-04 08:00', 'NBO', 'ADM')));
  r := pg_temp.load(jsonb_build_array(pg_temp.r(1, 'X1', '2026-11-04 08:00', 'NBO', 'ADM')), 1000, 'token-test-1', repeat('0', 64));
  PERFORM pg_temp.ok(r->>'error' = 'CL_SHA256_MISMATCH', 'sha distinto: ' || r::text);
  PERFORM pg_temp.run();
  PERFORM pg_temp.ok((SELECT status = 'rejected' AND error = 'CL_SHA256_MISMATCH' FROM public.cl_deliveries WHERE id = v1), 'rejected por sha');
  PERFORM pg_temp.ok(pg_temp.staging(v1) = 0, 'sha: zona de paso vacia');

  -- max_rows = 60 en el conector F: 61 filas -> rejected CL_TOO_MANY_ROWS (sin insertar el trozo que se pasa).
  PERFORM pg_temp.mk(v2::text, 'f0000000-0000-0000-0000-0000000000a1', '2026-11-03', '2026-11-09',
                     (SELECT jsonb_agg(pg_temp.r(g, 'Y' || g, '2026-11-04 08:00', 'NBO', 'ADM')) FROM generate_series(1, 61) g));
  r := pg_temp.load((SELECT jsonb_agg(pg_temp.r(g, 'Y' || g, '2026-11-04 08:00', 'NBO', 'ADM')) FROM generate_series(1, 61) g), 50);
  PERFORM pg_temp.ok(r->>'error' = 'CL_TOO_MANY_ROWS', 'max_rows: ' || r::text);
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_delivery_rows WHERE delivery_id = v2) = 50, 'solo el primer trozo');
  PERFORM pg_temp.run();
  PERFORM pg_temp.ok((SELECT status = 'rejected' AND error = 'CL_TOO_MANY_ROWS' FROM public.cl_deliveries WHERE id = v2), 'rejected por filas');
  PERFORM pg_temp.ok(pg_temp.staging(v2) = 0, 'max_rows: zona de paso vacia');
END $$;

-- ================================================================ 5. entrega completa martes 10/11 .. lunes 16/11
-- W46 (9-15/11): I1-I6 validos (poblacion 6, cuota 4: la entrega cierra la semana).
-- W47 (16-22/11): I7, I8 y I16 (con una lectura en KSM, ciudad C3) llegan el lunes 16 (cuota 5 * 1/5 = 1).
-- Rechazados: I9 no_end, I10 no_start, I11 end_out_of_period, I12 unknown_product, I13 start_after_end,
-- I14 no_stratum (C1 -> C3 sin cuota), I15 already_sampled, I17 product_mismatch (producto PR2 sin plan),
-- I18 same_reading (una sola lectura en KSM 'both' -> sin cuota pero antes same_reading).
-- Por fila: bad_record, bad_value (item_id de 201), missing_field, bad_timestamp, unknown_reading_point (XXX en I1).
CREATE TEMP TABLE t_rows ON COMMIT DROP AS
SELECT jsonb_agg(x.j ORDER BY x.n) AS rows FROM (
  SELECT row_number() OVER (ORDER BY o) AS n, jsonb_set(j, '{n}', to_jsonb(row_number() OVER (ORDER BY o))) AS j
    FROM (VALUES
      (1,  pg_temp.r(0, 'I1', '2026-11-10 08:00', 'NBO', 'ADM', 'EXP', '{"weight": 2, "name": "Juan Perez"}')),
      (2,  pg_temp.r(0, 'I1', '2026-11-10 20:00', 'HUB')),
      (3,  pg_temp.r(0, 'I1', '2026-11-11 01:00', 'XXX')),
      (4,  pg_temp.r(0, 'I1', '2026-11-12 10:00', 'MBA', 'DLV', 'EXP', '{"weight": 3}')),
      (5,  pg_temp.r(0, 'I2', '2026-11-10 09:00', 'NBO', 'ADM')),
      (6,  pg_temp.r(0, 'I2', '2026-11-13 09:00', 'MBA')),
      (7,  pg_temp.r(0, 'I3', '2026-11-11 09:00', 'NBO', 'ADM')),
      (8,  pg_temp.r(0, 'I3', '2026-11-14 09:00', 'MBA')),
      (9,  pg_temp.r(0, 'I4', '2026-11-11 09:00', 'NBO', 'ADM')),
      (10, pg_temp.r(0, 'I4', '2026-11-15 22:00', 'MBA')),
      (11, pg_temp.r(0, 'I5', '2026-11-09 09:00', 'NBO', 'ADM')),
      (12, pg_temp.r(0, 'I5', '2026-11-10 09:00', 'MBA')),
      (13, pg_temp.r(0, 'I6', '2026-11-12 09:00', 'NBO', 'ADM')),
      (14, pg_temp.r(0, 'I6', '2026-11-13 09:00', 'MBA')),
      (15, pg_temp.r(0, 'I7', '2026-11-13 09:00', 'NBO', 'ADM')),
      (16, pg_temp.r(0, 'I7', '2026-11-16 09:00', 'MBA')),
      (17, pg_temp.r(0, 'I8', '2026-11-14 09:00', 'NBO', 'ADM')),
      (18, pg_temp.r(0, 'I8', '2026-11-16 23:30', 'MBA')),
      (19, pg_temp.r(0, 'I16', '2026-11-14 09:00', 'NBO', 'ADM')),
      (20, pg_temp.r(0, 'I16', '2026-11-15 09:00', 'KSM')),
      (21, pg_temp.r(0, 'I16', '2026-11-16 12:00', 'MBA')),
      (22, pg_temp.r(0, 'I9', '2026-11-12 09:00', 'NBO', 'ADM')),
      (23, pg_temp.r(0, 'I10', '2026-11-12 09:00', 'MBA')),
      (24, pg_temp.r(0, 'I11', '2026-11-14 09:00', 'NBO', 'ADM')),
      (25, pg_temp.r(0, 'I11', '2026-11-17 00:30', 'MBA')),
      (26, pg_temp.r(0, 'I12', '2026-11-12 09:00', 'NBO', 'ADM', 'ZZZ')),
      (27, pg_temp.r(0, 'I12', '2026-11-13 09:00', 'MBA')),
      (28, pg_temp.r(0, 'I13', '2026-11-13 09:00', 'NBO', 'ADM')),
      (29, pg_temp.r(0, 'I13', '2026-11-12 09:00', 'MBA')),
      (30, pg_temp.r(0, 'I14', '2026-11-12 09:00', 'NBO', 'ADM')),
      (31, pg_temp.r(0, 'I14', '2026-11-13 09:00', 'KSM')),
      (32, pg_temp.r(0, 'I15', '2026-11-12 09:00', 'NBO', 'ADM')),
      (33, pg_temp.r(0, 'I15', '2026-11-13 09:00', 'MBA')),
      (34, pg_temp.r(0, 'I17', '2026-11-12 09:00', 'NBO', 'ADM', 'PR2')),
      (35, pg_temp.r(0, 'I17', '2026-11-13 09:00', 'MBA', NULL, 'PR2')),
      (36, pg_temp.r(0, 'I18', '2026-11-13 09:00', 'KSM')),
      (37, jsonb_build_object('n', 0, 'r', NULL)),
      (38, pg_temp.r(0, repeat('Z', 201), '2026-11-13 09:00', 'MBA')),
      (39, pg_temp.r(0, 'I19', NULL, 'MBA')),
      (40, pg_temp.r(0, 'I19', 'not a date', 'MBA'))
    ) v(o, j)) x(n, j);
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','PR2','Prod2',48);

DO $$
DECLARE
  v_id uuid := 'de000000-0000-0000-0000-000000000010';
  v_rows jsonb := (SELECT rows FROM t_rows);
  r jsonb; v_phases text[]; v_seed46 text; v_seed47 text; v_exp46 text[]; v_exp47 text[]; v_got text[];
  d public.cl_deliveries;
BEGIN
  PERFORM pg_temp.mk(v_id::text, 'f0000000-0000-0000-0000-0000000000a1', '2026-11-10', '2026-11-16', v_rows);
  r := pg_temp.load(v_rows, 15);
  PERFORM pg_temp.ok(r->>'phase' = 'resolve' AND (r->>'rows_total')::int = 40, 'carga completa: ' || r::text);
  -- Lista cerrada: el campo personal 'name' no llega; extra solo 'weight'.
  PERFORM pg_temp.ok((SELECT extra = '{"weight": 2}'::jsonb FROM public.cl_delivery_rows WHERE delivery_id = v_id AND row_no = 1),
                     'extra solo campos permitidos');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_delivery_rows t WHERE t.delivery_id = v_id
                                   AND (t.extra::text LIKE '%Juan%' OR t.item_id LIKE '%Juan%')), 'sin datos personales');
  PERFORM pg_temp.ok(public.cl_delivery_worker_claim('token-test-9')->>'action' = 'sql', 'fase de base: el worker no hace nada');
  PERFORM pg_temp.ok((public.cl_delivery_summary(v_id))->>'phase' = 'resolve'
                     AND ((public.cl_delivery_summary(v_id))->>'rows_loaded')::int = 40, 'resumen con avance');

  -- Trozos pequenos: resolve de 10 filas, items de 10 filas.
  v_phases := pg_temp.run(10);
  PERFORM pg_temp.ok(v_phases[1:4] = ARRAY['resolve','resolve','resolve','resolve'] AND 'items' = ANY (v_phases)
                     AND v_phases[array_length(v_phases, 1)] = 'idle', 'fases: ' || v_phases::text);
  SELECT * INTO d FROM public.cl_deliveries WHERE id = v_id;
  PERFORM pg_temp.ok(d.status = 'processed' AND d.error IS NULL AND d.finished_at IS NOT NULL AND d.progress->>'phase' = 'done',
                     'processed: ' || d.status || ' ' || COALESCE(d.error, ''));
  PERFORM pg_temp.ok(pg_temp.staging(v_id) = 0, 'R25: zona de paso vacia tras procesar');
  PERFORM pg_temp.ok(d.rows_total = 40 AND d.rows_rejected = 6, 'filas: ' || d.rows_total || '/' || d.rows_rejected);
  PERFORM pg_temp.ok(d.rejected_reasons->'rows' = '{"bad_record":1,"bad_value":1,"missing_field":1,"bad_timestamp":1,"unknown_product":1,"unknown_reading_point":1}'::jsonb,
                     'motivos por fila: ' || (d.rejected_reasons->'rows')::text);
  PERFORM pg_temp.ok(d.rejected_reasons->'shipments' = '{"no_end":1,"no_start":2,"end_out_of_period":1,"unknown_product":1,"start_after_end":1,"no_stratum":1,"already_sampled":1,"product_mismatch":1,"same_reading":1}'::jsonb,
                     'motivos por envio: ' || (d.rejected_reasons->'shipments')::text);
  -- 19 envios (I1..I19; I19 sin lecturas validas -> no_start); 9 validos; 5 elegidos.
  PERFORM pg_temp.ok(d.shipments_total = 19 AND d.shipments_valid = 9 AND d.shipments_drawn = 5,
                     'envios: ' || d.shipments_total || '/' || d.shipments_valid || '/' || d.shipments_drawn);

  -- Estratos: W46 6 / 4 / 4 y W47 3 / 1 / 1; W48 no se solapa.
  PERFORM pg_temp.ok((SELECT population = 6 AND quota_for_delivery = 4 AND selected = 4 FROM public.cl_delivery_strata
                       WHERE delivery_id = v_id AND quota_id = '91000000-0000-0000-0000-000000000046'), 'estrato W46');
  PERFORM pg_temp.ok((SELECT population = 3 AND quota_for_delivery = 1 AND selected = 1 FROM public.cl_delivery_strata
                       WHERE delivery_id = v_id AND quota_id = '91000000-0000-0000-0000-000000000047'), 'estrato W47');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_delivery_strata WHERE delivery_id = v_id) = 2, 'solo cuotas solapadas');

  -- Sorteo determinista md5(seed || item_id).
  SELECT seed INTO v_seed46 FROM public.cl_delivery_strata WHERE delivery_id = v_id AND quota_id = '91000000-0000-0000-0000-000000000046';
  SELECT seed INTO v_seed47 FROM public.cl_delivery_strata WHERE delivery_id = v_id AND quota_id = '91000000-0000-0000-0000-000000000047';
  SELECT array_agg(x ORDER BY x) INTO v_exp46 FROM (SELECT x FROM unnest(ARRAY['I1','I2','I3','I4','I5','I6']) x
                                                     ORDER BY md5(v_seed46 || x), x COLLATE "C" LIMIT 4) z;
  SELECT array_agg(x ORDER BY x) INTO v_exp47 FROM (SELECT x FROM unnest(ARRAY['I7','I8','I16']) x
                                                     ORDER BY md5(v_seed47 || x), x COLLATE "C" LIMIT 1) z;
  SELECT array_agg(item_id ORDER BY item_id) INTO v_got FROM public.cl_samples
   WHERE delivery_id = v_id AND quota_id = '91000000-0000-0000-0000-000000000046';
  PERFORM pg_temp.ok(v_got = v_exp46, 'sorteo W46: ' || v_got::text || ' vs ' || v_exp46::text);
  SELECT array_agg(item_id ORDER BY item_id) INTO v_got FROM public.cl_samples
   WHERE delivery_id = v_id AND quota_id = '91000000-0000-0000-0000-000000000047';
  PERFORM pg_temp.ok(v_got = v_exp47, 'sorteo W47: ' || v_got::text || ' vs ' || v_exp47::text);

  -- Muestras: ciudades reales, lecturas de inicio/fin, one_db con equivalencia, posible mal encaminado solo I16.
  PERFORM pg_temp.ok((SELECT bool_and(s.plan_id = '90000000-0000-0000-0000-0000000000a1' AND s.batch_id IS NULL
                                      AND s.origin_city_id = 'c1000000-0000-0000-0000-000000000001'
                                      AND s.destination_city_id = 'c2000000-0000-0000-0000-000000000002'
                                      AND s.start_reader_id = 'ad000000-0000-0000-0000-000000000001'
                                      AND s.end_reader_id = 'ad000000-0000-0000-0000-000000000003'
                                      AND s.possible_misrouting = (s.item_id = 'I16'))
                        FROM public.cl_samples s WHERE s.delivery_id = v_id), 'muestras');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.one_db o JOIN public.cl_samples s ON s.id = o.cl_sample_id
                       WHERE s.delivery_id = v_id AND o.source = 'carrier' AND o.equivalence_hours = 12
                         AND o.on_time_delivery IS NOT NULL) = 5, 'one_db con equivalencia y en plazo');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_sample_scans sc JOIN public.cl_samples s ON s.id = sc.sample_id
                                  WHERE s.delivery_id = v_id AND sc.reader_id = 'ad000000-0000-0000-0000-000000000002'),
                     'sin lecturas intermedias (sin diagnostico)');
  IF 'I1' = ANY (v_exp46) THEN
    PERFORM pg_temp.ok((SELECT s.extra = '{"weight": 3}'::jsonb AND (SELECT array_agg(sc.role ORDER BY sc.scan_at) FROM public.cl_sample_scans sc
                                                                       WHERE sc.sample_id = s.id) = ARRAY['start','end']
                          FROM public.cl_samples s WHERE s.delivery_id = v_id AND s.item_id = 'I1'), 'I1: extra y papeles');
  END IF;
  IF 'I16' = ANY (v_exp47) THEN
    PERFORM pg_temp.ok((SELECT array_agg(sc.role ORDER BY sc.scan_at) FROM public.cl_sample_scans sc
                         JOIN public.cl_samples s ON s.id = sc.sample_id WHERE s.delivery_id = v_id AND s.item_id = 'I16')
                       = ARRAY['start','end','end'], 'I16: KSM (both) tras el inicio cuenta como fin');
  END IF;

  -- Cuotas: W46 cumplida (liquidada por cerrar la semana), W47 sigue pending con 1 obtenida.
  PERFORM pg_temp.ok((SELECT status = 'fulfilled' AND samples_obtained = 4 FROM public.cl_plan_quotas
                       WHERE id = '91000000-0000-0000-0000-000000000046'), 'W46 fulfilled');
  PERFORM pg_temp.ok((SELECT status = 'pending' AND samples_obtained = 1 FROM public.cl_plan_quotas
                       WHERE id = '91000000-0000-0000-0000-000000000047'), 'W47 pending');

  -- Alertas de la entrega.
  PERFORM pg_temp.ok((SELECT details->'values' FROM public.cl_alerts WHERE delivery_id = v_id AND alert_type = 'unknown_product')
                     = '["ZZZ"]'::jsonb, 'alerta unknown_product');
  PERFORM pg_temp.ok((SELECT details->'points' FROM public.cl_alerts WHERE delivery_id = v_id AND alert_type = 'unknown_reading_point')
                     = '[{"mode_ref": null, "place_ref": "XXX"}]'::jsonb, 'alerta unknown_reading_point');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM public.cl_alerts WHERE delivery_id = v_id AND alert_type = 'rejected_ratio'),
                     'alerta rejected_ratio');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM public.cl_alerts WHERE delivery_id = v_id AND alert_type = 'possible_misrouting')
                     = ('I16' = ANY (v_exp47)), 'alerta possible_misrouting solo si I16 elegido');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_alerts WHERE delivery_id = v_id AND alert_type = 'insufficient_candidates'),
                     'sin insufficient_candidates');
  PERFORM pg_temp.ok((SELECT bool_and(account_id = 'a0000000-0000-0000-0000-000000000001') FROM public.cl_alerts WHERE delivery_id = v_id),
                     'alertas de la cuenta');
  -- Aislamiento: ningun punto de la otra cuenta.
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_sample_scans sc JOIN public.cl_samples s ON s.id = sc.sample_id
                                  WHERE s.delivery_id = v_id AND sc.reader_id = 'ad000000-0000-0000-0000-000000000099'),
                     'sin puntos de otra cuenta');
  -- Una entrega procesada no se vuelve a tomar; el worker queda idle.
  PERFORM pg_temp.ok(public.cl_delivery_worker_claim('token-test-1')->>'action' = 'idle', 'idle tras procesar');
END $$;

-- ================================================================ 6. siguiente entrega: cierra W47 con deficit
-- 17-23/11: solo I20 e I21 validos en W47 (cuota = 5 - 1 = 4, poblacion 2): 2 elegidos, deficit 2 -> W48 (pending,
-- mismo mes) recibe 2 y W47 queda carried; alerta insufficient_candidates. W48 (23-29) se solapa el 23: 0 envios.
DO $$
DECLARE v_id uuid := 'de000000-0000-0000-0000-000000000011'; v_rows jsonb; d public.cl_deliveries; v_used text;
BEGIN
  SELECT min(item_id) INTO v_used FROM public.cl_samples WHERE delivery_id = 'de000000-0000-0000-0000-000000000010';
  v_rows := jsonb_build_array(
    pg_temp.r(1, 'I20', '2026-11-17 09:00', 'NBO', 'ADM'), pg_temp.r(2, 'I20', '2026-11-18 09:00', 'MBA'),
    pg_temp.r(3, 'I21', '2026-11-19 09:00', 'NBO', 'ADM'), pg_temp.r(4, 'I21', '2026-11-20 09:00', 'MBA'),
    pg_temp.r(5, v_used, '2026-11-19 09:00', 'NBO', 'ADM'), pg_temp.r(6, v_used, '2026-11-20 09:00', 'MBA'));
  PERFORM pg_temp.mk(v_id::text, 'f0000000-0000-0000-0000-0000000000a1', '2026-11-17', '2026-11-23', v_rows);
  PERFORM pg_temp.load(v_rows);
  PERFORM pg_temp.run();
  SELECT * INTO d FROM public.cl_deliveries WHERE id = v_id;
  PERFORM pg_temp.ok(d.status = 'processed' AND d.shipments_drawn = 2, 'segunda entrega');
  PERFORM pg_temp.ok((SELECT population = 2 AND quota_for_delivery = 4 AND selected = 2 FROM public.cl_delivery_strata
                       WHERE delivery_id = v_id AND quota_id = '91000000-0000-0000-0000-000000000047'), 'W47: cuota = resto');
  PERFORM pg_temp.ok((SELECT status = 'carried' AND samples_obtained = 3 FROM public.cl_plan_quotas
                       WHERE id = '91000000-0000-0000-0000-000000000047'), 'W47 carried');
  PERFORM pg_temp.ok((SELECT status = 'pending' AND samples_carried_in = 2 FROM public.cl_plan_quotas
                       WHERE id = '91000000-0000-0000-0000-000000000048'), 'W48 recibe el deficit');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM public.cl_alerts WHERE delivery_id = v_id AND alert_type = 'insufficient_candidates'
                               AND quota_id = '91000000-0000-0000-0000-000000000047'), 'alerta insufficient_candidates');
  -- Un elegido de la primera entrega que vuelve a llegar -> already_sampled.
  PERFORM pg_temp.ok(d.rejected_reasons->'shipments' = '{"already_sampled": 1}'::jsonb, 'already_sampled entre entregas');
END $$;

-- ================================================================ 7. entrega de prueba (is_test)
DO $$
DECLARE v_id uuid := 'de000000-0000-0000-0000-000000000020'; v_rows jsonb; d public.cl_deliveries;
BEGIN
  v_rows := jsonb_build_array(
    pg_temp.r(1, 'T1', '2026-11-10 09:00', 'NBO', 'ADM'), pg_temp.r(2, 'T1', '2026-11-11 09:00', 'MBA'),
    pg_temp.r(3, 'T2', '2026-11-10 09:00', 'NBO', 'ADM'));
  PERFORM pg_temp.mk(v_id::text, 'f0000000-0000-0000-0000-0000000000a2', '2026-11-10', '2026-11-16', v_rows, true);
  PERFORM pg_temp.load(v_rows);
  PERFORM pg_temp.ok(NOT ('draw' = ANY (pg_temp.run())), 'prueba: sin sorteo');
  SELECT * INTO d FROM public.cl_deliveries WHERE id = v_id;
  PERFORM pg_temp.ok(d.status = 'processed' AND d.shipments_total = 2 AND d.shipments_valid = 1 AND d.shipments_drawn = 0,
                     'prueba: validada y contada');
  PERFORM pg_temp.ok((SELECT population = 1 AND selected = 0 FROM public.cl_delivery_strata
                       WHERE delivery_id = v_id AND quota_id = '91000000-0000-0000-0000-0000000000f6'), 'prueba: poblacion');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_samples WHERE delivery_id = v_id), 'prueba: sin muestras');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_alerts WHERE delivery_id = v_id), 'prueba: sin alertas');
  PERFORM pg_temp.ok((SELECT status = 'pending' AND samples_obtained = 0 FROM public.cl_plan_quotas
                       WHERE id = '91000000-0000-0000-0000-0000000000f6'), 'prueba: cuota sin tocar');
  PERFORM pg_temp.ok(pg_temp.staging(v_id) = 0, 'prueba: zona de paso vacia');
END $$;

-- ================================================================ 8. reanudar: caida (zona de paso perdida) y fallo a mitad
-- Plan aparte (P2, conector F2) para repetir la primera entrega con otra semilla y mismas reglas.
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status, emit_days, emit_hour) VALUES
  ('f0000000-0000-0000-0000-0000000000a3','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed F2','active','{2}',3);
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000a3','a0000000-0000-0000-0000-000000000001','P2','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',6,'2026-11-02','2026-11-29','active','f0000000-0000-0000-0000-0000000000a3');
INSERT INTO public.cl_plan_quotas (id, account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned) VALUES
  ('91000000-0000-0000-0000-0000000000e6','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a3','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,46,'2026-11-09','2026-11-15',5);

DO $$
DECLARE
  v_id uuid := 'de000000-0000-0000-0000-000000000030';
  v_rows jsonb;
  v text; v_seed text; v_exp text[]; v_got text[]; i int := 0; d public.cl_deliveries;
BEGIN
  -- 8 envios validos de W46 (J1..J8), cuota 5.
  SELECT jsonb_agg(x ORDER BY (x->>'n')::int) INTO v_rows FROM (
    SELECT pg_temp.r(2 * g - 1, 'J' || g, '2026-11-10 09:00', 'NBO', 'ADM') AS x FROM generate_series(1, 8) g
    UNION ALL SELECT pg_temp.r(2 * g, 'J' || g, '2026-11-12 09:00', 'MBA') FROM generate_series(1, 8) g) y;
  PERFORM pg_temp.mk(v_id::text, 'f0000000-0000-0000-0000-0000000000a3', '2026-11-10', '2026-11-16', v_rows);
  PERFORM pg_temp.load(v_rows, 5);
  -- Caida simulada durante resolve: la zona de paso UNLOGGED queda vacia.
  PERFORM pg_temp.ok(public.cl_process_delivery(NULL, 4) = 'resolve', 'un trozo de resolve');
  TRUNCATE public.cl_delivery_rows, public.cl_delivery_items;
  PERFORM pg_temp.ok(public.cl_process_delivery(NULL, 4) = 'reset', 'detecta la zona perdida');
  SELECT * INTO d FROM public.cl_deliveries WHERE id = v_id;
  PERFORM pg_temp.ok(d.status = 'processing' AND d.progress->>'phase' = 'load' AND (d.progress->'load'->>'offset')::int = 0
                     AND (d.progress->>'staging_lost')::int = 1 AND d.rows_total IS NULL, 'vuelve a cargar desde el byte 0');
  -- Caida durante la carga: el worker lo detecta al tomar (falta la ultima fila confirmada).
  PERFORM pg_temp.ok(public.cl_delivery_worker_claim('token-test-4')->>'action' = 'load', 'claim tras reset');
  PERFORM public.cl_delivery_load_rows(v_id, 'token-test-4', 0,
            (SELECT jsonb_agg(e) FROM jsonb_array_elements(v_rows) e WHERE (e->>'n')::int <= 3),
            '{"offset": 7, "rows": 3, "sha_offset": 7}');
  TRUNCATE public.cl_delivery_rows;
  PERFORM pg_temp.ok((public.cl_delivery_worker_claim('token-test-5', 120, now() + interval '10 minutes')->'load'->>'offset')::int = 0,
                     'claim tras caida en la carga: cursor a cero');
  PERFORM pg_temp.load(v_rows, 5, 'token-test-5');

  -- Fallo a mitad del paso a muestras (1 envio por paso con p_chunk = 200): tras 2 muestras.
  LOOP
    v := public.cl_process_delivery(NULL, 200);
    i := i + 1;
    EXIT WHEN v = 'transfer' AND (SELECT count(*) FROM public.cl_samples WHERE delivery_id = v_id) = 2;
    PERFORM pg_temp.ok(i < 100 AND v NOT IN ('idle','load'), 'llega a transfer: ' || v);
  END LOOP;
  PERFORM public.cl_process_delivery_failed('XX000', 'boom with item J3 inside');
  PERFORM pg_temp.run();
  SELECT * INTO d FROM public.cl_deliveries WHERE id = v_id;
  PERFORM pg_temp.ok(d.status = 'failed' AND d.error = 'CL_PROCESSING_ERROR XX000' AND pg_temp.staging(v_id) = 0,
                     'failed, sin texto libre y zona vacia: ' || d.status || ' ' || COALESCE(d.error, ''));
  PERFORM pg_temp.ok((SELECT samples_obtained FROM public.cl_plan_quotas WHERE id = '91000000-0000-0000-0000-0000000000e6') = 2,
                     'dos muestras ya pasadas');
  -- Reintento automatico (5 min despues): mismo sorteo (semilla y cuota guardadas), sin duplicados.
  PERFORM pg_temp.ok(public.cl_delivery_worker_claim('token-test-6')->>'action' = 'idle', 'espera antes de reintentar');
  PERFORM pg_temp.ok((public.cl_delivery_worker_claim('token-test-6', 120, now() + interval '10 minutes')->>'action') = 'load',
                     'reintento');
  PERFORM pg_temp.ok((SELECT (progress->>'attempts')::int FROM public.cl_deliveries WHERE id = v_id) = 2, 'intento 2');
  PERFORM pg_temp.load(v_rows, 5, 'token-test-6');
  PERFORM pg_temp.run();
  SELECT * INTO d FROM public.cl_deliveries WHERE id = v_id;
  PERFORM pg_temp.ok(d.status = 'processed' AND d.shipments_drawn = 5 AND d.error IS NULL, 'processed al reintentar');
  SELECT seed INTO v_seed FROM public.cl_delivery_strata WHERE delivery_id = v_id;
  SELECT array_agg(x ORDER BY x) INTO v_exp FROM (SELECT 'J' || g AS x FROM generate_series(1, 8) g
                                                   ORDER BY md5(v_seed || 'J' || g), ('J' || g) COLLATE "C" LIMIT 5) z;
  SELECT array_agg(item_id ORDER BY item_id) INTO v_got FROM public.cl_samples WHERE delivery_id = v_id AND status = 'active';
  PERFORM pg_temp.ok(v_got = v_exp, 'mismo sorteo tras el fallo: ' || v_got::text || ' vs ' || v_exp::text);
  PERFORM pg_temp.ok((SELECT samples_obtained = 5 AND status = 'fulfilled' FROM public.cl_plan_quotas
                       WHERE id = '91000000-0000-0000-0000-0000000000e6'), 'cuota sin dobles');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.one_db o JOIN public.cl_samples s ON s.id = o.cl_sample_id
                       WHERE s.delivery_id = v_id) = 5, 'one_db sin dobles');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_delivery_strata WHERE delivery_id = v_id) = 1, 'un estrato');
END $$;

-- ================================================================ 9. retencion de ficheros (M3) y arranque del worker
DO $$
DECLARE l jsonb; v_old uuid := 'de000000-0000-0000-0000-000000000040';
BEGIN
  -- Rechazadas hace mas de 1 hora: se borran; procesadas: tras file_retention_days (30); objeto huerfano: tras 1 dia.
  UPDATE public.cl_deliveries SET finished_at = now() - interval '2 hours' WHERE status = 'rejected';
  INSERT INTO storage.objects (bucket_id, name, metadata, created_at)
  VALUES ('cl-deliveries', 'a0000000-0000-0000-0000-000000000001/orphan.jsonl', '{"size": 1}', now() - interval '2 days'),
         ('cl-deliveries', 'a0000000-0000-0000-0000-000000000001/fresh.jsonl', '{"size": 1}', now());
  l := public.cl_delivery_sweep_list();
  PERFORM pg_temp.ok(l @> to_jsonb(ARRAY['a0000000-0000-0000-0000-000000000001/orphan.jsonl'])
                     AND NOT l @> to_jsonb(ARRAY['a0000000-0000-0000-0000-000000000001/fresh.jsonl']), 'huerfanos tras 1 dia');
  PERFORM pg_temp.ok((SELECT bool_and(l @> to_jsonb(ARRAY[d.file_path])) FROM public.cl_deliveries d WHERE d.status = 'rejected'),
                     'rechazadas en la lista');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_deliveries d WHERE d.status = 'processed' AND l @> to_jsonb(ARRAY[d.file_path])),
                     'procesadas recientes se conservan');
  PERFORM pg_temp.ok(public.cl_delivery_sweep_list(100, now() + interval '31 days')
                     @> to_jsonb(ARRAY['a0000000-0000-0000-0000-000000000001/f0000000-0000-0000-0000-0000000000a1/de000000-0000-0000-0000-000000000010.jsonl']),
                     'procesada tras la retencion');
  PERFORM pg_temp.ok(public.cl_delivery_sweep_done(ARRAY(SELECT jsonb_array_elements_text(l))) =
                     (SELECT count(*) FROM public.cl_deliveries WHERE status = 'rejected'), 'marca file_deleted_at');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_deliveries WHERE status = 'rejected' AND file_deleted_at IS NULL),
                     'rechazadas borradas');
  PERFORM pg_temp.ok(NOT public.cl_delivery_sweep_list() @> to_jsonb(ARRAY[(SELECT file_path FROM public.cl_deliveries
                       WHERE id = 'de000000-0000-0000-0000-0000000000a0')]), 'ya borradas no vuelven');

  -- Subida abandonada (pending_upload > 7 dias) -> rejected CL_UPLOAD_EXPIRED. Sin secretos en Vault no llama.
  INSERT INTO public.cl_deliveries (id, account_id, feed_id, period_start, period_end, source, format, compression,
                                    file_path, sha256, created_at)
  VALUES (v_old, 'a0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-0000000000a1', '2026-10-06', '2026-10-12',
          'api', 'jsonl', 'none', 'a0000000-0000-0000-0000-000000000001/x/old.jsonl', repeat('a', 64), now() - interval '8 days');
  PERFORM pg_temp.ok(public.cl_delivery_kick_worker() = false, 'sin Vault no llama');
  PERFORM pg_temp.ok((SELECT status = 'rejected' AND error = 'CL_UPLOAD_EXPIRED' FROM public.cl_deliveries WHERE id = v_old),
                     'subida caducada');
END $$;

ROLLBACK;
