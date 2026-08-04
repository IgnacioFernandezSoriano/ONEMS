-- Verifica que apply_reassignment_proposal muta el plan por acción y cierra la propuesta,
-- que 'none' solo descarta, y que bulk aplica todas las pending.
\set ON_ERROR_STOP on
BEGIN;

-- ---------- fixture (idéntico esqueleto al de generate) ----------
INSERT INTO public.accounts (id, name, slug) VALUES ('a0000000-0000-0000-0000-000000000001','Acc','acc');
INSERT INTO public.regions (id, account_id, name, code) VALUES ('e0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','Reg','R1');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City1','C1');
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','N1'),
  ('b2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','N2');
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language) VALUES
  ('e1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','P1','Pan1','p1@t.l','1','b1000000-0000-0000-0000-000000000001','active','en'),
  ('e2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','P2','Pan2','p2@t.l','2','b2000000-0000-0000-0000-000000000002','active','en');
INSERT INTO public.carriers (id, account_id, code, name) VALUES ('ca000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','CA','Carrier');
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','PR','Prod',48);
INSERT INTO public.allocation_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date) VALUES
  ('cc000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','Plan','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2026-09-01','2026-09-30');
INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status) VALUES
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000002','2026-09-10',37,9,2026,'pending');
INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status) VALUES
  ('b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','2026-09-10','2026-09-12','vacation','active');

-- Actor autenticado de la misma cuenta, para que auth.uid()/la guarda multi-tenant resuelvan
-- (auth.uid() lee request.jwt.claim.sub via el shim de supabase:tests/00_bootstrap_supabase_shim.sql).
INSERT INTO auth.users (id, email) VALUES
  ('99000000-0000-0000-0000-000000000099','actor@test.local');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('99000000-0000-0000-0000-000000000099','actor@test.local','Actor','user','a0000000-0000-0000-0000-000000000001');
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
-- Propuesta reroute de envío (S1 -> N2), pending
INSERT INTO public.panelist_reassignment_proposal
  (id, account_id, unavailability_id, allocation_plan_detail_id, affected_role, sample_status_at_detection, suggested_action, suggested_target_node_id)
VALUES
  ('f1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','origin','pending','reroute','b2000000-0000-0000-0000-000000000002');

-- ---------- reroute aplica y cierra ----------
DO $$
DECLARE v_origin uuid; v_orig_orig uuid; v_status text; v_reason text;
BEGIN
  PERFORM apply_reassignment_proposal('f1000000-0000-0000-0000-000000000001','reroute','b2000000-0000-0000-0000-000000000002',NULL);
  SELECT origin_node_id, original_origin_node_id, reassignment_reason
    INTO v_origin, v_orig_orig, v_reason FROM allocation_plan_details WHERE id='d1000000-0000-0000-0000-000000000001';
  IF v_origin <> 'b2000000-0000-0000-0000-000000000002' THEN RAISE EXCEPTION 'FAIL: origin no cambió (% )', v_origin; END IF;
  IF v_orig_orig <> 'b1000000-0000-0000-0000-000000000001' THEN RAISE EXCEPTION 'FAIL: original_origin no guardado (% )', v_orig_orig; END IF;
  IF v_reason <> 'panelist_unavailable' THEN RAISE EXCEPTION 'FAIL: reason (% )', v_reason; END IF;
  SELECT status INTO v_status FROM panelist_reassignment_proposal WHERE id='f1000000-0000-0000-0000-000000000001';
  IF v_status <> 'confirmed' THEN RAISE EXCEPTION 'FAIL: propuesta no confirmed (% )', v_status; END IF;
  RAISE NOTICE 'PASS: reroute muta plan + guarda original + confirma propuesta';
END $$;

-- ---------- re-aplicar una propuesta ya confirmada falla ----------
DO $$ BEGIN
  BEGIN
    PERFORM apply_reassignment_proposal('f1000000-0000-0000-0000-000000000001','cancel',NULL,NULL);
    RAISE EXCEPTION 'FAIL: se pudo re-aplicar una propuesta confirmada';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: re-aplicar propuesta confirmada es rechazado (%)', SQLERRM;
  END;
END $$;

-- ---------- 'none' solo descarta, no muta ----------
INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status) VALUES
  ('d2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000001','2026-09-11',37,9,2026,'sent');
INSERT INTO public.panelist_reassignment_proposal
  (id, account_id, unavailability_id, allocation_plan_detail_id, affected_role, sample_status_at_detection, suggested_action)
VALUES
  ('f2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000002','destination','sent','none');
DO $$
DECLARE v_status text; v_dstatus text;
BEGIN
  PERFORM apply_reassignment_proposal('f2000000-0000-0000-0000-000000000002','none',NULL,NULL);
  SELECT status INTO v_status FROM panelist_reassignment_proposal WHERE id='f2000000-0000-0000-0000-000000000002';
  SELECT status INTO v_dstatus FROM allocation_plan_details WHERE id='d2000000-0000-0000-0000-000000000002';
  IF v_status <> 'dismissed' THEN RAISE EXCEPTION 'FAIL: none no marcó dismissed (% )', v_status; END IF;
  IF v_dstatus <> 'sent' THEN RAISE EXCEPTION 'FAIL: none mutó el plan (% )', v_dstatus; END IF;
  RAISE NOTICE 'PASS: none descarta sin mutar';
END $$;

ROLLBACK;
