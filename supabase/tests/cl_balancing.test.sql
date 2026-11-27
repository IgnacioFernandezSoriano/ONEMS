-- Carrier Link fase 2, tarea 5: cl_plan_rebalance_quotas (balanceo de cuotas, espejo del Load Balancing E2E sin maximo
-- por panelista) y cl_plan_quota_totals. Autorizacion/aislamiento, total conservado, fence y cuotas bloqueadas en plan
-- activo, borrador sin fence, creacion de filas nuevas, ceros, idempotencia, escala (15.660 cuotas) y totales con
-- cada filtro. El lint de pg-safeupdate de las funciones cl_* lo cubre cl_safeupdate_lint.test.sql.
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

-- Cambio JSON de una entrada.
CREATE OR REPLACE FUNCTION pg_temp.ch(o text, d text, y int, w int, s int) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('origin_city_id', o, 'destination_city_id', d, 'iso_year', y, 'iso_week', w, 'samples', s)
$$;

-- samples_planned de una cuota (NULL si no existe).
CREATE OR REPLACE FUNCTION pg_temp.sp(p uuid, o uuid, d uuid, y int, w int) RETURNS int LANGUAGE sql AS $$
  SELECT samples_planned FROM public.cl_plan_quotas
   WHERE plan_id = p AND origin_city_id = o AND destination_city_id = d AND iso_year = y AND iso_week = w
$$;

CREATE OR REPLACE FUNCTION pg_temp.total(p uuid) RETURNS bigint LANGUAGE sql AS $$
  SELECT COALESCE(sum(samples_planned), 0) FROM public.cl_plan_quotas WHERE plan_id = p
$$;

BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION pg_temp.ch(text, text, int, int, int) TO authenticated;

-- 93 AM de A1 (Edit), 94 do_coordinator de A1 (View en cl_plans), 92 UPU AM de A2, 91 sin rol (A1), 97 superadmin.
INSERT INTO auth.users (id, email) VALUES
  ('93000000-0000-0000-0000-000000000093','am@t.l'),
  ('94000000-0000-0000-0000-000000000094','do@t.l'),
  ('92000000-0000-0000-0000-000000000092','upu2@t.l'),
  ('91000000-0000-0000-0000-000000000091','x@t.l'),
  ('97000000-0000-0000-0000-000000000097','super@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('93000000-0000-0000-0000-000000000093','am@t.l','AM','user','a0000000-0000-0000-0000-000000000001'),
  ('94000000-0000-0000-0000-000000000094','do@t.l','DO','user','a0000000-0000-0000-0000-000000000001'),
  ('92000000-0000-0000-0000-000000000092','upu2@t.l','UPU2','user','a0000000-0000-0000-0000-000000000002'),
  ('91000000-0000-0000-0000-000000000091','x@t.l','X','user','a0000000-0000-0000-0000-000000000001'),
  ('97000000-0000-0000-0000-000000000097','super@t.l','Super','superadmin',NULL);
INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000093','account_manager'),
  ('a0000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000094','do_coordinator'),
  ('a0000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000092','upu_account_manager');

-- A2: ciudad, carrier y producto propios. A1: tercera ciudad C5.
INSERT INTO public.regions (id, account_id, name, code) VALUES
  ('e0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','Reg2','R2');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','CityB','CB'),
  ('c4000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','CityB2','CB2'),
  ('c5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City5','C5');
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','CB','Carrier2');
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','PB','Prod2',48);

-- Planes:
--  d1 borrador de A1 en el PASADO (2026-W02..W09): en borrador no hay fence, cualquier semana vale.
--  a1 activo de A1: desde el lunes de hace 2 semanas hasta 8 semanas despues del lunes actual.
--  x1 cerrado de A1. f2 borrador de A2.
CREATE TEMP TABLE t_dates AS
SELECT d.today,
       (d.today - (extract(isodow FROM d.today)::int - 1))::date AS mon,               -- lunes de esta semana
       (d.today + (7 - extract(isodow FROM d.today)::int))::date AS sun                -- domingo de esta semana
  FROM (SELECT (now() AT TIME ZONE a.timezone)::date AS today FROM public.accounts a
         WHERE a.id = 'a0000000-0000-0000-0000-000000000001') d;   -- zona de la cuenta (como E2E)
GRANT SELECT ON t_dates TO authenticated;

INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status)
SELECT v.id::uuid, v.acc::uuid, v.n, v.ca::uuid, v.pr::uuid, 100, v.s, v.e, v.st
  FROM t_dates t,
       LATERAL (VALUES
         ('90000000-0000-0000-0000-0000000000d1','a0000000-0000-0000-0000-000000000001','D1','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001', DATE '2026-01-05', DATE '2026-03-01', 'draft'),
         ('90000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','A1','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001', t.mon - 14, t.mon + 62, 'draft'),
         ('90000000-0000-0000-0000-0000000000e1','a0000000-0000-0000-0000-000000000001','X1','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001', DATE '2026-01-05', DATE '2026-03-01', 'draft'),
         ('90000000-0000-0000-0000-0000000000f2','a0000000-0000-0000-0000-000000000002','F2','ca000000-0000-0000-0000-000000000002','cb000000-0000-0000-0000-000000000002', DATE '2026-01-05', DATE '2026-03-01', 'draft')
       ) v(id, acc, n, ca, pr, s, e, st);

-- Cuotas iniciales (como postgres, con cl_plan_set_quotas mientras son borrador).
SELECT public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000d1', jsonb_build_array(
  pg_temp.ch('c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,2,5),
  pg_temp.ch('c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,3,5),
  pg_temp.ch('c2000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000001',2026,2,4),
  pg_temp.ch('c2000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000001',2026,4,2)));
-- a1: semanas pasada (-1), actual (0), siguiente (+1) y +2, ruta C1->C2.
SELECT public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000a1', (
  SELECT jsonb_agg(pg_temp.ch('c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',
                              extract(isoyear FROM t.mon + 7 * k)::int, extract(week FROM t.mon + 7 * k)::int, 10))
    FROM t_dates t, generate_series(-1, 2) k));
SELECT public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000e1', jsonb_build_array(
  pg_temp.ch('c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,2,5)));
SELECT public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000f2', jsonb_build_array(
  pg_temp.ch('c3000000-0000-0000-0000-000000000003','c4000000-0000-0000-0000-000000000004',2026,2,5),
  pg_temp.ch('c3000000-0000-0000-0000-000000000003','c4000000-0000-0000-0000-000000000004',2026,3,5)));
UPDATE public.cl_plans SET status = 'active' WHERE id = '90000000-0000-0000-0000-0000000000a1';
UPDATE public.cl_plans SET status = 'closed' WHERE id = '90000000-0000-0000-0000-0000000000e1';

-- ===================================================================== 0. permisos e indice
DO $$
BEGIN
  PERFORM pg_temp.ok(NOT has_function_privilege('anon', 'public.cl_plan_rebalance_quotas(uuid,jsonb,date)', 'EXECUTE'), 'anon sin EXECUTE (rebalance)');
  PERFORM pg_temp.ok(NOT has_function_privilege('anon', 'public.cl_plan_quota_totals(uuid,uuid,uuid,integer,integer,text)', 'EXECUTE'), 'anon sin EXECUTE (totals)');
  PERFORM pg_temp.ok(has_function_privilege('authenticated', 'public.cl_plan_rebalance_quotas(uuid,jsonb,date)', 'EXECUTE'), 'authenticated con EXECUTE (rebalance)');
  PERFORM pg_temp.ok(has_function_privilege('authenticated', 'public.cl_plan_quota_totals(uuid,uuid,uuid,integer,integer,text)', 'EXECUTE'), 'authenticated con EXECUTE (totals)');
  PERFORM pg_temp.ok((SELECT prosecdef FROM pg_proc WHERE oid = 'public.cl_plan_rebalance_quotas(uuid,jsonb,date)'::regprocedure), 'rebalance SECURITY DEFINER');
  PERFORM pg_temp.ok((SELECT provolatile = 's' AND prosecdef FROM pg_proc WHERE oid = 'public.cl_plan_quota_totals(uuid,uuid,uuid,integer,integer,text)'::regprocedure), 'totals STABLE SECURITY DEFINER');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'cl_plan_quotas'
                              AND indexdef LIKE '%(plan_id, iso_year, iso_week, origin_city_id, destination_city_id, id)%'), 'indice de orden');
END $$;

-- ===================================================================== 1. autorizacion y aislamiento
-- Usuario de A2 sobre A1, plan inexistente: el mismo 42501 CL_FORBIDDEN (rebalance y totales).
SET ROLE authenticated;
SELECT pg_temp.as_user('92000000-0000-0000-0000-000000000092', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.msg_of($q$SELECT public.cl_plan_rebalance_quotas('90000000-0000-0000-0000-0000000000d1', '[]'::jsonb)$q$) = '42501:CL_FORBIDDEN', 'A2 no balancea A1');
  PERFORM pg_temp.ok(pg_temp.msg_of($q$SELECT public.cl_plan_rebalance_quotas('90000000-0000-0000-0000-00000000dead', '[]'::jsonb)$q$) = '42501:CL_FORBIDDEN', 'inexistente: mismo 42501');
  PERFORM pg_temp.ok(pg_temp.msg_of($q$SELECT * FROM public.cl_plan_quota_totals('90000000-0000-0000-0000-0000000000d1')$q$) = '42501:CL_FORBIDDEN', 'A2 no lee totales de A1');
  PERFORM pg_temp.ok(pg_temp.msg_of($q$SELECT * FROM public.cl_plan_quota_totals('90000000-0000-0000-0000-00000000dead')$q$) = '42501:CL_FORBIDDEN', 'totales inexistente: mismo 42501');
  -- Su propio plan si.
  PERFORM pg_temp.ok((SELECT quotas FROM public.cl_plan_quota_totals('90000000-0000-0000-0000-0000000000f2')) = 2, 'A2 lee sus totales');
  PERFORM pg_temp.ok(public.cl_plan_rebalance_quotas('90000000-0000-0000-0000-0000000000f2', jsonb_build_array(
      pg_temp.ch('c3000000-0000-0000-0000-000000000003','c4000000-0000-0000-0000-000000000004',2026,2,6),
      pg_temp.ch('c3000000-0000-0000-0000-000000000003','c4000000-0000-0000-0000-000000000004',2026,3,4))) ->> 'changed' = '2', 'A2 balancea su plan');
  -- Ciudad de otra cuenta en los cambios: rechazo.
  PERFORM pg_temp.ok(pg_temp.msg_of(format('SELECT public.cl_plan_rebalance_quotas(%L, %L::jsonb)', '90000000-0000-0000-0000-0000000000f2', jsonb_build_array(
      pg_temp.ch('c3000000-0000-0000-0000-000000000003','c1000000-0000-0000-0000-000000000001',2026,2,1),
      pg_temp.ch('c3000000-0000-0000-0000-000000000003','c4000000-0000-0000-0000-000000000004',2026,2,5))))
    = '22023:City does not belong to the plan account', 'ciudad ajena rechazada');
END $$;
RESET ROLE;

-- Solo View (do_coordinator): lee totales, no balancea. Sin rol: nada.
SET ROLE authenticated;
SELECT pg_temp.as_user('94000000-0000-0000-0000-000000000094', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.msg_of($q$SELECT public.cl_plan_rebalance_quotas('90000000-0000-0000-0000-0000000000d1', '[]'::jsonb)$q$) = '42501:CL_FORBIDDEN', 'view no balancea');
  PERFORM pg_temp.ok((SELECT planned FROM public.cl_plan_quota_totals('90000000-0000-0000-0000-0000000000d1')) = 16, 'view lee totales');
END $$;
RESET ROLE;
SET ROLE authenticated;
SELECT pg_temp.as_user('91000000-0000-0000-0000-000000000091', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.msg_of($q$SELECT public.cl_plan_rebalance_quotas('90000000-0000-0000-0000-0000000000d1', '[]'::jsonb)$q$) = '42501:CL_FORBIDDEN', 'sin rol no balancea');
  PERFORM pg_temp.ok(pg_temp.msg_of($q$SELECT * FROM public.cl_plan_quota_totals('90000000-0000-0000-0000-0000000000d1')$q$) = '42501:CL_FORBIDDEN', 'sin rol no lee totales');
END $$;
RESET ROLE;
-- Superadmin: cualquier cuenta.
SET ROLE authenticated;
SELECT pg_temp.as_user('97000000-0000-0000-0000-000000000097', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT quotas FROM public.cl_plan_quota_totals('90000000-0000-0000-0000-0000000000f2')) = 2, 'superadmin lee totales de A2');
  PERFORM pg_temp.ok(public.cl_plan_rebalance_quotas('90000000-0000-0000-0000-0000000000f2', '[]'::jsonb) = '{"changed":0,"created":0,"deleted":0,"fence":null}'::jsonb, 'superadmin balancea A2 (vacio)');
END $$;
RESET ROLE;

-- ===================================================================== 2. borrador: mover, crear, ceros, total, idempotencia
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE r jsonb; m text;
  p text := '90000000-0000-0000-0000-0000000000d1';
  c1 text := 'c1000000-0000-0000-0000-000000000001'; c2 text := 'c2000000-0000-0000-0000-000000000002';
  c5 text := 'c5000000-0000-0000-0000-000000000005';
  v_changes jsonb;
BEGIN
  -- Total cambiado: rechazo y nada escrito.
  m := pg_temp.msg_of(format('SELECT public.cl_plan_rebalance_quotas(%L, %L::jsonb)', p,
         jsonb_build_array(pg_temp.ch(c1, c2, 2026, 2, 7))));
  PERFORM pg_temp.ok(m = '22023:CL_REBALANCE_TOTAL_CHANGED: the changes alter the plan total by 2', 'total cambiado: ' || coalesce(m, 'null'));

  -- Semanas pasadas (plan en borrador: sin fence). C1->C2 W2 5->2, W3 5->8, nueva C1->C5 W9 = 2,
  -- C2->C1 W4 2->0 (se borra), C2->C1 W2 4 (sin cambio, se ignora), C5->C1 W5 0 sin fila (se ignora).
  v_changes := jsonb_build_array(pg_temp.ch(c1, c2, 2026, 2, 2), pg_temp.ch(c1, c2, 2026, 3, 8),
                                 pg_temp.ch(c1, c5, 2026, 9, 2), pg_temp.ch(c2, c1, 2026, 4, 0),
                                 pg_temp.ch(c2, c1, 2026, 2, 4), pg_temp.ch(c5, c1, 2026, 5, 0));
  r := public.cl_plan_rebalance_quotas(p::uuid, v_changes);
  PERFORM pg_temp.ok(r = '{"changed":2,"created":1,"deleted":1,"fence":null}'::jsonb, 'resultado borrador: ' || r::text);
  -- Idempotencia: la misma propuesta otra vez no hace nada.
  r := public.cl_plan_rebalance_quotas(p::uuid, v_changes);
  PERFORM pg_temp.ok(r = '{"changed":0,"created":0,"deleted":0,"fence":null}'::jsonb, 'idempotente: ' || r::text);
  -- p_fence no aplica en borrador.
  r := public.cl_plan_rebalance_quotas(p::uuid, jsonb_build_array(pg_temp.ch(c1, c2, 2026, 2, 3), pg_temp.ch(c1, c2, 2026, 3, 7)), DATE '2026-12-31');
  PERFORM pg_temp.ok(r ->> 'changed' = '2', 'borrador ignora el fence: ' || r::text);

  -- Validaciones.
  m := pg_temp.msg_of(format('SELECT public.cl_plan_rebalance_quotas(%L, %L::jsonb)', p,
         jsonb_build_array(pg_temp.ch(c1, c2, 2026, 2, 1), pg_temp.ch(c1, c2, 2026, 2, 3))));
  PERFORM pg_temp.ok(m LIKE '22023:CL_DUPLICATE_QUOTA: %', 'duplicado: ' || coalesce(m, 'null'));
  m := pg_temp.msg_of(format('SELECT public.cl_plan_rebalance_quotas(%L, %L::jsonb)', p,
         jsonb_build_array(pg_temp.ch(c1, c2, 2026, 2, -1), pg_temp.ch(c1, c2, 2026, 3, 9))));
  PERFORM pg_temp.ok(m = '22023:Invalid change: samples must be 0 or more', 'negativo: ' || coalesce(m, 'null'));
  m := pg_temp.msg_of(format('SELECT public.cl_plan_rebalance_quotas(%L, %L::jsonb)', p,
         jsonb_build_array(pg_temp.ch(c1, c2, 2026, 20, 1), pg_temp.ch(c1, c2, 2026, 2, 2))));
  PERFORM pg_temp.ok(m = '22023:Week 2026-W20 is outside the plan dates', 'fuera del plan: ' || coalesce(m, 'null'));
  m := pg_temp.msg_of(format('SELECT public.cl_plan_rebalance_quotas(%L, %L::jsonb)', p,
         jsonb_build_array(pg_temp.ch(c1, c2, 2026, 54, 1))));
  PERFORM pg_temp.ok(m LIKE '22023:Invalid %', 'semana ISO inexistente: ' || coalesce(m, 'null'));
  m := pg_temp.msg_of(format('SELECT public.cl_plan_rebalance_quotas(%L, %L::jsonb)', p,
         '[{"origin_city_id":"c1000000-0000-0000-0000-000000000001","destination_city_id":"c2000000-0000-0000-0000-000000000002","iso_year":2026,"iso_week":2,"samples":1.5}]'));
  PERFORM pg_temp.ok(m LIKE '22023:Invalid change entry: %', 'samples no entero: ' || coalesce(m, 'null'));
  m := pg_temp.msg_of(format('SELECT public.cl_plan_rebalance_quotas(%L, %L::jsonb)', p, '{"a":1}'));
  PERFORM pg_temp.ok(m = '22023:p_changes must be a JSON array', 'no array: ' || coalesce(m, 'null'));
END $$;
RESET ROLE;
DO $$
DECLARE p uuid := '90000000-0000-0000-0000-0000000000d1';
  c1 uuid := 'c1000000-0000-0000-0000-000000000001'; c2 uuid := 'c2000000-0000-0000-0000-000000000002';
  c5 uuid := 'c5000000-0000-0000-0000-000000000005';
BEGIN
  PERFORM pg_temp.ok(pg_temp.total(p) = 16, 'total del borrador conservado (16)');
  PERFORM pg_temp.ok(pg_temp.sp(p, c1, c2, 2026, 2) = 3 AND pg_temp.sp(p, c1, c2, 2026, 3) = 7, 'C1->C2 W2=3, W3=7');
  PERFORM pg_temp.ok(pg_temp.sp(p, c1, c5, 2026, 9) = 2, 'ruta-semana nueva creada');
  PERFORM pg_temp.ok((SELECT period_start = DATE '2026-02-23' AND period_end = DATE '2026-03-01' AND status = 'pending'
                             AND account_id = 'a0000000-0000-0000-0000-000000000001'
                        FROM public.cl_plan_quotas WHERE plan_id = p AND origin_city_id = c1 AND destination_city_id = c5), 'periodo de la nueva como cl_plan_set_quotas');
  PERFORM pg_temp.ok(pg_temp.sp(p, c2, c1, 2026, 4) IS NULL, 'cuota a 0 pendiente y libre: borrada');
  PERFORM pg_temp.ok(pg_temp.sp(p, c5, c1, 2026, 5) IS NULL, '0 sin fila: no se crea');
END $$;

-- Cuota pendiente con arrastre: a 0 se queda (no se borra). Cuota no pendiente en borrador: bloqueada.
UPDATE public.cl_plan_quotas SET samples_carried_in = 3
 WHERE plan_id = '90000000-0000-0000-0000-0000000000d1' AND origin_city_id = 'c2000000-0000-0000-0000-000000000002' AND iso_week = 2;
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE r jsonb;
BEGIN
  r := public.cl_plan_rebalance_quotas('90000000-0000-0000-0000-0000000000d1', jsonb_build_array(
         pg_temp.ch('c2000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000001',2026,2,0),
         pg_temp.ch('c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,3,11)));
  PERFORM pg_temp.ok(r = '{"changed":2,"created":0,"deleted":0,"fence":null}'::jsonb, 'cuota con arrastre a 0: se actualiza, no se borra: ' || r::text);
END $$;
RESET ROLE;
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.sp('90000000-0000-0000-0000-0000000000d1', 'c2000000-0000-0000-0000-000000000002', 'c1000000-0000-0000-0000-000000000001', 2026, 2) = 0, 'queda a 0 con su arrastre');
END $$;
UPDATE public.cl_plan_quotas SET status = 'open'
 WHERE plan_id = '90000000-0000-0000-0000-0000000000d1' AND origin_city_id = 'c1000000-0000-0000-0000-000000000001'
   AND destination_city_id = 'c2000000-0000-0000-0000-000000000002' AND iso_week = 3;
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE m text;
BEGIN
  m := pg_temp.msg_of(format('SELECT public.cl_plan_rebalance_quotas(%L, %L::jsonb)', '90000000-0000-0000-0000-0000000000d1', jsonb_build_array(
         pg_temp.ch('c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,3,8),
         pg_temp.ch('c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,2,4))));
  PERFORM pg_temp.ok(m LIKE '22023:CL_QUOTA_LOCKED: route % week 2026-W3 is not pending or is inside the fence (none)', 'no pendiente en borrador: ' || coalesce(m, 'null'));
  -- Reenviar su valor actual no la toca: no bloquea.
  PERFORM pg_temp.ok(public.cl_plan_rebalance_quotas('90000000-0000-0000-0000-0000000000d1', jsonb_build_array(
         pg_temp.ch('c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,3,11))) ->> 'changed' = '0', 'valor igual en cuota no pendiente: sin error');
END $$;
RESET ROLE;

-- ===================================================================== 3. plan activo: fence y cuotas bloqueadas
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE r jsonb; m text; t record;
  p text := '90000000-0000-0000-0000-0000000000a1';
  c1 text := 'c1000000-0000-0000-0000-000000000001'; c2 text := 'c2000000-0000-0000-0000-000000000002';
  c5 text := 'c5000000-0000-0000-0000-000000000005';
  y0 int; w0 int; y1 int; w1 int; y2 int; w2 int; ym int; wm int;
BEGIN
  SELECT * INTO t FROM t_dates;
  ym := extract(isoyear FROM t.mon - 7); wm := extract(week FROM t.mon - 7);
  y0 := extract(isoyear FROM t.mon);     w0 := extract(week FROM t.mon);
  y1 := extract(isoyear FROM t.mon + 7); w1 := extract(week FROM t.mon + 7);
  y2 := extract(isoyear FROM t.mon + 14); w2 := extract(week FROM t.mon + 14);

  -- Fence por defecto = domingo de esta semana: la semana actual esta dentro del fence.
  m := pg_temp.msg_of(format('SELECT public.cl_plan_rebalance_quotas(%L, %L::jsonb)', p,
         jsonb_build_array(pg_temp.ch(c1, c2, y0, w0, 9), pg_temp.ch(c1, c2, y1, w1, 11))));
  PERFORM pg_temp.ok(m = format('22023:CL_QUOTA_LOCKED: route %s -> %s week %s-W%s is not pending or is inside the fence (%s)', c1, c2, y0, w0, t.sun),
                     'semana actual bloqueada por el fence por defecto: ' || coalesce(m, 'null'));
  -- Semana pasada: bloqueada.
  m := pg_temp.msg_of(format('SELECT public.cl_plan_rebalance_quotas(%L, %L::jsonb)', p,
         jsonb_build_array(pg_temp.ch(c1, c2, ym, wm, 9), pg_temp.ch(c1, c2, y1, w1, 11))));
  PERFORM pg_temp.ok(m LIKE '22023:CL_QUOTA_LOCKED: %', 'semana pasada bloqueada: ' || coalesce(m, 'null'));
  -- Fence en el pasado = sin fence (desde hoy): la semana pasada sigue bloqueada (nunca el pasado).
  m := pg_temp.msg_of(format('SELECT public.cl_plan_rebalance_quotas(%L, %L::jsonb, %L::date)', p,
         jsonb_build_array(pg_temp.ch(c1, c2, ym, wm, 9), pg_temp.ch(c1, c2, y1, w1, 11)), t.today - 30));
  PERFORM pg_temp.ok(m = format('22023:CL_QUOTA_LOCKED: route %s -> %s week %s-W%s is not pending or is inside the fence (%s)', c1, c2, ym, wm, t.today - 1),
                     'fence pasado: nunca el pasado: ' || coalesce(m, 'null'));
  -- Fence explicito = domingo de la semana siguiente: la siguiente queda bloqueada.
  m := pg_temp.msg_of(format('SELECT public.cl_plan_rebalance_quotas(%L, %L::jsonb, %L::date)', p,
         jsonb_build_array(pg_temp.ch(c1, c2, y1, w1, 9), pg_temp.ch(c1, c2, y2, w2, 11)), t.sun + 7));
  PERFORM pg_temp.ok(m LIKE '22023:CL_QUOTA_LOCKED: % week ' || y1 || '-W' || w1 || ' %', 'fence explicito bloquea la siguiente: ' || coalesce(m, 'null'));
  -- Crear una fila nueva dentro del fence: bloqueada.
  m := pg_temp.msg_of(format('SELECT public.cl_plan_rebalance_quotas(%L, %L::jsonb)', p,
         jsonb_build_array(pg_temp.ch(c1, c5, y0, w0, 1), pg_temp.ch(c1, c2, y1, w1, 9))));
  PERFORM pg_temp.ok(m LIKE '22023:CL_QUOTA_LOCKED: route % -> c5% week ' || y0 || '-W' || w0 || ' %', 'nueva dentro del fence bloqueada: ' || coalesce(m, 'null'));

  -- Tras el fence: mover entre la siguiente y +2, y crear una ruta nueva en +2.
  r := public.cl_plan_rebalance_quotas(p::uuid, jsonb_build_array(
         pg_temp.ch(c1, c2, y1, w1, 6), pg_temp.ch(c1, c2, y2, w2, 11), pg_temp.ch(c1, c5, y2, w2, 3),
         -- valores iguales dentro del fence: se ignoran (no bloquean)
         pg_temp.ch(c1, c2, y0, w0, 10), pg_temp.ch(c1, c2, ym, wm, 10)));
  PERFORM pg_temp.ok(r = jsonb_build_object('changed', 2, 'created', 1, 'deleted', 0, 'fence', t.sun), 'activo tras el fence: ' || r::text);
END $$;
RESET ROLE;

-- Cuota futura no pendiente en plan activo: bloqueada. Plan cerrado: CL_PLAN_CLOSED.
UPDATE public.cl_plan_quotas q SET status = 'open'
  FROM t_dates t
 WHERE q.plan_id = '90000000-0000-0000-0000-0000000000a1' AND q.destination_city_id = 'c2000000-0000-0000-0000-000000000002'
   AND q.period_start = t.mon + 14;
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE m text; t record;
  c1 text := 'c1000000-0000-0000-0000-000000000001'; c2 text := 'c2000000-0000-0000-0000-000000000002';
BEGIN
  SELECT * INTO t FROM t_dates;
  m := pg_temp.msg_of(format('SELECT public.cl_plan_rebalance_quotas(%L, %L::jsonb)', '90000000-0000-0000-0000-0000000000a1', jsonb_build_array(
         pg_temp.ch(c1, c2, extract(isoyear FROM t.mon + 7)::int, extract(week FROM t.mon + 7)::int, 7),
         pg_temp.ch(c1, c2, extract(isoyear FROM t.mon + 14)::int, extract(week FROM t.mon + 14)::int, 10))));
  PERFORM pg_temp.ok(m LIKE '22023:CL_QUOTA_LOCKED: % week ' || extract(isoyear FROM t.mon + 14) || '-W' || extract(week FROM t.mon + 14) || ' %', 'futura no pendiente bloqueada: ' || coalesce(m, 'null'));
  m := pg_temp.msg_of(format('SELECT public.cl_plan_rebalance_quotas(%L, %L::jsonb)', '90000000-0000-0000-0000-0000000000e1', '[]'));
  PERFORM pg_temp.ok(m = '22023:CL_PLAN_CLOSED: plan is closed', 'plan cerrado: ' || coalesce(m, 'null'));
END $$;
RESET ROLE;
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.total('90000000-0000-0000-0000-0000000000a1') = 40, 'total del activo conservado (40)');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000a1') = 5, 'activo: 4 + 1 nueva');
END $$;

-- ===================================================================== 4. totales con cada filtro (como View)
UPDATE public.cl_plan_quotas SET samples_obtained = 2, demands_count = 1
 WHERE plan_id = '90000000-0000-0000-0000-0000000000d1' AND destination_city_id = 'c5000000-0000-0000-0000-000000000005';
SET ROLE authenticated;
SELECT pg_temp.as_user('94000000-0000-0000-0000-000000000094', 'authenticated');
DO $$
DECLARE r record; p uuid := '90000000-0000-0000-0000-0000000000d1';
BEGIN
  -- d1: C1->C2 W2=3 (pending), W3=11 (open); C2->C1 W2=0 (carried 3); C1->C5 W9=2 (obtained 2, demands 1).
  SELECT * INTO r FROM public.cl_plan_quota_totals(p);
  PERFORM pg_temp.ok((r.quotas, r.planned, r.carried, r.obtained, r.demands) = (4::bigint, 16::bigint, 3::bigint, 2::bigint, 1::bigint), 'sin filtro: ' || r::text);
  SELECT * INTO r FROM public.cl_plan_quota_totals(p, p_origin => 'c1000000-0000-0000-0000-000000000001');
  PERFORM pg_temp.ok((r.quotas, r.planned) = (3::bigint, 16::bigint), 'origen: ' || r::text);
  SELECT * INTO r FROM public.cl_plan_quota_totals(p, p_destination => 'c1000000-0000-0000-0000-000000000001');
  PERFORM pg_temp.ok((r.quotas, r.planned, r.carried) = (1::bigint, 0::bigint, 3::bigint), 'destino: ' || r::text);
  SELECT * INTO r FROM public.cl_plan_quota_totals(p, p_iso_year => 2026);
  PERFORM pg_temp.ok(r.quotas = 4, 'año: ' || r::text);
  SELECT * INTO r FROM public.cl_plan_quota_totals(p, p_iso_year => 2025);
  PERFORM pg_temp.ok((r.quotas, r.planned, r.carried, r.obtained, r.demands) = (0::bigint, 0::bigint, 0::bigint, 0::bigint, 0::bigint), 'año sin cuotas: ceros: ' || r::text);
  SELECT * INTO r FROM public.cl_plan_quota_totals(p, p_iso_week => 2);
  PERFORM pg_temp.ok((r.quotas, r.planned) = (2::bigint, 3::bigint), 'semana: ' || r::text);
  SELECT * INTO r FROM public.cl_plan_quota_totals(p, p_status => 'open');
  PERFORM pg_temp.ok((r.quotas, r.planned) = (1::bigint, 11::bigint), 'estado: ' || r::text);
  SELECT * INTO r FROM public.cl_plan_quota_totals(p, 'c1000000-0000-0000-0000-000000000001', 'c5000000-0000-0000-0000-000000000005', 2026, 9, 'pending');
  PERFORM pg_temp.ok((r.quotas, r.planned, r.obtained, r.demands) = (1::bigint, 2::bigint, 2::bigint, 1::bigint), 'todos los filtros: ' || r::text);
END $$;
RESET ROLE;

-- ===================================================================== 4b. "hoy" en la zona de la CUENTA (como E2E), no la del conector
-- A2: cuenta en Australia/Sydney (UTC+10/+11), conector en Etc/GMT+12 (UTC-12): sus fechas difieren 23 de cada 24 horas.
-- Con un fence en el pasado, el fence efectivo es hoy-1, asi que el resultado revela que "hoy" se uso.
SELECT pg_temp.as_user(NULL, NULL);
UPDATE public.accounts SET timezone = 'Australia/Sydney' WHERE id = 'a0000000-0000-0000-0000-000000000002';
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status, emit_timezone) VALUES
  ('f0000000-0000-0000-0000-0000000000f2','a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','Feed A2','active','Etc/GMT+12');
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id)
SELECT '90000000-0000-0000-0000-0000000000f3', 'a0000000-0000-0000-0000-000000000002', 'G2', 'ca000000-0000-0000-0000-000000000002',
       'cb000000-0000-0000-0000-000000000002', 10, t.mon - 14, t.mon + 62, 'active', 'f0000000-0000-0000-0000-0000000000f2'
  FROM t_dates t;
DO $$
DECLARE r jsonb; v_acc date; v_feed date;
BEGIN
  v_acc := (now() AT TIME ZONE 'Australia/Sydney')::date;
  v_feed := (now() AT TIME ZONE 'Etc/GMT+12')::date;
  r := public.cl_plan_rebalance_quotas('90000000-0000-0000-0000-0000000000f3', '[]'::jsonb, DATE '2000-01-01');
  PERFORM pg_temp.ok((r ->> 'fence')::date = v_acc - 1, 'fence pasado = hoy de la CUENTA - 1: ' || r::text || ' (cuenta ' || v_acc || ', conector ' || v_feed || ')');
  PERFORM pg_temp.ok(v_acc = v_feed OR (r ->> 'fence')::date <> v_feed - 1, 'no usa la zona del conector');
  r := public.cl_plan_rebalance_quotas('90000000-0000-0000-0000-0000000000f3', '[]'::jsonb);
  PERFORM pg_temp.ok((r ->> 'fence')::date = v_acc + (7 - extract(isodow FROM v_acc)::int), 'fence por defecto = domingo de la semana de la cuenta: ' || r::text);
  PERFORM set_config('t.tz', 'account ' || v_acc || ' vs feed ' || v_feed, true);
  -- Ambas funciones de escritura de cuotas comparten el bloqueo consultivo por plan.
  PERFORM pg_temp.ok((SELECT prosrc LIKE '%pg_advisory_xact_lock(hashtext(''cl_plan_quotas_write:''%' FROM pg_proc WHERE oid = 'public.cl_plan_set_quotas(uuid,jsonb)'::regprocedure)
                 AND (SELECT prosrc LIKE '%pg_advisory_xact_lock(hashtext(''cl_plan_quotas_write:''%' FROM pg_proc WHERE oid = 'public.cl_plan_rebalance_quotas(uuid,jsonb,date)'::regprocedure),
                     'mismo bloqueo consultivo por plan en set_quotas y rebalance');
END $$;
SELECT 'cl_balancing timezone: ' || current_setting('t.tz') AS tz;

-- ===================================================================== 5. escala: 15.660 cuotas (30 ciudades, 18 semanas)
INSERT INTO public.cities (account_id, region_id, name, code)
SELECT 'a0000000-0000-0000-0000-000000000001', 'e0000000-0000-0000-0000-000000000001', 'S' || g, 'S' || g
  FROM generate_series(1, 27) g;
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date) VALUES
  ('90000000-0000-0000-0000-0000000000b1','a0000000-0000-0000-0000-000000000001','Big','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',40000,'2027-01-04','2027-05-09');
CREATE TEMP TABLE big AS
SELECT jsonb_agg(pg_temp.ch(o.id::text, d.id::text, 2027, w, 1 + (w % 3))) AS q,
       -- misma ruta, valores rotados entre semanas: cada ruta conserva su suma (18 es multiplo de 3), todas cambian
       jsonb_agg(pg_temp.ch(o.id::text, d.id::text, 2027, w, 1 + ((w + 1) % 3))) AS r
  FROM public.cities o
  JOIN public.cities d ON d.account_id = o.account_id AND d.id <> o.id
 CROSS JOIN generate_series(1, 18) w
 WHERE o.account_id = 'a0000000-0000-0000-0000-000000000001';
GRANT SELECT ON big TO authenticated;
SELECT pg_temp.as_user(NULL, NULL);  -- como postgres sin sesion de usuario
SELECT public.cl_plan_set_quotas('90000000-0000-0000-0000-0000000000b1', (SELECT q FROM big));
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT jsonb_array_length(r) FROM big) = 15660, 'fixture: 15660 cambios');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000b1') = 15660, 'fixture: 15660 cuotas');
END $$;
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
DECLARE r jsonb; t0 timestamptz; v_ms numeric; v_ms2 numeric;
BEGIN
  t0 := clock_timestamp();
  r := public.cl_plan_rebalance_quotas('90000000-0000-0000-0000-0000000000b1', (SELECT big.r FROM big));
  v_ms := round(extract(epoch FROM clock_timestamp() - t0) * 1000);
  PERFORM pg_temp.ok(r = '{"changed":15660,"created":0,"deleted":0,"fence":null}'::jsonb, 'escala: ' || r::text);
  PERFORM pg_temp.ok(v_ms < 4000, '15660 cambios en < 4 s (tardo ' || v_ms || ' ms)');
  t0 := clock_timestamp();
  r := public.cl_plan_rebalance_quotas('90000000-0000-0000-0000-0000000000b1', (SELECT big.r FROM big));
  v_ms2 := round(extract(epoch FROM clock_timestamp() - t0) * 1000);
  PERFORM pg_temp.ok(r ->> 'changed' = '0', 'escala idempotente');
  PERFORM pg_temp.ok(v_ms2 < 4000, 'reenvio en < 4 s (tardo ' || v_ms2 || ' ms)');
  PERFORM set_config('t.ms', v_ms || ' ms, resend ' || v_ms2 || ' ms', true);
END $$;
RESET ROLE;
SELECT 'cl_balancing timing: rebalance 15660 = ' || current_setting('t.ms') AS timing;
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.total('90000000-0000-0000-0000-0000000000b1') = (SELECT sum(1 + (w % 3)) * 870 FROM generate_series(1, 18) w), 'escala: total conservado');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_plan_quotas WHERE plan_id = '90000000-0000-0000-0000-0000000000b1'
                       AND samples_planned <> 1 + ((iso_week + 1) % 3)) = 0, 'escala: valores aplicados');
END $$;

\echo cl_balancing: OK
ROLLBACK;
