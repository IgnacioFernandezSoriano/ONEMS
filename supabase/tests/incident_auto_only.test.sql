-- Bajas solo informativas (spec 2026-11-09): el motor resuelve TODAS las muestras afectadas.
-- Pasos 3 y 4 nuevos: si no cabe en el mes, se aplica la propuesta de incident_suggest (otra semana, mismo
-- nodo u otro de la ciudad) y, si no hay hueco en 8 semanas, se anula. Nunca queda una linea 'pending'.
-- Cada escenario va en su propia transaccion (BEGIN ... ROLLBACK) con la fixture comun y sin triggers.
-- Fechas: 2027-03-01, 03-08, 03-15, 03-22, 03-29, 04-05 son lunes; 2027-03-24 miercoles; 2027-04-01 jueves.
\set ON_ERROR_STOP on

-- ===== Utilidades de test (copiadas de resolve_unavailability_incident.test.sql) =====
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
-- p_n muestras <nodo> -> N4 cada 7 dias entre p_from y p_to (satura el nodo esas semanas con p_n=8).
CREATE FUNCTION pg_temp.fill(p_node text, p_from date, p_to date, p_n int)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE w date;
BEGIN
  FOR w IN SELECT g::date FROM generate_series(p_from, p_to, interval '7 day') g LOOP
    FOR i IN 1..p_n LOOP PERFORM pg_temp.mk(NULL, p_node, 'N4', w); END LOOP;
  END LOOP;
END $$;
-- Baja de P1 (id fijo f...01).
CREATE FUNCTION pg_temp.baja(p_start date, p_end date, p_status text DEFAULT 'active')
RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status)
  VALUES ('f0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',
          'e1000000-0000-0000-0000-000000000001', p_start, p_end, 'vacation', p_status);
$$;
CREATE FUNCTION pg_temp.run() RETURNS integer LANGUAGE sql AS $$
  SELECT public.resolve_unavailability_incident('f0000000-0000-0000-0000-000000000001');
$$;
CREATE FUNCTION pg_temp.line(p_detail uuid, p_role text DEFAULT NULL)
RETURNS public.panelist_reassignment_proposal LANGUAGE sql AS $$
  SELECT * FROM public.panelist_reassignment_proposal
   WHERE unavailability_id = 'f0000000-0000-0000-0000-000000000001'
     AND allocation_plan_detail_id = p_detail
     AND (p_role IS NULL OR affected_role = p_role);
$$;
CREATE FUNCTION pg_temp.inc() RETURNS public.panelist_unavailability LANGUAGE sql AS $$
  SELECT * FROM public.panelist_unavailability WHERE id = 'f0000000-0000-0000-0000-000000000001';
$$;
-- Linea 'pending' como las del motor viejo (insertada a mano, rol origen).
CREATE FUNCTION pg_temp.legacy_line(p_detail uuid) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.panelist_reassignment_proposal
    (account_id, unavailability_id, allocation_plan_detail_id, affected_role, sample_status_at_detection,
     suggested_action, suggested_reason, status)
  VALUES ('a0000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-000000000001', p_detail,
          'origin', 'pending', 'cancel', 'no_slot_8_weeks', 'pending')
  RETURNING id;
$$;
-- Comprobacion comun never_pending: ninguna linea pendiente y la baja nunca en pending_manager.
CREATE FUNCTION pg_temp.never_pending(p_scenario text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE n int; u public.panelist_unavailability;
BEGIN
  SELECT count(*) FILTER (WHERE status = 'pending') INTO n FROM public.panelist_reassignment_proposal
   WHERE unavailability_id = 'f0000000-0000-0000-0000-000000000001';
  u := pg_temp.inc();
  IF n <> 0 OR u.incident_status = 'pending_manager' THEN
    RAISE EXCEPTION 'FAIL never_pending (%) pendientes=% estado=%', p_scenario, n, u.incident_status; END IF;
  RAISE NOTICE 'PASS never_pending (%)', p_scenario;
END $$;

-- ===== later_week_same_node: no cabe en marzo -> semana siguiente, mismo nodo =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.baja('2027-03-22','2027-03-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-24');
DO $$
DECLARE l public.panelist_reassignment_proposal; s record; u public.panelist_unavailability;
BEGIN
  PERFORM pg_temp.run();
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  SELECT * INTO s FROM public.allocation_plan_details WHERE id='d0000000-0000-0000-0000-000000000001';
  u := pg_temp.inc();
  IF l.status <> 'auto_resolved' OR l.final_action IS DISTINCT FROM 'shift_date'
     OR l.final_date IS DISTINCT FROM '2027-04-01'::date OR l.suggested_reason IS DISTINCT FROM 'shift_later_week' THEN
    RAISE EXCEPTION 'FAIL later_week_same_node linea % % % %', l.status, l.final_action, l.final_date, l.suggested_reason; END IF;
  IF s.status <> 'pending' OR s.fecha_programada <> '2027-04-01'
     OR s.original_fecha_programada IS DISTINCT FROM '2027-03-24'::date
     OR s.origin_node_id <> 'b1000000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'FAIL later_week_same_node muestra % % %', s.status, s.fecha_programada, s.original_fecha_programada; END IF;
  IF u.incident_status <> 'auto_resolved' THEN RAISE EXCEPTION 'FAIL later_week_same_node estado %', u.incident_status; END IF;
  RAISE NOTICE 'PASS later_week_same_node';
END $$;
SELECT pg_temp.never_pending('later_week_same_node');
ROLLBACK;

-- ===== later_week_other_node: N1 tambien lleno la semana siguiente -> otro nodo de la ciudad =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.baja('2027-03-22','2027-03-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N1','2027-04-01','2027-05-27',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-24');
DO $$
DECLARE l public.panelist_reassignment_proposal; s record;
BEGIN
  PERFORM pg_temp.run();
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  SELECT * INTO s FROM public.allocation_plan_details WHERE id='d0000000-0000-0000-0000-000000000001';
  IF l.status <> 'auto_resolved' OR l.final_action IS DISTINCT FROM 'reroute'
     OR l.final_target_node_id IS DISTINCT FROM 'b2000000-0000-0000-0000-000000000002'::uuid
     OR l.final_date IS DISTINCT FROM '2027-04-05'::date OR l.suggested_reason IS DISTINCT FROM 'alt_node_later_week' THEN
    RAISE EXCEPTION 'FAIL later_week_other_node linea % % % % %', l.status, l.final_action, l.final_target_node_id,
      l.final_date, l.suggested_reason; END IF;
  IF s.origin_node_id <> 'b2000000-0000-0000-0000-000000000002' OR s.fecha_programada <> '2027-04-05'
     OR s.status <> 'pending' THEN
    RAISE EXCEPTION 'FAIL later_week_other_node muestra % % %', s.origin_node_id, s.fecha_programada, s.status; END IF;
  IF (pg_temp.inc()).incident_status <> 'auto_resolved' THEN
    RAISE EXCEPTION 'FAIL later_week_other_node estado %', (pg_temp.inc()).incident_status; END IF;
  RAISE NOTICE 'PASS later_week_other_node';
END $$;
SELECT pg_temp.never_pending('later_week_other_node');
ROLLBACK;

-- ===== cancel_no_slot: sin hueco en 8 semanas (hasta el 05-19) -> se anula =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.baja('2027-03-22','2027-03-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N1','2027-04-01','2027-05-27',8);
SELECT pg_temp.fill('N2','2027-04-05','2027-05-24',8);
SELECT pg_temp.fill('N3','2027-04-05','2027-05-24',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-24');
DO $$
DECLARE l public.panelist_reassignment_proposal; s record;
BEGIN
  PERFORM pg_temp.run();
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  SELECT * INTO s FROM public.allocation_plan_details WHERE id='d0000000-0000-0000-0000-000000000001';
  IF l.status <> 'auto_resolved' OR l.final_action IS DISTINCT FROM 'cancel'
     OR l.suggested_reason IS DISTINCT FROM 'no_slot_8_weeks' THEN
    RAISE EXCEPTION 'FAIL cancel_no_slot linea % % %', l.status, l.final_action, l.suggested_reason; END IF;
  IF s.status <> 'cancelled' OR s.fecha_programada <> '2027-03-24' THEN
    RAISE EXCEPTION 'FAIL cancel_no_slot muestra % %', s.status, s.fecha_programada; END IF;
  IF (pg_temp.inc()).incident_status <> 'auto_resolved'
     OR (pg_temp.inc()).auto_summary <> 'shift=0;reroute=0;cancel=1;info=0;pending=0' THEN
    RAISE EXCEPTION 'FAIL cancel_no_slot incidencia % %', (pg_temp.inc()).incident_status, (pg_temp.inc()).auto_summary; END IF;
  RAISE NOTICE 'PASS cancel_no_slot';
END $$;
SELECT pg_temp.never_pending('cancel_no_slot');
ROLLBACK;

-- ===== legacy_pending_line_resolved: linea pendiente del motor viejo -> se aplica la propuesta =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.baja('2027-03-22','2027-03-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N1','2027-04-01','2027-05-27',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-24');
SELECT pg_temp.legacy_line('d0000000-0000-0000-0000-000000000001');
DO $$
DECLARE l public.panelist_reassignment_proposal; s record; v_id uuid;
BEGIN
  v_id := (pg_temp.line('d0000000-0000-0000-0000-000000000001')).id;
  PERFORM pg_temp.run();
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  SELECT * INTO s FROM public.allocation_plan_details WHERE id='d0000000-0000-0000-0000-000000000001';
  IF l.id <> v_id THEN RAISE EXCEPTION 'FAIL legacy_pending_line_resolved: la linea vieja no se reutiliza'; END IF;
  IF l.status <> 'auto_resolved' OR l.final_action IS DISTINCT FROM 'reroute' OR l.final_date IS DISTINCT FROM '2027-04-05'::date THEN
    RAISE EXCEPTION 'FAIL legacy_pending_line_resolved linea % % %', l.status, l.final_action, l.final_date; END IF;
  IF s.fecha_programada <> '2027-04-05' OR s.origin_node_id <> 'b2000000-0000-0000-0000-000000000002' THEN
    RAISE EXCEPTION 'FAIL legacy_pending_line_resolved muestra % %', s.fecha_programada, s.origin_node_id; END IF;
  RAISE NOTICE 'PASS legacy_pending_line_resolved';
END $$;
SELECT pg_temp.never_pending('legacy_pending_line_resolved');
ROLLBACK;

-- ===== legacy_cancelled_line_info: linea pendiente sobre una muestra ya anulada (por otra baja) =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.baja('2027-03-22','2027-03-31');
-- updated_at fijo en el pasado: dentro de la transaccion now() es constante y no distinguiria un UPDATE.
INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, updated_at)
VALUES ('d0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-24','cancelled',
        '2026-01-01 00:00:00+00');
SELECT pg_temp.legacy_line('d0000000-0000-0000-0000-000000000001');
DO $$
DECLARE l public.panelist_reassignment_proposal; s record;
BEGIN
  PERFORM pg_temp.run();
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  SELECT * INTO s FROM public.allocation_plan_details WHERE id='d0000000-0000-0000-0000-000000000001';
  IF l.id IS NULL THEN RAISE EXCEPTION 'FAIL legacy_cancelled_line_info: la linea se ha borrado'; END IF;
  IF l.status <> 'info' OR l.final_action IS DISTINCT FROM 'none'
     OR l.suggested_reason IS DISTINCT FROM 'handled_by_other_incident' THEN
    RAISE EXCEPTION 'FAIL legacy_cancelled_line_info linea % % %', l.status, l.final_action, l.suggested_reason; END IF;
  IF s.status <> 'cancelled' OR s.updated_at <> '2026-01-01 00:00:00+00'::timestamptz OR s.reassigned_at IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL legacy_cancelled_line_info: la muestra ha cambiado % %', s.status, s.updated_at; END IF;
  IF (pg_temp.inc()).incident_status <> 'auto_resolved' THEN
    RAISE EXCEPTION 'FAIL legacy_cancelled_line_info estado %', (pg_temp.inc()).incident_status; END IF;
  RAISE NOTICE 'PASS legacy_cancelled_line_info';
END $$;
SELECT pg_temp.never_pending('legacy_cancelled_line_info');
ROLLBACK;

-- ===== engine_error_isolated: un fallo en una muestra no revierte las demas ni deja pendientes =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.baja('2027-03-22','2027-03-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N1','2027-04-01','2027-05-27',8);
SELECT pg_temp.fill('N2','2027-04-05','2027-05-24',8);
SELECT pg_temp.fill('N3','2027-04-05','2027-05-24',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-24');  -- X
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000002','N1','N4','2027-03-25');  -- Y
-- Trigger temporal (se deshace con el ROLLBACK): cualquier UPDATE de X falla.
CREATE FUNCTION public.tg_test_fail_x() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.id = 'd0000000-0000-0000-0000-000000000001' THEN RAISE EXCEPTION 'boom en X'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER test_fail_x BEFORE UPDATE ON public.allocation_plan_details
  FOR EACH ROW EXECUTE FUNCTION public.tg_test_fail_x();
DO $$
DECLARE lx public.panelist_reassignment_proposal; ly public.panelist_reassignment_proposal;
BEGIN
  PERFORM pg_temp.run();
  lx := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  ly := pg_temp.line('d0000000-0000-0000-0000-000000000002');
  IF lx.status <> 'info' OR lx.final_action IS DISTINCT FROM 'none' OR lx.suggested_reason IS DISTINCT FROM 'engine_error'
     OR COALESCE(lx.resolution_note, '') = '' THEN
    RAISE EXCEPTION 'FAIL engine_error_isolated X % % % %', lx.status, lx.final_action, lx.suggested_reason, lx.resolution_note; END IF;
  IF ly.status <> 'auto_resolved' OR ly.final_action IS DISTINCT FROM 'cancel' THEN
    RAISE EXCEPTION 'FAIL engine_error_isolated Y % %', ly.status, ly.final_action; END IF;
  IF (SELECT status FROM public.allocation_plan_details WHERE id='d0000000-0000-0000-0000-000000000001') <> 'pending'
     OR (SELECT status FROM public.allocation_plan_details WHERE id='d0000000-0000-0000-0000-000000000002') <> 'cancelled' THEN
    RAISE EXCEPTION 'FAIL engine_error_isolated estado de las muestras'; END IF;
  IF (pg_temp.inc()).incident_status <> 'auto_resolved' THEN
    RAISE EXCEPTION 'FAIL engine_error_isolated estado %', (pg_temp.inc()).incident_status; END IF;
  RAISE NOTICE 'PASS engine_error_isolated';
END $$;
SELECT pg_temp.never_pending('engine_error_isolated');
ROLLBACK;

-- ===== notified_today_resolved_sent_untouched: baja que empieza hoy (dia laborable) =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
CREATE TEMP TABLE d0 AS
  SELECT min(g::date) AS d FROM generate_series(current_date, current_date + 6, interval '1 day') g
   WHERE extract(isodow FROM g) BETWEEN 1 AND 5;
SELECT pg_temp.baja((SELECT d FROM d0), (SELECT d FROM d0));
SELECT pg_temp.mk('d0000000-0000-0000-0000-00000000000a','N1','N4',(SELECT d FROM d0),'notified');  -- A
INSERT INTO public.allocation_plan_details                                                         -- B
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, updated_at)
VALUES ('d0000000-0000-0000-0000-00000000000b','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004',(SELECT d FROM d0),'sent',
        '2026-01-01 00:00:00+00');
DO $$
DECLARE la public.panelist_reassignment_proposal; lb public.panelist_reassignment_proposal; a record; b record;
        v_d0 date := (SELECT d FROM d0);
BEGIN
  PERFORM pg_temp.run();
  la := pg_temp.line('d0000000-0000-0000-0000-00000000000a');
  lb := pg_temp.line('d0000000-0000-0000-0000-00000000000b');
  SELECT * INTO a FROM public.allocation_plan_details WHERE id='d0000000-0000-0000-0000-00000000000a';
  SELECT * INTO b FROM public.allocation_plan_details WHERE id='d0000000-0000-0000-0000-00000000000b';
  IF la.status <> 'auto_resolved' OR la.final_action NOT IN ('shift_date','reroute','cancel') THEN
    RAISE EXCEPTION 'FAIL notified_today A linea % %', la.status, la.final_action; END IF;
  IF NOT (a.status = 'cancelled'
          OR (a.status = 'pending' AND (a.fecha_programada <> v_d0
                                        OR a.origin_node_id <> 'b1000000-0000-0000-0000-000000000001'))) THEN
    RAISE EXCEPTION 'FAIL notified_today A muestra % % %', a.status, a.fecha_programada, a.origin_node_id; END IF;
  IF lb.status <> 'info' OR lb.final_action IS DISTINCT FROM 'none' OR lb.suggested_reason IS DISTINCT FROM 'already_sent' THEN
    RAISE EXCEPTION 'FAIL notified_today B linea % % %', lb.status, lb.final_action, lb.suggested_reason; END IF;
  IF b.status <> 'sent' OR b.fecha_programada <> v_d0 OR b.updated_at <> '2026-01-01 00:00:00+00'::timestamptz
     OR b.origin_node_id <> 'b1000000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'FAIL notified_today B muestra tocada % % %', b.status, b.fecha_programada, b.updated_at; END IF;
  RAISE NOTICE 'PASS notified_today_resolved_sent_untouched';
END $$;
SELECT pg_temp.never_pending('notified_today_resolved_sent_untouched');
ROLLBACK;

-- ===== Estructura: funcion nueva solo para service_role =====
DO $$
BEGIN
  IF to_regprocedure('public.incident_resolve_pending_lines(uuid,numeric,numeric)') IS NULL THEN
    RAISE EXCEPTION 'FAIL estructura: falta incident_resolve_pending_lines'; END IF;
  IF NOT has_function_privilege('service_role', 'public.incident_resolve_pending_lines(uuid,numeric,numeric)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.incident_resolve_pending_lines(uuid,numeric,numeric)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.incident_resolve_pending_lines(uuid,numeric,numeric)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL estructura: permisos de incident_resolve_pending_lines'; END IF;
  RAISE NOTICE 'PASS estructura y permisos';
END $$;
