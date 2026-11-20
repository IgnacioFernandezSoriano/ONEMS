-- Carrier Link tarea 10c (20261121100100_cl_ingest_perf.sql):
--   1. cl_is_valid_timezone con cache da el MISMO resultado que la consulta original sobre pg_timezone_names para todo
--      valor (zonas reales, NULL, inventadas, abreviaturas, POSIX, mayusculas distintas, vacio); la cache es una copia
--      exacta de pg_timezone_names, con RLS y sin conceder a anon/authenticated.
--   2. El disparador estatico de cl_batch_scans da exactamente el mismo resultado (SQLSTATE y mensaje) que el generico
--      cl_check_same_account con sus argumentos de 20261120110200, caso a caso, en INSERT y UPDATE (diferencial).
-- (El resumen y raw_payload de cl_ingest_batch los cubren cl_ingest, cl_wave2, cl_final_fixes y cl_ui_dry_run.)
-- Todo en BEGIN ... ROLLBACK.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.msg_of(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN 'ok'; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE || ':' || SQLERRM; END $$;

BEGIN;
-- 1. Zonas horarias: todas las reales + valores raros, mismo resultado que la definicion original.
SELECT pg_temp.ok(count(*) = 0, 'cl_is_valid_timezone differs from pg_timezone_names for: '
                  || string_agg(coalesce(v, '<NULL>'), ', '))
  FROM (SELECT z.name AS v FROM pg_catalog.pg_timezone_names z
        UNION ALL SELECT x FROM unnest(ARRAY[NULL, '', ' ', 'Mars/Base', 'africa/nairobi', 'AFRICA/NAIROBI', 'CEST',
                                             'cest', 'UTC+3', '+03', '<+03>-3', 'Factory', 'posixrules', 'UTC', 'utc',
                                             'Etc/GMT+3', 'Africa/Nairobi ', 'Africa/Atlantis']) x) t
 WHERE public.cl_is_valid_timezone(v)
       IS DISTINCT FROM (v IS NULL OR EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names z WHERE z.name = v));

SELECT pg_temp.ok(NOT EXISTS ((SELECT z.name FROM pg_catalog.pg_timezone_names z
                                EXCEPT SELECT c.name FROM public.cl_timezone_names c)
                               UNION ALL
                               (SELECT c.name FROM public.cl_timezone_names c
                                EXCEPT SELECT z.name FROM pg_catalog.pg_timezone_names z)),
                  'cache must be exactly pg_timezone_names');
SELECT pg_temp.ok(NOT has_table_privilege('anon', 'public.cl_timezone_names', 'SELECT')
              AND NOT has_table_privilege('authenticated', 'public.cl_timezone_names', 'SELECT'),
                  'cl_timezone_names must not be granted to anon/authenticated');
SELECT pg_temp.ok(NOT has_table_privilege('service_role', 'public.cl_timezone_names', 'SELECT')
              AND NOT has_table_privilege('service_role', 'public.cl_timezone_names', 'INSERT'),
                  'cl_timezone_names must not be granted to service_role');
SELECT pg_temp.ok(NOT has_function_privilege('anon', 'public.cl_is_valid_timezone(text)', 'EXECUTE'),
                  'anon must not execute cl_is_valid_timezone');
SELECT pg_temp.ok(has_function_privilege('authenticated', 'public.cl_is_valid_timezone(text)', 'EXECUTE')
              AND has_function_privilege('service_role', 'public.cl_is_valid_timezone(text)', 'EXECUTE'),
                  'authenticated and service_role keep EXECUTE on cl_is_valid_timezone (cl_feeds CHECK)');
SELECT pg_temp.ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.cl_timezone_names'::regclass),
                  'cl_timezone_names must have RLS enabled');

-- 2. Disparador estatico de cl_batch_scans frente al generico.
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
INSERT INTO public.regions (id, account_id, name, code) VALUES
  ('e0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','Reg2','R2');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','CityB','CB');
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','CB','Carrier2');
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','PR2','Prod2',48);
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001'),
  ('d2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','PC2','Center 2','CityB','c3000000-0000-0000-0000-000000000003');
INSERT INTO public.readers (id, account_id, postal_center_id, reader_id, name, type) VALUES
  ('f1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','R10C1','R1','Entry'),
  ('f2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','d2000000-0000-0000-0000-000000000002','R10C2','R2','Entry');
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name) VALUES
  ('f0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed A1'),
  ('f0000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','Feed A2');
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date) VALUES
  ('90000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','Plan A1','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2027-03-01','2027-03-31'),
  ('90000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000002','Plan A2','ca000000-0000-0000-0000-000000000002','cb000000-0000-0000-0000-000000000002',10,'2027-03-01','2027-03-31');
INSERT INTO public.cl_plan_quotas (id, account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned) VALUES
  ('91000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2027,10,'2027-03-08','2027-03-14',5),
  ('91000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-0000000000a2','c3000000-0000-0000-0000-000000000003','c3000000-0000-0000-0000-000000000003',2027,10,'2027-03-08','2027-03-14',5);
INSERT INTO public.cl_demands (id, account_id, plan_id, feed_id, random_seed, payload) VALUES
  ('92000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','f0000000-0000-0000-0000-0000000000a1','s1','{}'),
  ('92000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-0000000000a2','f0000000-0000-0000-0000-0000000000a2','s2','{}');
INSERT INTO public.cl_batches (id, account_id, demand_id, connector_batch_id, status) VALUES
  ('93000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','92000000-0000-0000-0000-0000000000a1','B1','received'),
  ('93000000-0000-0000-0000-0000000000a2','a0000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-0000000000a2','B1','received');
INSERT INTO public.cl_batch_scans (id, account_id, batch_id, stratum_id, item_id, status) VALUES
  ('96000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-0000000000a1',NULL,'BASE','valid');

-- Casos (lote, estrato, producto, lector) en una fila de A1: 'a1' = id de A1, 'X' = id de A2, NULL = sin valor,
-- otro texto = id inexistente.
CREATE TEMP TABLE t_cases (k int, b text, s text, p text, r text);
INSERT INTO t_cases VALUES
  (1, 'a1', NULL, NULL, NULL), (2, 'a1', 'a1', 'a1', 'a1'), (3, 'X', 'a1', 'a1', 'a1'), (4, 'a1', 'X', 'a1', 'a1'),
  (5, 'a1', 'a1', 'X', 'a1'), (6, 'a1', 'a1', 'a1', 'X'), (7, 'a1', 'X', 'X', 'X'), (8, 'a1', NULL, NULL, 'X'),
  (9, 'a1', 'a1', NULL, NULL), (10, 'a1', '00000000-0000-0000-0000-00000000dead', NULL, NULL);
CREATE TEMP TABLE t_res (impl text, k int, op text, msg text);

CREATE OR REPLACE FUNCTION pg_temp.run_cases(p_impl text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE c record; v_b text; v_s text; v_p text; v_r text;
BEGIN
  FOR c IN SELECT * FROM t_cases ORDER BY k LOOP
    v_b := CASE c.b WHEN 'a1' THEN '93000000-0000-0000-0000-0000000000a1' WHEN 'X' THEN '93000000-0000-0000-0000-0000000000a2' ELSE c.b END;
    v_s := CASE c.s WHEN 'a1' THEN '91000000-0000-0000-0000-0000000000a1' WHEN 'X' THEN '91000000-0000-0000-0000-0000000000a2' ELSE c.s END;
    v_p := CASE c.p WHEN 'a1' THEN 'cb000000-0000-0000-0000-000000000001' WHEN 'X' THEN 'cb000000-0000-0000-0000-000000000002' ELSE c.p END;
    v_r := CASE c.r WHEN 'a1' THEN 'f1000000-0000-0000-0000-000000000001' WHEN 'X' THEN 'f2000000-0000-0000-0000-000000000002' ELSE c.r END;
    INSERT INTO t_res VALUES (p_impl, c.k, 'insert', pg_temp.msg_of(format(
      'INSERT INTO public.cl_batch_scans (account_id, batch_id, stratum_id, product_id, reader_id, item_id, status) '
      'VALUES (''a0000000-0000-0000-0000-000000000001'', %L, %L, %L, %L, ''I'', ''valid'')', v_b, v_s, v_p, v_r)));
    INSERT INTO t_res VALUES (p_impl, c.k, 'update', pg_temp.msg_of(format(
      'UPDATE public.cl_batch_scans SET batch_id = %L, stratum_id = %L, product_id = %L, reader_id = %L '
      'WHERE id = ''96000000-0000-0000-0000-0000000000a1''', v_b, v_s, v_p, v_r)));
    DELETE FROM public.cl_batch_scans WHERE item_id = 'I';
    UPDATE public.cl_batch_scans SET batch_id = '93000000-0000-0000-0000-0000000000a1', stratum_id = NULL,
           product_id = NULL, reader_id = NULL
     WHERE id = '96000000-0000-0000-0000-0000000000a1';
  END LOOP;
END $$;

SELECT pg_temp.ok((SELECT tgfoid = 'public.cl_batch_scans_check_same_account()'::regprocedure FROM pg_trigger
                    WHERE tgrelid = 'public.cl_batch_scans'::regclass AND tgname = 'cl_same_account'),
                  'cl_batch_scans uses its static trigger function');
SELECT pg_temp.run_cases('static');
DROP TRIGGER cl_same_account ON public.cl_batch_scans;
CREATE TRIGGER cl_same_account BEFORE INSERT OR UPDATE ON public.cl_batch_scans FOR EACH ROW
  EXECUTE FUNCTION public.cl_check_same_account('batch_id','cl_batches','stratum_id','cl_plan_quotas',
                                                'product_id','products','reader_id','readers');
SELECT pg_temp.run_cases('generic');
SELECT pg_temp.ok(count(*) = 0, 'static and generic triggers differ: '
                  || string_agg(format('case %s %s: %s / %s', s.k, s.op, s.msg, g.msg), '; '))
  FROM t_res s JOIN t_res g ON g.k = s.k AND g.op = s.op AND g.impl = 'generic'
 WHERE s.impl = 'static' AND s.msg IS DISTINCT FROM g.msg;
SELECT pg_temp.ok((SELECT count(*) FROM t_res) = 40, 'all cases ran');
SELECT pg_temp.ok((SELECT count(DISTINCT msg) FROM t_res WHERE impl = 'static') >= 4,
                  'cases cover ok and the FK errors: ' || (SELECT string_agg(DISTINCT msg, ' | ') FROM t_res));
ROLLBACK;
