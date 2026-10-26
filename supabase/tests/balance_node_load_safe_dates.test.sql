-- rpc_balance_node_load_by_period: nunca mueve envios al pasado ni fuera del periodo, evita fin de semana y
-- festivos, y deja rastro (reassigned_by, original_*). Ciudad C1 con nodos N1, N2, N3 (fixture comun).
-- Las fechas se fijan en el futuro (2027) para que "hoy" no las recorte; el caso "periodo que empieza en el
-- pasado" usa fechas alrededor de current_date.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
-- auth.uid() -> actor 99
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);

CREATE FUNCTION pg_temp.mk(p_o text, p_date date, p_status text DEFAULT 'pending') RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.allocation_plan_details
    (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
  SELECT gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
         o.id, d.id, p_date, p_status
    FROM public.nodes o, public.nodes d WHERE o.auto_id = p_o AND d.auto_id = 'N4'
  RETURNING id;
$$;
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;

-- ===== Caso 1: periodo que empieza en jueves 4/3/2027 (2027-03-15 festivo). 30 envios todos en N1 el 4/3.
-- La version antigua creaba la celda desde el lunes 1/3 y podia mover envios a 1-3/3, antes del periodo.
INSERT INTO public.non_working_days (account_id, date, reason) VALUES
  ('a0000000-0000-0000-0000-000000000001', '2027-03-15', 'festivo test');
DO $$ BEGIN FOR i IN 1..30 LOOP PERFORM pg_temp.mk('N1', '2027-03-04'); END LOOP; END $$;

DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_node_load_by_period('c1000000-0000-0000-0000-000000000001', '2027-03-04', '2027-03-31', false);
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true, 'preview success: ' || r::text);
  -- preview no toca nada
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details WHERE fecha_programada <> '2027-03-04') <> 0, 'preview movio envios');
  r := public.rpc_balance_node_load_by_period('c1000000-0000-0000-0000-000000000001', '2027-03-04', '2027-03-31', true);
  PERFORM pg_temp.fail_if((r->>'movements_count')::int = 0, 'apply no movio nada: ' || r::text);
END $$;

-- Ninguno antes del inicio del periodo (4/3) ni despues del fin, aunque 1/3 fuera lunes de esa semana.
SELECT pg_temp.fail_if(count(*) > 0, 'envios fuera de [2027-03-04, 2027-03-31]: ' || count(*))
  FROM public.allocation_plan_details WHERE fecha_programada < '2027-03-04' OR fecha_programada > '2027-03-31';
-- Ni fin de semana ni festivo.
SELECT pg_temp.fail_if(count(*) > 0, 'envios en fin de semana: ' || count(*))
  FROM public.allocation_plan_details WHERE EXTRACT(isodow FROM fecha_programada) > 5;
SELECT pg_temp.fail_if(count(*) > 0, 'envios en festivo 15/3: ' || count(*))
  FROM public.allocation_plan_details WHERE fecha_programada = '2027-03-15';
-- Reparto entre los 3 nodos de C1 y rastro.
SELECT pg_temp.fail_if(count(DISTINCT origin_node_id) <> 3, 'no repartio entre los 3 nodos') FROM public.allocation_plan_details;
SELECT pg_temp.fail_if(count(*) > 0, 'movidos sin reassigned_by / original_*')
  FROM public.allocation_plan_details
 WHERE reassigned_at IS NOT NULL
   AND (reassigned_by IS DISTINCT FROM '99000000-0000-0000-0000-000000000099'
        OR original_fecha_programada IS DISTINCT FROM '2027-03-04'
        OR original_origin_node_id IS DISTINCT FROM 'b1000000-0000-0000-0000-000000000001');
-- Las celdas se reparten de forma pareja: max - min <= 1 por nodo-semana.
SELECT pg_temp.fail_if(max(n) - min(n) > 1, 'reparto desigual: ' || string_agg(n::text, ','))
  FROM (SELECT count(*) n FROM public.allocation_plan_details
         GROUP BY origin_node_id, date_trunc('week', fecha_programada)) x;
ROLLBACK;

-- ===== Caso 2: periodo que empieza en el pasado (como "octubre" pedido a final de mes): nada va al pasado.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
CREATE FUNCTION pg_temp.mk(p_o text, p_date date) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.allocation_plan_details
    (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
  SELECT gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
         o.id, d.id, p_date, 'pending'
    FROM public.nodes o, public.nodes d WHERE o.auto_id = p_o AND d.auto_id = 'N4' RETURNING id;
$$;
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;
-- 12 envios: 6 atrasados (hace 10 dias) y 6 dentro de 20 dias, todos en N1.
DO $$ BEGIN
  FOR i IN 1..6 LOOP PERFORM pg_temp.mk('N1', current_date - 10); END LOOP;
  FOR i IN 1..6 LOOP PERFORM pg_temp.mk('N1', current_date + 20); END LOOP;
END $$;
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_node_load_by_period('c1000000-0000-0000-0000-000000000001', current_date - 30, current_date + 30, true);
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true, 'apply success: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) > 0, 'envios en el pasado tras balancear: ' || count(*))
  FROM public.allocation_plan_details WHERE fecha_programada < current_date;
SELECT pg_temp.fail_if(count(*) > 0, 'envios fuera del periodo: ' || count(*))
  FROM public.allocation_plan_details WHERE fecha_programada > current_date + 30;
SELECT pg_temp.fail_if(count(*) > 0, 'fin de semana: ' || count(*))
  FROM public.allocation_plan_details WHERE EXTRACT(isodow FROM fecha_programada) > 5;
-- Periodo enteramente en el pasado: no hay celdas, no se mueve nada y no falla.
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_node_load_by_period('c1000000-0000-0000-0000-000000000001', current_date - 60, current_date - 31, true);
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true OR (r->>'movements_count')::int <> 0,
                          'periodo pasado: ' || r::text);
END $$;
ROLLBACK;
