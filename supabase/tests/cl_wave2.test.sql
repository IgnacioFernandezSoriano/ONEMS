-- Carrier Link, ola 2 de correcciones (20261120111000_cl_wave2_fixes.sql).
-- D1 alertas tras deshacer; D2 demandas de prueba solo dry_run; D3 reader_id sin espacios; D4 "ultima demanda" monotona;
-- D5 sin NOTICE de pg_temp.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.msg_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE || ':' || SQLERRM; END $$;

CREATE OR REPLACE FUNCTION pg_temp.qw(p_week int) RETURNS uuid LANGUAGE sql AS $$
  SELECT q.id FROM public.cl_plan_quotas q
   WHERE q.plan_id = '90000000-0000-0000-0000-0000000000a1' AND q.iso_year = 2026 AND q.iso_week = p_week
$$;

CREATE OR REPLACE FUNCTION pg_temp.qcol(p_week int) RETURNS public.cl_plan_quotas LANGUAGE sql AS $$
  SELECT q.* FROM public.cl_plan_quotas q WHERE q.id = pg_temp.qw(p_week)
$$;

-- Maestros, conector (activo) y plan activo con cuotas City1 -> City2 (close_lag_days = 0). GAR: destino en City3
-- (fuera de la ruta: una lectura alli marca posible mal encaminado). p_std = con estandar City1 -> City2.
CREATE OR REPLACE FUNCTION pg_temp.setup(p_weeks int[], p_samples int[], p_std boolean DEFAULT true) RETURNS void LANGUAGE plpgsql AS $$
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
    ('ad000000-0000-0000-0000-000000000008','a0000000-0000-0000-0000-000000000001','d3000000-0000-0000-0000-0000000000c3','GAR any','Exit','carrier_scan','ca000000-0000-0000-0000-000000000001','GAR',NULL,'destination');
  INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status) VALUES
    ('f0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed A1','active');
  INSERT INTO public.cl_field_mappings (account_id, carrier_id, standard_field, carrier_field) VALUES
    ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','item_id','trk'),
    ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','scan_at','ts'),
    ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','place_ref','office'),
    ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','mode_ref','evt');
  IF p_std THEN
    INSERT INTO public.delivery_standards (account_id, carrier_id, product_id, origin_city_id, destination_city_id, standard_time, time_unit, cl_first_mile_time, cl_last_mile_time)
    VALUES ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',
            'c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002', 48, 'hours', 0, 12);
  END IF;
  INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, feed_id, close_lag_days) VALUES
    ('90000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','CL Q4','ca000000-0000-0000-0000-000000000001',
     'cb000000-0000-0000-0000-000000000001', 100, '2026-10-05', '2026-12-13', 'f0000000-0000-0000-0000-0000000000a1', 0);
  PERFORM public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a1',
    (SELECT jsonb_agg(jsonb_build_object('origin_city_id','c1000000-0000-0000-0000-000000000001',
                                         'destination_city_id','c2000000-0000-0000-0000-000000000002',
                                         'iso_year',2026,'iso_week',w,'samples',s))
       FROM unnest(p_weeks, p_samples) u(w, s)));
  PERFORM public.cl_plan_activate('90000000-0000-0000-0000-0000000000a1');
END $$;

CREATE OR REPLACE FUNCTION pg_temp.emit(p_now timestamptz) RETURNS uuid LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.ok(public.cl_emit_due_demands(p_now) = 1, 'una demanda emitida en ' || p_now);
  RETURN (SELECT id FROM public.cl_demands WHERE requested_at = p_now);
END $$;

-- Un estrato: cada envio empieza en NBO ADM el lunes 08:00 y termina en MBA el martes 08:00; los de p_gar pasan
-- ademas por GAR (City3) el lunes 20:00; los de p_noend no tienen fin (no_end).
CREATE OR REPLACE FUNCTION pg_temp.stratum(p_week int, p_pop int, p_items text[], p_gar text[] DEFAULT '{}',
                                           p_noend text[] DEFAULT '{}') RETURNS jsonb LANGUAGE sql AS $$
  WITH d AS (SELECT period_start AS ps FROM public.cl_plan_quotas WHERE id = pg_temp.qw(p_week))
  SELECT jsonb_build_object('stratum_id', pg_temp.qw(p_week), 'population_size', p_pop,
                            'selection_method', 'uniform_random_within_stratum',
                            'rows', COALESCE((SELECT jsonb_agg(r ORDER BY o) FROM (
                               SELECT 3 * i AS o, jsonb_build_object('trk', it, 'office', 'NBO', 'evt', 'ADM',
                                        'ts', to_char(d.ps, 'YYYY-MM-DD') || 'T08:00:00Z') AS r
                                 FROM unnest(p_items) WITH ORDINALITY u(it, i), d
                               UNION ALL
                               SELECT 3 * i + 1, jsonb_build_object('trk', it, 'office', 'GAR', 'evt', 'DLV',
                                        'ts', to_char(d.ps, 'YYYY-MM-DD') || 'T20:00:00Z')
                                 FROM unnest(p_items) WITH ORDINALITY u(it, i), d WHERE it = ANY (p_gar)
                               UNION ALL
                               SELECT 3 * i + 2, jsonb_build_object('trk', it, 'office', 'MBA', 'evt', 'DLV',
                                        'ts', to_char(d.ps + 1, 'YYYY-MM-DD') || 'T08:00:00Z')
                                 FROM unnest(p_items) WITH ORDINALITY u(it, i), d WHERE NOT (it = ANY (p_noend))) s), '[]'::jsonb))
$$;

CREATE OR REPLACE FUNCTION pg_temp.ingest(p_demand uuid, p_cbid text, p_strata jsonb, p_dry boolean DEFAULT false) RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1',
           jsonb_build_object('demand_id', p_demand, 'batch_id', p_cbid, 'strata', p_strata), p_dry)
$$;

-- Entrada + sorteo de todos los estratos + cierre (como la funcion carrier-link-ingest). Devuelve el lote.
CREATE OR REPLACE FUNCTION pg_temp.deliver(p_demand uuid, p_cbid text, p_strata jsonb) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v_b uuid; s jsonb;
BEGIN
  v_b := (pg_temp.ingest(p_demand, p_cbid, p_strata)->>'batch')::uuid;
  FOR s IN SELECT jsonb_array_elements(p_strata) LOOP
    PERFORM public.cl_sample_stratum(v_b, (s->>'stratum_id')::uuid);
  END LOOP;
  PERFORM public.cl_finish_batch(v_b);
  RETURN v_b;
END $$;

-- ===================================================================== 0. Estructura y permisos
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
DO $$
BEGIN
  PERFORM pg_temp.ok(to_regprocedure('public.cl_raise_alert(uuid,uuid,text,text,jsonb)') IS NULL, 'sin la firma antigua de cl_raise_alert');
  PERFORM pg_temp.ok(to_regprocedure('public.cl_raise_alert(uuid,uuid,text,text,jsonb,uuid)') IS NOT NULL, 'cl_raise_alert con p_batch_id');
  PERFORM pg_temp.ok((SELECT bool_and(prosecdef AND 'search_path=public, extensions' = ANY (proconfig)) FROM pg_proc
                       WHERE oid IN ('public.cl_raise_alert(uuid,uuid,text,text,jsonb,uuid)'::regprocedure,
                                     'public.cl_ingest_batch(uuid,jsonb,boolean)'::regprocedure,
                                     'public.cl_sample_stratum(uuid,uuid)'::regprocedure,
                                     'public.cl_undo_batch(uuid)'::regprocedure,
                                     'public.cl_settle_quota(uuid)'::regprocedure,
                                     'public.cl_feeds_on_activate()'::regprocedure,
                                     'public.readers_cl_defaults()'::regprocedure)), 'SECURITY DEFINER + search_path');
  PERFORM pg_temp.ok(NOT has_function_privilege('service_role','public.cl_raise_alert(uuid,uuid,text,text,jsonb,uuid)','EXECUTE')
                     AND NOT has_function_privilege('authenticated','public.cl_raise_alert(uuid,uuid,text,text,jsonb,uuid)','EXECUTE')
                     AND NOT has_function_privilege('anon','public.cl_raise_alert(uuid,uuid,text,text,jsonb,uuid)','EXECUTE'), 'raise_alert interna');
  PERFORM pg_temp.ok(has_function_privilege('service_role','public.cl_ingest_batch(uuid,jsonb,boolean)','EXECUTE')
                     AND NOT has_function_privilege('authenticated','public.cl_ingest_batch(uuid,jsonb,boolean)','EXECUTE')
                     AND NOT has_function_privilege('anon','public.cl_ingest_batch(uuid,jsonb,boolean)','EXECUTE'), 'ingest: solo service_role');
  PERFORM pg_temp.ok(has_function_privilege('service_role','public.cl_sample_stratum(uuid,uuid)','EXECUTE')
                     AND NOT has_function_privilege('authenticated','public.cl_sample_stratum(uuid,uuid)','EXECUTE'), 'sample: solo service_role');
  PERFORM pg_temp.ok(has_function_privilege('authenticated','public.cl_undo_batch(uuid)','EXECUTE')
                     AND NOT has_function_privilege('anon','public.cl_undo_batch(uuid)','EXECUTE'), 'undo grants');
  PERFORM pg_temp.ok(NOT has_function_privilege('service_role','public.cl_settle_quota(uuid)','EXECUTE')
                     AND NOT has_function_privilege('authenticated','public.cl_settle_quota(uuid)','EXECUTE'), 'settle interna');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated','public.cl_feeds_on_activate()','EXECUTE')
                     AND NOT has_function_privilege('anon','public.cl_feeds_on_activate()','EXECUTE'), 'trigger de activacion sin EXECUTE');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'cl_feeds_on_activate' AND tgrelid = 'public.cl_feeds'::regclass), 'trigger cl_feeds_on_activate');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cl_demands'
                              AND column_name = 'seq' AND is_nullable = 'NO' AND is_identity = 'YES'), 'cl_demands.seq identidad');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cl_demands'
                              AND column_name = 'summary' AND data_type = 'jsonb'), 'cl_demands.summary');
END $$;
ROLLBACK;

-- ===================================================================== 1. D1: deshacer cierra las alertas del lote; el lote de reemplazo (mismo dia) tiene las suyas
-- Sin estandar City1 -> City2 (missing_standard). B1: P1, P2 (por GAR) validos; X1 sin fin (rejected_ratio 1/3).
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
SELECT pg_temp.setup(ARRAY[42], ARRAY[2], false);
DO $$
DECLARE v_d uuid; v_b1 uuid; v_d2 uuid; v_b2 uuid; t text;
BEGIN
  v_d := pg_temp.emit('2026-10-26 03:00+00');
  v_b1 := pg_temp.deliver(v_d, 'B1', jsonb_build_array(pg_temp.stratum(42, 3, ARRAY['P1','P2','X1'], ARRAY['P2'], ARRAY['X1'])));
  FOREACH t IN ARRAY ARRAY['rejected_ratio','possible_misrouting','missing_standard'] LOOP
    PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE alert_type = t AND status = 'open' AND batch_id = v_b1) = 1,
                       'B1: alerta ' || t || ' abierta con batch_id');
  END LOOP;
  PERFORM pg_temp.ok((pg_temp.qcol(42)).status = 'fulfilled', 'W42 fulfilled');

  PERFORM pg_temp.ok(public.cl_undo_batch(v_b1)->>'status' = 'undone', 'B1 deshecho');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_alerts WHERE status = 'open'), 'ninguna alerta abierta tras deshacer: '
                     || COALESCE((SELECT string_agg(alert_type, ',') FROM public.cl_alerts WHERE status = 'open'), ''));
  FOREACH t IN ARRAY ARRAY['rejected_ratio','possible_misrouting','missing_standard'] LOOP
    PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE alert_type = t AND status = 'dismissed'
                          AND details->>'dismissed_by_undo' = v_b1::text) = 1, 'B1: ' || t || ' dismissed con el lote en details');
  END LOOP;
  PERFORM pg_temp.ok((pg_temp.qcol(42)).status = 'pending', 'W42 pending');

  -- lote de reemplazo el mismo dia (now() fijo en la transaccion): alertas propias
  v_d2 := pg_temp.emit('2026-11-02 03:00+00');
  v_b2 := pg_temp.deliver(v_d2, 'B2', jsonb_build_array(pg_temp.stratum(42, 3, ARRAY['R1','R2','X2'], ARRAY['R2'], ARRAY['X2'])));
  FOREACH t IN ARRAY ARRAY['rejected_ratio','possible_misrouting','missing_standard'] LOOP
    PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE alert_type = t AND status = 'open' AND batch_id = v_b2) = 1,
                       'B2: alerta ' || t || ' nueva');
  END LOOP;
  PERFORM pg_temp.ok((SELECT details->'item_ids' FROM public.cl_alerts WHERE alert_type = 'possible_misrouting' AND status = 'open') = '["R2"]'::jsonb,
                     'possible_misrouting nombra la muestra nueva');
  PERFORM pg_temp.ok((SELECT s.batch_id FROM public.cl_alerts a JOIN public.cl_samples s ON s.id::text = a.details->>'first_sample_id'
                       WHERE a.alert_type = 'missing_standard' AND a.status = 'open') = v_b2, 'missing_standard nombra una muestra de B2');
  -- un segundo aviso del mismo lote, mismo dia: sigue el tope (plan+cuota+tipo+dia+lote)
  PERFORM public.cl_raise_alert('90000000-0000-0000-0000-0000000000a1', pg_temp.qw(42), 'rejected_ratio', 'medium', '{}'::jsonb, v_b2);
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE alert_type = 'rejected_ratio' AND batch_id = v_b2) = 1, 'tope por lote');
  -- sin lote: el tope de siempre (plan+cuota+tipo+dia)
  PERFORM public.cl_raise_alert('90000000-0000-0000-0000-0000000000a1', NULL, 'feed_silent', 'high', '{}'::jsonb);
  PERFORM public.cl_raise_alert('90000000-0000-0000-0000-0000000000a1', NULL, 'feed_silent', 'high', '{}'::jsonb);
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE alert_type = 'feed_silent') = 1, 'tope sin lote');
END $$;
ROLLBACK;

-- ===================================================================== 2. D1: missing_standard compartida con otro lote
-- B1 (W42) abre missing_standard; B2 (W43, otra demanda) la comparte. Deshacer B1: se cierra y se abre otra con una
-- muestra activa de B2 (la ruta sigue sin estandar).
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
SELECT pg_temp.setup(ARRAY[42,43], ARRAY[1,1], false);
DO $$
DECLARE v_d uuid; v_b1 uuid; v_d2 uuid; v_b2 uuid;
BEGIN
  v_d := pg_temp.emit('2026-10-19 03:00+00');            -- solo W42
  v_b1 := pg_temp.deliver(v_d, 'B1', jsonb_build_array(pg_temp.stratum(42, 1, ARRAY['P1'])));
  v_d2 := pg_temp.emit('2026-10-26 03:00+00');           -- W43
  v_b2 := pg_temp.deliver(v_d2, 'B2', jsonb_build_array(pg_temp.stratum(43, 1, ARRAY['Q1'])));
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE alert_type = 'missing_standard') = 1, 'una missing_standard (de B1)');
  PERFORM public.cl_undo_batch(v_b1);
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE alert_type = 'missing_standard' AND status = 'dismissed'
                        AND batch_id = v_b1) = 1, 'la de B1 dismissed');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts a JOIN public.cl_samples s ON s.id::text = a.details->>'first_sample_id'
                       WHERE a.alert_type = 'missing_standard' AND a.status = 'open' AND a.batch_id = v_b2
                         AND s.item_id = 'Q1' AND s.status = 'active') = 1, 'nueva missing_standard con la muestra de B2');
  -- deshacer B2: ya no queda muestra activa de la ruta -> ninguna abierta
  PERFORM public.cl_undo_batch(v_b2);
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_alerts WHERE alert_type = 'missing_standard' AND status = 'open'), 'sin missing_standard abierta');
END $$;
ROLLBACK;

-- ===================================================================== 3. D2: demanda de prueba solo dry_run; activar el conector la cierra
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
SELECT pg_temp.setup(ARRAY[42,43,46], ARRAY[2,3,3]);
UPDATE public.cl_feeds SET status = 'testing' WHERE id = 'f0000000-0000-0000-0000-0000000000a1';
DO $$
DECLARE v_d uuid; v_done uuid; v_d2 uuid; v_m text; v_r jsonb;
BEGIN
  v_d := pg_temp.emit('2026-10-26 03:00+00');            -- W42 y W43, en prueba
  PERFORM pg_temp.ok((SELECT feed_testing FROM public.cl_demands WHERE id = v_d), 'demanda de prueba');
  -- una demanda de prueba ya cumplida (como la de DEMO2): no se toca
  INSERT INTO public.cl_demands (id, account_id, plan_id, feed_id, status, random_seed, payload, feed_testing, requested_at)
  VALUES ('de000000-0000-0000-0000-0000000000f1','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1',
          'f0000000-0000-0000-0000-0000000000a1','fulfilled','x','{"strata":[]}', true, '2026-10-19 03:00+00');
  v_done := 'de000000-0000-0000-0000-0000000000f1';

  v_r := pg_temp.ingest(v_d, 'T1', jsonb_build_array(pg_temp.stratum(42, 2, ARRAY['P1','P2'])), true);
  PERFORM pg_temp.ok((v_r->>'dry_run')::boolean AND v_r->>'status' = 'validated', 'dry_run admitido');
  v_m := pg_temp.msg_of(format('SELECT public.cl_ingest_batch(%L, %L::jsonb, false)', 'f0000000-0000-0000-0000-0000000000a1',
           jsonb_build_object('demand_id', v_d, 'batch_id', 'T1', 'strata', jsonb_build_array(pg_temp.stratum(42, 2, ARRAY['P1','P2'])))));
  PERFORM pg_temp.ok(v_m LIKE '22023:CL_DEMAND_TESTING_DRY_RUN_ONLY%', 'lote real sobre demanda de prueba: ' || COALESCE(v_m, 'sin error'));
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_batches), 'sin lotes guardados');

  -- el conector pasa a activo: la demanda de prueba abierta se cierra; sus cuotas vuelven a pending sin gastar peticiones
  UPDATE public.cl_feeds SET status = 'active' WHERE id = 'f0000000-0000-0000-0000-0000000000a1';
  PERFORM pg_temp.ok((SELECT status = 'failed' AND summary->>'reason' = 'feed_activated' FROM public.cl_demands WHERE id = v_d),
                     'demanda de prueba failed (feed_activated): ' || (SELECT row_to_json(d)::text FROM public.cl_demands d WHERE id = v_d));
  PERFORM pg_temp.ok((pg_temp.qcol(42)).status = 'pending' AND (pg_temp.qcol(42)).demands_count = 0
                     AND (pg_temp.qcol(43)).status = 'pending' AND (pg_temp.qcol(43)).demands_count = 0, 'cuotas pending sin contar');
  PERFORM pg_temp.ok((SELECT status = 'fulfilled' AND summary IS NULL FROM public.cl_demands WHERE id = v_done), 'demanda cumplida intacta');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_alerts WHERE alert_type IN ('quota_unfilled','feed_silent','emit_failed')), 'sin alertas');
  -- la demanda cerrada ya no admite lotes
  v_m := pg_temp.msg_of(format('SELECT public.cl_ingest_batch(%L, %L::jsonb, false)', 'f0000000-0000-0000-0000-0000000000a1',
           jsonb_build_object('demand_id', v_d, 'batch_id', 'T2', 'strata', jsonb_build_array(pg_temp.stratum(42, 2, ARRAY['P1','P2'])))));
  PERFORM pg_temp.ok(v_m LIKE '%CL_DEMAND_NOT_OPEN%', 'demanda cerrada: ' || COALESCE(v_m, 'sin error'));

  -- siguiente hueco del calendario: demanda real que si cuenta
  v_d2 := pg_temp.emit('2026-11-02 03:00+00');
  PERFORM pg_temp.ok(NOT (SELECT feed_testing FROM public.cl_demands WHERE id = v_d2), 'demanda real');
  PERFORM pg_temp.ok((pg_temp.qcol(42)).status = 'open' AND (pg_temp.qcol(42)).demands_count = 1
                     AND (pg_temp.qcol(43)).demands_count = 1, 'real: suma demands_count');
  PERFORM pg_temp.ok((pg_temp.ingest(v_d2, 'R1', jsonb_build_array(pg_temp.stratum(42, 2, ARRAY['P1','P2'])))->>'status') = 'validated', 'lote real admitido');
  -- otro cambio de estado (activo -> pausado -> activo) no toca demandas reales
  UPDATE public.cl_feeds SET status = 'paused' WHERE id = 'f0000000-0000-0000-0000-0000000000a1';
  UPDATE public.cl_feeds SET status = 'active' WHERE id = 'f0000000-0000-0000-0000-0000000000a1';
  PERFORM pg_temp.ok((SELECT status FROM public.cl_demands WHERE id = v_d2) = 'open', 'demanda real sigue open');
END $$;
ROLLBACK;

-- ===================================================================== 4. D3: reader_id sin espacios en los componentes
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000001','CARRIER A ','Carrier A');
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001');
INSERT INTO public.readers (id, account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role) VALUES
  ('ad000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','NYC','Entry','carrier_scan',
   'ca000000-0000-0000-0000-0000000000a2',' NYC-RDC ',' ACC ','origin');
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT reader_id FROM public.readers WHERE id = 'ad000000-0000-0000-0000-0000000000a1') = 'CL:acc:CARRIER A:NYC-RDC:ACC',
                     'reader_id recortado: ' || (SELECT reader_id FROM public.readers WHERE id = 'ad000000-0000-0000-0000-0000000000a1'));
END $$;
-- Un reader_id antiguo con espacios (generado antes del arreglo) se normaliza con cualquier UPDATE de la fila, que es lo
-- que hace la migracion.
ALTER TABLE public.readers DISABLE TRIGGER readers_cl_defaults;
UPDATE public.readers SET reader_id = 'CL:acc:CARRIER A :NYC-RDC:ACC' WHERE id = 'ad000000-0000-0000-0000-0000000000a1';
ALTER TABLE public.readers ENABLE TRIGGER readers_cl_defaults;
UPDATE public.readers SET reader_id = reader_id WHERE id = 'ad000000-0000-0000-0000-0000000000a1';
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT reader_id FROM public.readers WHERE id = 'ad000000-0000-0000-0000-0000000000a1') = 'CL:acc:CARRIER A:NYC-RDC:ACC',
                     'reader_id antiguo normalizado');
END $$;
ROLLBACK;

-- ===================================================================== 5. D4: "ultima demanda" por orden de emision, no por requested_at
-- D1 se emite con p_now 02/11 y caduca sin lote; D2 se emite despues con un p_now ANTERIOR (26/10). La liquidacion de
-- W42 tras el lote de D2 (poblacion 1 = recibidos 1) debe usar D2: reparto (carried), no "poblacion desconocida".
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
SELECT pg_temp.setup(ARRAY[42,46], ARRAY[2,3]);
DO $$
DECLARE v_d1 uuid; v_d2 uuid;
BEGIN
  v_d1 := pg_temp.emit('2026-11-02 03:00+00');
  UPDATE public.cl_demands SET status = 'failed' WHERE id = v_d1;
  UPDATE public.cl_plan_quotas SET status = 'pending' WHERE id = pg_temp.qw(42);
  v_d2 := pg_temp.emit('2026-10-26 03:00+00');
  PERFORM pg_temp.ok((SELECT seq FROM public.cl_demands WHERE id = v_d2) > (SELECT seq FROM public.cl_demands WHERE id = v_d1), 'seq monotona');
  PERFORM pg_temp.deliver(v_d2, 'B1', jsonb_build_array(pg_temp.stratum(42, 1, ARRAY['P1'])));
  PERFORM pg_temp.ok((pg_temp.qcol(42)).status = 'carried', 'W42 liquidada con el sorteo de D2: ' || row_to_json(pg_temp.qcol(42))::text);
  PERFORM pg_temp.ok((pg_temp.qcol(46)).samples_carried_in = 1, 'W46 +1');
END $$;
ROLLBACK;

-- ===================================================================== 6. D5: sin DROP TABLE IF EXISTS pg_temp.* (NOTICE "schema pg_temp does not exist")
DO $$
BEGIN
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                                  WHERE n.nspname = 'public' AND p.proname LIKE 'cl\_%'
                                    AND p.prosrc ~* 'DROP\s+TABLE\s+IF\s+EXISTS\s+pg_temp\.'),
                     'ninguna funcion cl_* usa DROP TABLE IF EXISTS pg_temp.*: '
                     || COALESCE((SELECT string_agg(p.proname, ',') FROM pg_proc p WHERE p.proname LIKE 'cl\_%'
                                    AND p.prosrc ~* 'DROP\s+TABLE\s+IF\s+EXISTS\s+pg_temp\.'), ''));
END $$;

\echo cl_wave2: OK
