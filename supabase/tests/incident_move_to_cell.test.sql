-- Mover una muestra a una casilla nodo x semana: incident_suggest_cell (interna), suggest_for_cell y
-- apply_manager_move (publicas). Cada escenario va en su propia transaccion con la fixture comun.
-- Actor 99 = cuenta 1, 98 = cuenta 2. Umbral semanal por defecto: 6 * 1.3 = 7.8 -> cabe si carga <= 6.
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
-- Comprueba found:false con el motivo esperado.
CREATE FUNCTION pg_temp.expect_reason(j jsonb, p_reason text, p_label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF (j->>'found')::boolean IS DISTINCT FROM false OR j->>'reason' IS DISTINCT FROM p_reason THEN
    RAISE EXCEPTION 'FAIL % (esperaba %): %', p_label, p_reason, j; END IF;
END $$;

-- ===== Permisos =====
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.suggest_for_cell(uuid,uuid,date,numeric,numeric)',
    'public.apply_manager_move(uuid,uuid,date,numeric,numeric)'] LOOP
    IF NOT has_function_privilege('authenticated', f, 'EXECUTE') OR NOT has_function_privilege('service_role', f, 'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL falta GRANT en %', f; END IF;
    IF has_function_privilege('anon', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL anon con EXECUTE en %', f; END IF;
  END LOOP;
  IF has_function_privilege('anon', 'public.incident_suggest_cell(uuid,uuid,date,numeric,numeric)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.incident_suggest_cell(uuid,uuid,date,numeric,numeric)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL incident_suggest_cell ejecutable por anon/authenticated'; END IF;
  RAISE NOTICE 'PASS permisos';
END $$;

-- Escenario comun: baja de P1 (N1) todo marzo 2027, N2/N3 saturados en marzo (8 por semana, lunes).
--   d1: N1 -> N4 el 10/03 (otro extremo en otra ciudad).   d2: N1 -> N2 el 11/03 (intra-ciudad).
-- Ambas lineas (rol origen) quedan pendientes.

-- ===== Mismo nodo: semana posterior vacia -> lunes; si el lunes tiene mas muestras -> el dia mas vacio =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-01','2027-03-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10','notified');
SELECT public.resolve_unavailability_incident('f0000000-0000-0000-0000-000000000001');
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DO $$
DECLARE l public.panelist_reassignment_proposal; j jsonb; s public.allocation_plan_details;
BEGIN
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  IF l.status <> 'pending' THEN RAISE EXCEPTION 'FAIL precondicion linea %', l.status; END IF;

  -- Semana del 12/04 (se pasa un miercoles: se normaliza al lunes), vacia -> lunes 12/04.
  j := public.suggest_for_cell(l.id, 'b1000000-0000-0000-0000-000000000001', '2027-04-14');
  IF NOT (j->>'found')::boolean OR (j->>'date')::date <> '2027-04-12'
     OR (j->>'node_id')::uuid <> 'b1000000-0000-0000-0000-000000000001' OR j->>'node_code' <> 'N1'
     OR (j->>'load_after')::int <> 1 OR j->>'saturation_level' <> 'normal' OR NOT (j->>'same_node')::boolean THEN
    RAISE EXCEPTION 'FAIL mismo nodo semana vacia %', j; END IF;
  IF (pg_temp.line('d0000000-0000-0000-0000-000000000001')).status <> 'pending' THEN
    RAISE EXCEPTION 'FAIL suggest_for_cell escribe'; END IF;

  -- El lunes ya tiene una muestra de N1 -> martes 13/04.
  PERFORM pg_temp.mk(NULL, 'N1', 'N4', '2027-04-12');
  j := public.suggest_for_cell(l.id, 'b1000000-0000-0000-0000-000000000001', '2027-04-12');
  IF NOT (j->>'found')::boolean OR (j->>'date')::date <> '2027-04-13' OR (j->>'load_after')::int <> 2
     OR NOT (j->>'same_node')::boolean THEN
    RAISE EXCEPTION 'FAIL mismo nodo dia mas vacio %', j; END IF;

  -- Parametros nulos.
  PERFORM pg_temp.expect_err(format('SELECT public.apply_manager_move(%L,NULL,%L)', l.id, '2027-04-12'), 'Node and week required');
  PERFORM pg_temp.expect_err(format('SELECT public.apply_manager_move(%L,%L,NULL)', l.id, 'b1000000-0000-0000-0000-000000000001'), 'Node and week required');
  -- Semana sin hueco (N1 de baja en marzo): no cambia nada.
  PERFORM pg_temp.expect_err(format('SELECT public.apply_manager_move(%L,%L,%L)', l.id, 'b1000000-0000-0000-0000-000000000001', '2027-03-22'), 'Cannot move: no_day');
  IF (pg_temp.line('d0000000-0000-0000-0000-000000000001')).status <> 'pending' THEN RAISE EXCEPTION 'FAIL error muta la linea'; END IF;

  -- Aplicar: ultima linea pendiente -> incidencia resuelta.
  j := public.apply_manager_move(l.id, 'b1000000-0000-0000-0000-000000000001', '2027-04-12');
  s := pg_temp.smp('d0000000-0000-0000-0000-000000000001');
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  IF s.fecha_programada <> '2027-04-13' OR s.origin_node_id <> 'b1000000-0000-0000-0000-000000000001'
     OR s.original_fecha_programada <> '2027-03-10' OR s.original_origin_node_id IS NOT NULL OR s.status <> 'pending' THEN
    RAISE EXCEPTION 'FAIL mover mismo nodo muestra % % % %', s.fecha_programada, s.origin_node_id, s.original_fecha_programada, s.status; END IF;
  IF l.status <> 'manager_resolved' OR l.final_action <> 'shift_date' OR l.final_date <> '2027-04-13'
     OR l.final_target_node_id IS NOT NULL OR l.confirmed_by <> '99000000-0000-0000-0000-000000000099' THEN
    RAISE EXCEPTION 'FAIL mover mismo nodo linea % % %', l.status, l.final_action, l.final_date; END IF;
  IF NOT (j->>'ok')::boolean OR j->>'incident_status' <> 'resolved' OR j->>'final_action' <> 'shift_date'
     OR (j->>'final_date')::date <> '2027-04-13' OR j->'final_target_node_id' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'FAIL mover mismo nodo respuesta %', j; END IF;
  IF (pg_temp.inc()).incident_status <> 'resolved' OR (pg_temp.inc()).resolved_at IS NULL THEN
    RAISE EXCEPTION 'FAIL incidencia no resuelta'; END IF;

  -- Linea ya resuelta.
  PERFORM pg_temp.expect_reason(public.suggest_for_cell(l.id, 'b1000000-0000-0000-0000-000000000001', '2027-04-19'), 'not_pending', 'resuelta');
  PERFORM pg_temp.expect_err(format('SELECT public.apply_manager_move(%L,%L,%L)', l.id, 'b1000000-0000-0000-0000-000000000001', '2027-04-19'),
                             'Proposal ' || l.id || ' already manager_resolved');
  -- Linea inexistente.
  PERFORM pg_temp.expect_reason(public.suggest_for_cell(gen_random_uuid(), 'b1000000-0000-0000-0000-000000000001', '2027-04-19'), 'not_found', 'inexistente');
  RAISE NOTICE 'PASS mismo nodo (lunes, dia mas vacio, aplicar, resuelta, not_pending, not_found)';
END $$;
ROLLBACK;

-- ===== Otro nodo de la ciudad (reroute + fecha), otro extremo, otra ciudad, sin dia =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-01','2027-03-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000002','N1','N2','2027-03-11');
SELECT public.resolve_unavailability_incident('f0000000-0000-0000-0000-000000000001');
-- P3 (N3) de baja toda la semana del 19/04 (no tiene muestras: su incidencia no crea lineas).
INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status)
VALUES ('f0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001',
        'e3000000-0000-0000-0000-000000000003', '2027-04-19', '2027-04-25', 'vacation', 'active');
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DO $$
DECLARE l1 public.panelist_reassignment_proposal; l2 public.panelist_reassignment_proposal; j jsonb; s public.allocation_plan_details;
BEGIN
  l1 := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  l2 := pg_temp.line('d0000000-0000-0000-0000-000000000002');
  IF l1.status <> 'pending' OR l2.status <> 'pending' THEN RAISE EXCEPTION 'FAIL precondicion % %', l1.status, l2.status; END IF;

  -- Otro extremo: d2 va a N2 -> soltar en N2 dejaria origen = destino.
  PERFORM pg_temp.expect_reason(public.suggest_for_cell(l2.id, 'b2000000-0000-0000-0000-000000000002', '2027-04-12'), 'other_end', 'otro extremo');
  PERFORM pg_temp.expect_err(format('SELECT public.apply_manager_move(%L,%L,%L)', l2.id, 'b2000000-0000-0000-0000-000000000002', '2027-04-12'), 'Cannot move: other_end');
  -- Otra ciudad: N4 (C2). Tambien para d1, cuyo otro extremo es N4: other_city se mira antes.
  PERFORM pg_temp.expect_reason(public.suggest_for_cell(l2.id, 'b4000000-0000-0000-0000-000000000004', '2027-04-12'), 'other_city', 'otra ciudad d2');
  PERFORM pg_temp.expect_reason(public.suggest_for_cell(l1.id, 'b4000000-0000-0000-0000-000000000004', '2027-04-12'), 'other_city', 'otra ciudad d1');
  PERFORM pg_temp.expect_err(format('SELECT public.apply_manager_move(%L,%L,%L)', l1.id, 'b4000000-0000-0000-0000-000000000004', '2027-04-12'), 'Cannot move: other_city');
  -- Nodo saturado (N2 con 8 muestras la semana del 15/03).
  PERFORM pg_temp.expect_reason(public.suggest_for_cell(l1.id, 'b2000000-0000-0000-0000-000000000002', '2027-03-15'), 'no_day', 'saturado');
  -- Panelista del nodo destino (P3) de baja toda la semana.
  PERFORM pg_temp.expect_reason(public.suggest_for_cell(l1.id, 'b3000000-0000-0000-0000-000000000003', '2027-04-19'), 'no_day', 'destino de baja');
  -- El propio nodo de la baja, dentro de la baja.
  PERFORM pg_temp.expect_reason(public.suggest_for_cell(l1.id, 'b1000000-0000-0000-0000-000000000001', '2027-03-22'), 'no_day', 'nodo de la baja');
  -- Semana pasada.
  PERFORM pg_temp.expect_reason(public.suggest_for_cell(l1.id, 'b2000000-0000-0000-0000-000000000002', current_date - 14), 'no_day', 'semana pasada');
  -- Semana actual: nunca un dia anterior a hoy.
  j := public.suggest_for_cell(l1.id, 'b2000000-0000-0000-0000-000000000002', current_date);
  IF (j->>'found')::boolean AND (j->>'date')::date < current_date THEN RAISE EXCEPTION 'FAIL dia pasado %', j; END IF;

  -- Otro nodo de la ciudad: N2 la semana del 12/04 -> lunes 12/04, reencaminando.
  j := public.suggest_for_cell(l1.id, 'b2000000-0000-0000-0000-000000000002', '2027-04-12');
  IF NOT (j->>'found')::boolean OR (j->>'date')::date <> '2027-04-12'
     OR (j->>'node_id')::uuid <> 'b2000000-0000-0000-0000-000000000002' OR j->>'node_code' <> 'N2'
     OR (j->>'load_after')::int <> 1 OR j->>'saturation_level' <> 'normal' OR (j->>'same_node')::boolean THEN
    RAISE EXCEPTION 'FAIL otro nodo sugerencia %', j; END IF;

  j := public.apply_manager_move(l1.id, 'b2000000-0000-0000-0000-000000000002', '2027-04-12');
  s := pg_temp.smp('d0000000-0000-0000-0000-000000000001');
  l1 := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  IF s.origin_node_id <> 'b2000000-0000-0000-0000-000000000002' OR s.fecha_programada <> '2027-04-12'
     OR s.original_origin_node_id <> 'b1000000-0000-0000-0000-000000000001' OR s.original_fecha_programada <> '2027-03-10'
     OR s.destination_node_id <> 'b4000000-0000-0000-0000-000000000004' OR s.origin_panelist_name <> 'Pan2' THEN
    RAISE EXCEPTION 'FAIL reroute muestra % % % %', s.origin_node_id, s.fecha_programada, s.original_origin_node_id, s.origin_panelist_name; END IF;
  IF l1.status <> 'manager_resolved' OR l1.final_action <> 'reroute'
     OR l1.final_target_node_id <> 'b2000000-0000-0000-0000-000000000002' OR l1.final_date <> '2027-04-12' THEN
    RAISE EXCEPTION 'FAIL reroute linea % % %', l1.status, l1.final_action, l1.final_target_node_id; END IF;
  -- Queda d2 pendiente: la incidencia sigue esperando al manager.
  IF j->>'final_action' <> 'reroute' OR (j->>'final_target_node_id')::uuid <> 'b2000000-0000-0000-0000-000000000002'
     OR (j->>'final_date')::date <> '2027-04-12' OR j->>'incident_status' <> 'pending_manager' THEN
    RAISE EXCEPTION 'FAIL reroute respuesta %', j; END IF;

  -- d2 a N3 (misma ciudad, distinto del otro extremo) -> resuelve la incidencia.
  j := public.apply_manager_move(l2.id, 'b3000000-0000-0000-0000-000000000003', '2027-04-12');
  IF j->>'final_action' <> 'reroute' OR j->>'incident_status' <> 'resolved'
     OR (pg_temp.smp('d0000000-0000-0000-0000-000000000002')).origin_node_id <> 'b3000000-0000-0000-0000-000000000003' THEN
    RAISE EXCEPTION 'FAIL d2 a N3 %', j; END IF;
  RAISE NOTICE 'PASS otro nodo (reroute), other_end, other_city, no_day (saturado, baja, pasado)';
END $$;
ROLLBACK;

-- ===== Muestra ya enviada: sample_not_movable =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-01','2027-03-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
SELECT public.resolve_unavailability_incident('f0000000-0000-0000-0000-000000000001');
UPDATE public.allocation_plan_details SET status = 'sent' WHERE id = 'd0000000-0000-0000-0000-000000000001';
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
DO $$
DECLARE l public.panelist_reassignment_proposal;
BEGIN
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  IF l.status <> 'pending' THEN RAISE EXCEPTION 'FAIL precondicion %', l.status; END IF;
  PERFORM pg_temp.expect_reason(public.suggest_for_cell(l.id, 'b1000000-0000-0000-0000-000000000001', '2027-04-12'), 'sample_not_movable', 'enviada');
  PERFORM pg_temp.expect_err(format('SELECT public.apply_manager_move(%L,%L,%L)', l.id, 'b1000000-0000-0000-0000-000000000001', '2027-04-12'), 'Cannot move: sample_not_movable');
  RAISE NOTICE 'PASS sample_not_movable';
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
  PERFORM pg_temp.expect_err(format('SELECT public.suggest_for_cell(%L,%L,%L)', l, 'b1000000-0000-0000-0000-000000000001', '2027-04-12'), 'Cross-tenant access denied');
  PERFORM pg_temp.expect_err(format('SELECT public.apply_manager_move(%L,%L,%L)', l, 'b1000000-0000-0000-0000-000000000001', '2027-04-12'), 'Cross-tenant access denied');
  IF (pg_temp.line('d0000000-0000-0000-0000-000000000001')).status <> 'pending'
     OR (pg_temp.smp('d0000000-0000-0000-0000-000000000001')).fecha_programada <> '2027-03-10' THEN
    RAISE EXCEPTION 'FAIL cross-tenant muta'; END IF;
  PERFORM set_config('request.jwt.claim.sub','', true);
  RAISE NOTICE 'PASS cross-tenant';
END $$;
ROLLBACK;

-- ===== Envoltorios como rol authenticated =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-01','2027-03-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
SELECT public.resolve_unavailability_incident('f0000000-0000-0000-0000-000000000001');
SELECT (pg_temp.line('d0000000-0000-0000-0000-000000000001')).id AS lid \gset
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SET LOCAL ROLE authenticated;
SELECT set_config('t.sug', public.suggest_for_cell(:'lid', 'b2000000-0000-0000-0000-000000000002', '2027-04-12')->>'found', true);
SELECT set_config('t.st', public.apply_manager_move(:'lid', 'b2000000-0000-0000-0000-000000000002', '2027-04-12')->>'incident_status', true);
RESET ROLE;
DO $$
BEGIN
  IF current_setting('t.sug') <> 'true' THEN RAISE EXCEPTION 'FAIL suggest_for_cell como authenticated'; END IF;
  IF current_setting('t.st') <> 'resolved' THEN
    RAISE EXCEPTION 'FAIL apply_manager_move como authenticated (%)', current_setting('t.st'); END IF;
  RAISE NOTICE 'PASS envoltorios ejecutables como authenticated';
END $$;
ROLLBACK;
