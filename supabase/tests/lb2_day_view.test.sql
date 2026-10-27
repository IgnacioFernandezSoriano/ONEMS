-- Load Balancing v2, tarea 2: rpc_get_node_load_by_day (una fila por nodo x dia) + guarda de cuenta.
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;

BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);

CREATE FUNCTION pg_temp.mk(p_o text, p_date date, p_status text DEFAULT 'pending') RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.allocation_plan_details
    (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
  SELECT gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
         o.id, d.id, p_date, p_status
    FROM public.nodes o, public.nodes d WHERE o.auto_id = p_o AND d.auto_id = 'N4'
  RETURNING id;
$$;
SELECT pg_temp.mk('N1', '2027-03-04') FROM generate_series(1, 3);
SELECT pg_temp.mk('N1', '2027-03-06');
SELECT pg_temp.mk('N1', '2027-03-04', 'sent');  -- cuenta en shipment_count pero no en pending_count

INSERT INTO public.panelist_unavailability (panelist_id, start_date, end_date, reason, status, account_id)
VALUES ('e2000000-0000-0000-0000-000000000002', '2027-03-08', '2027-03-09', 'vacation', 'active',
        'a0000000-0000-0000-0000-000000000001');

CREATE TEMP TABLE r AS
  SELECT * FROM public.rpc_get_node_load_by_day('a0000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31');

SELECT pg_temp.fail_if((SELECT count(*) FROM r) <> 4 * 31, 'filas: ' || (SELECT count(*) FROM r));
SELECT pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM r WHERE node_id = 'b1000000-0000-0000-0000-000000000001'
  AND day = '2027-03-04' AND shipment_count = 4 AND pending_count = 3 AND city_name = 'City1' AND panelist_name = 'Pan1'),
  'N1 04/03 conteos');
SELECT pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM r WHERE node_id = 'b1000000-0000-0000-0000-000000000001'
  AND day = '2027-03-06' AND NOT is_working_day AND shipment_count = 1), 'N1 06/03 sabado');
SELECT pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM r WHERE node_id = 'b2000000-0000-0000-0000-000000000002'
  AND day = '2027-03-08' AND is_unavailable), 'N2 08/03 no disponible');
SELECT pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM r WHERE node_id = 'b2000000-0000-0000-0000-000000000002'
  AND day = '2027-03-10' AND NOT is_unavailable), 'N2 10/03 disponible');
SELECT pg_temp.fail_if(EXISTS (SELECT 1 FROM r WHERE node_id = 'b1000000-0000-0000-0000-000000000001' AND is_unavailable),
  'N1 nunca no disponible');

-- Guarda: actor 98 (cuenta 2) pidiendo la cuenta 1 => error.
SELECT set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000098', true);
DO $$
BEGIN
  PERFORM * FROM public.rpc_get_node_load_by_day('a0000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31');
  RAISE EXCEPTION 'FAIL actor de otra cuenta no debio poder leer';
EXCEPTION WHEN insufficient_privilege THEN NULL;
END $$;
-- Un superadmin si puede (account_id NULL por el check de profiles).
INSERT INTO auth.users (id, email) VALUES ('97000000-0000-0000-0000-000000000097', 'sa@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id)
  VALUES ('97000000-0000-0000-0000-000000000097', 'sa@t.l', 'SA', 'superadmin', NULL);
SELECT set_config('request.jwt.claim.sub','97000000-0000-0000-0000-000000000097', true);
SELECT pg_temp.fail_if((SELECT count(*) FROM public.rpc_get_node_load_by_day('a0000000-0000-0000-0000-000000000001', '2027-03-01', '2027-03-31')) <> 4 * 31,
  'superadmin deberia leer');
ROLLBACK;
