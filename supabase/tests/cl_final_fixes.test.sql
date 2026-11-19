-- Carrier Link: correcciones de la revision final (20261120110800_cl_final_fixes.sql).
-- I1 demanda caducada con lote a medio sortear; I2 conector en prueba; I3 plan no borrador; I4 puntos del
-- transportista fuera de las listas RFID; M2 reenrich solo con filas one_db de panelistas.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.sqlstate_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE; END $$;

CREATE OR REPLACE FUNCTION pg_temp.msg_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE || ':' || SQLERRM; END $$;

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

-- Maestros, conector (activo) y plan activo con cuotas City1 -> City2. close_lag_days = 0.
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

CREATE OR REPLACE FUNCTION pg_temp.ingest(p_demand uuid, p_cbid text, p_strata jsonb) RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.cl_ingest_batch('f0000000-0000-0000-0000-0000000000a1',
           jsonb_build_object('demand_id', p_demand, 'batch_id', p_cbid, 'strata', p_strata))
$$;

-- ===================================================================== 0. Estructura y permisos
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_get_constraintdef((SELECT oid FROM pg_constraint WHERE conname = 'cl_batches_status_check'
                                            AND conrelid = 'public.cl_batches'::regclass)) LIKE '%expired%', 'cl_batches admite expired');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cl_demands'
                              AND column_name = 'feed_testing' AND is_nullable = 'NO' AND column_default = 'false'), 'cl_demands.feed_testing');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'cl_plans_lock_fields' AND tgrelid = 'public.cl_plans'::regclass), 'trigger cl_plans_lock_fields');
  PERFORM pg_temp.ok((SELECT bool_and(prosecdef AND 'search_path=public, extensions' = ANY (proconfig)) FROM pg_proc
                       WHERE oid IN ('public.cl_sample_stratum(uuid,uuid)'::regprocedure, 'public.cl_emit_due_demands(timestamptz)'::regprocedure,
                                     'public.cl_build_demand(uuid,uuid[])'::regprocedure, 'public.cl_undo_batch(uuid)'::regprocedure,
                                     'public.cl_plan_set_quotas(uuid,jsonb)'::regprocedure)), 'SECURITY DEFINER + search_path');
  PERFORM pg_temp.ok(has_function_privilege('service_role','public.cl_sample_stratum(uuid,uuid)','EXECUTE')
                     AND NOT has_function_privilege('authenticated','public.cl_sample_stratum(uuid,uuid)','EXECUTE'), 'sample: solo service_role');
  PERFORM pg_temp.ok(has_function_privilege('service_role','public.cl_emit_due_demands(timestamptz)','EXECUTE')
                     AND NOT has_function_privilege('authenticated','public.cl_emit_due_demands(timestamptz)','EXECUTE'), 'emit: solo service_role');
  PERFORM pg_temp.ok(NOT has_function_privilege('service_role','public.cl_build_demand(uuid,uuid[])','EXECUTE')
                     AND NOT has_function_privilege('authenticated','public.cl_build_demand(uuid,uuid[])','EXECUTE'), 'build_demand interna');
  PERFORM pg_temp.ok(has_function_privilege('authenticated','public.cl_plan_set_quotas(uuid,jsonb)','EXECUTE')
                     AND NOT has_function_privilege('anon','public.cl_plan_set_quotas(uuid,jsonb)','EXECUTE'), 'set_quotas grants');
  PERFORM pg_temp.ok(has_function_privilege('authenticated','public.cl_undo_batch(uuid)','EXECUTE')
                     AND NOT has_function_privilege('anon','public.cl_undo_batch(uuid)','EXECUTE'), 'undo grants');
END $$;
ROLLBACK;

-- ===================================================================== 1. I1: sorteo a medias + caducidad + reenvio
-- W42 (2 previstas, poblacion 1) sorteada en B1 sin cerrar; W43 sin sortear. A los 7 dias: demanda failed, lote
-- expired, W42 (con sorteo, aun 'open') liquidada -> carried a W44; W43 -> pending. El reenvio no sortea nada mas.
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
SELECT pg_temp.setup(ARRAY[42,43,44], ARRAY[2,3,3]);
DO $$
DECLARE v_d uuid; v_b uuid; v_m text; v_r jsonb; v_n bigint;
BEGIN
  v_d := pg_temp.emit('2026-10-26 03:00+00');            -- vencen W42 y W43
  v_b := (pg_temp.ingest(v_d, 'B1', jsonb_build_array(pg_temp.stratum(42, 1, ARRAY['P1']),
                                                      pg_temp.stratum(43, 2, ARRAY['Q1','Q2'])))->>'batch')::uuid;
  PERFORM public.cl_sample_stratum(v_b, pg_temp.qw(42));   -- el conector se corta aqui: W43 sin sortear, sin cierre
  PERFORM pg_temp.ok((pg_temp.qcol(42)).status = 'open' AND (pg_temp.qcol(42)).samples_obtained = 1, 'W42 open con 1');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_batches WHERE id = v_b) = 'validated', 'B1 validated');

  PERFORM public.cl_emit_due_demands('2026-11-03 10:00+00');   -- caducidad (fuera del calendario)
  PERFORM pg_temp.ok((SELECT status FROM public.cl_demands WHERE id = v_d) = 'failed', 'demanda failed');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_batches WHERE id = v_b) = 'expired', 'lote expired');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE alert_type = 'feed_silent' AND details->>'demand_id' = v_d::text) = 1, 'feed_silent');
  PERFORM pg_temp.ok((pg_temp.qcol(42)).status = 'carried', 'W42 (con sorteo) liquidada: ' || row_to_json(pg_temp.qcol(42))::text);
  PERFORM pg_temp.ok((pg_temp.qcol(44)).samples_carried_in = 1 AND (pg_temp.qcol(44)).status = 'pending', 'W44 +1');
  PERFORM pg_temp.ok((pg_temp.qcol(43)).status = 'pending' AND (pg_temp.qcol(43)).samples_obtained = 0
                     AND (pg_temp.qcol(43)).demands_count = 1, 'W43 (sin sorteo) pending');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000a1' AND status = 'open'),
                     'ninguna cuota queda open');
  SELECT count(*) INTO v_n FROM public.cl_samples WHERE batch_id = v_b AND status = 'active';

  -- reenvio del conector: el lote devuelve su resumen; el sorteo pendiente y el cierre se rechazan; nada nuevo
  PERFORM pg_temp.ok((pg_temp.ingest(v_d, 'B1', jsonb_build_array(pg_temp.stratum(42, 1, ARRAY['P1']),
                                                                  pg_temp.stratum(43, 2, ARRAY['Q1','Q2'])))->>'batch')::uuid = v_b, 'reenvio: su resumen');
  v_m := pg_temp.msg_of(format('SELECT public.cl_sample_stratum(%L, %L)', v_b, pg_temp.qw(43)));
  PERFORM pg_temp.ok(v_m LIKE '22023:CL_%', 'sorteo de W43 tras caducar rechazado: ' || COALESCE(v_m, 'sin error'));
  v_r := public.cl_sample_stratum(v_b, pg_temp.qw(42));
  PERFORM pg_temp.ok((v_r->>'samples_selected')::int = 1, 'W42 ya sorteada: devuelve el sorteo guardado');
  v_m := pg_temp.msg_of(format('SELECT public.cl_finish_batch(%L)', v_b));
  PERFORM pg_temp.ok(v_m LIKE '22023:CL_BATCH_NOT_VALIDATED%', 'cierre rechazado: ' || COALESCE(v_m, 'sin error'));
  v_m := pg_temp.msg_of(format('SELECT public.cl_ingest_batch(%L, %L::jsonb)', 'f0000000-0000-0000-0000-0000000000a1',
           jsonb_build_object('demand_id', v_d, 'batch_id', 'B2', 'strata', jsonb_build_array(pg_temp.stratum(43, 2, ARRAY['Q1','Q2'])))));
  PERFORM pg_temp.ok(v_m LIKE '%CL_DEMAND_NOT_OPEN%', 'lote nuevo tras caducar: ' || COALESCE(v_m, 'sin error'));
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_samples WHERE status = 'active') = v_n AND v_n = 1, 'sin muestras nuevas');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_sampling_runs WHERE batch_id = v_b AND stratum_id = pg_temp.qw(43)), 'sin sorteo de W43');
  PERFORM pg_temp.ok((pg_temp.qcol(42)).samples_obtained = 1 AND (pg_temp.qcol(43)).samples_obtained = 0, 'sin doble cuenta');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE alert_type = 'emit_failed') = 0, 'sin emit_failed');

  -- una segunda caducidad no vuelve a liquidar nada
  PERFORM public.cl_emit_due_demands('2026-11-04 10:00+00');
  PERFORM pg_temp.ok((pg_temp.qcol(44)).samples_carried_in = 1, 'sin doble reparto');

  -- el lote expired se puede deshacer (sus muestras no quedan sin vuelta atras)
  PERFORM pg_temp.ok(public.cl_undo_batch(v_b)->>'status' = 'undone', 'expired se deshace');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_samples WHERE batch_id = v_b AND status = 'active') = 0
                     AND (SELECT count(*) FROM public.one_db WHERE source = 'carrier') = 0, 'muestras anuladas');
END $$;
ROLLBACK;

-- ===================================================================== 2. I1a: lote validated con la demanda ya cerrada -> CL_DEMAND_NOT_OPEN
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
SELECT pg_temp.setup(ARRAY[42,43], ARRAY[2,3]);
DO $$
DECLARE v_d uuid; v_b uuid; v_m text;
BEGIN
  v_d := pg_temp.emit('2026-10-26 03:00+00');
  v_b := (pg_temp.ingest(v_d, 'B1', jsonb_build_array(pg_temp.stratum(42, 2, ARRAY['P1','P2']),
                                                      pg_temp.stratum(43, 2, ARRAY['Q1','Q2'])))->>'batch')::uuid;
  PERFORM public.cl_sample_stratum(v_b, pg_temp.qw(42));
  UPDATE public.cl_demands SET status = 'failed' WHERE id = v_d;     -- la demanda se cierra con el lote aun validated
  v_m := pg_temp.msg_of(format('SELECT public.cl_sample_stratum(%L, %L)', v_b, pg_temp.qw(43)));
  PERFORM pg_temp.ok(v_m LIKE '22023:CL_DEMAND_NOT_OPEN%', 'demanda no open: ' || COALESCE(v_m, 'sin error'));
  PERFORM pg_temp.ok((public.cl_sample_stratum(v_b, pg_temp.qw(42))->>'samples_selected')::int = 2, 'estrato ya sorteado: idempotente');
  PERFORM pg_temp.ok((pg_temp.qcol(43)).samples_obtained = 0
                     AND NOT EXISTS (SELECT 1 FROM public.cl_samples WHERE quota_id = pg_temp.qw(43)), 'W43 sin muestras');
END $$;
ROLLBACK;

-- ===================================================================== 3. I2: conector en prueba
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
SELECT pg_temp.setup(ARRAY[42,43,44], ARRAY[2,3,3]);
UPDATE public.cl_feeds SET status = 'testing' WHERE id = 'f0000000-0000-0000-0000-0000000000a1';
DO $$
DECLARE v_d uuid; v_d2 uuid;
BEGIN
  v_d := pg_temp.emit('2026-10-26 03:00+00');            -- W42 y W43
  PERFORM pg_temp.ok((SELECT feed_testing FROM public.cl_demands WHERE id = v_d), 'demanda marcada feed_testing');
  PERFORM pg_temp.ok((pg_temp.qcol(42)).status = 'open' AND (pg_temp.qcol(42)).demands_count = 0
                     AND (pg_temp.qcol(43)).demands_count = 0, 'en prueba no suma demands_count');
  -- aunque la cuota ya hubiera gastado sus 3 peticiones, la caducidad de prueba no reparte
  UPDATE public.cl_plan_quotas SET demands_count = 3 WHERE id = pg_temp.qw(43);
  PERFORM public.cl_emit_due_demands('2026-11-03 10:00+00');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_demands WHERE id = v_d) = 'failed', 'demanda de prueba failed');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE alert_type = 'feed_silent' AND details->>'demand_id' = v_d::text) = 1, 'feed_silent');
  PERFORM pg_temp.ok((pg_temp.qcol(42)).status = 'pending' AND (pg_temp.qcol(42)).demands_count = 0, 'W42 pending sin gastar');
  PERFORM pg_temp.ok((pg_temp.qcol(43)).status = 'pending' AND (pg_temp.qcol(43)).demands_count = 3, 'W43 pending (no carried)');
  PERFORM pg_temp.ok((pg_temp.qcol(44)).samples_carried_in = 0, 'sin reparto');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_alerts WHERE alert_type = 'quota_unfilled'), 'sin unfilled');

  -- conector activo: la demanda siguiente si cuenta
  UPDATE public.cl_feeds SET status = 'active' WHERE id = 'f0000000-0000-0000-0000-0000000000a1';
  UPDATE public.cl_plan_quotas SET demands_count = 0 WHERE id = pg_temp.qw(43);
  v_d2 := pg_temp.emit('2026-11-09 03:00+00');
  PERFORM pg_temp.ok(NOT (SELECT feed_testing FROM public.cl_demands WHERE id = v_d2), 'demanda real');
  PERFORM pg_temp.ok((pg_temp.qcol(42)).demands_count = 1 AND (pg_temp.qcol(42)).status = 'open', 'activo: suma demands_count');
END $$;
ROLLBACK;

-- ===================================================================== 4. I3: plan no borrador
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
SELECT pg_temp.setup(ARRAY[42,43], ARRAY[2,3]);
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status) VALUES
  ('f0000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed A1 bis','active');
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','PR2','Prod2',48);
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000d1','a0000000-0000-0000-0000-000000000001','Borrador','ca000000-0000-0000-0000-000000000001',
   'cb000000-0000-0000-0000-000000000001', 10, '2026-10-05', '2026-12-13', 'f0000000-0000-0000-0000-0000000000a1');
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000001','C9','Carrier 9');
INSERT INTO auth.users (id, email) VALUES ('93000000-0000-0000-0000-000000000093','am@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('93000000-0000-0000-0000-000000000093','am@t.l','AM','user','a0000000-0000-0000-0000-000000000001');
INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000093','account_manager');

-- cuotas: solo en borrador (tambien para el backend)
DO $$
DECLARE v_m text;
BEGIN
  v_m := pg_temp.msg_of($q$SELECT public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a1', '[]'::jsonb)$q$);
  PERFORM pg_temp.ok(v_m LIKE '22023:CL_PLAN_NOT_DRAFT%', 'plan activo: ' || COALESCE(v_m, 'sin error'));
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000a1') = 2, 'cuotas intactas');
  PERFORM pg_temp.ok(public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000d1', jsonb_build_array(jsonb_build_object(
            'origin_city_id','c1000000-0000-0000-0000-000000000001','destination_city_id','c2000000-0000-0000-0000-000000000002',
            'iso_year',2026,'iso_week',42,'samples',2))) = 1, 'borrador: cuotas fijadas');
  -- el backend puede corregir un plan activo
  UPDATE public.cl_plans SET start_date = '2026-10-06' WHERE id = '90000000-0000-0000-0000-0000000000a1';
  PERFORM pg_temp.ok((SELECT start_date FROM public.cl_plans WHERE id = '90000000-0000-0000-0000-0000000000a1') = '2026-10-06', 'backend cambia start_date');
END $$;

SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE c text; v_m text;
BEGIN
  FOREACH c IN ARRAY ARRAY[
      $q$UPDATE public.cl_plans SET feed_id = 'f0000000-0000-0000-0000-0000000000a2' WHERE id = '90000000-0000-0000-0000-0000000000a1'$q$,
      $q$UPDATE public.cl_plans SET product_id = 'cb000000-0000-0000-0000-000000000002' WHERE id = '90000000-0000-0000-0000-0000000000a1'$q$,
      $q$UPDATE public.cl_plans SET start_date = '2026-10-12' WHERE id = '90000000-0000-0000-0000-0000000000a1'$q$,
      $q$UPDATE public.cl_plans SET feed_id = NULL WHERE id = '90000000-0000-0000-0000-0000000000a1'$q$] LOOP
    v_m := pg_temp.msg_of(c);
    PERFORM pg_temp.ok(v_m LIKE '22023:CL_PLAN_LOCKED_FIELD%', c || ' -> ' || COALESCE(v_m, 'sin error'));
  END LOOP;
  -- el carrier tampoco (el trigger corta antes que cualquier otra comprobacion)
  v_m := pg_temp.msg_of($q$UPDATE public.cl_plans SET carrier_id = 'ca000000-0000-0000-0000-000000000009' WHERE id = '90000000-0000-0000-0000-0000000000a1'$q$);
  PERFORM pg_temp.ok(v_m LIKE '22023:CL_PLAN_LOCKED_FIELD%', 'carrier_id -> ' || COALESCE(v_m, 'sin error'));
  -- otros campos del plan activo si; los campos fijos de un borrador tambien
  PERFORM pg_temp.ok(pg_temp.msg_of($q$UPDATE public.cl_plans SET plan_name = 'Otro', end_date = '2026-12-20' WHERE id = '90000000-0000-0000-0000-0000000000a1'$q$) IS NULL, 'nombre y fin editables');
  PERFORM pg_temp.ok(pg_temp.msg_of($q$UPDATE public.cl_plans SET start_date = '2026-10-12', feed_id = 'f0000000-0000-0000-0000-0000000000a2', product_id = 'cb000000-0000-0000-0000-000000000002' WHERE id = '90000000-0000-0000-0000-0000000000d1'$q$) IS NULL, 'borrador editable');
  v_m := pg_temp.msg_of($q$SELECT public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a1', '[]'::jsonb)$q$);
  PERFORM pg_temp.ok(v_m LIKE '22023:CL_PLAN_NOT_DRAFT%', 'AM: cuotas de plan activo -> ' || COALESCE(v_m, 'sin error'));
END $$;
RESET ROLE;
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT feed_id = 'f0000000-0000-0000-0000-0000000000a1' AND product_id = 'cb000000-0000-0000-0000-000000000001'
                             AND carrier_id = 'ca000000-0000-0000-0000-000000000001' AND start_date = '2026-10-06' AND plan_name = 'Otro'
                        FROM public.cl_plans WHERE id = '90000000-0000-0000-0000-0000000000a1'), 'plan activo: campos fijos intactos');
  PERFORM pg_temp.ok((SELECT start_date = '2026-10-12' AND feed_id = 'f0000000-0000-0000-0000-0000000000a2'
                        FROM public.cl_plans WHERE id = '90000000-0000-0000-0000-0000000000d1'), 'borrador cambiado');
END $$;
ROLLBACK;

-- ===================================================================== 5. I4: puntos del transportista fuera de las listas RFID
BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
UPDATE public.accounts SET timezone = 'UTC' WHERE id = 'a0000000-0000-0000-0000-000000000001';
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001');
INSERT INTO public.readers (id, account_id, postal_center_id, reader_id, name, type) VALUES
  ('f1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','LPI1','R1','Mixed');
INSERT INTO public.readers (id, account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, e2e_role) VALUES
  ('ad000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','NBO','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','NBO','origin');
DO $$
DECLARE r jsonb;
BEGIN
  r := ops_report._data('a0000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-12');
  PERFORM pg_temp.ok(r->'readers' = jsonb_build_array(jsonb_build_object('lpi','LPI1','name','R1','postal_center','Center 1')),
                     'informe: solo el lector RFID en readers: ' || (r->'readers')::text);
  PERFORM pg_temp.ok((SELECT e->'readers' FROM jsonb_array_elements(r->'rfid_study') e WHERE e->>'postal_center' = 'Center 1') = '["LPI1"]'::jsonb,
                     'informe: solo el lector RFID en el centro: ' || (r->'rfid_study')::text);
  PERFORM pg_temp.ok((SELECT array_agg(reader_id) FROM public.v_mobile_readers WHERE account_id = 'a0000000-0000-0000-0000-000000000001')
                     = ARRAY['f1000000-0000-0000-0000-000000000001'::uuid], 'v_mobile_readers: solo RFID');
END $$;
ROLLBACK;

-- ===================================================================== 6. M2: reenrich solo con one_db de panelistas
BEGIN;
\ir fixtures/incident_city.sql
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001');
INSERT INTO public.readers (id, account_id, postal_center_id, reader_id, name, type) VALUES
  ('f1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','LPI1','R1','Mixed');
INSERT INTO public.processed_events (account_id, tag_id, reader_id, postal_center_id, event_type, timestamp, analysis_datetime,
  postal_center_code_snapshot, postal_center_name_snapshot, postal_center_city_snapshot, reader_id_snapshot, reader_type_snapshot, is_consolidated)
VALUES ('a0000000-0000-0000-0000-000000000001','00000009','f1000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','entry',
        '2027-03-05 08:00+00','2027-03-05 08:00+00','PC1','Center 1','City1','LPI1','Mixed',false);
INSERT INTO public.one_db (account_id, tag_id, plan_name, carrier_name, product_name, origin_city_name, destination_city_name, sent_at, received_at, total_transit_days, source_data_snapshot, source)
VALUES ('a0000000-0000-0000-0000-000000000001','00000009','CL','Carrier','PR','City2','City1','2027-03-05 07:00+00','2027-03-06 08:00+00',1,'{}','carrier');
DO $$
BEGIN
  PERFORM pg_temp.ok(public.reenrich_processed_events('a0000000-0000-0000-0000-000000000001') = 0, 'fila del transportista: no enriquece');
  PERFORM pg_temp.ok((SELECT origin_city_name IS NULL FROM public.processed_events WHERE tag_id = '00000009'), 'evento sin tocar');
END $$;
INSERT INTO public.one_db (account_id, tag_id, plan_name, carrier_name, product_name, origin_city_name, destination_city_name, sent_at, received_at, total_transit_days, source_data_snapshot)
VALUES ('a0000000-0000-0000-0000-000000000001','00000009','Mar27','Carrier','PR','City1','City2','2027-03-01 07:00+00','2027-03-02 08:00+00',1,'{}');
DO $$
BEGIN
  PERFORM pg_temp.ok(public.reenrich_processed_events('a0000000-0000-0000-0000-000000000001') = 1, 'fila de panelista: enriquece');
  PERFORM pg_temp.ok((SELECT origin_city_name = 'City1' FROM public.processed_events WHERE tag_id = '00000009'), 'ciudad del panelista (no la del transportista)');
END $$;
ROLLBACK;

-- ===================================================================== 7. Seguridad: v_mobile_readers con permisos del usuario, sin anon
BEGIN;
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001');
INSERT INTO public.regions (id, account_id, name, code) VALUES
  ('e0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','Reg2','R2');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','CityB','CB');
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d3000000-0000-0000-0000-0000000000c3','a0000000-0000-0000-0000-000000000002','PCB','Center B','CityB','c3000000-0000-0000-0000-000000000003');
INSERT INTO public.readers (id, account_id, postal_center_id, reader_id, name, type) VALUES
  ('f1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','LPI-A','RA','Mixed'),
  ('f2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','d3000000-0000-0000-0000-0000000000c3','LPI-B','RB','Mixed');
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT reloptions FROM pg_class WHERE oid = 'public.v_mobile_readers'::regclass) @> ARRAY['security_invoker=true'], 'security_invoker');
  PERFORM pg_temp.ok(NOT has_table_privilege('anon', 'public.v_mobile_readers', 'SELECT')
                     AND NOT has_table_privilege('anon', 'public.v_mobile_readers', 'INSERT')
                     AND NOT has_table_privilege('anon', 'public.v_mobile_readers', 'DELETE')
                     AND NOT has_table_privilege('anon', 'public.v_mobile_readers', 'TRUNCATE'), 'anon sin permisos');
  PERFORM pg_temp.ok(has_table_privilege('authenticated', 'public.v_mobile_readers', 'SELECT')
                     AND NOT has_table_privilege('authenticated', 'public.v_mobile_readers', 'INSERT')
                     AND NOT has_table_privilege('authenticated', 'public.v_mobile_readers', 'UPDATE')
                     AND NOT has_table_privilege('authenticated', 'public.v_mobile_readers', 'DELETE'), 'authenticated solo SELECT');
END $$;
SET ROLE authenticated;
SELECT pg_temp.as_user('99000000-0000-0000-0000-000000000099', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT array_agg(reader_code ORDER BY reader_code) FROM public.v_mobile_readers) = ARRAY['LPI-A'],
                     'usuario de A: solo sus lectores');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.v_mobile_readers WHERE account_id = 'a0000000-0000-0000-0000-000000000002'), 'nada de B');
  PERFORM pg_temp.ok((SELECT current_center_code FROM public.v_mobile_readers WHERE reader_code = 'LPI-A') = 'PC1', 'centro visible');
END $$;
RESET ROLE;
SET ROLE anon;
SELECT pg_temp.as_user(NULL, 'anon');
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.sqlstate_of('SELECT * FROM public.v_mobile_readers') = '42501', 'anon no lee la vista');
END $$;
RESET ROLE;
ROLLBACK;

\echo cl_final_fixes: OK
