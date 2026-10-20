-- RPCs del manager: suggest_for_week, apply_manager_decision, set_incident_resolution
-- + seguridad de apply_reassignment_proposal (nodo destino de la misma cuenta y ciudad).
-- Cada escenario va en su propia transaccion con la fixture comun. Actor 99 = cuenta 1, 98 = cuenta 2.
\set ON_ERROR_STOP on

CREATE FUNCTION pg_temp.mk(p_id uuid, p_o text, p_d text, p_date date, p_status text DEFAULT 'pending')
RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.allocation_plan_details
    (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
  SELECT COALESCE(p_id, gen_random_uuid()), 'a0000000-0000-0000-0000-000000000001',
         'cc000000-0000-0000-0000-000000000001', o.id, d.id, p_date, p_status
    FROM public.nodes o, public.nodes d
   WHERE o.auto_id = p_o AND d.auto_id = p_d
     AND o.account_id = 'a0000000-0000-0000-0000-000000000001'
     AND d.account_id = 'a0000000-0000-0000-0000-000000000001';
$$;
CREATE FUNCTION pg_temp.fill(p_node text, p_from date, p_to date, p_n int)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE w date;
BEGIN
  FOR w IN SELECT g::date FROM generate_series(p_from, p_to, interval '7 day') g LOOP
    FOR i IN 1..p_n LOOP PERFORM pg_temp.mk(NULL, p_node, 'N4', w); END LOOP;
  END LOOP;
END $$;
CREATE FUNCTION pg_temp.baja(p_start date, p_end date)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status)
  VALUES ('f0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',
          'e1000000-0000-0000-0000-000000000001', p_start, p_end, 'vacation', 'active');
$$;
CREATE FUNCTION pg_temp.line(p_detail uuid) RETURNS public.panelist_reassignment_proposal LANGUAGE sql AS $$
  SELECT * FROM public.panelist_reassignment_proposal
   WHERE unavailability_id = 'f0000000-0000-0000-0000-000000000001' AND allocation_plan_detail_id = p_detail;
$$;
CREATE FUNCTION pg_temp.inc() RETURNS public.panelist_unavailability LANGUAGE sql AS $$
  SELECT * FROM public.panelist_unavailability WHERE id = 'f0000000-0000-0000-0000-000000000001';
$$;
CREATE FUNCTION pg_temp.smp(p_id uuid) RETURNS public.allocation_plan_details LANGUAGE sql AS $$
  SELECT * FROM public.allocation_plan_details WHERE id = p_id;
$$;
-- Ejecuta la sentencia y espera un error que empiece por p_msg.
CREATE FUNCTION pg_temp.expect_err(p_sql text, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE p_msg || '%' THEN
      RAISE EXCEPTION 'FAIL error inesperado "%" (esperaba "%") en %', SQLERRM, p_msg, p_sql; END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL no fallo (esperaba "%"): %', p_msg, p_sql;
END $$;

-- ===== Permisos =====
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.suggest_for_week(uuid,date,numeric,numeric)',
    'public.apply_manager_decision(uuid,text,date,numeric,numeric)',
    'public.set_incident_resolution(uuid,text)'] LOOP
    IF NOT has_function_privilege('authenticated', f, 'EXECUTE') OR NOT has_function_privilege('service_role', f, 'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL falta GRANT en %', f; END IF;
    IF has_function_privilege('anon', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL anon con EXECUTE en %', f; END IF;
  END LOOP;
  IF has_function_privilege('anon', 'public.apply_reassignment_proposal(uuid,text,uuid,date)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL anon con EXECUTE en apply_reassignment_proposal'; END IF;
  -- Motor y propuesta: solo service_role (la web usa los envoltorios).
  IF has_function_privilege('authenticated', 'public.resolve_unavailability_incident(uuid,numeric,numeric)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.incident_suggest(uuid,date,numeric,numeric)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL authenticated con EXECUTE en motor/incident_suggest'; END IF;
  -- Heredadas: bulk sin uso -> nadie salvo service_role/owner; list_reroute_candidates solo authenticated (plan 2).
  IF has_function_privilege('authenticated', 'public.apply_reassignment_proposals_bulk(uuid)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.apply_reassignment_proposals_bulk(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL apply_reassignment_proposals_bulk ejecutable por anon/authenticated'; END IF;
  IF has_function_privilege('anon', 'public.list_reroute_candidates(uuid,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.list_reroute_candidates(uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL permisos de list_reroute_candidates'; END IF;
  RAISE NOTICE 'PASS permisos';
END $$;

-- ===== Escenario base: semana elegida, doble llamada, resolucion, estado =====
-- Marzo saturado en N2/N3 -> la muestra del 10/03 (N1) queda pendiente con propuesta.
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-01','2027-03-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10','notified');
SELECT public.resolve_unavailability_incident('f0000000-0000-0000-0000-000000000001');
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DO $$
DECLARE l public.panelist_reassignment_proposal; j jsonb; s public.allocation_plan_details; u public.panelist_unavailability;
BEGIN
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  IF l.status <> 'pending' THEN RAISE EXCEPTION 'FAIL precondicion linea %', l.status; END IF;

  j := public.suggest_for_week(l.id, '2027-04-12');
  IF NOT (j->>'found')::boolean OR (j->>'date')::date <> '2027-04-12' THEN RAISE EXCEPTION 'FAIL suggest_for_week %', j; END IF;
  IF (pg_temp.line('d0000000-0000-0000-0000-000000000001')).status <> 'pending' THEN
    RAISE EXCEPTION 'FAIL suggest_for_week escribe'; END IF;

  -- Decision desconocida y semana sin hueco / sin semana: no cambian nada.
  PERFORM pg_temp.expect_err(format('SELECT public.apply_manager_decision(%L,%L)', l.id, 'bogus'), 'Unknown decision');
  PERFORM pg_temp.expect_err(format('SELECT public.apply_manager_decision(%L,%L,%L)', l.id, 'week', '2027-03-15'), 'No slot in week');
  PERFORM pg_temp.expect_err(format('SELECT public.apply_manager_decision(%L,%L)', l.id, 'week'), 'Week start required');
  IF (pg_temp.line('d0000000-0000-0000-0000-000000000001')).status <> 'pending' THEN RAISE EXCEPTION 'FAIL error muta la linea'; END IF;

  j := public.apply_manager_decision(l.id, 'week', '2027-04-12');
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  s := pg_temp.smp('d0000000-0000-0000-0000-000000000001');
  u := pg_temp.inc();
  IF s.fecha_programada <> '2027-04-12' OR s.plan_id <> 'cc000000-0000-0000-0000-000000000001' OR s.status <> 'pending'
     OR s.origin_node_id <> 'b1000000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'FAIL week muestra % % %', s.fecha_programada, s.plan_id, s.status; END IF;
  IF l.status <> 'manager_resolved' OR l.final_action <> 'shift_date' OR l.confirmed_by <> '99000000-0000-0000-0000-000000000099' THEN
    RAISE EXCEPTION 'FAIL week linea % % %', l.status, l.final_action, l.confirmed_by; END IF;
  IF NOT (j->>'ok')::boolean OR j->>'incident_status' <> 'resolved' OR j->>'final_action' <> 'shift_date'
     OR (j->>'final_date')::date <> '2027-04-12' OR j->'final_target_node_id' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'FAIL week respuesta %', j; END IF;
  IF u.incident_status <> 'resolved' OR u.resolved_at IS NULL OR u.review_status <> 'reviewed' THEN
    RAISE EXCEPTION 'FAIL week baja % %', u.incident_status, u.review_status; END IF;

  -- Segunda llamada sobre la misma linea.
  PERFORM pg_temp.expect_err(format('SELECT public.apply_manager_decision(%L,%L)', l.id, 'accept'),
                             'Proposal ' || l.id || ' already manager_resolved');
  PERFORM pg_temp.expect_err(format('SELECT public.apply_manager_decision(%L,%L)', l.id, 'cancel'), 'Proposal');
  IF (pg_temp.smp('d0000000-0000-0000-0000-000000000001')).fecha_programada <> '2027-04-12' THEN RAISE EXCEPTION 'FAIL doble llamada muta'; END IF;

  PERFORM public.set_incident_resolution('f0000000-0000-0000-0000-000000000001', 'Hablado con el panelista');
  u := pg_temp.inc();
  IF u.final_resolution <> 'Hablado con el panelista' OR u.updated_by <> '99000000-0000-0000-0000-000000000099' THEN
    RAISE EXCEPTION 'FAIL set_incident_resolution % %', u.final_resolution, u.updated_by; END IF;
  RAISE NOTICE 'PASS escenario base (week, doble llamada, resolucion)';
END $$;
ROLLBACK;

-- ===== accept (shift_date), cancel, varias lineas y recompute, info =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-01','2027-03-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000002','N1','N4','2027-03-11');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000003','N1','N4','2027-03-12','sent');
SELECT public.resolve_unavailability_incident('f0000000-0000-0000-0000-000000000001');
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DO $$
DECLARE l1 public.panelist_reassignment_proposal; l2 public.panelist_reassignment_proposal; l3 public.panelist_reassignment_proposal;
        j jsonb; u public.panelist_unavailability;
BEGIN
  l1 := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  l2 := pg_temp.line('d0000000-0000-0000-0000-000000000002');
  l3 := pg_temp.line('d0000000-0000-0000-0000-000000000003');
  IF l1.status <> 'pending' OR l2.status <> 'pending' OR l3.status <> 'info' THEN RAISE EXCEPTION 'FAIL precondicion'; END IF;

  -- info: no se puede decidir.
  PERFORM pg_temp.expect_err(format('SELECT public.apply_manager_decision(%L,%L)', l3.id, 'accept'), 'Proposal ' || l3.id || ' already info');

  -- accept con propuesta sin fecha ni nodo.
  UPDATE public.panelist_reassignment_proposal SET suggested_action='shift_date', suggested_date=NULL, suggested_target_node_id=NULL WHERE id=l1.id;
  PERFORM pg_temp.expect_err(format('SELECT public.apply_manager_decision(%L,%L)', l1.id, 'accept'), 'Proposal has no actionable suggestion');
  UPDATE public.panelist_reassignment_proposal SET suggested_date=l2.suggested_date WHERE id=l1.id;

  -- accept: aplica suggested_date; queda otra pendiente -> baja sigue pending_manager.
  j := public.apply_manager_decision(l1.id, 'accept');
  IF (pg_temp.smp('d0000000-0000-0000-0000-000000000001')).fecha_programada <> l2.suggested_date
     OR (j->>'final_action') <> 'shift_date' OR j->>'incident_status' <> 'pending_manager' THEN
    RAISE EXCEPTION 'FAIL accept % %', j, (pg_temp.smp('d0000000-0000-0000-0000-000000000001')).fecha_programada; END IF;
  IF (pg_temp.inc()).resolved_at IS NOT NULL THEN RAISE EXCEPTION 'FAIL baja resuelta con pendientes'; END IF;

  -- cancel: ultima pendiente -> resolved.
  j := public.apply_manager_decision(l2.id, 'cancel');
  IF (pg_temp.smp('d0000000-0000-0000-0000-000000000002')).status <> 'cancelled'
     OR (pg_temp.line('d0000000-0000-0000-0000-000000000002')).final_action <> 'cancel'
     OR (pg_temp.line('d0000000-0000-0000-0000-000000000002')).status <> 'manager_resolved'
     OR j->>'final_action' <> 'cancel' OR j->>'incident_status' <> 'resolved' THEN
    RAISE EXCEPTION 'FAIL cancel %', j; END IF;
  u := pg_temp.inc();
  IF u.incident_status <> 'resolved' OR u.resolved_at IS NULL OR u.review_status <> 'reviewed' THEN RAISE EXCEPTION 'FAIL baja tras ultima pendiente'; END IF;
  RAISE NOTICE 'PASS accept, cancel, info, sin accion, recompute';
END $$;
ROLLBACK;

-- ===== accept con propuesta de otro nodo (reroute) =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-01','2027-03-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N1','2027-04-01','2027-04-01',8);
SELECT pg_temp.fill('N1','2027-04-05','2027-04-05',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
SELECT public.resolve_unavailability_incident('f0000000-0000-0000-0000-000000000001');
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DO $$
DECLARE l public.panelist_reassignment_proposal; j jsonb; s public.allocation_plan_details;
BEGIN
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  IF l.suggested_action <> 'reroute' THEN RAISE EXCEPTION 'FAIL precondicion reroute %', l.suggested_action; END IF;
  j := public.apply_manager_decision(l.id, 'accept');
  s := pg_temp.smp('d0000000-0000-0000-0000-000000000001');
  IF s.origin_node_id <> 'b2000000-0000-0000-0000-000000000002' OR s.fecha_programada <> '2027-04-05'
     OR j->>'final_action' <> 'reroute' OR (j->>'final_target_node_id')::uuid <> 'b2000000-0000-0000-0000-000000000002' THEN
    RAISE EXCEPTION 'FAIL accept reroute % %', j, s.origin_node_id; END IF;
  RAISE NOTICE 'PASS accept reroute';
END $$;
ROLLBACK;

-- ===== accept con suggested_action cancel =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-05-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-06-07',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-06-07',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
SELECT public.resolve_unavailability_incident('f0000000-0000-0000-0000-000000000001');
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DO $$
DECLARE l public.panelist_reassignment_proposal; j jsonb;
BEGIN
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  IF l.suggested_action <> 'cancel' THEN RAISE EXCEPTION 'FAIL precondicion cancel %', l.suggested_action; END IF;
  j := public.apply_manager_decision(l.id, 'accept');
  IF (pg_temp.smp('d0000000-0000-0000-0000-000000000001')).status <> 'cancelled' OR j->>'final_action' <> 'cancel' THEN
    RAISE EXCEPTION 'FAIL accept cancel %', j; END IF;
  RAISE NOTICE 'PASS accept con suggested_action cancel';
END $$;
ROLLBACK;

-- ===== Cross-tenant (actor 98) =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-01','2027-03-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
SELECT public.resolve_unavailability_incident('f0000000-0000-0000-0000-000000000001');
DO $$
DECLARE l uuid := (pg_temp.line('d0000000-0000-0000-0000-000000000001')).id;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000098', true);
  PERFORM pg_temp.expect_err(format('SELECT public.suggest_for_week(%L,%L)', l, '2027-04-12'), 'Cross-tenant access denied');
  PERFORM pg_temp.expect_err(format('SELECT public.apply_manager_decision(%L,%L)', l, 'cancel'), 'Cross-tenant access denied');
  PERFORM pg_temp.expect_err(format('SELECT public.set_incident_resolution(%L,%L)', 'f0000000-0000-0000-0000-000000000001', 'x'), 'Cross-tenant access denied');
  IF (pg_temp.line('d0000000-0000-0000-0000-000000000001')).status <> 'pending'
     OR (pg_temp.inc()).final_resolution IS NOT NULL THEN RAISE EXCEPTION 'FAIL cross-tenant muta'; END IF;
  PERFORM set_config('request.jwt.claim.sub','', true);
  RAISE NOTICE 'PASS cross-tenant';
END $$;
ROLLBACK;

-- ===== Seguridad apply_reassignment_proposal: nodo destino =====
BEGIN;
\ir fixtures/incident_city.sql
INSERT INTO public.regions (id, account_id, name, code) VALUES
  ('e0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','Reg2','R2');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c9000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','CityX','CX');
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b9000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000002','c9000000-0000-0000-0000-000000000009','NX');
SELECT pg_temp.baja('2027-03-01','2027-03-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
SELECT public.resolve_unavailability_incident('f0000000-0000-0000-0000-000000000001');
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DO $$
DECLARE l uuid := (pg_temp.line('d0000000-0000-0000-0000-000000000001')).id;
BEGIN
  PERFORM pg_temp.expect_err(format('SELECT public.apply_reassignment_proposal(%L,%L,%L,NULL)', l, 'reroute', 'b9000000-0000-0000-0000-000000000009'), 'Target node not allowed');
  PERFORM pg_temp.expect_err(format('SELECT public.apply_reassignment_proposal(%L,%L,%L,NULL)', l, 'reroute', 'b4000000-0000-0000-0000-000000000004'), 'Target node not allowed');
  PERFORM pg_temp.expect_err(format('SELECT public.apply_reassignment_proposal(%L,%L,%L,NULL)', l, 'manual', 'b4000000-0000-0000-0000-000000000004'), 'Target node not allowed');
  IF (pg_temp.line('d0000000-0000-0000-0000-000000000001')).status <> 'pending'
     OR (pg_temp.smp('d0000000-0000-0000-0000-000000000001')).origin_node_id <> 'b1000000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'FAIL nodo no permitido muta'; END IF;
  PERFORM public.apply_reassignment_proposal(l, 'reroute', 'b2000000-0000-0000-0000-000000000002', NULL);
  IF (pg_temp.smp('d0000000-0000-0000-0000-000000000001')).origin_node_id <> 'b2000000-0000-0000-0000-000000000002'
     OR (pg_temp.line('d0000000-0000-0000-0000-000000000001')).status <> 'manager_resolved' THEN
    RAISE EXCEPTION 'FAIL nodo valido no aplica'; END IF;
  RAISE NOTICE 'PASS apply_reassignment_proposal valida nodo destino';
END $$;
ROLLBACK;

-- ===== Envoltorios como rol authenticated (sin EXECUTE directo sobre motor / incident_suggest) =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-01','2027-03-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10','notified');
SELECT public.resolve_unavailability_incident('f0000000-0000-0000-0000-000000000001');
SELECT (pg_temp.line('d0000000-0000-0000-0000-000000000001')).id AS lid \gset
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SET LOCAL ROLE authenticated;
SELECT set_config('t.sug', public.suggest_for_week(:'lid', '2027-04-12')->>'found', true);
SELECT set_config('t.st', public.apply_manager_decision(:'lid', 'accept')->>'incident_status', true);
RESET ROLE;
DO $$
BEGIN
  IF current_setting('t.sug') <> 'true' THEN RAISE EXCEPTION 'FAIL suggest_for_week como authenticated'; END IF;
  IF current_setting('t.st') <> 'resolved' THEN
    RAISE EXCEPTION 'FAIL apply_manager_decision como authenticated (%)', current_setting('t.st'); END IF;
  RAISE NOTICE 'PASS envoltorios ejecutables como authenticated';
END $$;
ROLLBACK;
