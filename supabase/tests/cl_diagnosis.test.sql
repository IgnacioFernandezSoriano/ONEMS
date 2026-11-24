-- Carrier Link v4, tarea 7: diagnostico (20261124200500_cl_diagnosis.sql). Spec v4.2 R33-R36.
-- 1. Kenya intacta: el ETL RFID (process_rfid_pipeline) sobre un fixture solo RFID da EXACTAMENTE lo mismo con la
--    migracion que sin ella (se emula "sin ella" dentro de la transaccion: DROP de sus disparadores y columnas), y todo
--    queda capture_source = 'rfid'.
-- 2. Entrega real de un plan con Diagnostico: una fila raw por lectura valida de los envios SORTEADOS en puntos con
--    centro (las intermedias tambien, las del no sorteado no); formato del ETL; punto sin centro -> fuera + aviso (R36).
-- 3. Idempotencia (event_id determinista). 4. Mezcla RFID + carrier: lo RFID sale identico; lo carrier, origen
--    'carrier' en eventos y tramos, enriquecido, sin incidencias unknown_*.
-- 5. Plan sin Diagnostico y entrega de prueba: nada. 6. Deshacer antes y despues de consolidar; el ETL descarta lo de
--    una muestra anulada. 7. Reinicio de la cuenta con diagnostico del carrier. Todo en BEGIN ... ROLLBACK.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

-- Lectura del fichero del carrier (nombres del carrier).
CREATE OR REPLACE FUNCTION pg_temp.r(p_n int, p_trk text, p_ts text, p_office text, p_evt text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('n', p_n, 'r', jsonb_strip_nulls(jsonb_build_object(
           'trk', p_trk, 'ts', p_ts, 'office', p_office, 'evt', p_evt, 'svc', 'EXP')))
$$;

CREATE OR REPLACE FUNCTION pg_temp.mk(p_id text, p_feed text, p_rows jsonb, p_is_test boolean DEFAULT false) RETURNS uuid
LANGUAGE sql AS $$
  INSERT INTO public.cl_deliveries (id, account_id, feed_id, period_start, period_end, source, is_test, format,
                                    compression, file_path, file_bytes, sha256, status, received_at)
  VALUES (p_id::uuid, 'a0000000-0000-0000-0000-000000000001', p_feed::uuid, '2026-11-10', '2026-11-16', 'api',
          p_is_test, 'jsonl', 'none', 'a0000000-0000-0000-0000-000000000001/' || p_feed || '/' || p_id || '.jsonl',
          octet_length(p_rows::text), encode(sha256(convert_to(p_rows::text, 'UTF8')), 'hex'), 'received',
          now() - interval '1 hour')
  RETURNING id
$$;

-- Simula el worker: toma la entrega y la carga entera en un trozo.
CREATE OR REPLACE FUNCTION pg_temp.load(p_rows jsonb, p_token text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE c jsonb; v_id uuid; v_len bigint;
BEGIN
  c := public.cl_delivery_worker_claim(p_token);
  IF c->>'action' <> 'load' THEN RAISE EXCEPTION 'FAIL: claim %', c; END IF;
  v_id := (c->>'delivery_id')::uuid;
  v_len := (c->>'file_bytes')::bigint;
  PERFORM public.cl_delivery_load_rows(v_id, p_token, 0, p_rows,
            jsonb_build_object('offset', v_len, 'rows', jsonb_array_length(p_rows), 'sha', jsonb_build_object('h', '[]'::jsonb),
                               'sha_offset', v_len, 'header', NULL));
  RETURN public.cl_delivery_load_done(v_id, p_token, v_len, (SELECT d.sha256 FROM public.cl_deliveries d WHERE d.id = v_id), v_len);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.run() RETURNS void LANGUAGE plpgsql AS $$
DECLARE v text; i int := 0;
BEGIN
  LOOP
    v := public.cl_process_delivery(NULL, 100000); i := i + 1;
    EXIT WHEN v IN ('idle','load','reset');
    IF i > 500 THEN RAISE EXCEPTION 'FAIL: el proceso no termina'; END IF;
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION pg_temp.run_until(p_phase text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE i int := 0;
BEGIN
  WHILE (SELECT progress->>'phase' FROM public.cl_deliveries WHERE status = 'processing') IS DISTINCT FROM p_phase LOOP
    PERFORM public.cl_process_delivery(NULL, 100000);
    i := i + 1;
    IF i > 200 THEN RAISE EXCEPTION 'FAIL: no llega a %', p_phase; END IF;
  END LOOP;
END $$;

-- ETL RFID completo de la cuenta (lo que hace el cron del poll); todas las fases deben acabar en success.
CREATE OR REPLACE FUNCTION pg_temp.etl() RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(p.phase || ':' || p.status || ':' || COALESCE(p.message, ''), ' | ') INTO v_bad
    FROM public.process_rfid_pipeline('a0000000-0000-0000-0000-000000000001') p WHERE p.status <> 'success';
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'FAIL: ETL con errores: %', v_bad; END IF;
END $$;

-- Foto del resultado del ETL para las etiquetas RFID (las que no empiezan por 'K'): raw, eventos, tramos, viajes e
-- incidencias, sin ids ni la columna nueva. SQL (no plpgsql): se replanifica en cada llamada, aunque la tabla cambie.
CREATE OR REPLACE FUNCTION pg_temp.snap() RETURNS text LANGUAGE sql AS $$
  SELECT concat_ws(E'\n',
    (SELECT string_agg(concat_ws('|', w.event_id, w.tag_id, w.reader_id, w.is_processed), E'\n' ORDER BY w.event_id)
       FROM public.rfid_events_raw w WHERE w.tag_id NOT LIKE 'K%'),
    (SELECT string_agg(x::text, E'\n' ORDER BY x::text) FROM (
       SELECT to_jsonb(e) - 'id' - 'capture_source' AS x FROM public.processed_events e WHERE e.tag_id NOT LIKE 'K%') e),
    (SELECT string_agg(x::text, E'\n' ORDER BY x::text) FROM (
       SELECT to_jsonb(s) - 'id' - 'capture_source' - 'entry_event_id' - 'exit_event_id'
              || jsonb_build_object('entry', (SELECT concat_ws('|', e.reader_id_snapshot, e.event_type, e.timestamp)
                                                FROM public.processed_events e WHERE e.id = s.entry_event_id),
                                    'exit',  (SELECT concat_ws('|', e.reader_id_snapshot, e.event_type, e.timestamp)
                                                FROM public.processed_events e WHERE e.id = s.exit_event_id)) AS x
         FROM public.journey_segments s WHERE s.tag_id NOT LIKE 'K%') s),
    (SELECT string_agg(x::text, E'\n' ORDER BY x::text) FROM (
       SELECT to_jsonb(j) - 'id' - 'route_path' AS x FROM public.journeys j WHERE j.tag_id NOT LIKE 'K%') j),
    (SELECT string_agg(concat_ws('|', i.incident_type, i.tag_id, i.metadata), E'\n' ORDER BY i.incident_type, i.tag_id)
       FROM public.incidents i WHERE i.account_id = 'a0000000-0000-0000-0000-000000000001'
         AND COALESCE(i.tag_id, '') NOT LIKE 'K%'))
$$;

BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
UPDATE public.accounts SET timezone = 'Africa/Nairobi' WHERE id = 'a0000000-0000-0000-0000-000000000001';

-- ---------------------------------------------------------------- fixture RFID (como Kenya)
-- PR1 en City1 (lector Mixed); PR2 en City2 (lectores Entry y Exit). Dias naturales (sin calendario laboral en el fixture).
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id, calculation_mode, opening_hour, working_hours_end, timezone) VALUES
  ('d1000000-0000-0000-0000-0000000000f1','a0000000-0000-0000-0000-000000000001','PR1','Rfid 1','City1','c1000000-0000-0000-0000-000000000001','natural_days',NULL,NULL,'UTC'),
  ('d2000000-0000-0000-0000-0000000000f2','a0000000-0000-0000-0000-000000000001','PR2','Rfid 2','City2','c2000000-0000-0000-0000-000000000002','natural_days',NULL,NULL,'UTC');
INSERT INTO public.readers (id, account_id, postal_center_id, reader_id, name, type) VALUES
  ('f1000000-0000-0000-0000-0000000000f1','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000f1','LPI-R1','R1','Mixed'),
  ('f2000000-0000-0000-0000-0000000000f2','a0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-0000000000f2','LPI-R2','R2','Entry'),
  ('f3000000-0000-0000-0000-0000000000f3','a0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-0000000000f2','LPI-R3','R3','Exit');
INSERT INTO public.slas (account_id, sla_type, postal_center_id, expected_time_minutes, on_time_percentage, warning_threshold, critical_threshold, is_active)
VALUES ('a0000000-0000-0000-0000-000000000001','operational','d2000000-0000-0000-0000-0000000000f2',120,100,100,100,true);
INSERT INTO public.one_db (account_id, tag_id, plan_name, carrier_name, product_name, origin_city_name, destination_city_name,
                           sent_at, received_at, total_transit_days, source_data_snapshot, source)
VALUES
  ('a0000000-0000-0000-0000-000000000001','00000201','Mar27','Carrier','Prod','City1','City2','2027-03-01 08:00+00','2027-03-02 11:00+00',1,'{}','panelist'),
  ('a0000000-0000-0000-0000-000000000001','00000202','Mar27','Carrier','PR','City1','City2','2027-03-01 10:00+00','2027-03-03 12:00+00',2,'{}','panelist');
-- 201: lecturas repetidas en R1 (Mixed) y R2, salida en R3. 202: R1 y R3. 203: sin one_db. 204: lector desconocido.
INSERT INTO public.rfid_events_raw (account_id, event_id, read_local_datetime, reader_id, tag_id) VALUES
  ('a0000000-0000-0000-0000-000000000001','rf-01','2027-03-01 08:00+00','LPI-R1','00000201'),
  ('a0000000-0000-0000-0000-000000000001','rf-02','2027-03-01 08:05+00','LPI-R1','00000201'),
  ('a0000000-0000-0000-0000-000000000001','rf-03','2027-03-01 09:30+00','LPI-R1','00000201'),
  ('a0000000-0000-0000-0000-000000000001','rf-04','2027-03-02 09:00+00','LPI-R2','00000201'),
  ('a0000000-0000-0000-0000-000000000001','rf-05','2027-03-02 09:10+00','LPI-R2','00000201'),
  ('a0000000-0000-0000-0000-000000000001','rf-06','2027-03-02 11:00+00','LPI-R3','00000201'),
  ('a0000000-0000-0000-0000-000000000001','rf-07','2027-03-01 10:00+00','LPI-R1','00000202'),
  ('a0000000-0000-0000-0000-000000000001','rf-08','2027-03-03 12:00+00','LPI-R3','00000202'),
  ('a0000000-0000-0000-0000-000000000001','rf-09','2027-03-02 08:30+00','LPI-R2','00000203'),
  ('a0000000-0000-0000-0000-000000000001','rf-10','2027-03-01 07:00+00','LPI-NOPE','00000204');

-- ---------------------------------------------------------------- fixture Carrier Link
-- Centros: CA (City1), CB (City2), CH (City1, centro intermedio). Puntos: NBO origen (CA, Entry), HUB intermedio con
-- centro (CH, Entry), HU2 intermedio SIN centro, MBA destino (CB, Exit).
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','CA','Center A','City1','c1000000-0000-0000-0000-000000000001'),
  ('d2000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000001','CB','Center B','City2','c2000000-0000-0000-0000-000000000002'),
  ('d3000000-0000-0000-0000-0000000000a3','a0000000-0000-0000-0000-000000000001','CH','Hub','City1','c1000000-0000-0000-0000-000000000001');
INSERT INTO public.readers (id, account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role) VALUES
  ('ad000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000a1','NBO ADM','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','NBO','ADM','origin'),
  ('ad000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','d3000000-0000-0000-0000-0000000000a3','HUB','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','HUB',NULL,'none'),
  ('ad000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001',NULL,'HUB2','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','HU2',NULL,'none'),
  ('ad000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-0000000000a2','MBA','Exit','carrier_scan','ca000000-0000-0000-0000-000000000001','MBA',NULL,'destination');
-- Conectores: FD (plan con Diagnostico), FN (plan sin), FT (prueba, plan con Diagnostico).
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status, emit_days, emit_hour) VALUES
  ('f0000000-0000-0000-0000-0000000000d1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed D','active','{2}',3),
  ('f0000000-0000-0000-0000-0000000000d2','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed N','active','{2}',3),
  ('f0000000-0000-0000-0000-0000000000d3','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed T','testing','{2}',3);
INSERT INTO public.cl_field_mappings (account_id, carrier_id, standard_field, carrier_field, format, timezone) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','item_id','trk',NULL,NULL),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','product','svc',NULL,NULL),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','scan_at','ts','YYYY-MM-DD HH24:MI','Africa/Nairobi'),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','place_ref','office',NULL,NULL),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','mode_ref','evt',NULL,NULL);
INSERT INTO public.cl_value_mappings (account_id, carrier_id, kind, carrier_value, onems_value) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','product','EXP','PR');
INSERT INTO public.delivery_standards (account_id, carrier_id, product_id, origin_city_id, destination_city_id, standard_time, time_unit, cl_first_mile_time, cl_last_mile_time)
VALUES ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002', 96, 'hours', 0, 12);
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id, feed_diagnosis) VALUES
  ('90000000-0000-0000-0000-0000000000d1','a0000000-0000-0000-0000-000000000001','PD','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',2,'2026-11-02','2026-11-29','active','f0000000-0000-0000-0000-0000000000d1',true),
  ('90000000-0000-0000-0000-0000000000d2','a0000000-0000-0000-0000-000000000001','PN','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',2,'2026-11-02','2026-11-29','active','f0000000-0000-0000-0000-0000000000d2',false),
  ('90000000-0000-0000-0000-0000000000d3','a0000000-0000-0000-0000-000000000001','PT','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',2,'2026-11-02','2026-11-29','active','f0000000-0000-0000-0000-0000000000d3',true);
-- W46 (9-15/11), ruta C1 -> C2: 2 muestras por plan (la entrega 10-16/11 cierra la semana: pide todo).
INSERT INTO public.cl_plan_quotas (id, account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned) VALUES
  ('91000000-0000-0000-0000-0000000000d1','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000d1','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,46,'2026-11-09','2026-11-15',2),
  ('91000000-0000-0000-0000-0000000000d2','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000d2','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,46,'2026-11-09','2026-11-15',2),
  ('91000000-0000-0000-0000-0000000000d3','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000d3','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,46,'2026-11-09','2026-11-15',2);

-- ================================================================ 1. Kenya: mismo resultado con y sin la migracion
SAVEPOINT antes;
-- "Sin la migracion": fuera sus disparadores y columnas (DDL transaccional; ROLLBACK TO lo devuelve todo).
DROP TRIGGER cl_processed_events_capture_source ON public.processed_events;
DROP TRIGGER cl_journey_segments_capture_source ON public.journey_segments;
DROP TRIGGER cl_readers_delete_diagnosis ON public.readers;
ALTER TABLE public.processed_events DROP COLUMN capture_source;
ALTER TABLE public.journey_segments DROP COLUMN capture_source;
SELECT pg_temp.etl();
SELECT pg_temp.ok((SELECT count(*) FROM public.processed_events) >= 6 AND (SELECT count(*) FROM public.journey_segments) >= 3
                   AND (SELECT count(*) FROM public.journeys) >= 1, 'el fixture RFID produce eventos, tramos y viajes');
SELECT pg_temp.snap() AS kenya_sin \gset
ROLLBACK TO SAVEPOINT antes;

SELECT pg_temp.ok(EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'processed_events'
                           AND column_name = 'capture_source'), 'la columna vuelve tras el ROLLBACK TO');
SELECT pg_temp.etl();
SELECT pg_temp.ok(pg_temp.snap() = :'kenya_sin', 'Kenya: mismo resultado del ETL con la migracion que sin ella');
SELECT pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.processed_events WHERE capture_source <> 'rfid')
                  AND NOT EXISTS (SELECT 1 FROM public.journey_segments WHERE capture_source <> 'rfid'),
                  'Kenya: todo queda con origen rfid');
ROLLBACK TO SAVEPOINT antes;
-- La foto "sin migracion" queda a mano de los bloques DO (fuera de la subtransaccion deshecha).
SELECT set_config('cl_test.kenya_sin', :'kenya_sin', false) IS NOT NULL AS foto_guardada;

-- ================================================================ 2. entrega real de un plan con Diagnostico
-- Tres envios validos (K1-K3), cuota 2: se sortean 2 (md5(seed || item_id), cualquiera de los tres). Lecturas de K1:
-- NBO, HUB (intermedio con centro), HU2 (sin centro), XXX (lugar desconocido), MBA. K2 lleva una lectura repetida.
CREATE TEMP TABLE t_d AS SELECT jsonb_build_array(
  pg_temp.r(1,  'K1', '2026-11-10 08:00', 'NBO', 'ADM'),
  pg_temp.r(2,  'K1', '2026-11-10 20:00', 'HUB'),
  pg_temp.r(3,  'K1', '2026-11-11 01:00', 'HU2'),
  pg_temp.r(4,  'K1', '2026-11-11 02:00', 'XXX'),
  pg_temp.r(5,  'K1', '2026-11-12 10:00', 'MBA'),
  pg_temp.r(6,  'K2', '2026-11-10 09:00', 'NBO', 'ADM'),
  pg_temp.r(7,  'K2', '2026-11-11 09:00', 'HUB'),
  pg_temp.r(8,  'K2', '2026-11-11 09:00', 'HUB'),
  pg_temp.r(9,  'K2', '2026-11-13 09:00', 'MBA'),
  pg_temp.r(10, 'K3', '2026-11-10 07:00', 'NBO', 'ADM'),
  pg_temp.r(11, 'K3', '2026-11-11 07:00', 'HUB'),
  pg_temp.r(12, 'K3', '2026-11-13 07:00', 'MBA')) AS rows;

DO $$
DECLARE
  v_id uuid := 'de000000-0000-0000-0000-0000000000d1';
  v_rows jsonb := (SELECT rows FROM t_d);
  v_drawn text[];
  v_undrawn text;
  v_n int;
  a jsonb;
BEGIN
  PERFORM pg_temp.mk(v_id::text, 'f0000000-0000-0000-0000-0000000000d1', v_rows);
  PERFORM pg_temp.load(v_rows, 'token-diag-01');
  -- Hasta finish: la zona de paso aun existe -> idempotencia del paso al diagnostico.
  PERFORM pg_temp.run_until('finish');
  SELECT array_agg(item_id ORDER BY item_id) INTO v_drawn FROM public.cl_samples WHERE delivery_id = v_id AND status = 'active';
  PERFORM pg_temp.ok(cardinality(v_drawn) = 2, 'dos envios sorteados: ' || COALESCE(v_drawn::text, '-'));
  SELECT x INTO v_undrawn FROM unnest(ARRAY['K1','K2','K3']) x WHERE x <> ALL (v_drawn);
  SELECT count(*) INTO v_n FROM public.rfid_events_raw WHERE event_id LIKE 'cl:%';
  -- K1 (si se sorteo) deja 2 lecturas pendientes: XXX (lugar desconocido) y HU2 (sin centro).
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_diagnosis_pending) = CASE WHEN 'K1' = ANY (v_drawn) THEN 2 ELSE 0 END,
                     'pendientes: ' || (SELECT count(*) FROM public.cl_diagnosis_pending));
  FOR i IN 1 .. 2 LOOP
    PERFORM pg_temp.ok(public.cl_diagnosis_feed_item((SELECT d FROM public.cl_deliveries d WHERE d.id = v_id),
                         'ca000000-0000-0000-0000-000000000001',
                         (SELECT id FROM public.cl_samples WHERE item_id = v_drawn[i] AND status = 'active'), v_drawn[i],
                         'cb000000-0000-0000-0000-000000000001') = 0
                       AND (SELECT count(*) FROM public.rfid_events_raw WHERE event_id LIKE 'cl:%') = v_n
                       AND (SELECT count(*) FROM public.cl_diagnosis_pending) = CASE WHEN 'K1' = ANY (v_drawn) THEN 2 ELSE 0 END,
                       'idempotente: repetir el paso no anade filas ni pendientes (' || v_drawn[i] || ')');
  END LOOP;
  PERFORM pg_temp.run();
  PERFORM pg_temp.ok((SELECT status FROM public.cl_deliveries WHERE id = v_id) = 'processed', 'entrega procesada');

  -- Solo los sorteados (R33).
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.rfid_events_raw WHERE tag_id = v_undrawn), 'el no sorteado no entra');
  -- Una fila por lectura valida en punto con centro: K1 = NBO, HUB, MBA (HU2 sin centro y XXX desconocido fuera);
  -- K2 = NBO, HUB (dos lecturas identicas -> una), MBA; K3 = NBO, HUB, MBA.
  PERFORM pg_temp.ok((SELECT count(*) FROM public.rfid_events_raw WHERE tag_id = ANY (v_drawn)) = 6,
                     'tres filas por envio sorteado: ' || (SELECT count(*) FROM public.rfid_events_raw WHERE tag_id = ANY (v_drawn)));
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.rfid_events_raw WHERE reader_id LIKE '%:HU2' OR reader_id LIKE '%:XXX'),
                     'punto sin centro y lugar desconocido fuera');
  -- Formato que espera el ETL.
  PERFORM pg_temp.ok(NOT EXISTS (
      SELECT 1 FROM public.rfid_events_raw w
       WHERE w.tag_id = ANY (v_drawn)
         AND NOT (w.account_id = 'a0000000-0000-0000-0000-000000000001' AND w.event_id LIKE 'cl:%'
                  AND length(w.event_id) = 35 AND w.is_processed = false
                  AND w.carrier_id = 'ca000000-0000-0000-0000-000000000001'
                  AND w.product_id = 'cb000000-0000-0000-0000-000000000001'
                  AND w.reader_id IN (SELECT rd.reader_id FROM public.readers rd
                                       WHERE rd.capture_source = 'carrier_scan' AND rd.postal_center_id IS NOT NULL))),
    'filas raw con el formato del ETL (cl:md5, lector CL:, carrier, producto, sin procesar)');
  PERFORM pg_temp.ok((SELECT reader_id FROM public.rfid_events_raw WHERE tag_id = v_drawn[1]
                       AND read_local_datetime = (SELECT min(read_local_datetime) FROM public.rfid_events_raw WHERE tag_id = v_drawn[1]))
                     = 'CL:acc:CA:NBO:ADM', 'reader_id = el del punto (CL:<cuenta>:<carrier>:<lugar>:<modo>)');
  -- event_id determinista: el mismo calculo da el mismo valor.
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM public.rfid_events_raw w WHERE w.tag_id = 'K2'
                     AND w.event_id = 'cl:' || md5('K2|CL:acc:CA:MBA|2026-11-13T06:00:00.000000')) OR v_undrawn = 'K2',
                     'event_id = cl: || md5(item | lector | hora UTC)');
  -- R36: aviso por la lectura de K1 en HU2 (si K1 se sorteo).
  SELECT details INTO a FROM public.cl_alerts
   WHERE delivery_id = v_id AND alert_type = 'diagnosis_point_without_center' AND plan_id = '90000000-0000-0000-0000-0000000000d1';
  IF 'K1' = ANY (v_drawn) THEN
    PERFORM pg_temp.ok(a IS NOT NULL AND (a->>'readings')::int = 1 AND (a->>'shipments')::int = 1
                       AND a->'points'->0->>'place_ref' = 'HU2', 'aviso R36: ' || COALESCE(a::text, 'ninguno'));
  ELSE
    PERFORM pg_temp.ok(a IS NULL, 'sin lectura en HU2 de un sorteado: sin aviso');
  END IF;
  -- El plan sigue activo (R36: el plan se activa igual).
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plans WHERE id = '90000000-0000-0000-0000-0000000000d1') = 'active', 'plan activo');
END $$;

-- El aviso R36 con todos los envios sorteados se comprueba tambien en la seccion 5 (E1, KE1 en HU2).

-- ================================================================ 3. ETL con RFID + carrier mezclados
SELECT pg_temp.etl();
SELECT pg_temp.ok(pg_temp.snap() = :'kenya_sin', 'mezcla: lo RFID sale identico');
SELECT pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.processed_events WHERE tag_id NOT LIKE 'K%' AND capture_source <> 'rfid'),
                  'mezcla: eventos RFID con origen rfid');
DO $$
DECLARE v_drawn text[] := ARRAY(SELECT item_id FROM public.cl_samples WHERE delivery_id = 'de000000-0000-0000-0000-0000000000d1' AND status = 'active');
BEGIN
  PERFORM pg_temp.ok((SELECT count(*) FROM public.processed_events WHERE tag_id = ANY (v_drawn)) = 6,
                     'carrier: un evento por lector y envio (' || (SELECT count(*) FROM public.processed_events WHERE tag_id = ANY (v_drawn)) || ')');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.processed_events WHERE tag_id = ANY (v_drawn)
                                   AND (capture_source <> 'carrier' OR carrier_id IS DISTINCT FROM 'ca000000-0000-0000-0000-000000000001'
                                        OR product_id IS DISTINCT FROM 'cb000000-0000-0000-0000-000000000001'
                                        OR origin_city_name <> 'City1' OR destination_city_name <> 'City2')),
                     'carrier: origen carrier y enriquecido con one_db (carrier, producto, ciudades)');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.journey_segments WHERE tag_id = ANY (v_drawn)) >= 2
                     AND NOT EXISTS (SELECT 1 FROM public.journey_segments WHERE tag_id = ANY (v_drawn) AND capture_source <> 'carrier'),
                     'carrier: tramos con origen carrier');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.journey_segments WHERE tag_id NOT LIKE 'K%' AND capture_source <> 'rfid'),
                     'mezcla: tramos RFID con origen rfid');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.journeys WHERE tag_id = ANY (v_drawn)) = 2, 'carrier: un viaje por envio');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.incidents WHERE tag_id = ANY (v_drawn)), 'carrier: sin incidencias unknown_*');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.rfid_events_raw WHERE is_processed = false), 'todo consolidado');
END $$;

-- ================================================================ 4. plan sin Diagnostico y entrega de prueba: nada
DO $$
DECLARE v_rows jsonb;
BEGIN
  v_rows := jsonb_build_array(pg_temp.r(1, 'N1', '2026-11-10 08:00', 'NBO', 'ADM'), pg_temp.r(2, 'N1', '2026-11-11 08:00', 'HUB'),
                              pg_temp.r(3, 'N1', '2026-11-11 09:00', 'HU2'), pg_temp.r(4, 'N1', '2026-11-12 08:00', 'MBA'));
  PERFORM pg_temp.mk('de000000-0000-0000-0000-0000000000d2', 'f0000000-0000-0000-0000-0000000000d2', v_rows);
  PERFORM pg_temp.load(v_rows, 'token-diag-02');
  PERFORM pg_temp.run();
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_samples WHERE item_id = 'N1' AND status = 'active') = 1, 'sin Diagnostico: muestra creada');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.rfid_events_raw WHERE tag_id = 'N1'), 'sin Diagnostico: nada al ETL');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_alerts WHERE delivery_id = 'de000000-0000-0000-0000-0000000000d2'
                                   AND alert_type = 'diagnosis_point_without_center'), 'sin Diagnostico: sin aviso R36');

  v_rows := jsonb_build_array(pg_temp.r(1, 'T1', '2026-11-10 08:00', 'NBO', 'ADM'), pg_temp.r(2, 'T1', '2026-11-11 09:00', 'HU2'),
                              pg_temp.r(3, 'T1', '2026-11-12 08:00', 'MBA'));
  PERFORM pg_temp.mk('de000000-0000-0000-0000-0000000000d3', 'f0000000-0000-0000-0000-0000000000d3', v_rows, true);
  PERFORM pg_temp.load(v_rows, 'token-diag-03');
  PERFORM pg_temp.run();
  PERFORM pg_temp.ok((SELECT status FROM public.cl_deliveries WHERE id = 'de000000-0000-0000-0000-0000000000d3') = 'processed', 'prueba procesada');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.rfid_events_raw WHERE tag_id = 'T1'), 'prueba: nada al ETL');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_alerts WHERE delivery_id = 'de000000-0000-0000-0000-0000000000d3'),
                     'prueba: sin avisos');
END $$;

-- ================================================================ 5. deshacer: antes y despues de consolidar
-- E1 se deshace ANTES del ETL; la entrega D1 (ya consolidada) DESPUES. Plan con Diagnostico, todo se sortea (cuota 3).
DO $$
DECLARE
  e1 uuid := 'de000000-0000-0000-0000-0000000000e1';
  d1 uuid := 'de000000-0000-0000-0000-0000000000d1';
  v_rows jsonb;
  v_d1_items text[] := ARRAY(SELECT item_id FROM public.cl_samples WHERE delivery_id = d1 AND status = 'active');
  r jsonb;
BEGIN
  -- Otra semana para no chocar con la cuota ya liquidada: W47 (16-22/11).
  INSERT INTO public.cl_plan_quotas (id, account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned)
  VALUES ('91000000-0000-0000-0000-0000000000e1','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000d1',
          'c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,47,'2026-11-16','2026-11-22',3);
  v_rows := jsonb_build_array(
    pg_temp.r(1, 'KE1', '2026-11-17 08:00', 'NBO', 'ADM'), pg_temp.r(2, 'KE1', '2026-11-18 08:00', 'HUB'),
    pg_temp.r(3, 'KE1', '2026-11-18 09:00', 'HU2'), pg_temp.r(4, 'KE1', '2026-11-19 08:00', 'MBA'),
    pg_temp.r(5, 'KE2', '2026-11-17 09:00', 'NBO', 'ADM'), pg_temp.r(6, 'KE2', '2026-11-20 09:00', 'MBA'));
  INSERT INTO public.cl_deliveries (id, account_id, feed_id, period_start, period_end, source, is_test, format, compression,
                                    file_path, file_bytes, sha256, status, received_at)
  VALUES (e1, 'a0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-0000000000d1', '2026-11-17', '2026-11-23', 'api',
          false, 'jsonl', 'none', 'a0000000-0000-0000-0000-000000000001/f/e1.jsonl', octet_length(v_rows::text),
          encode(sha256(convert_to(v_rows::text, 'UTF8')), 'hex'), 'received', now() - interval '1 hour');
  PERFORM pg_temp.load(v_rows, 'token-diag-04');
  PERFORM pg_temp.run();
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_samples WHERE delivery_id = e1 AND status = 'active') = 2, 'E1: 2 muestras');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.rfid_events_raw WHERE tag_id IN ('KE1','KE2')) = 5, 'E1: 5 filas raw');
  PERFORM pg_temp.ok((SELECT (details->>'readings')::int FROM public.cl_alerts WHERE delivery_id = e1
                       AND alert_type = 'diagnosis_point_without_center') = 1, 'E1: aviso R36 (KE1 en HU2)');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_diagnosis_pending WHERE item_id = 'KE1' AND place_ref = 'HU2'
                        AND reason = 'point_without_center') = 1, 'E1: la lectura en HU2 queda pendiente');

  -- Deshacer E1 antes del ETL (lo que hace el fallo terminal): sus filas raw y pendientes se van.
  PERFORM pg_temp.ok(public.cl_delivery_undo_samples((SELECT d FROM public.cl_deliveries d WHERE d.id = e1)) = 2, 'E1 deshecha');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.rfid_events_raw WHERE tag_id IN ('KE1','KE2'))
                     AND NOT EXISTS (SELECT 1 FROM public.cl_diagnosis_pending WHERE item_id IN ('KE1','KE2')),
                     'E1: raw y pendientes borradas antes de consolidar');

  -- Deshacer D1 despues del ETL: eventos, tramos, viajes e incidencias del carrier fuera; lo RFID intacto.
  PERFORM pg_temp.ok(public.cl_delivery_undo_samples((SELECT d FROM public.cl_deliveries d WHERE d.id = d1)) = 2, 'D1 deshecha');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.rfid_events_raw WHERE tag_id = ANY (v_d1_items))
                     AND NOT EXISTS (SELECT 1 FROM public.processed_events WHERE tag_id = ANY (v_d1_items))
                     AND NOT EXISTS (SELECT 1 FROM public.journey_segments WHERE tag_id = ANY (v_d1_items))
                     AND NOT EXISTS (SELECT 1 FROM public.journeys WHERE tag_id = ANY (v_d1_items)),
                     'D1: diagnostico ya consolidado borrado');
  PERFORM pg_temp.ok(pg_temp.snap() = (SELECT current_setting('cl_test.kenya_sin')), 'deshacer no toca lo RFID');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.processed_events WHERE capture_source = 'carrier'), 'sin eventos carrier');

  -- Carrera con el ETL: una fila raw de un envio cuya muestra se anulo no crea evento (el disparador la descarta) y
  -- queda procesada (sin one_db, la consolidacion anota su unknown_tag de siempre).
  INSERT INTO public.rfid_events_raw (account_id, event_id, read_local_datetime, reader_id, tag_id, carrier_id, product_id)
  VALUES ('a0000000-0000-0000-0000-000000000001', 'cl:late', '2026-11-12 07:00+00', 'CL:acc:CA:MBA', v_d1_items[1],
          'ca000000-0000-0000-0000-000000000001', 'cb000000-0000-0000-0000-000000000001');
  PERFORM pg_temp.etl();
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.processed_events WHERE tag_id = v_d1_items[1])
                     AND (SELECT is_processed FROM public.rfid_events_raw WHERE event_id = 'cl:late'),
                     'muestra anulada: el ETL no crea el evento');
  PERFORM pg_temp.ok(pg_temp.snap() = (SELECT current_setting('cl_test.kenya_sin')), 'lo RFID sigue identico');
END $$;

-- ================================================================ 6. entrada tardia y reinicio de la cuenta
-- KF1: NBO, HUB, ZZZ (lugar sin punto), HU2 (punto sin centro), MBA. Entran 3; ZZZ y HU2 quedan pendientes y entran al
-- dar de alta ZZZ (con centro) y al asignar centro a HU2; el ETL rehace la etiqueta entera.
-- Despues, reinicio: los reinicios borran los puntos carrier_scan; processed_events.reader_id es ON DELETE RESTRICT. El
-- disparador de readers borra antes el diagnostico del punto, asi que el reinicio no falla.
DO $$
DECLARE v_rows jsonb; j jsonb; v_seg int;
BEGIN
  INSERT INTO public.cl_plan_quotas (id, account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned)
  VALUES ('91000000-0000-0000-0000-0000000000f1','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000d1',
          'c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,48,'2026-11-23','2026-11-29',1);
  v_rows := jsonb_build_array(pg_temp.r(1, 'KF1', '2026-11-24 08:00', 'NBO', 'ADM'), pg_temp.r(2, 'KF1', '2026-11-25 08:00', 'HUB'),
                              pg_temp.r(3, 'KF1', '2026-11-25 12:00', 'ZZZ', 'ARR'), pg_temp.r(4, 'KF1', '2026-11-25 18:00', 'HU2'),
                              pg_temp.r(5, 'KF1', '2026-11-26 08:00', 'MBA'));
  INSERT INTO public.cl_deliveries (id, account_id, feed_id, period_start, period_end, source, is_test, format, compression,
                                    file_path, file_bytes, sha256, status, received_at)
  VALUES ('de000000-0000-0000-0000-0000000000f1', 'a0000000-0000-0000-0000-000000000001', 'f0000000-0000-0000-0000-0000000000d1',
          '2026-11-24', '2026-11-30', 'api', false, 'jsonl', 'none', 'a0000000-0000-0000-0000-000000000001/f/f1.jsonl',
          octet_length(v_rows::text), encode(sha256(convert_to(v_rows::text, 'UTF8')), 'hex'), 'received', now() - interval '1 hour');
  PERFORM pg_temp.load(v_rows, 'token-diag-05');
  PERFORM pg_temp.run();
  PERFORM pg_temp.etl();
  PERFORM pg_temp.ok((SELECT count(*) FROM public.processed_events WHERE tag_id = 'KF1' AND capture_source = 'carrier') = 3,
                     'KF1 consolidado');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_diagnosis_pending WHERE item_id = 'KF1') = 2, 'KF1: 2 pendientes');
  SELECT count(*) INTO v_seg FROM public.journey_segments WHERE tag_id = 'KF1';
  -- Alta del lugar ZZZ (punto sin modo: vale para cualquier modo) con centro: entra su lectura.
  INSERT INTO public.readers (id, account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role)
  VALUES ('ad000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000001','d3000000-0000-0000-0000-0000000000a3',
          'ZZZ','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','ZZZ',NULL,'none');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM public.rfid_events_raw WHERE tag_id = 'KF1' AND reader_id = 'CL:acc:CA:ZZZ'
                               AND event_id = public.cl_diagnosis_event_id('KF1', 'CL:acc:CA:ZZZ', '2026-11-25 09:00+00'))
                     AND (SELECT count(*) FROM public.cl_diagnosis_pending WHERE item_id = 'KF1') = 1,
                     'alta del punto: la lectura pendiente entra');
  -- HU2 recibe centro: entra la suya.
  UPDATE public.readers SET postal_center_id = 'd3000000-0000-0000-0000-0000000000a3' WHERE id = 'ad000000-0000-0000-0000-000000000005';
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM public.rfid_events_raw WHERE tag_id = 'KF1' AND reader_id = 'CL:acc:CA:HU2')
                     AND NOT EXISTS (SELECT 1 FROM public.cl_diagnosis_pending WHERE item_id = 'KF1'),
                     'centro asignado: la lectura pendiente entra');
  PERFORM pg_temp.etl();
  PERFORM pg_temp.ok((SELECT count(*) FROM public.processed_events WHERE tag_id = 'KF1' AND capture_source = 'carrier') = 5,
                     'KF1: 5 eventos tras la entrada tardia');
  -- Antes el transito CH -> CB salia de la lectura en HUB (05:00 UTC); rehecho, sale de la ultima del centro (HU2, 15:00).
  PERFORM pg_temp.ok(v_seg = 2 AND (SELECT entry_timestamp FROM public.journey_segments WHERE tag_id = 'KF1'
                       AND from_postal_center_code_snapshot = 'CH' AND to_postal_center_code_snapshot = 'CB') = '2026-11-25 15:00+00'
                     AND NOT EXISTS (SELECT 1 FROM public.journey_segments WHERE tag_id = 'KF1' AND capture_source <> 'carrier'),
                     'KF1: tramos rehechos con los eventos tardios');
  PERFORM pg_temp.ok(pg_temp.snap() = (SELECT current_setting('cl_test.kenya_sin')), 'entrada tardia: lo RFID identico');
  j := public.admin_reset_account_data('a0000000-0000-0000-0000-000000000001');
  PERFORM pg_temp.ok((j->>'success')::boolean, 'reinicio de cuenta: ' || j::text);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.readers WHERE capture_source = 'carrier_scan'
                                   AND account_id = 'a0000000-0000-0000-0000-000000000001'), 'puntos borrados');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.processed_events WHERE reader_id_snapshot LIKE 'CL:%')
                     AND NOT EXISTS (SELECT 1 FROM public.rfid_events_raw WHERE event_id LIKE 'cl:%')
                     AND NOT EXISTS (SELECT 1 FROM public.journeys WHERE tag_id = 'KF1'), 'diagnostico del carrier borrado');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.readers WHERE capture_source = 'rfid'
                       AND account_id = 'a0000000-0000-0000-0000-000000000001') = 3, 'lectores RFID intactos');
END $$;

-- ================================================================ 7. estructura y privilegios
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT p.oid::regprocedure::text AS fn, p.prosecdef, p.proconfig
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public'
              AND p.proname IN ('cl_diagnosis_feed_item','cl_diagnosis_point_alerts','cl_diagnosis_remove',
                                'cl_processed_events_capture_source','cl_journey_segments_capture_source',
                                'cl_readers_delete_diagnosis','cl_diagnosis_retry_pending','cl_readers_retry_diagnosis')
  LOOP
    PERFORM pg_temp.ok(r.prosecdef AND 'search_path=public, extensions' = ANY (r.proconfig), r.fn || ' definer + search_path');
    PERFORM pg_temp.ok(NOT has_function_privilege('service_role', r.fn, 'EXECUTE')
                       AND NOT has_function_privilege('authenticated', r.fn, 'EXECUTE')
                       AND NOT has_function_privilege('anon', r.fn, 'EXECUTE'), r.fn || ' sin grants');
  END LOOP;
  PERFORM pg_temp.ok((SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                       WHERE n.nspname = 'public' AND p.proname IN ('cl_diagnosis_feed_item','cl_diagnosis_point_alerts',
                         'cl_diagnosis_remove','cl_processed_events_capture_source','cl_journey_segments_capture_source',
                         'cl_readers_delete_diagnosis','cl_diagnosis_retry_pending','cl_readers_retry_diagnosis')) = 8,
                     'ocho funciones SECURITY DEFINER nuevas');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', 'public.cl_diagnosis_event_id(text,text,timestamptz)', 'EXECUTE')
                     AND NOT has_function_privilege('service_role', 'public.cl_diagnosis_event_id(text,text,timestamptz)', 'EXECUTE'),
                     'cl_diagnosis_event_id sin grants');
  PERFORM pg_temp.ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.cl_diagnosis_pending'::regclass)
                     AND NOT EXISTS (SELECT 1 FROM information_schema.role_table_grants WHERE table_name = 'cl_diagnosis_pending'
                                       AND grantee IN ('anon','authenticated','service_role','PUBLIC')),
                     'cl_diagnosis_pending con RLS y sin privilegios');
  -- El disparador de eventos solo mira lectores CL: (las filas RFID no lo llaman).
  PERFORM pg_temp.ok(pg_get_triggerdef((SELECT oid FROM pg_trigger WHERE tgname = 'cl_processed_events_capture_source'))
                     LIKE '%reader_id_snapshot ~~ ''CL:%', 'WHEN del disparador de eventos');
  PERFORM pg_temp.ok(pg_get_triggerdef((SELECT oid FROM pg_trigger WHERE tgname = 'cl_readers_delete_diagnosis'))
                     LIKE '%carrier_scan%', 'WHEN del disparador de readers (borrado)');
  PERFORM pg_temp.ok(pg_get_triggerdef((SELECT oid FROM pg_trigger WHERE tgname = 'cl_readers_retry_diagnosis'))
                     LIKE '%carrier_scan%', 'WHEN del disparador de readers (entrada tardia)');
END $$;

ROLLBACK;
