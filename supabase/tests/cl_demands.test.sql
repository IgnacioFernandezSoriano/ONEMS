-- Carrier Link fase 1, tarea 6: emision de demandas.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.sqlstate_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE; END $$;

BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001'),
  ('d2000000-0000-0000-0000-0000000000c2','a0000000-0000-0000-0000-000000000001','PC2','Center 2','City2','c2000000-0000-0000-0000-000000000002');
INSERT INTO public.readers (account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role) VALUES
  ('a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','O1','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','NBO','M1','origin'),
  ('a0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-0000000000c2','D1','Exit','carrier_scan','ca000000-0000-0000-0000-000000000001','MBA',NULL,'destination');
-- Calendario por defecto: lunes 03:00 en la zona del conector (Nairobi, UTC+3: lunes 03:00 local = domingo/lunes 00:00 UTC).
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status, emit_timezone) VALUES
  ('f0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed A1','active','Africa/Nairobi');
INSERT INTO public.cl_value_mappings (account_id, carrier_id, kind, carrier_value, onems_value)
  SELECT 'a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','product','EXPRESS-K', code
    FROM public.products WHERE id = 'cb000000-0000-0000-0000-000000000001';

-- Plan activo (semana 47: 2026-11-16..22), plan draft con cuota pendiente.
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','P1','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',6,'2026-11-16','2026-11-22','active','f0000000-0000-0000-0000-0000000000a1'),
  ('90000000-0000-0000-0000-0000000000a5','a0000000-0000-0000-0000-000000000001','Draft','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',6,'2026-11-16','2026-11-22','draft','f0000000-0000-0000-0000-0000000000a1');
INSERT INTO public.cl_plan_quotas (id, account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned) VALUES
  ('91000000-0000-0000-0000-0000000000b1','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,47,'2026-11-16','2026-11-22',6),
  ('91000000-0000-0000-0000-0000000000b5','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a5','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,47,'2026-11-16','2026-11-22',6);

-- 1. Permisos y cron.
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT prosecdef FROM pg_proc WHERE oid = 'public.cl_emit_due_demands(timestamptz)'::regprocedure), 'emit SECURITY DEFINER');
  PERFORM pg_temp.ok(has_function_privilege('service_role','public.cl_emit_due_demands(timestamptz)','EXECUTE'), 'service_role ejecuta emit');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated','public.cl_emit_due_demands(timestamptz)','EXECUTE'), 'authenticated no ejecuta emit');
  PERFORM pg_temp.ok(NOT has_function_privilege('anon','public.cl_emit_due_demands(timestamptz)','EXECUTE'), 'anon no ejecuta emit');
  PERFORM pg_temp.ok(NOT has_function_privilege('authenticated','public.cl_build_demand(uuid,uuid[])','EXECUTE'), 'authenticated no ejecuta build');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cl-emit-demands' AND schedule = '15 * * * *'
     AND command = 'SELECT public.cl_emit_due_demands();'), 'job cron cl-emit-demands');
END $$;

-- 2. Calendario y vencimiento. Cuota W47 vence (period_end + 7) el 2026-11-29 hora local.
DO $$
BEGIN
  -- Lunes 11-23 03:00 local: dentro del calendario pero la cuota aun no ha vencido (+1 dia).
  PERFORM pg_temp.ok(public.cl_emit_due_demands(TIMESTAMPTZ '2026-11-23 00:00:00+00') = 0, 'no vencida: no emite');
  -- Lunes 11-30: 03:00 local = 00:00 UTC. Una hora antes/despues, otro dia y la hora en UTC no emiten.
  PERFORM pg_temp.ok(public.cl_emit_due_demands(TIMESTAMPTZ '2026-11-29 23:00:00+00') = 0, '02:00 local no emite');
  PERFORM pg_temp.ok(public.cl_emit_due_demands(TIMESTAMPTZ '2026-11-30 01:00:00+00') = 0, '04:00 local no emite');
  PERFORM pg_temp.ok(public.cl_emit_due_demands(TIMESTAMPTZ '2026-11-30 03:00:00+00') = 0, '03:00 UTC (06:00 local) no emite');
  PERFORM pg_temp.ok(public.cl_emit_due_demands(TIMESTAMPTZ '2026-12-01 00:00:00+00') = 0, 'martes no emite');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_demands) = 0, 'sin demandas');
END $$;

-- 3. +7 = 2026-11-29: emite 1 (solo el plan activo).
DO $$
DECLARE d public.cl_demands; s jsonb;
BEGIN
  PERFORM pg_temp.ok(public.cl_emit_due_demands(TIMESTAMPTZ '2026-11-30 00:00:00+00') = 1, 'en su hueco local emite 1');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_demands) = 1, 'una demanda');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_demands WHERE plan_id = '90000000-0000-0000-0000-0000000000a5') = 0, 'draft no emite');
  SELECT * INTO d FROM public.cl_demands;
  PERFORM pg_temp.ok(d.status = 'open' AND d.feed_id = 'f0000000-0000-0000-0000-0000000000a1', 'demanda open con feed');
  PERFORM pg_temp.ok(length(d.random_seed) = 32, 'random_seed de 32 hex');
  PERFORM pg_temp.ok(position(d.random_seed IN d.payload::text) = 0, 'semilla fuera del payload');
  PERFORM pg_temp.ok(NOT (d.payload ? 'random_seed'), 'sin clave random_seed');
  PERFORM pg_temp.ok(d.payload->>'schema_version' = '1.1', 'schema_version');
  PERFORM pg_temp.ok(d.payload->>'demand_id' = d.id::text, 'demand_id');
  PERFORM pg_temp.ok(d.payload->>'carrier' = (SELECT code FROM public.carriers WHERE id = 'ca000000-0000-0000-0000-000000000001'), 'carrier code');
  PERFORM pg_temp.ok(d.payload->'products' = '["EXPRESS-K"]'::jsonb, 'producto del carrier');
  PERFORM pg_temp.ok((d.payload->>'include_all_scans')::boolean = false, 'include_all_scans false');
  PERFORM pg_temp.ok(jsonb_array_length(d.payload->'strata') = 1, 'un estrato');
  s := d.payload->'strata'->0;
  PERFORM pg_temp.ok(s->>'stratum_id' = '91000000-0000-0000-0000-0000000000b1', 'stratum_id');
  PERFORM pg_temp.ok(s->'period'->>'iso_week' = '2026-W47' AND s->'period'->>'start' = '2026-11-16' AND s->'period'->>'end' = '2026-11-22', 'periodo');
  PERFORM pg_temp.ok(s->'start_points' = '[{"place_ref":"NBO","mode_ref":"M1"}]'::jsonb, 'start_points');
  PERFORM pg_temp.ok(s->'end_points' = '[{"place_ref":"MBA","mode_ref":null}]'::jsonb, 'end_points');
  PERFORM pg_temp.ok((s->>'samples_required')::int = 6 AND (s->>'candidates_requested')::int = 30, 'required 6, candidatos 30');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plan_quotas WHERE id = '91000000-0000-0000-0000-0000000000b1') = 'open', 'cuota open');
  PERFORM pg_temp.ok((SELECT demands_count FROM public.cl_plan_quotas WHERE id = '91000000-0000-0000-0000-0000000000b1') = 1, 'demands_count 1');
  PERFORM pg_temp.ok(d.payload->'schedule' = '{"days":[1],"hour":3,"timezone":"Africa/Nairobi"}'::jsonb, 'schedule en el payload');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plans WHERE id = '90000000-0000-0000-0000-0000000000a1') = 'active', 'plan sigue activo (cuota open)');
END $$;

-- 4. Idempotente en el mismo hueco (cuotas open; y aunque se reabran, la demanda del hueco lo impide).
DO $$
BEGIN
  PERFORM pg_temp.ok(public.cl_emit_due_demands(TIMESTAMPTZ '2026-11-30 00:30:00+00') = 0, 'segunda llamada no emite');
  UPDATE public.cl_plan_quotas SET status = 'pending' WHERE id = '91000000-0000-0000-0000-0000000000b1';
  PERFORM pg_temp.ok(public.cl_emit_due_demands(TIMESTAMPTZ '2026-11-30 00:45:00+00') = 0, 'mismo hueco con cuota pending: no emite');
  UPDATE public.cl_plan_quotas SET status = 'open' WHERE id = '91000000-0000-0000-0000-0000000000b1';
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_demands) = 1, 'sigue habiendo 1 demanda');
END $$;

-- 5. Conector pausado no emite; requerido <= 0 no emite; testing si; required = planned + carried - obtained.
DO $$
BEGIN
  UPDATE public.cl_plan_quotas SET status = 'pending' WHERE id = '91000000-0000-0000-0000-0000000000b1';
  UPDATE public.cl_feeds SET status = 'paused';
  PERFORM pg_temp.ok(public.cl_emit_due_demands(TIMESTAMPTZ '2026-12-07 00:00:00+00') = 0, 'feed paused no emite');
  UPDATE public.cl_feeds SET status = 'testing';
  UPDATE public.cl_plan_quotas SET samples_obtained = 6 WHERE id = '91000000-0000-0000-0000-0000000000b1';
  PERFORM pg_temp.ok(public.cl_emit_due_demands(TIMESTAMPTZ '2026-12-07 00:00:00+00') = 0, 'requerido 0 no emite');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plans WHERE id = '90000000-0000-0000-0000-0000000000a1') = 'closed', 'cuota sin requerido se cumple y el plan vencido se cierra');
  UPDATE public.cl_plans SET status = 'active' WHERE id = '90000000-0000-0000-0000-0000000000a1';
  UPDATE public.cl_plan_quotas SET status = 'pending', samples_obtained = 2, samples_carried_in = 1 WHERE id = '91000000-0000-0000-0000-0000000000b1';
  PERFORM pg_temp.ok(public.cl_emit_due_demands(TIMESTAMPTZ '2026-12-07 00:00:00+00') = 1, 'feed testing emite');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM public.cl_demands WHERE (payload->'strata'->0->>'samples_required')::int = 5
                AND (payload->'strata'->0->>'candidates_requested')::int = 25), 'required = 6+1-2 = 5, candidatos 25');
END $$;

-- 6. Cierre del plan: sin cuotas pending/open y end_date + 7 pasado.
DO $$
BEGIN
  UPDATE public.cl_plan_quotas SET status = 'fulfilled' WHERE plan_id = '90000000-0000-0000-0000-0000000000a1';
  PERFORM public.cl_emit_due_demands(TIMESTAMPTZ '2026-11-29 12:00:00+00');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plans WHERE id = '90000000-0000-0000-0000-0000000000a1') = 'active', 'no se cierra antes de end_date + lag');
  PERFORM public.cl_emit_due_demands(TIMESTAMPTZ '2026-11-30 12:00:00+00');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plans WHERE id = '90000000-0000-0000-0000-0000000000a1') = 'closed', 'plan cerrado');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plans WHERE id = '90000000-0000-0000-0000-0000000000a5') = 'draft', 'draft intacto');
END $$;

-- 7. Validaciones del calendario del conector.
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT emit_days = '{1}' AND emit_hour = 3 FROM public.cl_feeds LIMIT 1), 'defaults lunes 03h');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$UPDATE public.cl_feeds SET emit_timezone = 'Mars/Olympus'$q$) = '23514', 'zona invalida rechazada');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$UPDATE public.cl_feeds SET emit_days = '{0}'$q$) = '23514', 'emit_days {0} rechazado');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$UPDATE public.cl_feeds SET emit_days = '{8}'$q$) = '23514', 'emit_days {8} rechazado');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$UPDATE public.cl_feeds SET emit_days = '{}'$q$) = '23514', 'emit_days vacio rechazado');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$UPDATE public.cl_feeds SET emit_hour = 24$q$) = '23514', 'emit_hour 24 rechazado');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$UPDATE public.cl_feeds SET emit_timezone = NULL, emit_days = '{1,7}', emit_hour = 0$q$) IS NULL, 'valores validos aceptados');
END $$;

\echo cl_demands: OK
ROLLBACK;
