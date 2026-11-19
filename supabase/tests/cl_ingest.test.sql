-- Carrier Link fase 1, tarea 7: entrada del lote (equivalencias, resolucion de puntos y validacion).
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.sqlstate_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE; END $$;

CREATE OR REPLACE FUNCTION pg_temp.errmsg_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLERRM; END $$;

-- Una lectura con los nombres de campo del carrier (y dos campos no mapeados: uno permitido y uno personal).
CREATE OR REPLACE FUNCTION pg_temp.rd(p_trk text, p_svc text, p_ts text, p_office text, p_evt text) RETURNS jsonb
LANGUAGE sql AS $$
  SELECT jsonb_build_object('trk', p_trk, 'svc', p_svc, 'ts', p_ts, 'office', p_office, 'evt', p_evt,
                            'weight', '1.2', 'recipient_name', 'Juan Secreto')
$$;

CREATE OR REPLACE FUNCTION pg_temp.mk(p_batch text, p_rows jsonb, p_method text DEFAULT 'uniform_random_within_stratum',
                                      p_pop integer DEFAULT 48, p_stratum text DEFAULT '91000000-0000-0000-0000-0000000000b1')
RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('demand_id', current_setting('t.demand'), 'batch_id', p_batch,
           'strata', jsonb_build_array(jsonb_build_object('stratum_id', p_stratum, 'population_size', p_pop,
                                                          'selection_method', p_method, 'rows', p_rows)))
$$;

CREATE OR REPLACE FUNCTION pg_temp.rows_main() RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_array(
    pg_temp.rd('A1',       'EXP', '20/10/2026 09:14', 'NBO', 'ADM'),
    pg_temp.rd('A1',       'EXP', '20/10/2026 12:00', 'XYZ', 'ADM'),   -- lugar sin punto: se guarda rechazada
    pg_temp.rd('A1',       'EXP', '21/10/2026 10:00', 'MBA', 'DLV'),
    pg_temp.rd('00-12 34', 'EXP', '21/10/2026 08:00', 'NBO', 'ADM'),
    pg_temp.rd('00-12 34', 'EXP', '21/10/2026 09:00', 'NBO', 'XXX'),   -- punto "cualquier modo" (intermedio)
    pg_temp.rd('00-12 34', 'EXP', '23/10/2026 12:00', 'MBA', 'DLV'),
    pg_temp.rd('A3',       'EXP', '21/10/2026 08:00', 'NBO', 'ADM'),   -- sin fin
    pg_temp.rd('A4',       'EXP', '24/10/2026 08:00', 'NBO', 'ADM'),
    pg_temp.rd('A4',       'EXP', '26/10/2026 01:00', 'MBA', 'DLV'),   -- 25/10 22:00Z, pero 26/10 en Nairobi
    pg_temp.rd('A5',       'ZZZ', '21/10/2026 08:00', 'NBO', 'ADM'),   -- producto desconocido
    pg_temp.rd('A5',       'ZZZ', '22/10/2026 08:00', 'MBA', 'DLV'))
$$;

BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

UPDATE public.accounts SET timezone = 'Africa/Nairobi' WHERE id = 'a0000000-0000-0000-0000-000000000001';
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001'),
  ('d2000000-0000-0000-0000-0000000000c2','a0000000-0000-0000-0000-000000000001','PC2','Center 2','City2','c2000000-0000-0000-0000-000000000002');
-- NBO tiene un punto especifico (ADM, origen) y un punto "cualquier modo" (intermedio); MBA solo "cualquier modo" (destino).
INSERT INTO public.readers (id, account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role) VALUES
  ('ad000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','NBO ADM','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','NBO','ADM','origin'),
  ('ad000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','NBO any','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','NBO',NULL,'none'),
  ('ad000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-0000000000c2','MBA any','Exit','carrier_scan','ca000000-0000-0000-0000-000000000001','MBA',NULL,'destination'),
  -- KSM: "cualquier modo" de origen y un punto especifico intermedio (D4: el especifico manda).
  ('ad000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','KSM any','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','KSM',NULL,'origin'),
  ('ad000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','KSM SRT','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','KSM','SRT','none'),
  -- NBO BTH: punto de inicio y fin (ruta intraurbana City1 -> City1).
  ('ad000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','NBO BTH','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','NBO','BTH','both');
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status) VALUES
  ('f0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed A1','active'),
  ('f0000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed A2','active');
INSERT INTO public.cl_field_mappings (account_id, carrier_id, standard_field, carrier_field, format, timezone) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','item_id','trk',NULL,NULL),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','product','svc',NULL,NULL),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','scan_at','ts','DD/MM/YYYY HH24:MI','Africa/Nairobi'),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','place_ref','office',NULL,NULL),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','mode_ref','evt',NULL,NULL);
INSERT INTO public.cl_value_mappings (account_id, carrier_id, kind, carrier_value, onems_value) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','product','EXP','PR');
INSERT INTO public.cl_extra_fields (account_id, carrier_id, carrier_field) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','weight');
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','P1','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',2,'2026-10-19','2026-10-25','active','f0000000-0000-0000-0000-0000000000a1');
INSERT INTO public.cl_plan_quotas (id, account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned) VALUES
  ('91000000-0000-0000-0000-0000000000b1','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,43,'2026-10-19','2026-10-25',2),
  ('91000000-0000-0000-0000-0000000000b2','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','c1000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001',2026,43,'2026-10-19','2026-10-25',2);
SELECT set_config('t.demand', public.cl_build_demand('90000000-0000-0000-0000-0000000000a1',
  ARRAY['91000000-0000-0000-0000-0000000000b1','91000000-0000-0000-0000-0000000000b2']::uuid[])::text, true);

-- 1. Permisos.
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT prosecdef FROM pg_proc WHERE oid = 'public.cl_ingest_batch(uuid,jsonb,boolean)'::regprocedure), 'SECURITY DEFINER');
  PERFORM pg_temp.ok(has_function_privilege('service_role','public.cl_ingest_batch(uuid,jsonb,boolean)','EXECUTE'), 'service_role ejecuta');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated','public.cl_ingest_batch(uuid,jsonb,boolean)','EXECUTE'), 'authenticated no ejecuta');
  PERFORM pg_temp.ok(NOT has_function_privilege('anon','public.cl_ingest_batch(uuid,jsonb,boolean)','EXECUTE'), 'anon no ejecuta');
  PERFORM pg_temp.ok(NOT has_function_privilege('service_role','public.cl_parse_scan_at(text,text,text)','EXECUTE'), 'helper interno');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated','public.cl_parse_scan_at(text,text,text)','EXECUTE'), 'helper interno (auth)');
END $$;

-- 2. Conversion de horas (zona de la lectura) sin cambiar la zona de la sesion.
DO $$
DECLARE v_tz text := current_setting('TimeZone');
BEGIN
  PERFORM pg_temp.ok(public.cl_parse_scan_at('20/10/2026 09:14', 'DD/MM/YYYY HH24:MI', 'Africa/Nairobi') = TIMESTAMPTZ '2026-10-20 06:14:00+00', 'formato en Nairobi');
  PERFORM pg_temp.ok(public.cl_parse_scan_at('2026-10-20 09:14', NULL, 'Africa/Nairobi') = TIMESTAMPTZ '2026-10-20 06:14:00+00', 'sin formato ni desfase: zona del mapeo');
  PERFORM pg_temp.ok(public.cl_parse_scan_at('2026-10-20T09:14:00Z', NULL, 'Africa/Nairobi') = TIMESTAMPTZ '2026-10-20 09:14:00+00', 'con Z se respeta');
  PERFORM pg_temp.ok(public.cl_parse_scan_at('2026-10-20 09:14+01', NULL, 'Africa/Nairobi') = TIMESTAMPTZ '2026-10-20 08:14:00+00', 'con desfase se respeta');
  PERFORM pg_temp.ok(public.cl_parse_scan_at('ayer', NULL, 'UTC') IS NULL, 'texto invalido -> NULL');
  PERFORM pg_temp.ok(public.cl_parse_scan_at('32/10/2026 09:14', 'DD/MM/YYYY HH24:MI', 'UTC') IS NULL, 'fecha invalida -> NULL');
  PERFORM pg_temp.ok(current_setting('TimeZone') = v_tz, 'zona de la sesion intacta');
END $$;

-- 3. Lote de 5 envios en un estrato.
DO $$
DECLARE r jsonb; s jsonb; v_batch uuid;
BEGIN
  r := public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.mk('B1', pg_temp.rows_main()));
  v_batch := (r->>'batch')::uuid;
  PERFORM pg_temp.ok(v_batch IS NOT NULL, 'devuelve el id del lote');
  PERFORM pg_temp.ok(r->>'status' = 'validated', 'estado validated');
  s := r->'strata'->0;
  PERFORM pg_temp.ok(s->>'stratum_id' = '91000000-0000-0000-0000-0000000000b1', 'stratum_id');
  PERFORM pg_temp.ok((s->>'population_size')::int = 48, 'population_size');
  PERFORM pg_temp.ok((s->>'rows')::int = 11, 'rows 11');
  PERFORM pg_temp.ok((s->>'candidates')::int = 5, 'candidates 5');
  PERFORM pg_temp.ok((s->>'candidates_valid')::int = 2, 'candidates_valid 2: ' || s::text);
  PERFORM pg_temp.ok(s->'rejected' = '{"no_end":1,"end_out_of_period":1,"unknown_product":1}'::jsonb, 'motivos de rechazo: ' || (s->'rejected')::text);
  PERFORM pg_temp.ok(s->'rows_rejected' = '{"unknown_product":2,"unknown_reading_point":1}'::jsonb, 'rechazos por fila: ' || (s->'rows_rejected')::text);

  PERFORM pg_temp.ok((SELECT status = 'validated' AND connector_batch_id = 'B1' AND summary = r FROM public.cl_batches WHERE id = v_batch), 'cl_batches validated con el resumen');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_batch_scans WHERE batch_id = v_batch) = 11, '11 lecturas guardadas');
  PERFORM pg_temp.ok((SELECT scan_at FROM public.cl_batch_scans WHERE batch_id = v_batch AND item_id = 'A1' AND place_ref = 'NBO')
                     = TIMESTAMPTZ '2026-10-20 06:14:00+00', '20/10/2026 09:14 Nairobi = 06:14Z');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_batch_scans WHERE batch_id = v_batch AND item_id = '00-12 34') = 3, 'identificador tal cual');
  PERFORM pg_temp.ok((SELECT reader_id FROM public.cl_batch_scans WHERE batch_id = v_batch AND item_id = '00-12 34' AND mode_ref = 'ADM')
                     = 'ad000000-0000-0000-0000-000000000001', 'lugar+modo -> punto especifico');
  PERFORM pg_temp.ok((SELECT reader_id FROM public.cl_batch_scans WHERE batch_id = v_batch AND item_id = '00-12 34' AND mode_ref = 'XXX')
                     = 'ad000000-0000-0000-0000-000000000002', 'otro modo -> punto cualquier modo');
  PERFORM pg_temp.ok((SELECT reader_id FROM public.cl_batch_scans WHERE batch_id = v_batch AND item_id = 'A1' AND place_ref = 'MBA')
                     = 'ad000000-0000-0000-0000-000000000003', 'MBA -> punto cualquier modo');
  PERFORM pg_temp.ok((SELECT status = 'rejected' AND reject_reason = 'unknown_reading_point' AND reader_id IS NULL
                        FROM public.cl_batch_scans WHERE batch_id = v_batch AND place_ref = 'XYZ'), 'lugar desconocido guardado y rechazado');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_batch_scans WHERE batch_id = v_batch AND status = 'valid') = 5, 'filas validas = A1 (2) + 00-12 34 (3)');
  PERFORM pg_temp.ok((SELECT bool_and(status = 'rejected' AND reject_reason = 'no_end') FROM public.cl_batch_scans WHERE batch_id = v_batch AND item_id = 'A3'), 'A3 no_end');
  PERFORM pg_temp.ok((SELECT bool_and(reject_reason = 'end_out_of_period') FROM public.cl_batch_scans WHERE batch_id = v_batch AND item_id = 'A4'), 'A4 fuera de periodo (fecha local)');
  PERFORM pg_temp.ok((SELECT bool_and(reject_reason = 'unknown_product' AND product_id IS NULL) FROM public.cl_batch_scans WHERE batch_id = v_batch AND item_id = 'A5'), 'A5 producto desconocido');
  PERFORM pg_temp.ok((SELECT bool_and(product_id = 'cb000000-0000-0000-0000-000000000001') FROM public.cl_batch_scans WHERE batch_id = v_batch AND item_id = 'A1'), 'EXP -> PR');
  PERFORM pg_temp.ok((SELECT bool_and(extra = '{"weight":"1.2"}'::jsonb) FROM public.cl_batch_scans WHERE batch_id = v_batch), 'campo permitido en extra');

  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM public.cl_alerts WHERE alert_type = 'rejected_ratio' AND quota_id = '91000000-0000-0000-0000-0000000000b1'
                              AND details->>'batch_id' = v_batch::text), 'alerta rejected_ratio (3/5)');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM public.cl_alerts WHERE alert_type = 'unknown_product' AND details->'values' ? 'ZZZ'), 'alerta unknown_product');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM public.cl_alerts WHERE alert_type = 'unknown_reading_point'), 'alerta unknown_reading_point');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_alerts WHERE alert_type IN ('population_incoherent','empty_stratum')), 'sin alertas de poblacion');
  PERFORM pg_temp.ok((SELECT last_batch_at IS NOT NULL FROM public.cl_feeds WHERE id = 'f0000000-0000-0000-0000-0000000000a1'), 'last_batch_at');
END $$;

-- 4. Datos personales: recipient_name no esta en ninguna tabla cl_*.
DO $$
DECLARE t text; n bigint;
BEGIN
  FOR t IN SELECT c.relname FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
            WHERE ns.nspname = 'public' AND c.relkind = 'r' AND c.relname LIKE 'cl\_%' LOOP
    EXECUTE format('SELECT count(*) FROM public.%I x WHERE x::text LIKE %L OR x::text LIKE %L', t, '%Juan Secreto%', '%recipient_name%') INTO n;
    PERFORM pg_temp.ok(n = 0, 'recipient_name aparece en ' || t);
  END LOOP;
  PERFORM pg_temp.ok((SELECT raw_payload->'strata'->0->'rows'->0 FROM public.cl_batches WHERE connector_batch_id = 'B1')
                     = '{"trk":"A1","svc":"EXP","ts":"20/10/2026 09:14","office":"NBO","evt":"ADM","weight":"1.2"}'::jsonb, 'raw_payload solo con campos mapeados y permitidos');
END $$;

-- 5. Mismo lote otra vez: mismo resumen, nada nuevo.
DO $$
DECLARE r1 jsonb; r2 jsonb; n_scans bigint; n_alerts bigint;
BEGIN
  SELECT summary INTO r1 FROM public.cl_batches WHERE connector_batch_id = 'B1';
  n_scans := (SELECT count(*) FROM public.cl_batch_scans);
  n_alerts := (SELECT count(*) FROM public.cl_alerts);
  r2 := public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.mk('B1', pg_temp.rows_main()));
  PERFORM pg_temp.ok(r2 = r1, 'mismo resumen');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_batch_scans) = n_scans, 'mismas filas en cl_batch_scans');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_batches) = 1, 'un solo lote');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts) = n_alerts, 'sin alertas nuevas');
END $$;

-- 6. dry_run: resumen sin filas.
DO $$
DECLARE r jsonb; n_b bigint; n_s bigint; n_a bigint;
BEGIN
  n_b := (SELECT count(*) FROM public.cl_batches);
  n_s := (SELECT count(*) FROM public.cl_batch_scans);
  n_a := (SELECT count(*) FROM public.cl_alerts);
  r := public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.mk('B-DRY', pg_temp.rows_main(), p_pop => 0), true);
  PERFORM pg_temp.ok((r->>'dry_run')::boolean AND r->'batch' = 'null'::jsonb, 'dry_run marcado y sin id de lote');
  PERFORM pg_temp.ok((r->'strata'->0->>'candidates_valid')::int = 2, 'dry_run calcula el resumen');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_batches) = n_b, 'dry_run sin lotes');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_batch_scans) = n_s, 'dry_run sin lecturas');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts) = n_a, 'dry_run sin alertas');
  -- el mismo batch_id despues se puede cargar de verdad
  r := public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.mk('B-DRY', pg_temp.rows_main()));
  PERFORM pg_temp.ok(r->>'batch' IS NOT NULL AND NOT (r ? 'dry_run'), 'tras dry_run se carga de verdad');
END $$;

-- 7. Poblacion incoherente y estrato vacio; ya muestreado no cuenta como rechazo.
DO $$
DECLARE r jsonb;
BEGIN
  r := public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1',
         pg_temp.mk('B-POP', jsonb_build_array(pg_temp.rd('A3', 'EXP', '21/10/2026 08:00', 'NBO', 'ADM')), p_pop => 0));
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM public.cl_alerts WHERE alert_type = 'population_incoherent'), 'alerta population_incoherent');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM public.cl_alerts WHERE alert_type = 'empty_stratum'), 'alerta empty_stratum');

  INSERT INTO public.cl_samples (account_id, plan_id, carrier_id, item_id)
  VALUES ('a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','ca000000-0000-0000-0000-000000000001','A1');
  r := public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.mk('B-SAMPLED', jsonb_build_array(
         pg_temp.rd('A1',       'EXP', '20/10/2026 09:14', 'NBO', 'ADM'),
         pg_temp.rd('A1',       'EXP', '21/10/2026 10:00', 'MBA', 'DLV'),
         pg_temp.rd('00-12 34', 'EXP', '21/10/2026 08:00', 'NBO', 'ADM'),
         pg_temp.rd('00-12 34', 'EXP', '23/10/2026 12:00', 'MBA', 'DLV'))));
  PERFORM pg_temp.ok((r->'strata'->0->>'candidates')::int = 2 AND (r->'strata'->0->>'candidates_valid')::int = 1, 'A1 ya es muestra');
  PERFORM pg_temp.ok(r->'strata'->0->'rejected' = '{"already_sampled":1}'::jsonb, 'motivo already_sampled');
END $$;

-- 8. selection_method distinto: lote rejected con alerta y sin lecturas.
DO $$
DECLARE r jsonb;
BEGIN
  r := public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.mk('B-METHOD', pg_temp.rows_main(), 'first_n'));
  PERFORM pg_temp.ok(r->>'status' = 'rejected', 'resumen rejected');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_batches WHERE connector_batch_id = 'B-METHOD') = 'rejected', 'lote rejected');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_batch_scans s JOIN public.cl_batches b ON b.id = s.batch_id WHERE b.connector_batch_id = 'B-METHOD') = 0, 'sin lecturas');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM public.cl_alerts WHERE alert_type = 'selection_method'), 'alerta selection_method');
  PERFORM pg_temp.ok(public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.mk('B-METHOD', pg_temp.rows_main(), 'first_n')) = r, 'rechazo idempotente');
END $$;

-- 8b. Precedencia D4, lugar con espacios, hora mala, campo ausente, valores enormes y extras no escalares.
DO $$
DECLARE r jsonb; s jsonb; v_batch uuid;
  v_huge text := (SELECT string_agg(md5(i::text), '') FROM generate_series(1, 94) i);   -- ~3000 caracteres incompresibles
BEGIN
  r := public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.mk('B-MISC', jsonb_build_array(
         pg_temp.rd(v_huge, 'EXP', '21/10/2026 08:00', 'NBO', 'ADM'),
         pg_temp.rd('C1', 'EXP', '21/10/2026 08:00', 'NBO', 'ADM') || jsonb_build_object('weight', jsonb_build_object('a', 1)),
         pg_temp.rd('C1', 'EXP', '22/10/2026 08:00', 'MBA ', 'DLV') || jsonb_build_object('weight', repeat('w', 501)),
         pg_temp.rd('C2', 'EXP', 'garbage',          'NBO', 'ADM'),
         pg_temp.rd('C2', 'EXP', '22/10/2026 08:00', 'MBA', 'DLV'),
         pg_temp.rd('C3', 'EXP', '21/10/2026 08:00', 'NBO', 'ADM'),
         pg_temp.rd('C3', 'EXP', NULL,               'MBA', 'DLV'),
         pg_temp.rd(repeat('X', 201), 'EXP', '21/10/2026 08:00', 'NBO', 'ADM'),
         pg_temp.rd('C5', 'EXP', '21/10/2026 08:00', 'NBO', 'ADM'),
         pg_temp.rd('C5', 'EXP', '22/10/2026 08:00', repeat('P', 201), 'DLV'),
         pg_temp.rd('C7', 'EXP', '21/10/2026 08:00', 'KSM', 'SRT'),
         pg_temp.rd('C7', 'EXP', '22/10/2026 08:00', 'MBA', 'DLV'),
         pg_temp.rd('C8', 'EXP', '21/10/2026 08:00', 'KSM', 'ANY'),
         pg_temp.rd('C8', 'EXP', '22/10/2026 08:00', 'MBA', 'DLV'))));
  v_batch := (r->>'batch')::uuid;
  s := r->'strata'->0;
  PERFORM pg_temp.ok((s->>'candidates')::int = 6 AND (s->>'candidates_valid')::int = 2, 'C1 y C8 validos de 6: ' || s::text);
  PERFORM pg_temp.ok(s->'rejected' = '{"no_start":2,"no_end":2}'::jsonb, 'motivos B-MISC: ' || (s->'rejected')::text);
  PERFORM pg_temp.ok(s->'rows_rejected' = '{"bad_timestamp":1,"missing_field":1,"bad_value":3}'::jsonb, 'filas B-MISC: ' || (s->'rows_rejected')::text);
  PERFORM pg_temp.ok((SELECT reader_id FROM public.cl_batch_scans WHERE batch_id = v_batch AND item_id = 'C1' AND place_ref = 'MBA')
                     = 'ad000000-0000-0000-0000-000000000003', 'lugar con espacio final recortado y resuelto');
  PERFORM pg_temp.ok((SELECT bool_and(status = 'valid' AND extra IS NULL) FROM public.cl_batch_scans WHERE batch_id = v_batch AND item_id = 'C1'),
                     'extras no escalares o largos descartados, fila conservada');
  PERFORM pg_temp.ok((SELECT reject_reason FROM public.cl_batch_scans WHERE batch_id = v_batch AND item_id = 'C2' AND place_ref = 'NBO') = 'bad_timestamp', 'bad_timestamp');
  PERFORM pg_temp.ok((SELECT reject_reason FROM public.cl_batch_scans WHERE batch_id = v_batch AND item_id = 'C3' AND place_ref = 'MBA') = 'missing_field', 'missing_field');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_batch_scans WHERE batch_id = v_batch AND item_id IS NULL AND reject_reason = 'bad_value') = 2, 'item_id enorme (incluido uno incompresible): bad_value sin valor');
  PERFORM pg_temp.ok((SELECT raw_payload->'strata'->0->'rows'->0->'trk' FROM public.cl_batches WHERE id = v_batch) = 'null'::jsonb
                     AND position(v_huge IN (SELECT raw_payload::text FROM public.cl_batches WHERE id = v_batch)) = 0
                     AND position(repeat('P', 201) IN (SELECT raw_payload::text FROM public.cl_batches WHERE id = v_batch)) = 0,
                     'raw_payload sin los valores gigantes');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_batch_scans WHERE batch_id = v_batch AND item_id = 'C5' AND place_ref IS NULL AND reject_reason = 'bad_value') = 1, 'place_ref enorme: bad_value sin valor');
  PERFORM pg_temp.ok((SELECT reader_id FROM public.cl_batch_scans WHERE batch_id = v_batch AND item_id = 'C7' AND place_ref = 'KSM')
                     = 'ad000000-0000-0000-0000-000000000005', 'KSM SRT -> punto especifico intermedio');
  PERFORM pg_temp.ok((SELECT bool_and(reject_reason = 'no_start') FROM public.cl_batch_scans WHERE batch_id = v_batch AND item_id = 'C7'),
                     'el punto especifico intermedio no cuenta como inicio por el cualquier-modo de origen');
  PERFORM pg_temp.ok((SELECT bool_and(status = 'valid') FROM public.cl_batch_scans WHERE batch_id = v_batch AND item_id = 'C8'), 'KSM otro modo -> origen');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_batch_scans WHERE length(item_id) > 200 OR length(place_ref) > 200), 'nada enorme guardado');
END $$;

-- 8c. Una sola lectura no es inicio y fin a la vez (punto both, ruta City1 -> City1).
DO $$
DECLARE r jsonb;
BEGIN
  r := public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.mk('B-BOTH', jsonb_build_array(
         pg_temp.rd('S1', 'EXP', '21/10/2026 08:00', 'NBO', 'BTH'),
         pg_temp.rd('S2', 'EXP', '21/10/2026 08:00', 'NBO', 'BTH'),
         pg_temp.rd('S2', 'EXP', '21/10/2026 10:00', 'NBO', 'BTH'),
         -- misma hora: la lectura solo de inicio (ADM) es el inicio y la de BTH el fin
         pg_temp.rd('S3', 'EXP', '21/10/2026 08:00', 'NBO', 'BTH'),
         pg_temp.rd('S3', 'EXP', '21/10/2026 08:00', 'NBO', 'ADM')), p_stratum => '91000000-0000-0000-0000-0000000000b2'));
  PERFORM pg_temp.ok((r->'strata'->0->>'candidates_valid')::int = 2, 'S2 y S3 validos: ' || r::text);
  PERFORM pg_temp.ok(r->'strata'->0->'rejected' = '{"same_reading":1}'::jsonb, 'S1 same_reading');
END $$;

-- 8d. Conector pausado: ni lote nuevo ni prueba (un lote ya guardado si se devuelve); testing acepta.
DO $$
BEGIN
  UPDATE public.cl_feeds SET status = 'paused' WHERE id = 'f0000000-0000-0000-0000-0000000000a1';
  PERFORM pg_temp.ok(public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.mk('B1', pg_temp.rows_main()))
                     = (SELECT summary FROM public.cl_batches WHERE connector_batch_id = 'B1'), 'pausado: reenvio de un lote guardado devuelve su resumen');
  PERFORM pg_temp.ok(pg_temp.errmsg_of(format('SELECT public.cl_ingest_batch(%L, %L::jsonb)', 'f0000000-0000-0000-0000-0000000000a1',
                     pg_temp.mk('B-P', pg_temp.rows_main()))) LIKE 'CL_FEED_PAUSED%', 'pausado rechaza el lote');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of(format('SELECT public.cl_ingest_batch(%L, %L::jsonb, true)', 'f0000000-0000-0000-0000-0000000000a1',
                     pg_temp.mk('B-P', pg_temp.rows_main()))) = '22023', 'pausado rechaza el dry_run');
  UPDATE public.cl_feeds SET status = 'testing' WHERE id = 'f0000000-0000-0000-0000-0000000000a1';
  PERFORM pg_temp.ok(public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.mk('B-P', pg_temp.rows_main()), true) ? 'strata', 'testing acepta');
  UPDATE public.cl_feeds SET status = 'active' WHERE id = 'f0000000-0000-0000-0000-0000000000a1';
END $$;

-- 9. Errores: otro conector, demanda inexistente, estrato ajeno, tamano, demanda cerrada.
DO $$
DECLARE v_big jsonb;
BEGIN
  PERFORM pg_temp.ok(pg_temp.errmsg_of(format('SELECT public.cl_ingest_batch(%L, %L::jsonb)', 'f0000000-0000-0000-0000-0000000000a2',
                     pg_temp.mk('B-X', pg_temp.rows_main()))) LIKE 'CL_DEMAND_NOT_OPEN%', 'demanda de otro conector');
  PERFORM pg_temp.ok(pg_temp.errmsg_of(format('SELECT public.cl_ingest_batch(%L, %L::jsonb)', 'f0000000-0000-0000-0000-0000000000a1',
                     pg_temp.mk('B-X', pg_temp.rows_main()) || '{"demand_id":"not-a-uuid"}')) LIKE 'CL_DEMAND_NOT_OPEN%', 'demand_id invalido');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of(format('SELECT public.cl_ingest_batch(%L, %L::jsonb)', 'f0000000-0000-0000-0000-0000000000a1',
                     pg_temp.mk('B-X', pg_temp.rows_main(), p_stratum => '91000000-0000-0000-0000-0000000000ff'))) = '22023', 'estrato ajeno a la demanda');
  SELECT jsonb_agg(pg_temp.rd('T' || g, 'EXP', '21/10/2026 08:00', 'NBO', 'ADM')) INTO v_big FROM generate_series(1, 5001) g;
  PERFORM pg_temp.ok(pg_temp.errmsg_of(format('SELECT public.cl_ingest_batch(%L, %L::jsonb)', 'f0000000-0000-0000-0000-0000000000a1',
                     pg_temp.mk('B-BIG', v_big))) LIKE 'CL_TOO_MANY_ROWS%', 'mas de 5000 filas');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of(format('SELECT public.cl_ingest_batch(%L, %L::jsonb)', 'f0000000-0000-0000-0000-0000000000a1',
                     pg_temp.mk('B-BIG', v_big))) = '22023', 'mas de 5000 filas: 22023');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_batches WHERE connector_batch_id IN ('B-X','B-BIG')), 'nada escrito en errores');

  UPDATE public.cl_demands SET status = 'fulfilled';
  PERFORM pg_temp.ok((public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.mk('B1', pg_temp.rows_main()))->>'status') = 'validated',
                     'repetir un lote ya cargado devuelve su resumen aunque la demanda este cerrada');
  PERFORM pg_temp.ok(pg_temp.errmsg_of(format('SELECT public.cl_ingest_batch(%L, %L::jsonb)', 'f0000000-0000-0000-0000-0000000000a1',
                     pg_temp.mk('B-NEW', pg_temp.rows_main()))) LIKE 'CL_DEMAND_NOT_OPEN%', 'lote nuevo en demanda cerrada');
END $$;

\echo cl_ingest: OK
ROLLBACK;
