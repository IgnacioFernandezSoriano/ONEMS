-- Cubre list_reroute_candidates: candidatos por ciudad/rol, exclusión del nodo propio,
-- flag is_available, validación de rol y guarda cross-tenant. Se ejecuta como postgres.
\set ON_ERROR_STOP on
BEGIN;

INSERT INTO public.accounts (id, name, slug) VALUES
  ('a0000000-0000-0000-0000-000000000001','Acc','acc');
INSERT INTO public.regions (id, account_id, name, code) VALUES
  ('e0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','Reg','R1');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City1','C1'),
  ('c2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City2','C2');
-- N1 nodo actual (origin), N2 mismo city disponible, N4 mismo city con panelista de baja (no disponible),
-- N3 en otra ciudad (no debe salir).
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','N1'),
  ('b2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','N2'),
  ('b4000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','N4'),
  ('b3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002','N3');
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language) VALUES
  ('e1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','P1','Pan1','p1@t.l','1','b1000000-0000-0000-0000-000000000001','active','en'),
  ('e2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','P2','Pan2','p2@t.l','2','b2000000-0000-0000-0000-000000000002','active','en'),
  ('e4000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','P4','Pan4','p4@t.l','4','b4000000-0000-0000-0000-000000000004','active','en');
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','CA','Carrier');
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','PR','Prod',48);
INSERT INTO public.allocation_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date) VALUES
  ('cc000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','Plan','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2026-09-01','2026-09-30');
-- Muestra origin en N1, fecha 2026-09-10.
INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status) VALUES
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000003','2026-09-10',37,9,2026,'pending');
-- P4 (nodo N4) está de baja el 2026-09-10 -> N4 no disponible ese día.
INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status) VALUES
  ('b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000004','2026-09-10','2026-09-10','vacation','active');

-- Candidatos para el rol origin: deben ser N2 y N4 (misma ciudad, no N1, no N3). N2 disponible, N4 no.
DO $$
DECLARE v_count integer; v_n2_avail boolean; v_n4_avail boolean; v_has_n1 integer; v_has_n3 integer;
BEGIN
  SELECT count(*) INTO v_count FROM list_reroute_candidates('d1000000-0000-0000-0000-000000000001','origin');
  IF v_count <> 2 THEN RAISE EXCEPTION 'FAIL: esperaba 2 candidatos, obtuve %', v_count; END IF;

  SELECT is_available INTO v_n2_avail FROM list_reroute_candidates('d1000000-0000-0000-0000-000000000001','origin') WHERE node_id='b2000000-0000-0000-0000-000000000002';
  SELECT is_available INTO v_n4_avail FROM list_reroute_candidates('d1000000-0000-0000-0000-000000000001','origin') WHERE node_id='b4000000-0000-0000-0000-000000000004';
  IF v_n2_avail IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: N2 debería estar disponible'; END IF;
  IF v_n4_avail IS DISTINCT FROM false THEN RAISE EXCEPTION 'FAIL: N4 debería estar NO disponible'; END IF;

  SELECT count(*) INTO v_has_n1 FROM list_reroute_candidates('d1000000-0000-0000-0000-000000000001','origin') WHERE node_id='b1000000-0000-0000-0000-000000000001';
  SELECT count(*) INTO v_has_n3 FROM list_reroute_candidates('d1000000-0000-0000-0000-000000000001','origin') WHERE node_id='b3000000-0000-0000-0000-000000000003';
  IF v_has_n1 <> 0 THEN RAISE EXCEPTION 'FAIL: N1 (nodo propio) no debe aparecer'; END IF;
  IF v_has_n3 <> 0 THEN RAISE EXCEPTION 'FAIL: N3 (otra ciudad) no debe aparecer'; END IF;
  RAISE NOTICE 'PASS: candidatos correctos, is_available correcto, exclusiones correctas';
END $$;

-- Rol inválido -> excepción.
DO $$
BEGIN
  BEGIN
    PERFORM * FROM list_reroute_candidates('d1000000-0000-0000-0000-000000000001','bogus');
    RAISE EXCEPTION 'FAIL: rol inválido debería fallar';
  EXCEPTION WHEN OTHERS THEN
    IF position('Invalid role' in SQLERRM) > 0 THEN RAISE NOTICE 'PASS: rol inválido rechazado';
    ELSE RAISE EXCEPTION 'FAIL: error inesperado: %', SQLERRM; END IF;
  END;
END $$;

-- Guarda cross-tenant.
INSERT INTO public.accounts (id, name, slug) VALUES
  ('a0000000-0000-0000-0000-000000000002','AccB','accb');
INSERT INTO auth.users (id, email) VALUES
  ('99999999-0000-0000-0000-000000000009','user.b@test.local');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('99999999-0000-0000-0000-000000000009','user.b@test.local','UserB','user','a0000000-0000-0000-0000-000000000002');
GRANT USAGE ON SCHEMA public TO authenticated;
CREATE OR REPLACE FUNCTION pg_temp.login(p_uid text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
END $$;
SET ROLE authenticated;
SELECT pg_temp.login('99999999-0000-0000-0000-000000000009');
DO $$
BEGIN
  BEGIN
    PERFORM * FROM list_reroute_candidates('d1000000-0000-0000-0000-000000000001','origin');
    RAISE EXCEPTION 'FAIL guarda: se permitió acceso cross-tenant';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM = 'Cross-tenant access denied' THEN RAISE NOTICE 'PASS: guarda cross-tenant';
    ELSE RAISE EXCEPTION 'FAIL guarda: error inesperado: %', SQLERRM; END IF;
  END;
END $$;
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);

ROLLBACK;
