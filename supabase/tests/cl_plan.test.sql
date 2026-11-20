-- Carrier Link fase 1, tarea 5: cuotas y activacion del plan.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid text, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  PERFORM set_config('request.jwt.claim.role', coalesce(p_role, ''), true);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.sqlstate_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE; END $$;

CREATE OR REPLACE FUNCTION pg_temp.msg_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE || ':' || SQLERRM; END $$;

BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- 93 AM de A1 (Edit en cl_plans), 92 UPU AM de A2, 91 sin rol (A1), 97 superadmin.
INSERT INTO auth.users (id, email) VALUES
  ('93000000-0000-0000-0000-000000000093','am@t.l'),
  ('92000000-0000-0000-0000-000000000092','upu2@t.l'),
  ('91000000-0000-0000-0000-000000000091','x@t.l'),
  ('97000000-0000-0000-0000-000000000097','super@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('93000000-0000-0000-0000-000000000093','am@t.l','AM','user','a0000000-0000-0000-0000-000000000001'),
  ('92000000-0000-0000-0000-000000000092','upu2@t.l','UPU2','user','a0000000-0000-0000-0000-000000000002'),
  ('91000000-0000-0000-0000-000000000091','x@t.l','X','user','a0000000-0000-0000-0000-000000000001'),
  ('97000000-0000-0000-0000-000000000097','super@t.l','Super','superadmin',NULL);
INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000093','account_manager'),
  ('a0000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000092','upu_account_manager');

-- Ciudad de A2 y centros con ciudad en A1.
INSERT INTO public.regions (id, account_id, name, code) VALUES
  ('e0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','Reg2','R2');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','CityB','CB');
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001'),
  ('d2000000-0000-0000-0000-0000000000c2','a0000000-0000-0000-0000-000000000001','PC2','Center 2','City2','c2000000-0000-0000-0000-000000000002');
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name) VALUES
  ('f0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed A1');

-- Plan 2026-11-16 .. 2026-11-29 (semanas ISO 47 y 48), con feed; plan sin feed; plan cerrado; plan de A2.
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','P1','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2026-11-16','2026-11-29','f0000000-0000-0000-0000-0000000000a1'),
  ('90000000-0000-0000-0000-0000000000a3','a0000000-0000-0000-0000-000000000001','Sin feed','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2026-11-16','2026-11-29',NULL);
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status) VALUES
  ('90000000-0000-0000-0000-0000000000a4','a0000000-0000-0000-0000-000000000001','Cerrado','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2026-11-16','2026-11-29','closed');
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','CB','Carrier2');
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','PR2','Prod2',48);
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date) VALUES
  ('90000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000002','P2','ca000000-0000-0000-0000-000000000002','cb000000-0000-0000-0000-000000000002',10,'2026-11-16','2026-11-29');

-- 1. Funciones: existen, SECURITY DEFINER, anon sin EXECUTE.
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['cl_plan_set_quotas(uuid,jsonb)','cl_plan_missing_points(uuid)','cl_plan_missing_standards(uuid)','cl_plan_activate(uuid)'] LOOP
    PERFORM pg_temp.ok((SELECT prosecdef FROM pg_proc WHERE oid = ('public.' || f)::regprocedure), f || ' SECURITY DEFINER');
    PERFORM pg_temp.ok(NOT has_function_privilege('anon', ('public.' || f)::regprocedure, 'EXECUTE'), f || ' anon sin EXECUTE');
    PERFORM pg_temp.ok(has_function_privilege('authenticated', ('public.' || f)::regprocedure, 'EXECUTE'), f || ' authenticated EXECUTE');
  END LOOP;
END $$;

-- 2. Cuotas (como postgres): samples<=0 se ignora, periodo ISO, reemplazo de pendientes.
DO $$
DECLARE n int;
BEGIN
  n := public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a1', $j$[
    {"origin_city_id":"c1000000-0000-0000-0000-000000000001","destination_city_id":"c2000000-0000-0000-0000-000000000002","iso_year":2026,"iso_week":47,"samples":5},
    {"origin_city_id":"c1000000-0000-0000-0000-000000000001","destination_city_id":"c2000000-0000-0000-0000-000000000002","iso_year":2026,"iso_week":48,"samples":0}
  ]$j$::jsonb);
  PERFORM pg_temp.ok(n = 1, 'devuelve 1 cuota (devuelve ' || n || ')');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000a1') = 1, 'samples=0 no se guarda');
  PERFORM pg_temp.ok((SELECT period_start FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000a1') = DATE '2026-11-16', 'W47 empieza 2026-11-16');
  PERFORM pg_temp.ok((SELECT period_end FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000a1') = DATE '2026-11-22', 'W47 acaba 2026-11-22');
  PERFORM pg_temp.ok((SELECT samples_planned FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000a1') = 5, 'samples_planned = 5');
  -- reemplazo: una cuota no pending se conserva; las pending se sustituyen
  UPDATE public.cl_plan_quotas SET status = 'open' WHERE plan_id = '90000000-0000-0000-0000-0000000000a1';
  n := public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a1', $j$[
    {"origin_city_id":"c2000000-0000-0000-0000-000000000002","destination_city_id":"c1000000-0000-0000-0000-000000000001","iso_year":2026,"iso_week":48,"samples":3}]$j$::jsonb);
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000a1') = 2, 'open se conserva y se anade la nueva');
  DELETE FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000a1';
  n := public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a1', $j$[
    {"origin_city_id":"c1000000-0000-0000-0000-000000000001","destination_city_id":"c2000000-0000-0000-0000-000000000002","iso_year":2026,"iso_week":47,"samples":5}]$j$::jsonb);
  n := public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a1', $j$[
    {"origin_city_id":"c1000000-0000-0000-0000-000000000001","destination_city_id":"c2000000-0000-0000-0000-000000000002","iso_year":2026,"iso_week":47,"samples":6}]$j$::jsonb);
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000a1') = 1, 'pending se reemplazan');
  PERFORM pg_temp.ok((SELECT samples_planned FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000a1') = 6, 'valor nuevo tras reemplazar');
  n := public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a1', $j$[
    {"origin_city_id":"c1000000-0000-0000-0000-000000000001","destination_city_id":"c2000000-0000-0000-0000-000000000002","iso_year":2026,"iso_week":47,"samples":5}]$j$::jsonb);
END $$;

-- 3. Rechazos (22023), sin tocar lo existente.
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$SELECT public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a1', '[
    {"origin_city_id":"c1000000-0000-0000-0000-000000000001","destination_city_id":"c2000000-0000-0000-0000-000000000002","iso_year":2026,"iso_week":50,"samples":2}]'::jsonb)$q$) = '22023', 'semana fuera del plan');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$SELECT public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a1', '[
    {"origin_city_id":"c1000000-0000-0000-0000-000000000001","destination_city_id":"c3000000-0000-0000-0000-000000000003","iso_year":2026,"iso_week":47,"samples":2}]'::jsonb)$q$) = '22023', 'ciudad de otra cuenta');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$SELECT public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a4', '[]'::jsonb)$q$) = '22023', 'plan cerrado');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000a1') = 1, 'un rechazo no borra las cuotas');
END $$;

-- 3b. JSON mal formado, duplicados, cuotas bloqueadas, semanas ISO, feed de otro carrier.
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','CC','Carrier3');
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name) VALUES
  ('f0000000-0000-0000-0000-0000000000a5','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000003','Feed C3');
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000b1','a0000000-0000-0000-0000-000000000001','Mismatch','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2026-11-16','2026-11-29','f0000000-0000-0000-0000-0000000000a5'),
  ('90000000-0000-0000-0000-0000000000b2','a0000000-0000-0000-0000-000000000001','W53-2025','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2025-12-22','2026-01-11',NULL),
  ('90000000-0000-0000-0000-0000000000b3','a0000000-0000-0000-0000-000000000001','W53-2026','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2026-12-21','2027-01-10',NULL);
DO $$
DECLARE n int; r text;
BEGIN
  -- JSON mal formado: 22023, no 22P02
  FOREACH r IN ARRAY ARRAY[
    '[{ORIG,"iso_year":2026,"iso_week":47,"samples":"abc"}]',
    '[{ORIG,"iso_year":2026,"iso_week":47,"samples":2.5}]',
    '[{"origin_city_id":"nope","destination_city_id":"c2000000-0000-0000-0000-000000000002","iso_year":2026,"iso_week":47,"samples":2}]',
    '[{ORIG,"iso_year":2026,"iso_week":47}]',
    '[{ORIG,"iso_year":2026,"iso_week":47,"samples":null}]',
    '[{ORIG,"iso_year":"x","iso_week":47,"samples":2}]',
    '["texto"]',
    '[5]'
  ] LOOP
    r := replace(r, 'ORIG', '"origin_city_id":"c1000000-0000-0000-0000-000000000001","destination_city_id":"c2000000-0000-0000-0000-000000000002"');
    PERFORM pg_temp.ok(pg_temp.sqlstate_of(format('SELECT public.cl_plan_set_quotas(%L, %L::jsonb)', '90000000-0000-0000-0000-0000000000a1', r)) = '22023',
      'JSON invalido da 22023: ' || r);
  END LOOP;
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000a1') = 1, 'JSON invalido no borra nada');

  -- duplicados
  PERFORM pg_temp.ok(pg_temp.msg_of($q$SELECT public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a1', '[
    {"origin_city_id":"c1000000-0000-0000-0000-000000000001","destination_city_id":"c2000000-0000-0000-0000-000000000002","iso_year":2026,"iso_week":48,"samples":1},
    {"origin_city_id":"c1000000-0000-0000-0000-000000000001","destination_city_id":"c2000000-0000-0000-0000-000000000002","iso_year":2026,"iso_week":48,"samples":2}]'::jsonb)$q$) LIKE '22023:CL_DUPLICATE_QUOTA%', 'duplicado: CL_DUPLICATE_QUOTA');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000a1') = 1, 'duplicado no borra nada');

  -- cuota no pending
  UPDATE public.cl_plan_quotas SET status = 'open' WHERE plan_id = '90000000-0000-0000-0000-0000000000a1';
  PERFORM pg_temp.ok(pg_temp.msg_of($q$SELECT public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a1', '[
    {"origin_city_id":"c1000000-0000-0000-0000-000000000001","destination_city_id":"c2000000-0000-0000-0000-000000000002","iso_year":2026,"iso_week":47,"samples":9}]'::jsonb)$q$) LIKE '22023:CL_QUOTA_LOCKED%', 'cuota no pending: CL_QUOTA_LOCKED');
  PERFORM pg_temp.ok((SELECT samples_planned FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000a1') = 5, 'bloqueada no cambia');
  UPDATE public.cl_plan_quotas SET status = 'pending' WHERE plan_id = '90000000-0000-0000-0000-0000000000a1';

  -- semanas ISO
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$SELECT public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000b2', '[
    {"origin_city_id":"c1000000-0000-0000-0000-000000000001","destination_city_id":"c2000000-0000-0000-0000-000000000002","iso_year":2025,"iso_week":53,"samples":1}]'::jsonb)$q$) = '22023', '2025-W53 no existe');
  n := public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000b3', '[
    {"origin_city_id":"c1000000-0000-0000-0000-000000000001","destination_city_id":"c2000000-0000-0000-0000-000000000002","iso_year":2026,"iso_week":53,"samples":1}]'::jsonb);
  PERFORM pg_temp.ok(n = 1 AND (SELECT period_start FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000b3') = DATE '2026-12-28', '2026-W53 empieza 2026-12-28');
  n := public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000b2', '[
    {"origin_city_id":"c1000000-0000-0000-0000-000000000001","destination_city_id":"c2000000-0000-0000-0000-000000000002","iso_year":2026,"iso_week":1,"samples":1}]'::jsonb);
  PERFORM pg_temp.ok((SELECT period_start FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000b2') = DATE '2025-12-29', '2026-W01 empieza 2025-12-29');

  -- feed de otro carrier
  PERFORM pg_temp.ok(pg_temp.msg_of($q$SELECT public.cl_plan_activate('90000000-0000-0000-0000-0000000000b1')$q$) LIKE '22023:CL_FEED_CARRIER_MISMATCH%', 'feed de otro carrier');
END $$;

-- 4. Puntos que faltan y activacion.
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_missing_points('90000000-0000-0000-0000-0000000000a1')) = 2, 'sin puntos: 2 filas');
  PERFORM pg_temp.ok(pg_temp.msg_of($q$SELECT public.cl_plan_activate('90000000-0000-0000-0000-0000000000a1')$q$) LIKE '22023:CL_MISSING_POINTS%', 'activar sin puntos lanza CL_MISSING_POINTS');
  PERFORM pg_temp.ok(pg_temp.msg_of($q$SELECT public.cl_plan_activate('90000000-0000-0000-0000-0000000000a3')$q$) LIKE '22023:CL_NO_FEED%', 'sin feed: CL_NO_FEED');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plans WHERE id = '90000000-0000-0000-0000-0000000000a1') = 'draft', 'sigue en draft');

  INSERT INTO public.readers (account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, e2e_role)
  VALUES ('a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','O1','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','NBO','origin');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_missing_points('90000000-0000-0000-0000-0000000000a1')) = 1, 'con origin en A: falta solo destino');
  PERFORM pg_temp.ok((SELECT missing FROM public.cl_plan_missing_points('90000000-0000-0000-0000-0000000000a1')) = 'destination', 'falta destination');
  INSERT INTO public.readers (account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, e2e_role, is_active)
  VALUES ('a0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-0000000000c2','D1','Exit','carrier_scan','ca000000-0000-0000-0000-000000000001','MBA','destination', false);
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_missing_points('90000000-0000-0000-0000-0000000000a1')) = 1, 'punto inactivo no cuenta');
  UPDATE public.readers SET is_active = true, e2e_role = 'origin' WHERE name = 'D1';
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_missing_points('90000000-0000-0000-0000-0000000000a1')) = 1, 'rol origin no cubre destination');
  UPDATE public.readers SET e2e_role = 'destination' WHERE name = 'D1';
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_missing_points('90000000-0000-0000-0000-0000000000a1')) = 0, 'con origin y destination: 0 filas');

  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_missing_standards('90000000-0000-0000-0000-0000000000a1')) = 1, 'falta un estandar');
  INSERT INTO public.delivery_standards (account_id, carrier_id, product_id, origin_city_id, destination_city_id, standard_time, success_percentage)
  VALUES ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',48,90);
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_missing_standards('90000000-0000-0000-0000-0000000000a1')) = 0, 'estandar presente: 0 filas');

  PERFORM public.cl_plan_activate('90000000-0000-0000-0000-0000000000a1');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plans WHERE id = '90000000-0000-0000-0000-0000000000a1') = 'active', 'plan activo');

  UPDATE public.cl_plans SET feed_id = 'f0000000-0000-0000-0000-0000000000a1' WHERE id = '90000000-0000-0000-0000-0000000000a3';
  PERFORM pg_temp.ok(pg_temp.msg_of($q$SELECT public.cl_plan_activate('90000000-0000-0000-0000-0000000000a3')$q$) LIKE '22023:CL_NO_QUOTAS%', 'sin cuotas: CL_NO_QUOTAS');
END $$;

-- 5. Como AM de A1 (authenticated, no superadmin): puede en su plan; no en el de A2.
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE n int;
BEGIN
  n := public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a3', $j$[
    {"origin_city_id":"c1000000-0000-0000-0000-000000000001","destination_city_id":"c2000000-0000-0000-0000-000000000002","iso_year":2026,"iso_week":48,"samples":4}]$j$::jsonb);
  PERFORM pg_temp.ok(n = 1, 'AM fija cuotas en su plan');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000a3') = 1, 'AM ve sus cuotas');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_missing_points('90000000-0000-0000-0000-0000000000a3')) = 0, 'AM lee puntos');
  PERFORM public.cl_plan_activate('90000000-0000-0000-0000-0000000000a3');
  PERFORM pg_temp.ok((SELECT status FROM public.cl_plans WHERE id = '90000000-0000-0000-0000-0000000000a3') = 'active', 'AM activa su plan');
  PERFORM pg_temp.ok(pg_temp.msg_of($q$SELECT public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a2', '[]'::jsonb)$q$)
                   = pg_temp.msg_of($q$SELECT public.cl_plan_set_quotas('90000000-0000-0000-0000-00000000dead', '[]'::jsonb)$q$), 'mismo mensaje ajeno/inexistente');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$SELECT public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a2', '[]'::jsonb)$q$) = '42501', 'AM no fija cuotas en A2');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$SELECT public.cl_plan_activate('90000000-0000-0000-0000-0000000000a2')$q$) = '42501', 'AM no activa en A2');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$SELECT * FROM public.cl_plan_missing_points('90000000-0000-0000-0000-0000000000a2')$q$) = '42501', 'AM no lee puntos de A2');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$SELECT * FROM public.cl_plan_missing_standards('90000000-0000-0000-0000-0000000000a2')$q$) = '42501', 'AM no lee estandares de A2');
END $$;
RESET ROLE;

-- 6. Usuario de A2 sobre un plan de A1: 42501. Usuario sin rol de A1: 42501.
SET ROLE authenticated;
SELECT pg_temp.as_user('92000000-0000-0000-0000-000000000092', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$SELECT public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a1', '[]'::jsonb)$q$) = '42501', 'usuario de A2 no fija cuotas en A1');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$SELECT public.cl_plan_activate('90000000-0000-0000-0000-0000000000a1')$q$) = '42501', 'usuario de A2 no activa en A1');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$SELECT * FROM public.cl_plan_missing_points('90000000-0000-0000-0000-0000000000a1')$q$) = '42501', 'usuario de A2 no lee puntos de A1');
END $$;
RESET ROLE;
SET ROLE authenticated;
SELECT pg_temp.as_user('91000000-0000-0000-0000-000000000091', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$SELECT public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a1', '[]'::jsonb)$q$) = '42501', 'sin rol no fija cuotas');
  PERFORM pg_temp.ok(pg_temp.sqlstate_of($q$SELECT * FROM public.cl_plan_missing_points('90000000-0000-0000-0000-0000000000a1')$q$) = '42501', 'sin rol no lee puntos');
END $$;
RESET ROLE;

-- 7. Superadmin: puede en cualquier cuenta.
SET ROLE authenticated;
SELECT pg_temp.as_user('97000000-0000-0000-0000-000000000097', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok(public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a2', '[]'::jsonb) = 0, 'superadmin fija cuotas en A2');
END $$;
RESET ROLE;

\echo cl_plan: OK
ROLLBACK;
