-- POBOX: reparto de las muestras extra por producto (rpc_set/get_pobox_product_shares + rpc_balance_city_v2) y
-- waiting_reason en vivo de rpc_deferred_samples_summary. Fixture: C1 = N1..N3, C2 = N4; plan Mar27 (producto
-- cb..01); se anade el producto cb..02 con el plan Mar27b (mismas fechas). Actor 99 (cuenta 1).
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;
CREATE FUNCTION pg_temp.setup() RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
    ('cb000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001',
     'P2','Prod2',24);
  INSERT INTO public.allocation_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date) VALUES
    ('cc000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','Mar27b',
     'ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000002',10,'2027-03-01','2027-03-31');
  INSERT INTO public.account_config (account_id, pobox_enabled) VALUES ('a0000000-0000-0000-0000-000000000001', true)
  ON CONFLICT (account_id) DO UPDATE SET pobox_enabled = true;
$$;

-- ===== Caso 1: validaciones de rpc_set_pobox_product_shares y lectura.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.setup();
SELECT pg_temp.fail_if(public.rpc_set_pobox_product_shares('a0000000-0000-0000-0000-000000000001',
  '[{"product_id":"cb000000-0000-0000-0000-000000000001","pct":50},{"product_id":"cb000000-0000-0000-0000-000000000002","pct":40}]')->>'error'
  IS DISTINCT FROM 'shares_must_sum_100', 'c1 suma 90');
SELECT pg_temp.fail_if(public.rpc_set_pobox_product_shares('a0000000-0000-0000-0000-000000000001',
  '[{"product_id":"cb000000-0000-0000-0000-000000000009","pct":100}]')->>'error'
  IS DISTINCT FROM 'invalid_shares', 'c1 producto ajeno');
SELECT pg_temp.fail_if(public.rpc_set_pobox_product_shares('a0000000-0000-0000-0000-000000000001',
  '[{"product_id":"cb000000-0000-0000-0000-000000000001","pct":12.5},{"product_id":"cb000000-0000-0000-0000-000000000002","pct":87.5}]')->>'error'
  IS DISTINCT FROM 'invalid_shares', 'c1 decimales');
SELECT pg_temp.fail_if((public.rpc_set_pobox_product_shares('a0000000-0000-0000-0000-000000000001',
  '[{"product_id":"cb000000-0000-0000-0000-000000000001","pct":25},{"product_id":"cb000000-0000-0000-0000-000000000002","pct":75}]')->>'success')::boolean
  IS DISTINCT FROM true, 'c1 guardar 25/75');
SELECT pg_temp.fail_if(count(*) <> 2 OR sum((e->>'pct')::int) <> 100, 'c1 lectura')
  FROM jsonb_array_elements(public.rpc_get_pobox_product_shares('a0000000-0000-0000-0000-000000000001')) e;
-- otra cuenta no puede leer ni escribir
SELECT set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000098', true);
DO $$
BEGIN
  PERFORM public.rpc_get_pobox_product_shares('a0000000-0000-0000-0000-000000000001');
  RAISE EXCEPTION 'FAIL c1 lectura cruzada permitida';
EXCEPTION WHEN insufficient_privilege THEN NULL;
END $$;
ROLLBACK;

-- ===== Caso 2: C1 sin envios en marzo (23 dias laborables) => POBOX crea 23, repartidas 25/75 por producto.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.setup();
SELECT public.rpc_set_pobox_product_shares('a0000000-0000-0000-0000-000000000001',
  '[{"product_id":"cb000000-0000-0000-0000-000000000001","pct":25},{"product_id":"cb000000-0000-0000-0000-000000000002","pct":75}]');
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', true);
  PERFORM pg_temp.fail_if((r->'pobox'->>'days_created')::int IS DISTINCT FROM 23, 'c2 created: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) FILTER (WHERE ap.product_id = 'cb000000-0000-0000-0000-000000000002') NOT BETWEEN 17 AND 18
                       OR count(*) <> 23,
                       'c2 reparto 75%: ' || count(*) FILTER (WHERE ap.product_id = 'cb000000-0000-0000-0000-000000000002') || '/' || count(*))
  FROM public.allocation_plan_details a JOIN public.allocation_plans ap ON ap.id = a.plan_id
 WHERE a.generation_source = 'pobox';
ROLLBACK;

-- ===== Caso 2b: sin reparto, regla anterior (plan menos avanzado; con dos planes a 0 gana el de fin mas lejano/id).
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.setup();
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31', true);
  PERFORM pg_temp.fail_if((r->'pobox'->>'days_created')::int IS DISTINCT FROM 23, 'c2b created: ' || r::text);
END $$;
SELECT pg_temp.fail_if(count(*) <> 23, 'c2b total') FROM public.allocation_plan_details WHERE generation_source = 'pobox';
ROLLBACK;

-- ===== Caso 3: waiting_reason en vivo. Anotacion C1->C2 con C2 sin panelista y sin motivo guardado.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
INSERT INTO public.deferred_samples
  (account_id, plan_id, origin_city_id, dest_city_id, origin_node_id, destination_node_id, fecha_programada,
   reason, row_snapshot)
VALUES ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
        'c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',
        'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-02',
        'dest_no_panelist','{}');
DELETE FROM public.panelists WHERE id = 'e4000000-0000-0000-0000-000000000004';
SELECT pg_temp.fail_if(public.rpc_deferred_samples_summary('a0000000-0000-0000-0000-000000000001')->'by_city'->0->>'waiting_reason'
                       IS DISTINCT FROM 'no_dest_panelist', 'c3 no_dest_panelist');
-- con C1 tambien sin panelistas manda el origen
DELETE FROM public.panelists WHERE node_id IN (SELECT id FROM public.nodes WHERE city_id = 'c1000000-0000-0000-0000-000000000001');
SELECT pg_temp.fail_if(public.rpc_deferred_samples_summary('a0000000-0000-0000-0000-000000000001')->'by_city'->0->>'waiting_reason'
                       IS DISTINCT FROM 'no_origin_panelist', 'c3 no_origin_panelist');
ROLLBACK;
