-- rpc_balance_city_v2: fence (p_fence_until) y sustitucion de muestras 'pobox' por anotaciones del registro.
-- Fixture comun: C1 = N1, N2, N3 (P1..P3); C2 = N4 (P4); plan Mar27 (2027-03-01..31) 'active'; actor 99.
-- 2027-03-01 es lunes.
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;
CREATE FUNCTION pg_temp.mk_to(p_o text, p_d text, p_date date, p_src text DEFAULT 'plan') RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.allocation_plan_details
    (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, generation_source)
  SELECT gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
         o.id, d.id, p_date, 'pending', p_src
    FROM public.nodes o, public.nodes d WHERE o.auto_id = p_o AND d.auto_id = p_d
  RETURNING id;
$$;
CREATE FUNCTION pg_temp.mk_ds(p_o text, p_d text, p_date date) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.deferred_samples
    (account_id, plan_id, origin_city_id, dest_city_id, origin_node_id, destination_node_id, fecha_programada,
     reason, row_snapshot, created_by)
  SELECT 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001', o.city_id, d.city_id,
         o.id, d.id, p_date, 'dest_no_panelist', jsonb_build_object('id', gen_random_uuid()),
         '99000000-0000-0000-0000-000000000099'
    FROM public.nodes o, public.nodes d WHERE o.auto_id = p_o AND d.auto_id = p_d
  RETURNING id;
$$;

-- ===== Caso 1 (fence): 6 pendientes en N1 el 3/3 (dentro del fence 12/3) y 6 en N1 el 17/3 (fuera). Con fence
-- las del 3/3 no se tocan; las del 17/3 se reparten solo en dias > 12/3; la anotacion se reintroduce despues del
-- fence. Sin fence las del 3/3 si se moverian.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.mk_to('N1', 'N4', '2027-03-03') FROM generate_series(1, 6);
SELECT pg_temp.mk_to('N1', 'N4', '2027-03-17') FROM generate_series(1, 6);
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-02');
DO $$
DECLARE r jsonb;
BEGIN
  -- vista previa sin fence: hay movimientos desde el 3/3
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', false);
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'movements') m WHERE m->>'from_date' = '2027-03-03'),
                          'c1 sin fence deberia mover el 3/3: ' || r::text);
  PERFORM pg_temp.fail_if(r->>'fence_until' IS NOT NULL, 'c1 sin fence fence_until: ' || r::text);
  -- aplicar con fence
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', true, '2027-03-12');
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true, 'c1 success: ' || r::text);
  PERFORM pg_temp.fail_if(r->>'fence_until' IS DISTINCT FROM '2027-03-12', 'c1 fence_until: ' || r::text);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 1, 'c1 reintroduced: ' || r::text);
  PERFORM pg_temp.fail_if((r->>'movements_count')::int < 1, 'c1 deberia mover las del 17/3: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 6, 'c1 las 6 del 3/3 intactas en N1: ' || count(*))
  FROM public.allocation_plan_details
 WHERE fecha_programada = '2027-03-03' AND origin_node_id = 'b1000000-0000-0000-0000-000000000001'
   AND reassigned_at IS NULL;
SELECT pg_temp.fail_if(count(*) <> 0, 'c1 nada nuevo ni movido dentro del fence: ' || count(*))
  FROM public.allocation_plan_details
 WHERE fecha_programada BETWEEN '2027-03-01' AND '2027-03-12' AND fecha_programada <> '2027-03-03';
SELECT pg_temp.fail_if(count(*) <> 1 OR min(fecha_programada) <= '2027-03-12', 'c1 reintroducida tras el fence')
  FROM public.allocation_plan_details WHERE generation_source = 'compensation';
SELECT pg_temp.fail_if(count(DISTINCT origin_node_id) < 2, 'c1 las del 17/3 repartidas entre nodos')
  FROM public.allocation_plan_details WHERE fecha_programada > '2027-03-12' AND generation_source = 'plan';
ROLLBACK;

-- ===== Caso 1b (fence en el pasado o NULL = sin fence): fecha < hoy no congela nada.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.mk_to('N1', 'N4', '2027-03-03') FROM generate_series(1, 6);
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', false, '2020-01-01');
  PERFORM pg_temp.fail_if(r->>'fence_until' IS NOT NULL, 'c1b fence pasado ignorado: ' || r::text);
  PERFORM pg_temp.fail_if((r->>'movements_count')::int < 1, 'c1b sin fence mueve: ' || r::text);
END $$;
ROLLBACK;

-- ===== Caso 2 (sustitucion): C3 = N5 (P5). Una 'pobox' N1->N5 el 10/3 y una anotacion N1->N4 (ruta C1->C2).
-- La 'pobox' se convierte en 'compensation' (mismo id, destino N4, mismo dia y nodo origen): no se crea fila nueva.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City3','C3');
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000003','N5');
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language) VALUES
  ('e5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','P5','Pan5','p5@t.l','5',
   'b5000000-0000-0000-0000-000000000005','active','en');
CREATE TEMP TABLE t_ids AS SELECT pg_temp.mk_to('N1', 'N5', '2027-03-10', 'pobox') AS pb, pg_temp.mk_ds('N1', 'N4', '2027-03-02') AS ds;
DO $$
DECLARE r jsonb;
BEGIN
  -- la vista previa lo anuncia y no escribe
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-10', '2027-03-10', false);
  PERFORM pg_temp.fail_if((r->'deferred'->>'replaced_pobox')::int IS DISTINCT FROM 1, 'c2 preview replaced: ' || r::text);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 1, 'c2 preview reintroduced: ' || r::text);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.allocation_plan_details WHERE generation_source = 'compensation'),
                          'c2 preview no escribe');
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-10', '2027-03-10', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'replaced_pobox')::int IS DISTINCT FROM 1, 'c2 replaced: ' || r::text);
  -- la fila convertida cuenta una sola vez en la matriz
  PERFORM pg_temp.fail_if((SELECT COALESCE(sum((m->>'load_count')::int), 0) FROM jsonb_array_elements(r->'matrix_after') m) <> 1,
                          'c2 matrix_after: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 1, 'c2 una sola fila: ' || count(*)) FROM public.allocation_plan_details;
SELECT pg_temp.fail_if(count(*) <> 1, 'c2 fila convertida')
  FROM public.allocation_plan_details a JOIN t_ids t ON t.pb = a.id
 WHERE a.generation_source = 'compensation' AND a.status = 'pending'
   AND a.destination_node_id = 'b4000000-0000-0000-0000-000000000004'
   AND a.destination_panelist_id = 'e4000000-0000-0000-0000-000000000004' AND a.destination_panelist_name = 'Pan4'
   AND a.fecha_programada = '2027-03-10' AND a.original_destination_node_id IS NULL;
SELECT pg_temp.fail_if(count(*) <> 1, 'c2 anotacion enlazada a la fila pobox')
  FROM public.deferred_samples d JOIN t_ids t ON t.ds = d.id
 WHERE d.status = 'reintroduced' AND d.reintroduced_detail_id = t.pb;
-- idempotente
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-10', '2027-03-10', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'replaced_pobox')::int IS DISTINCT FROM 0, 'c2 2a replaced: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 1, 'c2 2a sigue una fila') FROM public.allocation_plan_details;
ROLLBACK;

-- ===== Caso 3: la ruta manda. Si la ciudad destino de la anotacion no tiene panelista, NO se sustituye (la 'pobox'
-- queda como esta) y la anotacion espera. Y una 'pobox' con material retenido nunca se convierte.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City3','C3');
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000003','N5');
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language) VALUES
  ('e5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','P5','Pan5','p5@t.l','5',
   'b5000000-0000-0000-0000-000000000005','active','en');
SELECT pg_temp.mk_to('N1', 'N5', '2027-03-10', 'pobox');
SELECT pg_temp.mk_ds('N1', 'N4', '2027-03-02');
DELETE FROM public.panelists WHERE id = 'e4000000-0000-0000-0000-000000000004';   -- C2 sin panelista
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-10', '2027-03-10', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'replaced_pobox')::int IS DISTINCT FROM 0, 'c3 replaced: ' || r::text);
  PERFORM pg_temp.fail_if((r->'deferred'->'waiting_by_reason'->>'no_dest_panelist')::int IS DISTINCT FROM 1,
                          'c3 waiting: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 1, 'c3 pobox intacta')
  FROM public.allocation_plan_details WHERE generation_source = 'pobox'
   AND destination_node_id = 'b5000000-0000-0000-0000-000000000005';
ROLLBACK;
