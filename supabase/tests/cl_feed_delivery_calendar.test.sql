-- Carrier Link v4, tarea 5: cl_feed_delivery_calendar (20261124200400). Lectura del calendario de entregas para la
-- pantalla Conectores: frecuencia, proximo periodo, margen de no recibido. Permiso View en cl_connectors de la cuenta
-- activa (o superadmin); lo demas, el mismo 42501 CL_FORBIDDEN. Todo en BEGIN ... ROLLBACK.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.raises(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE || ':' || SQLERRM; END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid text, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  PERFORM set_config('request.jwt.claim.role', coalesce(p_role, ''), true);
END $$;

BEGIN;
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- A1: conector semanal W (lunes) con margen 12 h y diario D sin margen (6 por defecto); plan activo en ambos.
-- A2: conector X. Usuario 96: perfil en A1 sin ningun rol (sin derecho).
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status, emit_days, emit_hour, config) VALUES
  ('f0000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed W','active','{1}',3,'{"missing_grace_hours":12}'),
  ('f0000000-0000-0000-0000-0000000000c2','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed D','testing','{1,2,3,4,5,6,7}',3,'{}');
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','PW','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,current_date - 30,current_date + 30,'active','f0000000-0000-0000-0000-0000000000c1'),
  ('90000000-0000-0000-0000-0000000000c2','a0000000-0000-0000-0000-000000000001','PD','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,current_date - 30,current_date + 30,'active','f0000000-0000-0000-0000-0000000000c2');
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','CB','Carrier2');
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status, emit_days, emit_hour) VALUES
  ('f0000000-0000-0000-0000-0000000000c3','a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','Feed X','active','{1}',3);
INSERT INTO auth.users (id, email) VALUES ('96000000-0000-0000-0000-000000000096','none@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('96000000-0000-0000-0000-000000000096','none@t.l','None','user','a0000000-0000-0000-0000-000000000001');
INSERT INTO public.account_access (account_id, role, option, level) VALUES
  ('a0000000-0000-0000-0000-000000000001','upu_account_manager','cl_connectors','view'),
  ('a0000000-0000-0000-0000-000000000002','upu_account_manager','cl_connectors','view')
ON CONFLICT DO NOTHING;

-- ================================================================ 1. firma y privilegios
DO $$
DECLARE f constant text := 'public.cl_feed_delivery_calendar(uuid)';
BEGIN
  PERFORM pg_temp.ok((SELECT prosecdef FROM pg_proc WHERE oid = f::regprocedure), 'SECURITY DEFINER');
  PERFORM pg_temp.ok((SELECT proconfig @> ARRAY['search_path=public, extensions'] FROM pg_proc WHERE oid = f::regprocedure),
                     'search_path');
  PERFORM pg_temp.ok((SELECT provolatile = 's' FROM pg_proc WHERE oid = f::regprocedure), 'STABLE (solo lectura)');
  PERFORM pg_temp.ok(has_function_privilege('authenticated', f, 'EXECUTE'), 'authenticated');
  PERFORM pg_temp.ok(NOT has_function_privilege('anon', f, 'EXECUTE'), 'sin anon');
  PERFORM pg_temp.ok(NOT has_function_privilege('service_role', f, 'EXECUTE'), 'sin service_role (es de la web)');
END $$;

-- ================================================================ 2. contenido y permiso
SET ROLE authenticated;
DO $$
DECLARE j jsonb; e text;
BEGIN
  PERFORM pg_temp.as_user('99000000-0000-0000-0000-000000000099', 'authenticated');
  j := public.cl_feed_delivery_calendar('f0000000-0000-0000-0000-0000000000c1');
  PERFORM pg_temp.ok(j->'calendar'->>'frequency' = 'weekly' AND (j->'calendar'->>'deliveries_per_week')::int = 1
                     AND j->'calendar'->'delivery_days' = '[1]'::jsonb AND (j->'calendar'->>'delivery_hour')::int = 3,
                     'calendario semanal: ' || j::text);
  PERFORM pg_temp.ok((j->>'missing_grace_hours')::int = 12, 'margen del config: ' || j::text);
  PERFORM pg_temp.ok(j->'next_period'->>'period_start' IS NOT NULL
                     AND extract(isodow FROM (j->'next_period'->>'period_start')::date) = 1
                     AND (j->'next_period'->>'period_end')::date - (j->'next_period'->>'period_start')::date = 6,
                     'proximo periodo lunes..domingo: ' || j::text);
  PERFORM pg_temp.ok(j->'last_delivery' = 'null'::jsonb AND (j->>'max_file_bytes')::bigint = 524288000,
                     'sin entregas y tope por defecto: ' || j::text);
  PERFORM pg_temp.ok(NOT (j ?| ARRAY['fields','points','products','plans','connector']), 'solo el subconjunto del calendario');

  j := public.cl_feed_delivery_calendar('f0000000-0000-0000-0000-0000000000c2');
  PERFORM pg_temp.ok(j->'calendar'->>'frequency' = 'daily' AND (j->>'missing_grace_hours')::int = 6
                     AND j->'next_period'->>'period_start' = j->'next_period'->>'period_end',
                     'diario, margen por defecto 6: ' || j::text);

  -- Ajeno, inexistente, NULL: el mismo error.
  e := pg_temp.raises($q$SELECT public.cl_feed_delivery_calendar('f0000000-0000-0000-0000-0000000000c3')$q$);
  PERFORM pg_temp.ok(e = '42501:CL_FORBIDDEN', 'ajeno: ' || coalesce(e, 'ok'));
  e := pg_temp.raises($q$SELECT public.cl_feed_delivery_calendar('f0000000-0000-0000-0000-0000000000ff')$q$);
  PERFORM pg_temp.ok(e = '42501:CL_FORBIDDEN', 'inexistente: ' || coalesce(e, 'ok'));
  e := pg_temp.raises($q$SELECT public.cl_feed_delivery_calendar(NULL)$q$);
  PERFORM pg_temp.ok(e = '42501:CL_FORBIDDEN', 'NULL: ' || coalesce(e, 'ok'));

  -- Sin rol en la cuenta: no ve el calendario de su propia cuenta.
  PERFORM pg_temp.as_user('96000000-0000-0000-0000-000000000096', 'authenticated');
  e := pg_temp.raises($q$SELECT public.cl_feed_delivery_calendar('f0000000-0000-0000-0000-0000000000c1')$q$);
  PERFORM pg_temp.ok(e = '42501:CL_FORBIDDEN', 'sin derecho: ' || coalesce(e, 'ok'));

  -- La otra cuenta ve el suyo.
  PERFORM pg_temp.as_user('98000000-0000-0000-0000-000000000098', 'authenticated');
  j := public.cl_feed_delivery_calendar('f0000000-0000-0000-0000-0000000000c3');
  PERFORM pg_temp.ok(j->'calendar'->>'frequency' = 'weekly' AND j->'next_period' = 'null'::jsonb,
                     'A2: semanal sin plan -> sin proximo periodo: ' || j::text);
END $$;
RESET ROLE;

-- Revision final (I1): con derecho pero sin cuenta activa (profiles.account_id NULL) -> el mismo 42501.
-- Hoy no se puede dar (check_account_role + account_id inmutable): se simula dentro de esta transaccion de prueba
-- (ROLLBACK) quitando la restriccion y sin disparadores para este UPDATE. La guarda debe negar igual.
ALTER TABLE public.profiles DROP CONSTRAINT check_account_role;
SET session_replication_role = replica;
UPDATE public.profiles SET account_id = NULL WHERE id = '99000000-0000-0000-0000-000000000099';
SET session_replication_role = origin;
SET ROLE authenticated;
DO $$
DECLARE e text;
BEGIN
  PERFORM pg_temp.as_user('99000000-0000-0000-0000-000000000099', 'authenticated');
  e := pg_temp.raises($q$SELECT public.cl_feed_delivery_calendar('f0000000-0000-0000-0000-0000000000c1')$q$);
  PERFORM pg_temp.ok(e = '42501:CL_FORBIDDEN', 'sin cuenta activa: ' || coalesce(e, 'ok'));
END $$;
RESET ROLE;
SET session_replication_role = replica;
UPDATE public.profiles SET account_id = 'a0000000-0000-0000-0000-000000000001' WHERE id = '99000000-0000-0000-0000-000000000099';
SET session_replication_role = origin;

SET ROLE anon;
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT public.cl_feed_delivery_calendar('f0000000-0000-0000-0000-0000000000c1')$q$)
                     LIKE '42501:%', 'anon no la ejecuta');
END $$;
RESET ROLE;

ROLLBACK;
