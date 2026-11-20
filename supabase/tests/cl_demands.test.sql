-- Carrier Link fase 1, tarea 6: emision de demandas.
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

-- 8. Robustez de la emision (todo en A1, zona UTC salvo donde se indica).
UPDATE public.accounts SET timezone = 'UTC' WHERE id = 'a0000000-0000-0000-0000-000000000001';
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status, emit_days, emit_hour) VALUES
  ('f0000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed A2 (zona de la cuenta)','active','{1,2,3,4,5,6,7}',3);
-- Plan M: cuota c2 -> c1 sin punto de inicio (c2 solo tiene destino).
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000b1','a0000000-0000-0000-0000-000000000001','M','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',6,'2026-11-16','2026-11-22','active','f0000000-0000-0000-0000-0000000000a2');
INSERT INTO public.cl_plan_quotas (id, account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned) VALUES
  ('91000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000b1','c2000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000001',2026,47,'2026-11-16','2026-11-22',6);
DO $$
BEGIN
  PERFORM pg_temp.ok(public.cl_emit_due_demands(TIMESTAMPTZ '2026-12-14 03:00:00+00') = 0, 'cuota sin puntos: no hay demanda');
  PERFORM pg_temp.ok((SELECT status = 'pending' AND demands_count = 0 FROM public.cl_plan_quotas WHERE id = '91000000-0000-0000-0000-0000000000c1'), 'cuota sin puntos sigue pending');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE plan_id = '90000000-0000-0000-0000-0000000000b1' AND alert_type = 'missing_points') = 1, 'alerta missing_points');
  PERFORM pg_temp.ok(public.cl_emit_due_demands(TIMESTAMPTZ '2026-12-14 03:30:00+00') = 0, 'segunda llamada sin demanda');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE plan_id = '90000000-0000-0000-0000-0000000000b1' AND alert_type = 'missing_points') = 1, 'alerta missing_points no se duplica el mismo dia');
END $$;

-- Zona de la cuenta NULL -> UTC; zona invalida -> UTC + alerta.
ALTER TABLE public.accounts ALTER COLUMN timezone DROP NOT NULL;
ALTER TABLE public.accounts DROP CONSTRAINT accounts_valid_timezone;
UPDATE public.accounts SET timezone = NULL WHERE id = 'a0000000-0000-0000-0000-000000000001';
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000b2','a0000000-0000-0000-0000-000000000001','P2','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',6,'2026-11-16','2026-11-22','active','f0000000-0000-0000-0000-0000000000a2');
INSERT INTO public.cl_plan_quotas (id, account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned) VALUES
  ('91000000-0000-0000-0000-0000000000c2','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000b2','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,47,'2026-11-16','2026-11-22',6);
DO $$
BEGIN
  PERFORM pg_temp.ok(public.cl_emit_due_demands(TIMESTAMPTZ '2026-12-14 03:00:00+00') = 1, 'cuenta sin zona: UTC, emite a las 03:00Z');
  PERFORM pg_temp.ok((SELECT payload->'schedule'->>'timezone' FROM public.cl_demands WHERE plan_id = '90000000-0000-0000-0000-0000000000b2') = 'UTC', 'schedule.timezone UTC');
  UPDATE public.accounts SET timezone = 'Mars/Base' WHERE id = 'a0000000-0000-0000-0000-000000000001';
  UPDATE public.cl_plan_quotas SET status = 'pending' WHERE id = '91000000-0000-0000-0000-0000000000c2';
  PERFORM pg_temp.ok(public.cl_emit_due_demands(TIMESTAMPTZ '2026-12-15 03:00:00+00') = 1, 'zona invalida: UTC, emite a las 03:00Z');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE plan_id = '90000000-0000-0000-0000-0000000000b2' AND alert_type = 'invalid_timezone') = 1, 'alerta invalid_timezone');
  UPDATE public.accounts SET timezone = 'UTC' WHERE id = 'a0000000-0000-0000-0000-000000000001';
END $$;

-- Aislamiento: P3 falla (trigger de prueba), P4 emite igualmente.
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000b3','a0000000-0000-0000-0000-000000000001','P3 falla','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',6,'2026-11-16','2026-11-22','active','f0000000-0000-0000-0000-0000000000a2'),
  ('90000000-0000-0000-0000-0000000000b4','a0000000-0000-0000-0000-000000000001','P4 ok','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',6,'2026-11-16','2026-11-22','active','f0000000-0000-0000-0000-0000000000a2');
INSERT INTO public.cl_plan_quotas (id, account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned) VALUES
  ('91000000-0000-0000-0000-0000000000c3','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000b3','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,47,'2026-11-16','2026-11-22',6),
  ('91000000-0000-0000-0000-0000000000c4','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000b4','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,47,'2026-11-16','2026-11-22',6);
CREATE FUNCTION public.t_fail_demand() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.plan_id = '90000000-0000-0000-0000-0000000000b3' THEN RAISE EXCEPTION 'fallo forzado'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER t_fail_demand BEFORE INSERT ON public.cl_demands FOR EACH ROW EXECUTE FUNCTION public.t_fail_demand();
DO $$
BEGIN
  PERFORM pg_temp.ok(public.cl_emit_due_demands(TIMESTAMPTZ '2026-12-16 03:00:00+00') = 1, 'un plan falla y el otro emite');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_demands WHERE plan_id = '90000000-0000-0000-0000-0000000000b4') = 1, 'P4 tiene su demanda');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_demands WHERE plan_id = '90000000-0000-0000-0000-0000000000b3') = 0, 'P3 sin demanda');
  PERFORM pg_temp.ok((SELECT status = 'pending' FROM public.cl_plan_quotas WHERE id = '91000000-0000-0000-0000-0000000000c3'), 'cuota de P3 intacta');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_alerts WHERE plan_id = '90000000-0000-0000-0000-0000000000b3' AND alert_type = 'emit_failed' AND severity = 'high'
                         AND details->>'error' = 'fallo forzado') = 1, 'alerta emit_failed con el error');
END $$;
DROP TRIGGER t_fail_demand ON public.cl_demands;

-- Plan activo sin conector: se cierra al pasar la ventana (zona de la cuenta).
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status) VALUES
  ('90000000-0000-0000-0000-0000000000b5','a0000000-0000-0000-0000-000000000001','Sin feed','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',6,'2026-11-16','2026-11-22','active');
DO $$
BEGIN
  PERFORM public.cl_emit_due_demands(TIMESTAMPTZ '2026-11-29 12:00:00+00');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plans WHERE id = '90000000-0000-0000-0000-0000000000b5') = 'active', 'sin feed: aun dentro de la ventana');
  PERFORM public.cl_emit_due_demands(TIMESTAMPTZ '2026-11-30 12:00:00+00');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plans WHERE id = '90000000-0000-0000-0000-0000000000b5') = 'closed', 'plan sin feed se cierra');
END $$;

-- 9. Endurecimiento: CHECKs, privilegios y estado solo por funciones.
DO $$
DECLARE f text;
BEGIN
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$UPDATE public.cl_plans SET oversampling_factor = 0.5$q$) = '23514', 'oversampling < 1 rechazado');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$UPDATE public.cl_plans SET oversampling_factor = 101$q$) = '23514', 'oversampling > 100 rechazado');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$UPDATE public.cl_plans SET close_lag_days = 366$q$) = '23514', 'close_lag > 365 rechazado');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$UPDATE public.cl_plans SET close_lag_days = -1$q$) = '23514', 'close_lag < 0 rechazado');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$UPDATE public.cl_plans SET total_samples = 0$q$) = '23514', 'total_samples 0 rechazado');
  FOREACH f IN ARRAY ARRAY['cl_build_demand(uuid,uuid[])','cl_active_points(uuid,uuid)','cl_effective_tz(uuid,uuid)','cl_raise_alert(uuid,uuid,text,text,jsonb)'] LOOP
    PERFORM pg_temp.ok(NOT has_function_privilege('service_role', ('public.' || f)::regprocedure, 'EXECUTE'), f || ' sin EXECUTE para service_role');
    PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', ('public.' || f)::regprocedure, 'EXECUTE'), f || ' sin EXECUTE para authenticated');
  END LOOP;
END $$;

INSERT INTO auth.users (id, email) VALUES ('93000000-0000-0000-0000-000000000093','am@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('93000000-0000-0000-0000-000000000093','am@t.l','AM','user','a0000000-0000-0000-0000-000000000001');
INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000093','account_manager');
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$UPDATE public.cl_plans SET status = 'active' WHERE id = '90000000-0000-0000-0000-0000000000a5'$q$) = '42501', 'AM no fija status por UPDATE');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$UPDATE public.cl_plans SET plan_name = 'Renombrado' WHERE id = '90000000-0000-0000-0000-0000000000a5'$q$) IS NULL, 'AM si edita el nombre');
  INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status)
  VALUES ('90000000-0000-0000-0000-0000000000b6','a0000000-0000-0000-0000-000000000001','Nuevo','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',6,'2026-11-16','2026-11-22','active');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plans WHERE id = '90000000-0000-0000-0000-0000000000b6') = 'draft', 'INSERT con status active nace draft');
  PERFORM public.cl_plan_activate('90000000-0000-0000-0000-0000000000a5');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plans WHERE id = '90000000-0000-0000-0000-0000000000a5') = 'active', 'cl_plan_activate sigue funcionando');
END $$;
RESET ROLE;

\echo cl_demands: OK
ROLLBACK;
