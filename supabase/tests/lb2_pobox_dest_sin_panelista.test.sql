-- POBOX: un envio cuyo destino no tiene panelista activo no sale nunca (el bot no lo avisa), asi que NO cubre su dia.
-- Caso real 2026-10-28: Garissa (POBOX) tenia como unico envio del dia uno a Busia (sin panelista) y se quedo sin enviar.
-- Fixture: C1 con solo N1 valido (se borran P2/P3); C2 = N4 (P4); C3 = N6 sin panelista. Plan Mar27.
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;
-- Dias laborables de [p_from, p_to] sin ningun envio de C1 que salga de verdad (no cancelado y destino con panelista activo).
CREATE FUNCTION pg_temp.c1_uncovered(p_from date, p_to date) RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM generate_series(p_from, p_to, interval '1 day') g(d)
   WHERE EXTRACT(isodow FROM g.d) <= 5
     AND NOT EXISTS (SELECT 1 FROM public.allocation_plan_details a JOIN public.nodes n ON n.id = a.origin_node_id
                      WHERE n.city_id = 'c1000000-0000-0000-0000-000000000001'
                        AND a.fecha_programada = g.d::date AND a.status <> 'cancelled'
                        AND EXISTS (SELECT 1 FROM public.panelists p
                                     WHERE p.node_id = a.destination_node_id AND p.status = 'active'));
$$;
CREATE FUNCTION pg_temp.setup() RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
  INSERT INTO public.account_config (account_id, pobox_enabled) VALUES ('a0000000-0000-0000-0000-000000000001', true)
  ON CONFLICT (account_id) DO UPDATE SET pobox_enabled = true;
  DELETE FROM public.panelists WHERE id IN ('e2000000-0000-0000-0000-000000000002', 'e3000000-0000-0000-0000-000000000003');
  INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
    ('c3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City3','C3');
  INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
    ('b6000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000003','N6');
  -- 8/3: N1 -> N4 (valido). 9/3: N1 -> N6 (sin panelista), unico envio del dia.
  INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
  VALUES ('d0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
          'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-08','pending'),
         ('d0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
          'b1000000-0000-0000-0000-000000000001','b6000000-0000-0000-0000-000000000006','2027-03-09','pending');
$$;

-- ===== Caso 1 (Garissa): la muestra sin destino se aparta al registro y POBOX cubre el 9 con un envio valido.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-09', true);
  PERFORM pg_temp.fail_if((r->'pobox'->>'days_missing')::int <> 1 OR (r->'pobox'->>'days_uncovered')::int <> 0,
                          'caso 1 pobox: ' || r::text);
END $$;
SELECT pg_temp.fail_if(pg_temp.c1_uncovered('2027-03-08', '2027-03-09') <> 0, 'caso 1: el 9 queda sin envio que salga');
ROLLBACK;

-- ===== Caso 2 (bloqueada): la muestra sin destino tiene una retencion de material => no se puede apartar y se queda
-- en el 9, pero no sale. POBOX no debe dar el 9 por cubierto.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
INSERT INTO public.material_hold (allocation_plan_detail_id, account_id, panelist_id)
VALUES ('d0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001');
DO $$
DECLARE r jsonb; p jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-09', false);
  p := r->'pobox';
  PERFORM pg_temp.fail_if((p->>'days_missing')::int <> 1 OR (p->>'days_created')::int <> 1
                          OR (p->>'days_uncovered')::int <> 0, 'caso 2 pobox: ' || r::text);
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-09', true);
  PERFORM pg_temp.fail_if(r->'pobox' IS DISTINCT FROM p, 'caso 2 apply y preview distintos: ' || r::text);
END $$;
SELECT pg_temp.fail_if(pg_temp.c1_uncovered('2027-03-08', '2027-03-09') <> 0, 'caso 2: el 9 queda sin envio que salga');
SELECT pg_temp.fail_if((SELECT fecha_programada FROM public.allocation_plan_details
                         WHERE id = 'd0000000-0000-0000-0000-000000000002') IS DISTINCT FROM '2027-03-09',
                       'caso 2: la bloqueada debe quedarse donde esta');
ROLLBACK;

-- ===== Caso 3 (donante): el 8 tiene un valido + la bloqueada sin destino; el 9 esta vacio. El 8 NO es un dia con
-- 2 envios que salgan, asi que no se le quita el valido (se quedaria sin cubrir): se crea uno para el 9.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
UPDATE public.allocation_plan_details SET fecha_programada = '2027-03-08' WHERE id = 'd0000000-0000-0000-0000-000000000002';
INSERT INTO public.material_hold (allocation_plan_detail_id, account_id, panelist_id)
VALUES ('d0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001');
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-08', '2027-03-09', true);
  PERFORM pg_temp.fail_if((r->'pobox'->>'days_moved')::int <> 0 OR (r->'pobox'->>'days_created')::int <> 1,
                          'caso 3 pobox: ' || r::text);
END $$;
SELECT pg_temp.fail_if(pg_temp.c1_uncovered('2027-03-08', '2027-03-09') <> 0, 'caso 3: algun dia sin envio que salga');
ROLLBACK;

SELECT 'PASS lb2_pobox_dest_sin_panelista';
