-- Cubre la cascada de generate_reassignment_proposals: envío reroute/shift/cancel,
-- recepción reroute/none, e idempotencia. Se ejecuta como postgres (la RPC es SECURITY DEFINER).
\set ON_ERROR_STOP on
BEGIN;

-- ---------- fixture ----------
INSERT INTO public.accounts (id, name, slug) VALUES
  ('a0000000-0000-0000-0000-000000000001','Acc','acc');
INSERT INTO public.regions (id, account_id, name, code) VALUES
  ('e0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','Reg','R1');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City1','C1'),
  ('c2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City2','C2');
-- Nodos: N1 (panelista de baja) y N2 (alternativo, mismo city C1); N3 en otra ciudad (aislado)
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','N1'),
  ('b2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','N2'),
  ('b3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002','N3');
-- Panelistas: P1 en N1 (se dará de baja), P2 en N2 (disponible), P3 en N3
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language) VALUES
  ('e1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','P1','Pan1','p1@t.l','1','b1000000-0000-0000-0000-000000000001','active','en'),
  ('e2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','P2','Pan2','p2@t.l','2','b2000000-0000-0000-0000-000000000002','active','en'),
  ('e3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','P3','Pan3','p3@t.l','3','b3000000-0000-0000-0000-000000000003','active','en');
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','CA','Carrier');
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','PR','Prod',48);
INSERT INTO public.allocation_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date) VALUES
  ('cc000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','Plan','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2026-09-01','2026-09-30');

-- Muestras dentro de la baja (2026-09-10..2026-09-12):
--  S1 envío desde N1, status pending  -> espera REROUTE a N2
--  S2 recepción en N1, status pending -> espera REROUTE (destino) a N2
--  S3 recepción en N1, status sent    -> espera NONE (ya salió)
INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status) VALUES
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000003','2026-09-10',37,9,2026,'pending'),
  ('d2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000003','b1000000-0000-0000-0000-000000000001','2026-09-11',37,9,2026,'pending'),
  ('d3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000003','b1000000-0000-0000-0000-000000000001','2026-09-12',37,9,2026,'sent');

-- La baja de P1 (dispara que N1 quede indisponible en el rango)
INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status) VALUES
  ('b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','2026-09-10','2026-09-12','vacation','active');

-- ---------- ejecutar el motor ----------
DO $$
DECLARE v_n integer;
BEGIN
  v_n := generate_reassignment_proposals('b0000000-0000-0000-0000-000000000001');
  IF v_n <> 3 THEN RAISE EXCEPTION 'FAIL: esperaba 3 propuestas, obtuve %', v_n; END IF;
  RAISE NOTICE 'PASS: 3 propuestas generadas';
END $$;

-- S1 envío -> reroute a N2
DO $$
DECLARE v_action text; v_node uuid;
BEGIN
  SELECT suggested_action, suggested_target_node_id INTO v_action, v_node
  FROM panelist_reassignment_proposal
  WHERE allocation_plan_detail_id='d1000000-0000-0000-0000-000000000001' AND affected_role='origin';
  IF v_action <> 'reroute' OR v_node <> 'b2000000-0000-0000-0000-000000000002' THEN
    RAISE EXCEPTION 'FAIL S1: esperaba reroute->N2, obtuve % / %', v_action, v_node;
  END IF;
  RAISE NOTICE 'PASS S1: envío reroute a N2';
END $$;

-- S2 recepción no salida -> reroute
DO $$
DECLARE v_action text;
BEGIN
  SELECT suggested_action INTO v_action FROM panelist_reassignment_proposal
  WHERE allocation_plan_detail_id='d2000000-0000-0000-0000-000000000002' AND affected_role='destination';
  IF v_action <> 'reroute' THEN RAISE EXCEPTION 'FAIL S2: esperaba reroute, obtuve %', v_action; END IF;
  RAISE NOTICE 'PASS S2: recepción no salida reroute';
END $$;

-- S3 recepción ya salida -> none
DO $$
DECLARE v_action text;
BEGIN
  SELECT suggested_action INTO v_action FROM panelist_reassignment_proposal
  WHERE allocation_plan_detail_id='d3000000-0000-0000-0000-000000000003' AND affected_role='destination';
  IF v_action <> 'none' THEN RAISE EXCEPTION 'FAIL S3: esperaba none, obtuve %', v_action; END IF;
  RAISE NOTICE 'PASS S3: recepción ya salida none';
END $$;

-- El motor NO mutó el plan (S1 sigue en N1)
DO $$
DECLARE v_origin uuid;
BEGIN
  SELECT origin_node_id INTO v_origin FROM allocation_plan_details WHERE id='d1000000-0000-0000-0000-000000000001';
  IF v_origin <> 'b1000000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'FAIL: el motor mutó el plan (S1 origin=% )', v_origin;
  END IF;
  RAISE NOTICE 'PASS: el plan no se mutó';
END $$;

-- Idempotencia: re-ejecutar deja el mismo número de propuestas pending (no duplica)
DO $$
DECLARE v_before integer; v_after integer;
BEGIN
  SELECT count(*) INTO v_before FROM panelist_reassignment_proposal WHERE unavailability_id='b0000000-0000-0000-0000-000000000001';
  PERFORM generate_reassignment_proposals('b0000000-0000-0000-0000-000000000001');
  SELECT count(*) INTO v_after FROM panelist_reassignment_proposal WHERE unavailability_id='b0000000-0000-0000-0000-000000000001';
  IF v_after <> v_before THEN RAISE EXCEPTION 'FAIL idempotencia: % -> %', v_before, v_after; END IF;
  RAISE NOTICE 'PASS: idempotencia (sin duplicar)';
END $$;

-- ---------- guarda multi-tenant (cross-tenant IDOR) ----------
-- Cuenta B ajena, con un usuario autenticado cuyo profile.account_id = B.
INSERT INTO public.accounts (id, name, slug) VALUES
  ('a0000000-0000-0000-0000-000000000002','AccB','accb');
INSERT INTO auth.users (id, email) VALUES
  ('99999999-0000-0000-0000-000000000009','user.b@test.local');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('99999999-0000-0000-0000-000000000009','user.b@test.local','UserB','user','a0000000-0000-0000-0000-000000000002');

GRANT USAGE ON SCHEMA public TO authenticated;

CREATE OR REPLACE FUNCTION pg_temp.login(p_uid text) RETURNS void
  LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
END $$;

-- Usuario de la cuenta B intenta generar propuestas sobre la baja de la cuenta A -> debe fallar.
SET ROLE authenticated;
SELECT pg_temp.login('99999999-0000-0000-0000-000000000009');

DO $$
BEGIN
  BEGIN
    PERFORM generate_reassignment_proposals('b0000000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'FAIL guarda: se permitió generar propuestas cross-tenant';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM = 'Cross-tenant access denied' THEN
        RAISE NOTICE 'PASS: guarda multi-tenant rechaza acceso cross-tenant';
      ELSE
        RAISE EXCEPTION 'FAIL guarda: error inesperado: %', SQLERRM;
      END IF;
  END;
END $$;

RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);

-- El path service-role (postgres, auth.uid() NULL) sigue funcionando igual que antes.
DO $$
DECLARE v_n integer;
BEGIN
  v_n := generate_reassignment_proposals('b0000000-0000-0000-0000-000000000001');
  IF v_n <> 3 THEN RAISE EXCEPTION 'FAIL: service-role esperaba 3 propuestas, obtuve %', v_n; END IF;
  RAISE NOTICE 'PASS: path service-role (auth.uid() NULL) sigue generando 3 propuestas';
END $$;

ROLLBACK;
