-- Carrier Link fase 2, tarea 1: cl_plan_set_quotas por conjuntos. Un plan de ~15.000 cuotas (30 ciudades -> 870 rutas
-- x 18 semanas) se guarda en < 2 s (el statement_timeout de authenticated es 8 s). Duplicados y semanas fuera del plan
-- siguen dando el mismo error, también en el lote grande, y un rechazo no borra nada.
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

INSERT INTO auth.users (id, email) VALUES ('93000000-0000-0000-0000-000000000093','am@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('93000000-0000-0000-0000-000000000093','am@t.l','AM','user','a0000000-0000-0000-0000-000000000001');
INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000093','account_manager');

-- 28 ciudades más en A1 (30 en total).
INSERT INTO public.cities (account_id, region_id, name, code)
SELECT 'a0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'S' || g, 'S' || g
  FROM generate_series(1, 28) g;

-- Plan de 18 semanas ISO: 2027-W01 (2027-01-04) .. 2027-W18 (2027-05-09).
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date) VALUES
  ('90000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','Big','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',20000,'2027-01-04','2027-05-09');

-- Todas las rutas entre ciudades distintas de A1, una cuota por semana.
CREATE TEMP TABLE big_quotas AS
SELECT jsonb_agg(jsonb_build_object('origin_city_id', o.id, 'destination_city_id', d.id,
                                    'iso_year', 2027, 'iso_week', w, 'samples', 1 + (w % 3))) AS j
  FROM public.cities o
  JOIN public.cities d ON d.account_id = o.account_id AND d.id <> o.id
 CROSS JOIN generate_series(1, 18) w
 WHERE o.account_id = 'a0000000-0000-0000-0000-000000000001';
GRANT SELECT ON big_quotas TO authenticated;

DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT jsonb_array_length(j) FROM big_quotas) = 15660, 'fixture: 870 rutas x 18 semanas = 15660 cuotas');
END $$;

-- 1. Guardado grande como AM (authenticated), con tiempo medido.
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE n int; t0 timestamptz; v_ms numeric;
BEGIN
  t0 := clock_timestamp();
  n := public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000c1', (SELECT j FROM big_quotas));
  v_ms := round(extract(epoch FROM clock_timestamp() - t0) * 1000);
  PERFORM set_config('t.first_ms', v_ms::text, true);
  PERFORM pg_temp.ok(n = 15660, 'devuelve 15660 (devuelve ' || n || ')');
  PERFORM pg_temp.ok(v_ms < 2000, '15660 cuotas en < 2 s (tardó ' || v_ms || ' ms)');
  -- Segundo guardado (reemplaza las pending): también < 2 s.
  t0 := clock_timestamp();
  n := public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000c1', (SELECT j FROM big_quotas));
  v_ms := round(extract(epoch FROM clock_timestamp() - t0) * 1000);
  PERFORM set_config('t.second_ms', v_ms::text, true);
  PERFORM pg_temp.ok(n = 15660, 'reemplazo devuelve 15660');
  PERFORM pg_temp.ok(v_ms < 2000, 'reemplazo de 15660 cuotas en < 2 s (tardó ' || v_ms || ' ms)');
END $$;
RESET ROLE;
SELECT 'cl_set_quotas_scale timing: first=' || current_setting('t.first_ms') || ' ms, replace=' || current_setting('t.second_ms') || ' ms' AS timing;

DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000c1') = 15660, '15660 filas guardadas');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000c1'
                       AND (period_start <> to_date('2027-' || lpad(iso_week::text, 2, '0'), 'IYYY-IW') OR period_end <> period_start + 6
                            OR samples_planned <> 1 + (iso_week % 3) OR account_id <> 'a0000000-0000-0000-0000-000000000001'
                            OR status <> 'pending')) = 0, 'periodos, muestras, cuenta y estado correctos');
  PERFORM pg_temp.ok((SELECT period_start FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000c1' AND iso_week = 1 LIMIT 1) = DATE '2027-01-04', 'W01 empieza 2027-01-04');
END $$;

-- 2. Lote grande con un duplicado o una semana fuera del plan: mismo error y no se borra nada.
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE v_dup jsonb; v_out jsonb; m text;
BEGIN
  v_dup := (SELECT j || jsonb_build_array(j->12345) FROM big_quotas);
  m := pg_temp.msg_of(format('SELECT public.cl_plan_set_quotas(%L, %L::jsonb)', '90000000-0000-0000-0000-0000000000c1', v_dup));
  PERFORM pg_temp.ok(m LIKE '22023:CL_DUPLICATE_QUOTA: route % -> % week 2027-W%appears twice', 'duplicado en lote grande: ' || coalesce(m, 'null'));

  v_out := (SELECT j || jsonb_build_array(jsonb_set(j->0, '{iso_week}', '19')) FROM big_quotas);
  m := pg_temp.msg_of(format('SELECT public.cl_plan_set_quotas(%L, %L::jsonb)', '90000000-0000-0000-0000-0000000000c1', v_out));
  PERFORM pg_temp.ok(m = '22023:Week 2027-W19 is outside the plan dates', 'semana fuera del plan: ' || coalesce(m, 'null'));

  -- Un duplicado con samples <= 0 no cuenta (se ignora como antes).
  v_dup := (SELECT j || jsonb_build_array(jsonb_set(j->12345, '{samples}', '0')) FROM big_quotas);
  PERFORM pg_temp.ok(public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000c1', v_dup) = 15660, 'duplicado con samples=0 se ignora');
END $$;
RESET ROLE;
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000c1') = 15660, 'los rechazos no borran nada');
END $$;

-- 3. Mensajes exactos de los rechazos (como postgres, plan pequeño de cl_plan_set_quotas).
DO $$
DECLARE m text;
  o text := 'c1000000-0000-0000-0000-000000000001'; d text := 'c2000000-0000-0000-0000-000000000002';
  p text := '90000000-0000-0000-0000-0000000000c1';
BEGIN
  m := pg_temp.msg_of(format('SELECT public.cl_plan_set_quotas(%L, %L::jsonb)', p,
         format('[{"origin_city_id":"%s","destination_city_id":"%s","iso_year":2027,"iso_week":2,"samples":1},'
                ' {"origin_city_id":"%s","destination_city_id":"%s","iso_year":2027,"iso_week":2,"samples":4}]', o, d, o, d)));
  PERFORM pg_temp.ok(m = format('22023:CL_DUPLICATE_QUOTA: route %s -> %s week 2027-W2 appears twice', o, d), 'mensaje duplicado exacto: ' || coalesce(m, 'null'));
  m := pg_temp.msg_of(format('SELECT public.cl_plan_set_quotas(%L, %L::jsonb)', p,
         format('[{"origin_city_id":"%s","destination_city_id":"c3000000-0000-0000-0000-00000000dead","iso_year":2027,"iso_week":2,"samples":1}]', o)));
  PERFORM pg_temp.ok(m = '22023:City does not belong to the plan account', 'ciudad ajena: ' || coalesce(m, 'null'));
  m := pg_temp.msg_of(format('SELECT public.cl_plan_set_quotas(%L, %L::jsonb)', p,
         format('[{"origin_city_id":"%s","destination_city_id":"%s","iso_year":2026,"iso_week":53,"samples":1}]', o, d)));
  PERFORM pg_temp.ok(m = '22023:Week 2026-W53 is outside the plan dates', 'semana existente fuera: ' || coalesce(m, 'null'));
  m := pg_temp.msg_of(format('SELECT public.cl_plan_set_quotas(%L, %L::jsonb)', p,
         format('[{"origin_city_id":"%s","destination_city_id":"%s","iso_year":2027,"iso_week":53,"samples":1}]', o, d)));
  PERFORM pg_temp.ok(m = '22023:Invalid ISO week 2027-W53', 'semana ISO inexistente: ' || coalesce(m, 'null'));
  m := pg_temp.msg_of(format('SELECT public.cl_plan_set_quotas(%L, %L::jsonb)', p,
         format('[{"origin_city_id":"%s","iso_year":2027,"iso_week":2,"samples":1}]', o)));
  PERFORM pg_temp.ok(m = '22023:Invalid quota: origin, destination, iso_year and iso_week are required', 'falta destino: ' || coalesce(m, 'null'));
  m := pg_temp.msg_of(format('SELECT public.cl_plan_set_quotas(%L, %L::jsonb)', p,
         format('[{"origin_city_id":"%s","destination_city_id":"nope","iso_year":2027,"iso_week":2,"samples":0}]', o)));
  PERFORM pg_temp.ok(m LIKE '22023:Invalid quota entry: %', 'uuid inválido aunque samples=0: ' || coalesce(m, 'null'));
  -- samples <= 0 no valida semana ni ciudad (como antes).
  PERFORM pg_temp.ok(public.cl_plan_set_quotas(p::uuid, format(
         '[{"origin_city_id":"%s","destination_city_id":"c3000000-0000-0000-0000-00000000dead","iso_year":2030,"iso_week":60,"samples":-1}]', o)::jsonb) = 0,
         'samples<=0: ni semana ni ciudad se validan');
  PERFORM pg_temp.ok(public.cl_plan_set_quotas(p::uuid, '[]'::jsonb) = 0, 'array vacío: 0');
END $$;

-- 4. Trigger cl_same_account de cl_plan_quotas (SQL estático): mismas comprobaciones y mensaje que el genérico.
INSERT INTO public.regions (id, account_id, name, code) VALUES
  ('e0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','Reg2','R2');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','CityB','CB');
DO $$
DECLARE m text;
  ins text := 'INSERT INTO public.cl_plan_quotas (account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end) '
              'VALUES (%L, %L, %L, %L, 2027, 2, ''2027-01-11'', ''2027-01-17'')';
  a1 text := 'a0000000-0000-0000-0000-000000000001'; a2 text := 'a0000000-0000-0000-0000-000000000002';
  p text := '90000000-0000-0000-0000-0000000000c1';
  c1 text := 'c1000000-0000-0000-0000-000000000001'; c2 text := 'c2000000-0000-0000-0000-000000000002'; cb text := 'c3000000-0000-0000-0000-000000000003';
BEGIN
  PERFORM pg_temp.ok((SELECT tgfoid = 'public.cl_plan_quotas_check_same_account()'::regprocedure FROM pg_trigger
                       WHERE tgrelid = 'public.cl_plan_quotas'::regclass AND tgname = 'cl_same_account'), 'trigger con la función propia');
  m := pg_temp.msg_of(format(ins, a2, p, cb, cb));
  PERFORM pg_temp.ok(m = '23514:cl_plan_quotas plan_id debe pertenecer a la misma cuenta (cl_plans)', 'plan de otra cuenta: ' || coalesce(m, 'null'));
  m := pg_temp.msg_of(format(ins, a1, p, cb, c2));
  PERFORM pg_temp.ok(m = '23514:cl_plan_quotas origin_city_id debe pertenecer a la misma cuenta (cities)', 'origen de otra cuenta: ' || coalesce(m, 'null'));
  m := pg_temp.msg_of(format(ins, a1, p, c1, cb));
  PERFORM pg_temp.ok(m = '23514:cl_plan_quotas destination_city_id debe pertenecer a la misma cuenta (cities)', 'destino de otra cuenta: ' || coalesce(m, 'null'));
  PERFORM pg_temp.ok(public.cl_plan_set_quotas(p::uuid, format(
         '[{"origin_city_id":"%s","destination_city_id":"%s","iso_year":2027,"iso_week":1,"samples":1}]', c1, c2)::jsonb) = 1, 'cuota válida pasa el trigger');
  m := pg_temp.msg_of(format('UPDATE public.cl_plan_quotas SET destination_city_id = %L WHERE plan_id = %L AND iso_week = 1 AND origin_city_id = %L AND destination_city_id = %L', cb, p, c1, c2));
  PERFORM pg_temp.ok(m = '23514:cl_plan_quotas destination_city_id debe pertenecer a la misma cuenta (cities)', 'UPDATE también comprobado: ' || coalesce(m, 'null'));
  PERFORM pg_temp.ok((SELECT count(*) FROM pg_indexes WHERE schemaname = 'public' AND indexname IN ('cl_samples_quota_idx','cl_alerts_quota_idx')) = 2, 'índices de quota_id');
END $$;

\echo cl_set_quotas_scale: OK
ROLLBACK;
