-- Carrier Link fase 1, tarea 8: sorteo reproducible, muestra y paso a la base E2E.
-- Escenario construido con las funciones reales (cuotas, activacion, emision y entrada del lote).
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.sqlstate_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE; END $$;

-- Ciudades del fixture: City1 (c1), City2 (c2) y City3 (c3, creada aqui).
CREATE OR REPLACE FUNCTION pg_temp.q(p_o text, p_d text, p_week int) RETURNS uuid LANGUAGE sql AS $$
  SELECT q.id FROM public.cl_plan_quotas q
   WHERE q.plan_id = '90000000-0000-0000-0000-0000000000a1' AND q.iso_week = p_week
     AND q.origin_city_id = (SELECT id FROM public.cities WHERE name = p_o AND account_id = 'a0000000-0000-0000-0000-000000000001')
     AND q.destination_city_id = (SELECT id FROM public.cities WHERE name = p_d AND account_id = 'a0000000-0000-0000-0000-000000000001')
$$;

CREATE OR REPLACE FUNCTION pg_temp.rd(p_trk text, p_ts text, p_office text, p_evt text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('trk', p_trk, 'ts', p_ts, 'office', p_office, 'evt', p_evt, 'weight', '1.2')
$$;

CREATE OR REPLACE FUNCTION pg_temp.stratum(p_id uuid, p_pop int, p_rows jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('stratum_id', p_id, 'population_size', p_pop,
                            'selection_method', 'uniform_random_within_stratum', 'rows', p_rows)
$$;

-- Maestros, conector y plan (borrador -> cuotas -> activo). p_q1 = muestras de la cuota City1->City2 W43.
CREATE OR REPLACE FUNCTION pg_temp.setup(p_q1 int) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
    ('c3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City3','C3');
  INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
    ('d1000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001'),
    ('d2000000-0000-0000-0000-0000000000c2','a0000000-0000-0000-0000-000000000001','PC2','Center 2','City2','c2000000-0000-0000-0000-000000000002'),
    ('d3000000-0000-0000-0000-0000000000c3','a0000000-0000-0000-0000-000000000001','PC3','Center 3','City3','c3000000-0000-0000-0000-000000000003');
  INSERT INTO public.readers (id, account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role) VALUES
    ('ad000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','NBO ADM','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','NBO','ADM','origin'),
    ('ad000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-0000000000c2','MBA any','Exit','carrier_scan','ca000000-0000-0000-0000-000000000001','MBA',NULL,'destination'),
    ('ad000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-0000000000c2','KSM any','Exit','carrier_scan','ca000000-0000-0000-0000-000000000001','KSM',NULL,'destination'),
    ('ad000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-0000000000c2','MBA ADM','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','MBA','ADM','origin'),
    ('ad000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','NBO any','Exit','carrier_scan','ca000000-0000-0000-0000-000000000001','NBO',NULL,'destination'),
    ('ad000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','ELD any','Exit','carrier_scan','ca000000-0000-0000-0000-000000000001','ELD',NULL,'destination');
  INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status) VALUES
    ('f0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed A1','active');
  INSERT INTO public.cl_field_mappings (account_id, carrier_id, standard_field, carrier_field) VALUES
    ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','item_id','trk'),
    ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','scan_at','ts'),
    ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','place_ref','office'),
    ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','mode_ref','evt');
  INSERT INTO public.cl_extra_fields (account_id, carrier_id, carrier_field) VALUES
    ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','weight');
  -- Estandar City1 -> City2: 48 h, ultimo tramo 12 h. City2 -> City1 sin estandar.
  INSERT INTO public.delivery_standards (account_id, carrier_id, product_id, origin_city_id, destination_city_id, standard_time, time_unit, cl_first_mile_time, cl_last_mile_time)
  VALUES ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',
          'c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002', 48, 'hours', 0, 12);
  INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, feed_id) VALUES
    ('90000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','CL Oct','ca000000-0000-0000-0000-000000000001',
     'cb000000-0000-0000-0000-000000000001', 13, '2026-10-19', '2026-11-01', 'f0000000-0000-0000-0000-0000000000a1');
  PERFORM public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a1', jsonb_build_array(
    jsonb_build_object('origin_city_id','c1000000-0000-0000-0000-000000000001','destination_city_id','c2000000-0000-0000-0000-000000000002','iso_year',2026,'iso_week',43,'samples',p_q1),
    jsonb_build_object('origin_city_id','c2000000-0000-0000-0000-000000000002','destination_city_id','c1000000-0000-0000-0000-000000000001','iso_year',2026,'iso_week',43,'samples',4),
    jsonb_build_object('origin_city_id','c1000000-0000-0000-0000-000000000001','destination_city_id','c2000000-0000-0000-0000-000000000002','iso_year',2026,'iso_week',44,'samples',5)));
  PERFORM public.cl_plan_activate('90000000-0000-0000-0000-0000000000a1');
  -- Lunes 2026-11-09 03:00 (zona de la cuenta, UTC): vencen W43 y W44 -> una demanda con tres estratos.
  PERFORM pg_temp.ok(public.cl_emit_due_demands(TIMESTAMPTZ '2026-11-09 03:00:00+00') = 1, 'setup: una demanda emitida');
END $$;

-- Lecturas de City1 -> City2 W43: n envios A01.. de 40 h habiles (lunes 08:00 -> miercoles 00:00) y uno sin fin.
CREATE OR REPLACE FUNCTION pg_temp.rows_q1(p_n int, p_end text DEFAULT '2026-10-21T00:00:00Z') RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_agg(x ORDER BY o) FROM (
    SELECT 2 * g AS o, pg_temp.rd('A' || lpad(g::text, 2, '0'), '2026-10-19T08:00:00Z', 'NBO', 'ADM') AS x FROM generate_series(1, p_n) g
    UNION ALL
    SELECT 2 * g + 1, pg_temp.rd('A' || lpad(g::text, 2, '0'), p_end, 'MBA', 'DLV') FROM generate_series(1, p_n) g
    UNION ALL
    SELECT 1000, pg_temp.rd('A99', '2026-10-19T08:00:00Z', 'NBO', 'ADM')) s
$$;

CREATE OR REPLACE FUNCTION pg_temp.batch_main(p_q1_rows jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('demand_id', (SELECT id FROM public.cl_demands), 'batch_id', 'B1', 'strata', jsonb_build_array(
    pg_temp.stratum(pg_temp.q('City1','City2',43), 40, p_q1_rows),
    -- City2 -> City1 W43: tres envios normales (uno con guiones, espacio y ceros a la izquierda) y B4, cuyo punto de
    -- fin (ELD) se movio a City3 despues de emitir la demanda.
    pg_temp.stratum(pg_temp.q('City2','City1',43), 4, jsonb_build_array(
      pg_temp.rd('00-12 34', '2026-10-20T08:00:00Z', 'MBA', 'ADM'), pg_temp.rd('00-12 34', '2026-10-21T08:00:00Z', 'NBO', 'DLV'),
      pg_temp.rd('B2',       '2026-10-20T08:00:00Z', 'MBA', 'ADM'), pg_temp.rd('B2',       '2026-10-21T08:00:00Z', 'NBO', 'DLV'),
      pg_temp.rd('B3',       '2026-10-20T08:00:00Z', 'MBA', 'ADM'), pg_temp.rd('B3',       '2026-10-21T08:00:00Z', 'NBO', 'DLV'),
      pg_temp.rd('B4',       '2026-10-20T08:00:00Z', 'MBA', 'ADM'), pg_temp.rd('B4',       '2026-10-21T08:00:00Z', 'ELD', 'DLV'))),
    -- City1 -> City2 W44 (cuota 5, solo 2 validos): C1 con fin en dos puntos (MBA y KSM), C2 de 12 h.
    pg_temp.stratum(pg_temp.q('City1','City2',44), 2, jsonb_build_array(
      pg_temp.rd('C1', '2026-10-26T08:00:00Z', 'NBO', 'ADM'), pg_temp.rd('C1', '2026-10-27T08:00:00Z', 'MBA', 'DLV'),
      pg_temp.rd('C1', '2026-10-27T10:00:00Z', 'KSM', 'DLV'),
      pg_temp.rd('C2', '2026-10-26T08:00:00Z', 'NBO', 'ADM'), pg_temp.rd('C2', '2026-10-26T20:00:00Z', 'MBA', 'DLV')))))
$$;

-- ===================================================================== Escenario principal
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
SELECT pg_temp.setup(4);
-- El punto ELD se corrige a un centro de City3 despues de emitir (el punto sigue en la foto de la demanda).
UPDATE public.readers SET postal_center_id = 'd3000000-0000-0000-0000-0000000000c3' WHERE id = 'ad000000-0000-0000-0000-000000000006';
SELECT set_config('t.batch', (public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.batch_main(pg_temp.rows_q1(10)))->>'batch'), true);

-- 1. Permisos.
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.cl_sample_stratum(uuid,uuid)','public.cl_finish_batch(uuid)','public.cl_transfer_sample(uuid)'] LOOP
    PERFORM pg_temp.ok((SELECT prosecdef FROM pg_proc WHERE oid = f::regprocedure), f || ' SECURITY DEFINER');
    PERFORM pg_temp.ok((SELECT 'search_path=public, extensions' = ANY (proconfig) FROM pg_proc WHERE oid = f::regprocedure), f || ' search_path');
    PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', f, 'EXECUTE'), f || ' authenticated no ejecuta');
    PERFORM pg_temp.ok(NOT has_function_privilege('anon', f, 'EXECUTE'), f || ' anon no ejecuta');
  END LOOP;
  PERFORM pg_temp.ok(has_function_privilege('service_role','public.cl_sample_stratum(uuid,uuid)','EXECUTE'), 'service_role sortea');
  PERFORM pg_temp.ok(has_function_privilege('service_role','public.cl_finish_batch(uuid)','EXECUTE'), 'service_role cierra el lote');
  PERFORM pg_temp.ok(NOT has_function_privilege('service_role','public.cl_transfer_sample(uuid)','EXECUTE'), 'transfer interna');
END $$;

-- 2. Sorteo de 4 entre 10 validos (A99 sin fin no entra), orden por md5(semilla:item_id).
DO $$
DECLARE r jsonb; v_seed text; v_exp text[]; v_q uuid := pg_temp.q('City1','City2',43);
BEGIN
  PERFORM pg_temp.ok((SELECT status FROM public.cl_batches WHERE id = current_setting('t.batch')::uuid) = 'validated', 'lote validado');
  SELECT random_seed INTO v_seed FROM public.cl_demands;
  SELECT array_agg(i ORDER BY md5(v_seed || ':' || i), i COLLATE "C") INTO v_exp
    FROM (SELECT i FROM unnest(ARRAY['A01','A02','A03','A04','A05','A06','A07','A08','A09','A10']) i
           ORDER BY md5(v_seed || ':' || i), i COLLATE "C" LIMIT 4) s;
  r := public.cl_sample_stratum(current_setting('t.batch')::uuid, v_q);
  PERFORM pg_temp.ok((r->>'samples_selected')::int = 4 AND (r->>'samples_required')::int = 4, 'selecciona 4: ' || r::text);
  PERFORM pg_temp.ok((r->>'candidates_valid')::int = 10 AND (r->>'population_size')::int = 40, 'validos 10, poblacion 40: ' || r::text);
  PERFORM pg_temp.ok(ARRAY(SELECT jsonb_array_elements_text(r->'selected_item_ids')) = v_exp, 'orden md5(semilla:item_id): ' || r::text);
  PERFORM pg_temp.ok((SELECT selected_item_ids = v_exp AND random_seed = v_seed AND samples_selected = 4
                        FROM public.cl_sampling_runs WHERE stratum_id = v_q), 'cl_sampling_runs con semilla y elegidos');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_samples WHERE quota_id = v_q) = 4, '4 muestras');
  PERFORM pg_temp.ok((SELECT samples_obtained FROM public.cl_plan_quotas WHERE id = v_q) = 4, 'samples_obtained 4');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.one_db o JOIN public.cl_samples s ON s.id = o.cl_sample_id WHERE s.quota_id = v_q) = 4, '4 filas one_db');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_samples WHERE item_id = 'A99'), 'A99 (no valido) nunca se elige');
  PERFORM pg_temp.ok((SELECT bool_and(s.start_reader_id = 'ad000000-0000-0000-0000-000000000001' AND s.end_reader_id = 'ad000000-0000-0000-0000-000000000002'
                                      AND s.start_at = '2026-10-19 08:00Z' AND s.end_at = '2026-10-21 00:00Z'
                                      AND s.origin_city_id = 'c1000000-0000-0000-0000-000000000001' AND s.destination_city_id = 'c2000000-0000-0000-0000-000000000002'
                                      AND NOT s.possible_misrouting AND s.extra = '{"weight":"1.2"}'::jsonb
                                      AND s.batch_id = current_setting('t.batch')::uuid AND s.plan_id = '90000000-0000-0000-0000-0000000000a1'
                                      AND s.carrier_id = 'ca000000-0000-0000-0000-000000000001' AND s.product_id = 'cb000000-0000-0000-0000-000000000001')
                        FROM public.cl_samples s WHERE s.quota_id = v_q), 'muestras con inicio, fin, ciudades y extra');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_sample_scans x JOIN public.cl_samples s ON s.id = x.sample_id WHERE s.quota_id = v_q) = 8
                     AND (SELECT count(*) FILTER (WHERE x.role = 'start') = 4 AND count(*) FILTER (WHERE x.role = 'end') = 4
                            FROM public.cl_sample_scans x JOIN public.cl_samples s ON s.id = x.sample_id WHERE s.quota_id = v_q), 'lecturas de inicio y fin con su papel');
END $$;

-- 3. Paso a E2E: 40 h habiles medidas + 12 h de ultimo tramo = 52 > 48 -> fuera de plazo.
DO $$
DECLARE v_q uuid := pg_temp.q('City1','City2',43);
BEGIN
  PERFORM pg_temp.ok((SELECT bool_and(o.source = 'carrier' AND o.tag_id = s.item_id AND o.carrier_id = s.carrier_id
                                      AND o.plan_name = 'CL Oct' AND o.carrier_name = 'Carrier' AND o.product_name = 'Prod'
                                      AND o.origin_city_name = 'City1' AND o.destination_city_name = 'City2'
                                      AND o.sent_at = s.start_at AND o.received_at = s.end_at AND o.allocation_detail_id IS NULL
                                      AND o.equivalence_hours = 12 AND o.equivalence_days = 1
                                      AND o.measured_business_hours = 40 AND o.business_transit_hours = 52
                                      AND o.on_time_delivery = false)
                        FROM public.one_db o JOIN public.cl_samples s ON s.id = o.cl_sample_id WHERE s.quota_id = v_q), 'one_db carrier: 40 + 12 = 52 h, fuera de plazo');
  PERFORM pg_temp.ok((SELECT bool_and(o.source_data_snapshot->>'sample_id' = s.id::text
                                      AND o.source_data_snapshot->>'plan_id' = s.plan_id::text
                                      AND o.source_data_snapshot->>'start_reader_id' = s.start_reader_id::text
                                      AND o.source_data_snapshot->>'end_reader_id' = s.end_reader_id::text
                                      AND o.source_data_snapshot->>'origin_city_id' = s.origin_city_id::text
                                      AND o.source_data_snapshot->>'destination_city_id' = s.destination_city_id::text
                                      AND o.source_data_snapshot->'extra' = s.extra)
                        FROM public.one_db o JOIN public.cl_samples s ON s.id = o.cl_sample_id WHERE s.quota_id = v_q), 'source_data_snapshot');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_alerts WHERE alert_type IN ('insufficient_candidates','missing_standard','possible_misrouting','suspicious_distribution')),
                     'sin alertas en el estrato normal');
END $$;

-- 4. Repetir el sorteo del estrato: mismo resumen, nada nuevo. Lote sin terminar: cl_finish_batch no cierra.
DO $$
DECLARE r1 jsonb; r2 jsonb; v_q uuid := pg_temp.q('City1','City2',43); f jsonb;
BEGIN
  SELECT jsonb_build_object('n', count(*)) INTO r1 FROM public.cl_samples;
  r1 := public.cl_sample_stratum(current_setting('t.batch')::uuid, v_q);
  r2 := public.cl_sample_stratum(current_setting('t.batch')::uuid, v_q);
  PERFORM pg_temp.ok(r1 = r2, 'mismo resumen');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_samples) = 4 AND (SELECT count(*) FROM public.one_db) = 4
                     AND (SELECT count(*) FROM public.cl_sampling_runs) = 1 AND (SELECT count(*) FROM public.cl_sample_scans) = 8, 'sin filas nuevas');
  PERFORM pg_temp.ok((SELECT samples_obtained FROM public.cl_plan_quotas WHERE id = v_q) = 4, 'samples_obtained sigue en 4');
  f := public.cl_finish_batch(current_setting('t.batch')::uuid);
  PERFORM pg_temp.ok(f->>'status' = 'pending' AND jsonb_array_length(f->'strata_pending') = 2, 'finish: faltan 2 estratos: ' || f::text);
  PERFORM pg_temp.ok((SELECT status FROM public.cl_batches WHERE id = current_setting('t.batch')::uuid) = 'validated', 'lote sigue validated');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_demands) = 'open', 'demanda sigue open');
  -- un estrato ajeno al lote
  PERFORM pg_temp.ok(pg_temp.sqlstate_of(format('SELECT public.cl_sample_stratum(%L, %L)', current_setting('t.batch'), gen_random_uuid())) = '22023', 'estrato ajeno: 22023');
END $$;

-- 5. Ruta sin estandar (City2 -> City1): 3 muestras sin "en plazo" y una sola alerta missing_standard.
--    B4 termina en un punto ahora en City3: muestra creada, possible_misrouting, destino real City3; cuenta para su cuota.
DO $$
DECLARE r jsonb; v_q uuid := pg_temp.q('City2','City1',43);
BEGIN
  r := public.cl_sample_stratum(current_setting('t.batch')::uuid, v_q);
  PERFORM pg_temp.ok((r->>'samples_selected')::int = 4, 'Q2: 4 muestras: ' || r::text);
  PERFORM pg_temp.ok((SELECT samples_obtained FROM public.cl_plan_quotas WHERE id = v_q) = 4, 'B4 cuenta para la cuota de la que salio');
  PERFORM pg_temp.ok((SELECT o.tag_id FROM public.one_db o JOIN public.cl_samples s ON s.id = o.cl_sample_id WHERE s.item_id = '00-12 34') = '00-12 34', 'tag_id tal cual');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.one_db WHERE origin_city_name = 'City2' AND destination_city_name = 'City1'
                         AND on_time_delivery IS NULL AND business_transit_hours = 24 AND equivalence_hours IS NULL) = 3, '3 muestras sin estandar: on_time NULL');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE alert_type = 'missing_standard'
                        AND details->>'origin_city_id' = 'c2000000-0000-0000-0000-000000000002'
                        AND details->>'destination_city_id' = 'c1000000-0000-0000-0000-000000000001') = 1, 'una sola alerta missing_standard para 3 muestras');
  PERFORM pg_temp.ok((SELECT s.possible_misrouting AND s.destination_city_id = 'c3000000-0000-0000-0000-000000000003' AND s.quota_id = v_q
                        FROM public.cl_samples s WHERE s.item_id = 'B4'), 'B4 possible_misrouting, destino City3');
  PERFORM pg_temp.ok((SELECT o.destination_city_name = 'City3' AND o.origin_city_name = 'City2' AND o.on_time_delivery IS NULL
                        FROM public.one_db o JOIN public.cl_samples s ON s.id = o.cl_sample_id WHERE s.item_id = 'B4'), 'one_db con la ciudad real');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE alert_type = 'missing_standard'
                        AND details->>'destination_city_id' = 'c3000000-0000-0000-0000-000000000003') = 1, 'alerta missing_standard de la ruta real de B4');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE alert_type = 'possible_misrouting' AND quota_id = v_q
                        AND details->'item_ids' = '["B4"]'::jsonb) = 1, 'alerta possible_misrouting con B4');
  PERFORM pg_temp.ok(NOT (SELECT bool_or(possible_misrouting) FROM public.cl_samples WHERE quota_id = v_q AND item_id <> 'B4'), 'el resto no');
END $$;

-- 6. Pocos candidatos (2 para 5): se toman todos, alerta insufficient_candidates; C1 con fin en dos puntos.
DO $$
DECLARE r jsonb; v_q uuid := pg_temp.q('City1','City2',44);
BEGIN
  r := public.cl_sample_stratum(current_setting('t.batch')::uuid, v_q);
  PERFORM pg_temp.ok((r->>'samples_selected')::int = 2 AND (r->>'samples_required')::int = 5, 'Q3: 2 de 5: ' || r::text);
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM public.cl_alerts WHERE alert_type = 'insufficient_candidates' AND quota_id = v_q), 'alerta insufficient_candidates');
  PERFORM pg_temp.ok((SELECT possible_misrouting AND end_reader_id = 'ad000000-0000-0000-0000-000000000003' AND end_at = '2026-10-27 10:00Z'
                             AND destination_city_id = 'c2000000-0000-0000-0000-000000000002'
                        FROM public.cl_samples WHERE item_id = 'C1'), 'C1: fin = ultima lectura de fin, dos puntos de fin -> misrouting');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_sample_scans x JOIN public.cl_samples s ON s.id = x.sample_id
                       WHERE s.item_id = 'C1' AND x.role = 'end') = 2, 'C1 guarda sus dos lecturas de fin');
  PERFORM pg_temp.ok((SELECT NOT possible_misrouting FROM public.cl_samples WHERE item_id = 'C2'), 'C2 normal');
  PERFORM pg_temp.ok((SELECT on_time_delivery AND business_transit_hours = 24 FROM public.one_db WHERE tag_id = 'C2'), 'C2: 12 + 12 = 24 h, en plazo');
END $$;

-- 7. Cierre del lote: sampled; demanda partial (Q3 incompleta); Q1 y Q2 fulfilled, Q3 sigue open.
DO $$
DECLARE f jsonb; f2 jsonb;
BEGIN
  f := public.cl_finish_batch(current_setting('t.batch')::uuid);
  PERFORM pg_temp.ok(f->>'status' = 'sampled' AND f->>'demand_status' = 'partial', 'finish: ' || f::text);
  PERFORM pg_temp.ok((SELECT status FROM public.cl_batches WHERE id = current_setting('t.batch')::uuid) = 'sampled', 'lote sampled');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_demands) = 'partial', 'demanda partial');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plan_quotas WHERE id = pg_temp.q('City1','City2',43)) = 'fulfilled', 'Q1 fulfilled');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plan_quotas WHERE id = pg_temp.q('City2','City1',43)) = 'fulfilled', 'Q2 fulfilled');
  PERFORM pg_temp.ok((SELECT status = 'open' AND samples_obtained = 2 FROM public.cl_plan_quotas WHERE id = pg_temp.q('City1','City2',44)), 'Q3 open con 2');
  f2 := public.cl_finish_batch(current_setting('t.batch')::uuid);
  PERFORM pg_temp.ok(f2 = f, 'finish idempotente');
  -- un lote ya muestreado devuelve el resumen guardado
  PERFORM pg_temp.ok((public.cl_sample_stratum(current_setting('t.batch')::uuid, pg_temp.q('City1','City2',44))->>'samples_selected')::int = 2, 'resumen tras sampled');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_alerts WHERE alert_type = 'suspicious_distribution'), 'n < 20: sin suspicious_distribution');
END $$;

-- 8. RLS/privilegios: authenticated solo lee las tablas del motor; one_db.cl_sample_id restringe el borrado.
DO $$
BEGIN
  PERFORM pg_temp.ok(NOT has_table_privilege('authenticated','public.cl_samples','INSERT')
                     AND NOT has_table_privilege('authenticated','public.cl_sampling_runs','INSERT')
                     AND NOT has_table_privilege('authenticated','public.cl_sample_scans','INSERT'), 'motor solo lectura');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of(format('DELETE FROM public.cl_samples WHERE item_id = %L', 'C2')) = '23503', 'muestra con fila one_db: no se borra');
END $$;

-- Para el escenario repetido.
SELECT random_seed AS seed FROM public.cl_demands \gset
SELECT array_to_string(selected_item_ids, ',') AS sel FROM public.cl_sampling_runs WHERE stratum_id = pg_temp.q('City1','City2',43) \gset
ROLLBACK;

-- ===================================================================== Mismo escenario, misma semilla fija: mismos item_id
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
SELECT pg_temp.setup(4);
UPDATE public.cl_demands SET random_seed = :'seed';
SELECT set_config('t.batch', (public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1', pg_temp.batch_main(pg_temp.rows_q1(10)))->>'batch'), true);
SELECT pg_temp.ok(array_to_string(ARRAY(SELECT jsonb_array_elements_text(
         public.cl_sample_stratum(current_setting('t.batch')::uuid, pg_temp.q('City1','City2',43))->'selected_item_ids')), ',') = :'sel',
       'misma semilla -> mismos item_id');
SELECT pg_temp.ok((SELECT array_agg(item_id ORDER BY item_id) FROM public.cl_samples)
                  = (SELECT array_agg(x ORDER BY x) FROM unnest(string_to_array(:'sel', ',')) x), 'mismas muestras');
ROLLBACK;

-- ===================================================================== 20 muestras, todas en plazo: suspicious_distribution
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
SELECT pg_temp.setup(20);
SELECT set_config('t.batch', (public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1',
         pg_temp.batch_main(pg_temp.rows_q1(20, '2026-10-19T20:00:00Z')))->>'batch'), true);
DO $$
DECLARE r jsonb; v_q uuid := pg_temp.q('City1','City2',43);
BEGIN
  r := public.cl_sample_stratum(current_setting('t.batch')::uuid, v_q);
  PERFORM pg_temp.ok((r->>'samples_selected')::int = 20, '20 muestras: ' || r::text);
  PERFORM pg_temp.ok((SELECT bool_and(on_time_delivery) AND count(*) = 20 FROM public.one_db), 'todas en plazo (12 + 12 = 24 h)');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM public.cl_alerts WHERE alert_type = 'suspicious_distribution' AND quota_id = v_q), 'alerta suspicious_distribution');
END $$;
ROLLBACK;
