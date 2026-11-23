-- Carrier Link v4, tarea 3: funciones de la API del conector (20261124100200_cl_delivery_api.sql).
-- Apertura sin compresion y con tamano declarado (CL_FILE_TOO_LARGE antes de crear la entrega), configuracion que
-- solo anuncia 'none', estado de una entrega (cl_delivery_status: mismo error para ajena e inexistente, alertas
-- filtradas para el transportista) y retirada del emisor de demandas v3. Todo en BEGIN ... ROLLBACK.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.raises(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE || ':' || SQLERRM; END $$;

CREATE OR REPLACE FUNCTION pg_temp.sha(p_n int) RETURNS text LANGUAGE sql AS $$
  SELECT encode(sha256(convert_to('file-' || p_n, 'UTF8')), 'hex')
$$;

BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- A1 (Nairobi): conector diario D activo con plan que cubre hoy +-30 dias; conector S con tope de 1000 bytes.
-- A2: conector X (otra cuenta).
UPDATE public.accounts SET timezone = 'Africa/Nairobi' WHERE id = 'a0000000-0000-0000-0000-000000000001';
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status, emit_days, emit_hour, config) VALUES
  ('f0000000-0000-0000-0000-0000000000d1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed D','active','{1,2,3,4,5,6,7}',3,'{}'),
  ('f0000000-0000-0000-0000-0000000000d2','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed S','active','{1,2,3,4,5,6,7}',3,'{"max_file_bytes":1000}');
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000d1','a0000000-0000-0000-0000-000000000001','PD','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,current_date - 30,current_date + 30,'active','f0000000-0000-0000-0000-0000000000d1'),
  ('90000000-0000-0000-0000-0000000000d2','a0000000-0000-0000-0000-000000000001','PS','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,current_date - 30,current_date + 30,'active','f0000000-0000-0000-0000-0000000000d2');
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','CB','Carrier2');
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status, emit_days, emit_hour) VALUES
  ('f0000000-0000-0000-0000-0000000000e2','a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','Feed X','active','{1,2,3,4,5,6,7}',3);

-- ================================================================ 1. firmas, privilegios y retirada v3
DO $$
DECLARE f text;
BEGIN
  PERFORM pg_temp.ok(to_regprocedure('public.cl_delivery_open(uuid,date,date,text,jsonb,text,text)') IS NULL,
                     'sin la firma con p_compression (API)');
  PERFORM pg_temp.ok(to_regprocedure('public.cl_manual_delivery_open(uuid,date,date,text,jsonb,text,text)') IS NULL,
                     'sin la firma con p_compression (web)');
  FOREACH f IN ARRAY ARRAY['public.cl_delivery_open(uuid,date,date,text,jsonb,text,bigint)',
                           'public.cl_delivery_status(uuid,uuid)', 'public.cl_connector_config(uuid,timestamptz)'] LOOP
    PERFORM pg_temp.ok((SELECT prosecdef FROM pg_proc WHERE oid = f::regprocedure), f || ' SECURITY DEFINER');
    PERFORM pg_temp.ok((SELECT proconfig @> ARRAY['search_path=public, extensions'] FROM pg_proc WHERE oid = f::regprocedure),
                       f || ' search_path');
    PERFORM pg_temp.ok(has_function_privilege('service_role', f, 'EXECUTE'), f || ' service_role');
    PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', f, 'EXECUTE')
                       AND NOT has_function_privilege('anon', f, 'EXECUTE'), f || ' solo service_role');
  END LOOP;
  f := 'public.cl_manual_delivery_open(uuid,date,date,text,jsonb,text)';
  PERFORM pg_temp.ok((SELECT prosecdef FROM pg_proc WHERE oid = f::regprocedure), f || ' SECURITY DEFINER');
  PERFORM pg_temp.ok(has_function_privilege('authenticated', f, 'EXECUTE') AND NOT has_function_privilege('anon', f, 'EXECUTE'),
                     f || ' authenticated, sin anon');
  -- Motor de demandas v3 retirado (los tests v3 lo recrean con fixtures/cl_v3_demand_emitter.sql y lo borran al final).
  PERFORM pg_temp.ok(to_regprocedure('public.cl_emit_due_demands(timestamptz)') IS NULL, 'cl_emit_due_demands retirada');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cl-emit-demands'), 'job cl-emit-demands retirado');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cl-delivery-worker-kick')
                     AND EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cl-delivery-process'), 'jobs v4 siguen');
  PERFORM pg_temp.ok(to_regclass('public.cl_demands') IS NOT NULL AND to_regclass('public.cl_batches') IS NOT NULL,
                     'tablas de demandas y lotes se quedan (historial)');
END $$;

-- ================================================================ 2. apertura: tamano declarado y sin compresion
DO $$
DECLARE
  d constant uuid := 'f0000000-0000-0000-0000-0000000000d1';
  s constant uuid := 'f0000000-0000-0000-0000-0000000000d2';
  v_day date := (now() AT TIME ZONE 'Africa/Nairobi')::date - 2;
  e text; j jsonb; j2 jsonb;
BEGIN
  e := pg_temp.raises(format('SELECT public.cl_delivery_open(%L, %L, %L, %L, ''[]'')', d, v_day, v_day, pg_temp.sha(1)));
  PERFORM pg_temp.ok(e LIKE '22023:CL_BAD_REQUEST%size_bytes%', 'sin tamano: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(format('SELECT public.cl_delivery_open(%L, %L, %L, %L, ''[]'', ''jsonl'', 0)', d, v_day, v_day, pg_temp.sha(1)));
  PERFORM pg_temp.ok(e LIKE '22023:CL_BAD_REQUEST%size_bytes%', 'tamano 0: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(format('SELECT public.cl_delivery_open(%L, %L, %L, %L, ''[]'', ''jsonl'', 524288001)', d, v_day, v_day, pg_temp.sha(1)));
  PERFORM pg_temp.ok(e LIKE '22023:CL_FILE_TOO_LARGE%', 'sobre 500 MB: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(format('SELECT public.cl_delivery_open(%L, %L, %L, %L, ''[]'', ''jsonl'', 1001)', s, v_day, v_day, pg_temp.sha(1)));
  PERFORM pg_temp.ok(e LIKE '22023:CL_FILE_TOO_LARGE%1000%', 'sobre el tope del conector: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(format('SELECT public.cl_delivery_open(%L, %L, %L, %L, ''[]'', ''jsonl'', 10)', gen_random_uuid(), v_day, v_day, pg_temp.sha(1)));
  PERFORM pg_temp.ok(e LIKE '22023:CL_FEED_NOT_FOUND%', 'conector inexistente: ' || coalesce(e, 'ok'));
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_deliveries) = 0, 'nada escrito tras errores');

  j := public.cl_delivery_open(s, v_day, v_day, pg_temp.sha(2), '[{"place_ref":"NBO","delivered":5}]', 'jsonl', 1000);
  PERFORM pg_temp.ok(j->>'status' = 'pending_upload' AND j->>'compression' = 'none' AND j->>'source' = 'api'
                     AND j->>'file_path' LIKE '%/' || (j->>'delivery_id') || '.jsonl'
                     AND (j->>'max_file_bytes')::bigint = 1000 AND NOT (j->>'existing')::boolean, 'abierta en el tope: ' || j::text);
  PERFORM pg_temp.ok((SELECT control_totals = '[{"place_ref":"NBO","delivered":5}]'::jsonb FROM public.cl_deliveries
                       WHERE id = (j->>'delivery_id')::uuid), 'totales guardados tal cual');
  j2 := public.cl_delivery_open(s, v_day, v_day, pg_temp.sha(2), '[]', 'jsonl', 999);
  PERFORM pg_temp.ok(j2->>'delivery_id' = j->>'delivery_id' AND (j2->>'existing')::boolean, 'idempotente: ' || j2::text);
  j := public.cl_delivery_open(d, v_day, v_day, pg_temp.sha(3), '[]', 'csv', 524288000);
  PERFORM pg_temp.ok(j->>'file_path' LIKE '%.csv' AND j->>'compression' = 'none', 'csv sin .gz: ' || j::text);
END $$;

-- ================================================================ 3. configuracion: solo 'none'
DO $$
DECLARE c jsonb := public.cl_connector_config('f0000000-0000-0000-0000-0000000000d1');
BEGIN
  PERFORM pg_temp.ok(c->'formats' = '{"format":["jsonl","csv"],"compression":["none"]}'::jsonb, 'formatos: ' || (c->'formats')::text);
  PERFORM pg_temp.ok(c::text NOT LIKE '%gzip%', 'gzip no se anuncia');
  PERFORM pg_temp.ok(c->>'schema_version' = '4.0' AND c ? 'next_period' AND c ? 'limits', 'resto de la configuracion');
END $$;

-- ================================================================ 4. estado de una entrega
DO $$
DECLARE
  d constant uuid := 'f0000000-0000-0000-0000-0000000000d1';
  xf constant uuid := 'f0000000-0000-0000-0000-0000000000e2';
  v_id uuid; j jsonb; e1 text; e2 text; e3 text; a jsonb;
BEGIN
  SELECT id INTO v_id FROM public.cl_deliveries WHERE feed_id = d;
  j := public.cl_delivery_status(d, v_id);
  PERFORM pg_temp.ok(j->>'delivery_id' = v_id::text AND j->>'status' = 'pending_upload' AND j->'alerts' = '[]'::jsonb
                     AND j ? 'phase' AND j ? 'rejected_reasons' AND j ? 'shipments_drawn' AND j ? 'rows_total',
                     'estado propio: ' || j::text);

  -- Ajena (otro conector, otra cuenta), inexistente y NULL: el mismo error.
  e1 := pg_temp.raises(format('SELECT public.cl_delivery_status(%L, %L)', xf, v_id));
  e2 := pg_temp.raises(format('SELECT public.cl_delivery_status(%L, %L)', d, gen_random_uuid()));
  e3 := pg_temp.raises(format('SELECT public.cl_delivery_status(%L, NULL)', d));
  PERFORM pg_temp.ok(e1 = '22023:CL_DELIVERY_NOT_FOUND' AND e2 = e1 AND e3 = e1,
                     'mismo error para ajena / inexistente / NULL: ' || coalesce(e1, 'ok') || ' | ' || coalesce(e2, 'ok'));
  e1 := pg_temp.raises(format('SELECT public.cl_delivery_status(%L, %L)', 'f0000000-0000-0000-0000-0000000000d2', v_id));
  PERFORM pg_temp.ok(e1 = '22023:CL_DELIVERY_NOT_FOUND', 'otro conector de la misma cuenta: ' || coalesce(e1, 'ok'));

  -- Alertas: solo las visibles para el transportista, con detalle filtrado.
  INSERT INTO public.cl_alerts (account_id, plan_id, quota_id, delivery_id, alert_type, severity, details, status) VALUES
    ('a0000000-0000-0000-0000-000000000001', NULL, NULL, v_id, 'unknown_product', 'medium',
     jsonb_build_object('values', '["ZZ"]'::jsonb, 'delivery_id', v_id, 'internal', 'x'), 'open'),
    ('a0000000-0000-0000-0000-000000000001', NULL, NULL, v_id, 'rejected_ratio', 'medium',
     jsonb_build_object('rejected', 3, 'shipments', 10, 'ratio', 0.3, 'reasons', '{"no_end":3}'::jsonb), 'open'),
    ('a0000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-0000000000d1', NULL, v_id, 'possible_misrouting', 'medium',
     jsonb_build_object('samples', '[{"sample_id":"s","item_id":"SECRET-ITEM-1"}]'::jsonb), 'open'),
    ('a0000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-0000000000d1', NULL, v_id, 'suspicious_distribution', 'medium',
     '{"samples":25,"on_time_ratio":1}'::jsonb, 'open'),
    ('a0000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-0000000000d1', NULL, v_id, 'insufficient_candidates', 'medium',
     '{"population":1,"quota_for_delivery":4}'::jsonb, 'acknowledged'),
    ('a0000000-0000-0000-0000-000000000001', NULL, NULL, v_id, 'unknown_reading_point', 'medium',
     '{"points":[{"place_ref":"QQ"}]}'::jsonb, 'dismissed');
  j := public.cl_delivery_status(d, v_id);
  a := j->'alerts';
  PERFORM pg_temp.ok((SELECT array_agg(x->>'type' ORDER BY x->>'type') FROM jsonb_array_elements(a) x)
                     = ARRAY['insufficient_candidates','rejected_ratio','unknown_product'], 'tipos visibles: ' || a::text);
  PERFORM pg_temp.ok(j::text NOT LIKE '%SECRET-ITEM-1%' AND j::text NOT LIKE '%on_time_ratio%', 'sin datos del sorteo');
  PERFORM pg_temp.ok((SELECT x->'details' FROM jsonb_array_elements(a) x WHERE x->>'type' = 'unknown_product')
                     = '{"values":["ZZ"]}'::jsonb, 'detalle de producto filtrado');
  PERFORM pg_temp.ok((SELECT x->'details' FROM jsonb_array_elements(a) x WHERE x->>'type' = 'rejected_ratio')
                     = '{"rejected":3,"shipments":10,"ratio":0.3}'::jsonb, 'detalle de rechazo filtrado');
  PERFORM pg_temp.ok((SELECT x->'details' FROM jsonb_array_elements(a) x WHERE x->>'type' = 'insufficient_candidates')
                     = '{}'::jsonb, 'sin detalle de cuota');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(a) x WHERE x ? 'plan_id' OR x ? 'quota_id' OR x ? 'id'),
                     'sin ids internos');
END $$;

-- ================================================================ 5. completar por la API
DO $$
DECLARE
  d constant uuid := 'f0000000-0000-0000-0000-0000000000d1';
  v_id uuid; v_path text; j jsonb; e text;
BEGIN
  SELECT id, file_path INTO v_id, v_path FROM public.cl_deliveries WHERE feed_id = d;
  e := pg_temp.raises(format('SELECT public.cl_delivery_complete(%L, %L)', d, v_id));
  PERFORM pg_temp.ok(e LIKE '22023:CL_FILE_NOT_UPLOADED%', 'sin fichero: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(format('SELECT public.cl_delivery_complete(%L, %L)', 'f0000000-0000-0000-0000-0000000000e2', v_id));
  PERFORM pg_temp.ok(e = '22023:CL_DELIVERY_NOT_FOUND', 'completar ajena: ' || coalesce(e, 'ok'));
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES ('cl-deliveries', v_path, '{"size": 123}');
  j := public.cl_delivery_complete(d, v_id);
  PERFORM pg_temp.ok(j->>'status' = 'received' AND (j->>'file_bytes')::bigint = 123, 'recibida: ' || j::text);
  j := public.cl_delivery_status(d, v_id);
  PERFORM pg_temp.ok(j->>'status' = 'received', 'estado tras completar');
END $$;

-- ================================================================ 6. mantenimiento (cl_housekeeping), fix ronda 1
-- Conector H semanal (lunes) con un plan vencido (05/10-18/10, margen 7 dias) y un plan futuro.
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status, emit_days, emit_hour) VALUES
  ('f0000000-0000-0000-0000-0000000000d3','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed H','active','{1}',3);
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000d3','a0000000-0000-0000-0000-000000000001','PH','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',5,'2026-10-05','2026-10-18','active','f0000000-0000-0000-0000-0000000000d3'),
  ('90000000-0000-0000-0000-0000000000d4','a0000000-0000-0000-0000-000000000001','PF','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',5,'2026-12-07','2026-12-20','active','f0000000-0000-0000-0000-0000000000d3');
INSERT INTO public.cl_plan_quotas (id, account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned, samples_obtained) VALUES
  ('91000000-0000-0000-0000-0000000000d1','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000d3','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,41,'2026-10-05','2026-10-11',2,2),
  ('91000000-0000-0000-0000-0000000000d2','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000d3','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,42,'2026-10-12','2026-10-18',3,1);
-- A2 con zona invalida y un plan activo en su conector X (sin zona propia).
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','PB','Prod2',48);
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000e2','a0000000-0000-0000-0000-000000000002','PX','ca000000-0000-0000-0000-000000000002','cb000000-0000-0000-0000-000000000002',5,'2026-11-02','2026-12-27','active','f0000000-0000-0000-0000-0000000000e2');
-- Una zona invalida guardada antes de la restriccion (como en cl_demands): se quita solo dentro de la transaccion.
ALTER TABLE public.accounts DROP CONSTRAINT accounts_valid_timezone;
UPDATE public.accounts SET timezone = 'Mars/Base' WHERE id = 'a0000000-0000-0000-0000-000000000002';

DO $$
DECLARE
  v_now constant timestamptz := '2026-11-23 10:00+03';
  h jsonb; c jsonb;
BEGIN
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cl-housekeeping' AND schedule = '20 * * * *'
                               AND command = 'SELECT public.cl_housekeeping();'), 'job cl-housekeeping cada hora');
  PERFORM pg_temp.ok(NOT has_function_privilege('service_role', 'public.cl_housekeeping(timestamptz)', 'EXECUTE')
                     AND NOT has_function_privilege('authenticated', 'public.cl_housekeeping(timestamptz)', 'EXECUTE'),
                     'cl_housekeeping solo postgres (pg_cron)');
  c := public.cl_connector_config('f0000000-0000-0000-0000-0000000000d3', v_now);
  PERFORM pg_temp.ok(jsonb_array_length(c->'plans') = 2, 'antes: config lista los dos planes');

  h := public.cl_housekeeping(v_now);
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plan_quotas WHERE id = '91000000-0000-0000-0000-0000000000d1') = 'fulfilled',
                     'semana vencida sin falta: liquidada (fulfilled)');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plan_quotas WHERE id = '91000000-0000-0000-0000-0000000000d2') = 'pending',
                     'semana vencida con falta: queda para la tarea 8');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plans WHERE id = '90000000-0000-0000-0000-0000000000d3') = 'active',
                     'plan con cuota pending no se cierra');
  PERFORM pg_temp.ok((h->>'quotas_settled')::int = 1 AND (h->>'timezone_alerts')::int = 1, 'resumen: ' || h::text);
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE plan_id = '90000000-0000-0000-0000-0000000000e2'
                        AND alert_type = 'invalid_timezone') = 1, 'alerta invalid_timezone');

  -- Segunda ejecucion (y al dia siguiente): nada que liquidar otra vez, la alerta no se repite.
  h := public.cl_housekeeping(v_now);
  PERFORM pg_temp.ok((h->>'quotas_settled')::int = 0 AND (h->>'timezone_alerts')::int = 0, 'idempotente: ' || h::text);
  UPDATE public.cl_alerts SET created_at = created_at - interval '1 day' WHERE alert_type = 'invalid_timezone';
  h := public.cl_housekeeping(v_now + interval '1 day');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE plan_id = '90000000-0000-0000-0000-0000000000e2'
                        AND alert_type = 'invalid_timezone') = 1, 'invalid_timezone una sola vez');

  -- La semana con falta se completa: se liquida y el plan vencido se cierra; el futuro sigue activo.
  UPDATE public.cl_plan_quotas SET samples_obtained = 3 WHERE id = '91000000-0000-0000-0000-0000000000d2';
  h := public.cl_housekeeping(v_now);
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plan_quotas WHERE id = '91000000-0000-0000-0000-0000000000d2') = 'fulfilled'
                     AND (h->>'plans_closed')::int = 1, 'segunda semana liquidada y plan cerrado: ' || h::text);
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plans WHERE id = '90000000-0000-0000-0000-0000000000d3') = 'closed'
                     AND (SELECT status FROM public.cl_plans WHERE id = '90000000-0000-0000-0000-0000000000d4') = 'active',
                     'vencido cerrado, futuro activo');
  c := public.cl_connector_config('f0000000-0000-0000-0000-0000000000d3', v_now);
  PERFORM pg_temp.ok(jsonb_array_length(c->'plans') = 1 AND c->'plans'->0->>'start_date' = '2026-12-07',
                     'GET /config ya no lista el plan cerrado: ' || (c->'plans')::text);
  -- Lo ya liquidado no se vuelve a tocar.
  h := public.cl_housekeeping(v_now);
  PERFORM pg_temp.ok((h->>'quotas_settled')::int = 0 AND (h->>'plans_closed')::int = 0, 'sin doble liquidacion: ' || h::text);
END $$;

-- ================================================================ 7. error de la entrega: solo codigos CL_ (fix ronda 1)
DO $$
DECLARE
  d constant uuid := 'f0000000-0000-0000-0000-0000000000d1';
  v_id uuid; j jsonb; e text; r text; i int;
BEGIN
  SELECT id INTO v_id FROM public.cl_deliveries WHERE feed_id = d;   -- recibida en la seccion 5
  UPDATE public.cl_deliveries SET status = 'processing', processing_started_at = now(),
         progress = jsonb_build_object('phase', 'resolve', 'attempts', 1)
   WHERE id = v_id;

  -- Error interno forzado: el texto lleva un valor de fila; solo queda el codigo + SQLSTATE.
  PERFORM public.cl_process_delivery_failed('22P02', 'invalid input syntax for type timestamp: "SECRET-ROW-VALUE"');
  PERFORM pg_temp.ok((SELECT progress->>'final_error' FROM public.cl_deliveries WHERE id = v_id) = 'CL_PROCESSING_ERROR 22P02',
                     'final_error = codigo + SQLSTATE');
  -- Un llamador que pase texto libre a mark_abort tambien queda saneado.
  PERFORM public.cl_delivery_mark_abort(v_id, 'failed', 'boom near "SECRET-ROW-VALUE"');
  PERFORM pg_temp.ok((SELECT progress->>'final_error' FROM public.cl_deliveries WHERE id = v_id) = 'CL_PROCESSING_ERROR',
                     'texto libre -> CL_PROCESSING_ERROR');
  FOR i IN 1..5 LOOP   -- abort -> cleanup -> failed
    EXIT WHEN (SELECT status FROM public.cl_deliveries WHERE id = v_id) <> 'processing';
    r := public.cl_process_delivery(v_id)::text;
  END LOOP;
  PERFORM pg_temp.ok((SELECT status = 'failed' AND error = 'CL_PROCESSING_ERROR' FROM public.cl_deliveries WHERE id = v_id),
                     'entrega failed con el codigo: ' || coalesce(r::text, 'null'));

  -- Lo que ve el transportista: solo el codigo, tambien en last_error de una alerta.
  INSERT INTO public.cl_alerts (account_id, plan_id, delivery_id, alert_type, severity, details) VALUES
    ('a0000000-0000-0000-0000-000000000001', '90000000-0000-0000-0000-0000000000d1', v_id, 'delivery_retries_exhausted', 'high',
     '{"last_error":"ERROR: value \"SECRET-ROW-VALUE\" at line 3","attempts":3,"samples_voided":2}'::jsonb);
  j := public.cl_delivery_status(d, v_id);
  PERFORM pg_temp.ok(j->>'error' = 'CL_PROCESSING_ERROR' AND j::text NOT LIKE '%SECRET-ROW-VALUE%', 'estado sin texto interno: ' || j::text);
  PERFORM pg_temp.ok((SELECT x->'details' FROM jsonb_array_elements(j->'alerts') x WHERE x->>'type' = 'delivery_retries_exhausted')
                     = '{"last_error":"CL_PROCESSING_ERROR","attempts":3}'::jsonb, 'last_error saneado');

  -- La base no admite texto libre en error.
  e := pg_temp.raises(format('UPDATE public.cl_deliveries SET error = %L WHERE id = %L', 'value "SECRET-ROW-VALUE"', v_id));
  PERFORM pg_temp.ok(e LIKE '23514:%', 'CHECK solo codigos: ' || coalesce(e, 'ok'));
  PERFORM pg_temp.ok(public.cl_delivery_safe_error('CL_PROCESSING_ERROR 57014') = 'CL_PROCESSING_ERROR 57014'
                     AND public.cl_delivery_safe_error('CL_SHA256_MISMATCH') = 'CL_SHA256_MISMATCH'
                     AND public.cl_delivery_safe_error('CL_X: detail') = 'CL_PROCESSING_ERROR'
                     AND public.cl_delivery_safe_error(NULL) IS NULL, 'cl_delivery_safe_error');
END $$;

ROLLBACK;
\echo cl_delivery_api: OK
