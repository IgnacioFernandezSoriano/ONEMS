-- Carrier Link: cl_feed_options (lista de conectores para el generador). El Allocation Plan Manager (Edit en cl_plans,
-- sin cl_connectors) la lee; usuario de otra cuenta, sin rol o cuenta inexistente: el mismo 42501 CL_FORBIDDEN;
-- superadmin: cualquier cuenta. Nunca devuelve secretos (solo id, carrier_id, name, status).
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid text, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  PERFORM set_config('request.jwt.claim.role', coalesce(p_role, ''), true);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.msg_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE || ':' || SQLERRM; END $$;

BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- 95 APM de A1, 94 do_coordinator de A1 (View en cl_plans), 92 UPU AM de A2, 91 sin rol (A1), 97 superadmin.
INSERT INTO auth.users (id, email) VALUES
  ('95000000-0000-0000-0000-000000000095','apm@t.l'),
  ('94000000-0000-0000-0000-000000000094','do@t.l'),
  ('92000000-0000-0000-0000-000000000092','upu2@t.l'),
  ('91000000-0000-0000-0000-000000000091','x@t.l'),
  ('97000000-0000-0000-0000-000000000097','super@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('95000000-0000-0000-0000-000000000095','apm@t.l','APM','user','a0000000-0000-0000-0000-000000000001'),
  ('94000000-0000-0000-0000-000000000094','do@t.l','DO','user','a0000000-0000-0000-0000-000000000001'),
  ('92000000-0000-0000-0000-000000000092','upu2@t.l','UPU2','user','a0000000-0000-0000-0000-000000000002'),
  ('91000000-0000-0000-0000-000000000091','x@t.l','X','user','a0000000-0000-0000-0000-000000000001'),
  ('97000000-0000-0000-0000-000000000097','super@t.l','Super','superadmin',NULL);
INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000095','allocation_plan_manager'),
  ('a0000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000094','do_coordinator'),
  ('a0000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000092','upu_account_manager');

INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','CB','Carrier2'),
  ('ca000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','CC','Carrier3');
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status, config, secret_ref) VALUES
  ('f0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed B','active','{"token":"s3cr3t"}','vault:a1'),
  ('f0000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed A','testing','{}',NULL),
  ('f0000000-0000-0000-0000-0000000000a3','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000003','Feed C','paused','{}',NULL),
  ('f0000000-0000-0000-0000-0000000000b1','a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','Feed A2','active','{}','vault:b1');

-- ===================================================================== 0. firma, permisos, sin secretos
DO $$
BEGIN
  PERFORM pg_temp.ok(NOT has_function_privilege('anon', 'public.cl_feed_options(uuid,uuid)', 'EXECUTE'), 'anon sin EXECUTE');
  PERFORM pg_temp.ok(has_function_privilege('authenticated', 'public.cl_feed_options(uuid,uuid)', 'EXECUTE'), 'authenticated con EXECUTE');
  PERFORM pg_temp.ok((SELECT provolatile = 's' AND prosecdef
                        AND proconfig @> ARRAY['search_path=public, extensions']
                        FROM pg_proc WHERE oid = 'public.cl_feed_options(uuid,uuid)'::regprocedure), 'STABLE SECURITY DEFINER con search_path');
  -- Solo estas cuatro columnas de salida: nada de config, secret_ref ni claves.
  PERFORM pg_temp.ok((SELECT array_agg(n ORDER BY n) FROM unnest(
                        (SELECT proargnames FROM pg_proc WHERE oid = 'public.cl_feed_options(uuid,uuid)'::regprocedure)) n
                       WHERE n NOT LIKE 'p\_%') = ARRAY['carrier_id','id','name','status'], 'columnas sin secretos');
END $$;

-- ===================================================================== 1. APM (Edit cl_plans, sin cl_connectors): permitido
SET ROLE authenticated;
SELECT pg_temp.as_user('95000000-0000-0000-0000-000000000095', 'authenticated');
DO $$
DECLARE v text;
BEGIN
  -- El APM no lee cl_feeds directamente (RLS de cl_connectors): de ahi la funcion.
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_feeds) = 0, 'APM no lee cl_feeds directamente');
  SELECT string_agg(name || ':' || status, ',' ORDER BY name) INTO v
    FROM public.cl_feed_options('a0000000-0000-0000-0000-000000000001');
  PERFORM pg_temp.ok(v = 'Feed A:testing,Feed B:active,Feed C:paused', 'APM ve los conectores de su cuenta: ' || coalesce(v, 'null'));
  SELECT string_agg(name, ',' ORDER BY name) INTO v
    FROM public.cl_feed_options('a0000000-0000-0000-0000-000000000001', 'ca000000-0000-0000-0000-000000000001');
  PERFORM pg_temp.ok(v = 'Feed A,Feed B', 'filtro por carrier: ' || coalesce(v, 'null'));
  PERFORM pg_temp.ok(pg_temp.msg_of($q$SELECT * FROM public.cl_feed_options('a0000000-0000-0000-0000-000000000002')$q$) = '42501:CL_FORBIDDEN', 'APM no lee otra cuenta');
  PERFORM pg_temp.ok(pg_temp.msg_of($q$SELECT * FROM public.cl_feed_options('a0000000-0000-0000-0000-00000000dead')$q$) = '42501:CL_FORBIDDEN', 'cuenta inexistente: mismo 42501');
  PERFORM pg_temp.ok(pg_temp.msg_of($q$SELECT * FROM public.cl_feed_options(NULL)$q$) = '42501:CL_FORBIDDEN', 'cuenta NULL: mismo 42501');
END $$;
RESET ROLE;

-- ===================================================================== 2. View en cl_plans (do_coordinator): permitido
SET ROLE authenticated;
SELECT pg_temp.as_user('94000000-0000-0000-0000-000000000094', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_feed_options('a0000000-0000-0000-0000-000000000001')) = 3, 'view en cl_plans lee la lista');
END $$;
RESET ROLE;

-- ===================================================================== 3. otra cuenta y sin rol: denegado
SET ROLE authenticated;
SELECT pg_temp.as_user('92000000-0000-0000-0000-000000000092', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.msg_of($q$SELECT * FROM public.cl_feed_options('a0000000-0000-0000-0000-000000000001')$q$) = '42501:CL_FORBIDDEN', 'A2 no lee A1');
  PERFORM pg_temp.ok((SELECT string_agg(name, ',') FROM public.cl_feed_options('a0000000-0000-0000-0000-000000000002')) = 'Feed A2', 'A2 lee la suya');
END $$;
RESET ROLE;
SET ROLE authenticated;
SELECT pg_temp.as_user('91000000-0000-0000-0000-000000000091', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.msg_of($q$SELECT * FROM public.cl_feed_options('a0000000-0000-0000-0000-000000000001')$q$) = '42501:CL_FORBIDDEN', 'sin rol: denegado');
END $$;
RESET ROLE;

-- ===================================================================== 4. superadmin: cualquier cuenta
SET ROLE authenticated;
SELECT pg_temp.as_user('97000000-0000-0000-0000-000000000097', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_feed_options('a0000000-0000-0000-0000-000000000002')) = 1, 'superadmin lee A2');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_feed_options('a0000000-0000-0000-0000-000000000001')) = 3, 'superadmin lee A1');
END $$;
RESET ROLE;

\echo cl_feed_options: OK
ROLLBACK;
