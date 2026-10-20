-- Motor resolve_unavailability_incident: retrasar (paso 1), otro nodo de la ciudad (paso 2/2b),
-- propuesta al manager (incident_suggest), estado de la incidencia, aditivo/idempotente, guarda multi-tenant.
-- Cada escenario va en su propia transaccion (BEGIN ... ROLLBACK) con la fixture comun.
-- Las bajas se insertan ANTES que sus muestras: el trigger viejo (Tarea 6 lo sustituye) llama a la funcion
-- borrada y solo deja WARNING; el motor se llama siempre de forma explicita.
-- Fechas: 2027-03-08 es lunes; 2027-03-10 miercoles; 2027-04-01 jueves.
\set ON_ERROR_STOP on

-- ===== Utilidades de test (pg_temp: viven solo en esta sesion) =====
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
-- p_n muestras <nodo> -> N4 cada lunes entre p_from y p_to (satura el nodo esas semanas con p_n=8).
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
CREATE FUNCTION pg_temp.nlines() RETURNS integer LANGUAGE sql AS $$
  SELECT count(*)::int FROM public.panelist_reassignment_proposal
   WHERE unavailability_id = 'f0000000-0000-0000-0000-000000000001';
$$;

-- ===== Estructura: funcion vieja borrada, permisos =====
DO $$
BEGIN
  IF to_regprocedure('public.generate_reassignment_proposals(uuid)') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL generate_reassignment_proposals sigue existiendo'; END IF;
  IF NOT has_function_privilege('authenticated', 'public.resolve_unavailability_incident(uuid,numeric,numeric)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.resolve_unavailability_incident(uuid,numeric,numeric)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.incident_suggest(uuid,date,numeric,numeric)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.incident_suggest(uuid,date,numeric,numeric)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL faltan GRANT a authenticated/service_role'; END IF;
  IF has_function_privilege('anon', 'public.resolve_unavailability_incident(uuid,numeric,numeric)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.incident_suggest(uuid,date,numeric,numeric)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.incident_recompute_status(uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.incident_recompute_status(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL anon/authenticated con EXECUTE indebido'; END IF;
  RAISE NOTICE 'PASS estructura y permisos';
END $$;

-- ===== Sin muestras =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-12');
DO $$
DECLARE n int; u public.panelist_unavailability;
BEGIN
  n := pg_temp.run();
  u := pg_temp.inc();
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL sin muestras devuelve %', n; END IF;
  IF u.incident_status <> 'auto_resolved' THEN RAISE EXCEPTION 'FAIL sin muestras estado %', u.incident_status; END IF;
  IF u.auto_summary IS DISTINCT FROM 'shift=0;reroute=0;cancel=0;info=0;pending=0' THEN
    RAISE EXCEPTION 'FAIL sin muestras summary %', u.auto_summary; END IF;
  IF u.review_status <> 'reviewed' OR u.resolved_at IS NULL THEN RAISE EXCEPTION 'FAIL sin muestras review/resolved_at'; END IF;
  RAISE NOTICE 'PASS sin muestras';
END $$;
ROLLBACK;

-- ===== Baja inactiva: no hace nada =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-12','cancelled');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10','notified');
DO $$
BEGIN
  IF pg_temp.run() <> 0 OR pg_temp.nlines() <> 0 THEN RAISE EXCEPTION 'FAIL baja cancelada genera lineas'; END IF;
  IF (pg_temp.inc()).incident_status <> 'new' THEN RAISE EXCEPTION 'FAIL baja cancelada cambia estado'; END IF;
  RAISE NOTICE 'PASS baja no activa';
END $$;
ROLLBACK;

-- ===== Nodo sin panelista activo (P1 inactive) =====
BEGIN;
\ir fixtures/incident_city.sql
UPDATE public.panelists SET status='inactive' WHERE id='e1000000-0000-0000-0000-000000000001';
SELECT pg_temp.baja('2027-03-10','2027-03-12');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10','notified');
DO $$
BEGIN
  IF pg_temp.run() <> 0 OR pg_temp.nlines() <> 0 THEN RAISE EXCEPTION 'FAIL panelista inactivo genera lineas'; END IF;
  IF (pg_temp.inc()).incident_status <> 'auto_resolved' THEN RAISE EXCEPTION 'FAIL panelista inactivo estado'; END IF;
  IF (SELECT fecha_programada FROM public.allocation_plan_details WHERE id='d0000000-0000-0000-0000-000000000001') <> '2027-03-10' THEN
    RAISE EXCEPTION 'FAIL panelista inactivo toca la muestra'; END IF;
  RAISE NOTICE 'PASS nodo sin panelista activo';
END $$;
ROLLBACK;

-- ===== Paso 1: retrasar =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-12');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10','notified');
DO $$
DECLARE l public.panelist_reassignment_proposal; s record; u public.panelist_unavailability;
BEGIN
  IF pg_temp.run() <> 1 THEN RAISE EXCEPTION 'FAIL paso 1 no devuelve 1'; END IF;
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  SELECT * INTO s FROM public.allocation_plan_details WHERE id='d0000000-0000-0000-0000-000000000001';
  u := pg_temp.inc();
  IF l.status <> 'auto_resolved' OR l.final_action <> 'shift_date' OR l.final_date IS DISTINCT FROM '2027-03-15'::date
     OR l.affected_role <> 'origin' OR l.sample_status_at_detection <> 'notified' THEN
    RAISE EXCEPTION 'FAIL paso 1 linea % % % %', l.status, l.final_action, l.final_date, l.affected_role; END IF;
  IF s.status <> 'pending' OR s.fecha_programada <> '2027-03-15' OR s.original_fecha_programada IS DISTINCT FROM '2027-03-10'::date
     OR s.origin_node_id <> 'b1000000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'FAIL paso 1 muestra % % %', s.status, s.fecha_programada, s.original_fecha_programada; END IF;
  IF u.incident_status <> 'auto_resolved' OR u.auto_summary <> 'shift=1;reroute=0;cancel=0;info=0;pending=0'
     OR u.review_status <> 'reviewed' THEN
    RAISE EXCEPTION 'FAIL paso 1 incidencia % %', u.incident_status, u.auto_summary; END IF;
  RAISE NOTICE 'PASS paso 1 retrasar';
END $$;
ROLLBACK;

-- ===== Reparto por dias: dos muestras del mismo dia =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-12');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000002','N1','N4','2027-03-10');
DO $$
BEGIN
  IF pg_temp.run() <> 2 THEN RAISE EXCEPTION 'FAIL reparto no devuelve 2'; END IF;
  IF (pg_temp.line('d0000000-0000-0000-0000-000000000001')).final_date IS DISTINCT FROM '2027-03-15'::date
     OR (pg_temp.line('d0000000-0000-0000-0000-000000000002')).final_date IS DISTINCT FROM '2027-03-16'::date THEN
    RAISE EXCEPTION 'FAIL reparto fechas % %', (pg_temp.line('d0000000-0000-0000-0000-000000000001')).final_date,
      (pg_temp.line('d0000000-0000-0000-0000-000000000002')).final_date; END IF;
  RAISE NOTICE 'PASS reparto por dias';
END $$;
ROLLBACK;

-- ===== Baja que cruza fin de mes: muestras en dos meses =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-29','2027-04-02');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-30');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000002','N1','N4','2027-04-01');
DO $$
DECLARE l1 public.panelist_reassignment_proposal; l2 public.panelist_reassignment_proposal;
BEGIN
  IF pg_temp.run() <> 2 THEN RAISE EXCEPTION 'FAIL fin de mes no devuelve 2'; END IF;
  l1 := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  l2 := pg_temp.line('d0000000-0000-0000-0000-000000000002');
  -- Marzo: no hay dia de marzo tras el 02/04 -> otro nodo, misma fecha.
  IF l1.final_action <> 'reroute' OR l1.final_target_node_id IS DISTINCT FROM 'b2000000-0000-0000-0000-000000000002'::uuid
     OR l1.final_date IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL fin de mes marzo % % %', l1.final_action, l1.final_target_node_id, l1.final_date; END IF;
  -- Abril: primer laborable tras la baja dentro de abril.
  IF l2.final_action <> 'shift_date' OR l2.final_date IS DISTINCT FROM '2027-04-05'::date THEN
    RAISE EXCEPTION 'FAIL fin de mes abril % %', l2.final_action, l2.final_date; END IF;
  RAISE NOTICE 'PASS baja cruzando fin de mes';
END $$;
ROLLBACK;

-- ===== Paso 2: baja hasta fin de mes -> otro nodo =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-31');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10','notified');
DO $$
DECLARE l public.panelist_reassignment_proposal; s record;
BEGIN
  IF pg_temp.run() <> 1 THEN RAISE EXCEPTION 'FAIL paso 2 no devuelve 1'; END IF;
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  SELECT * INTO s FROM public.allocation_plan_details WHERE id='d0000000-0000-0000-0000-000000000001';
  IF l.status <> 'auto_resolved' OR l.final_action <> 'reroute'
     OR l.final_target_node_id IS DISTINCT FROM 'b2000000-0000-0000-0000-000000000002'::uuid OR l.final_date IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL paso 2 linea % % %', l.final_action, l.final_target_node_id, l.final_date; END IF;
  IF s.origin_node_id <> 'b2000000-0000-0000-0000-000000000002' OR s.original_origin_node_id IS DISTINCT FROM 'b1000000-0000-0000-0000-000000000001'::uuid
     OR s.origin_panelist_name IS DISTINCT FROM 'Pan2' OR s.fecha_programada <> '2027-03-10' OR s.status <> 'pending' THEN
    RAISE EXCEPTION 'FAIL paso 2 muestra % % %', s.origin_node_id, s.origin_panelist_name, s.fecha_programada; END IF;
  IF (pg_temp.inc()).auto_summary <> 'shift=0;reroute=1;cancel=0;info=0;pending=0' THEN
    RAISE EXCEPTION 'FAIL paso 2 summary %', (pg_temp.inc()).auto_summary; END IF;
  RAISE NOTICE 'PASS paso 2 otro nodo';
END $$;
ROLLBACK;

-- ===== Paso 2: nodo alternativo sin panelista activo se salta =====
BEGIN;
\ir fixtures/incident_city.sql
UPDATE public.panelists SET status='inactive' WHERE id='e2000000-0000-0000-0000-000000000002';
SELECT pg_temp.baja('2027-03-10','2027-03-31');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
DO $$
BEGIN
  PERFORM pg_temp.run();
  IF (pg_temp.line('d0000000-0000-0000-0000-000000000001')).final_target_node_id IS DISTINCT FROM 'b3000000-0000-0000-0000-000000000003'::uuid THEN
    RAISE EXCEPTION 'FAIL alternativo sin panelista: %', (pg_temp.line('d0000000-0000-0000-0000-000000000001')).final_target_node_id; END IF;
  RAISE NOTICE 'PASS alternativo sin panelista activo se salta';
END $$;
ROLLBACK;

-- ===== Paso 2: nunca crea origen = destino (muestra intra-ciudad N1->N2 y N2->N1) =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-31');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N2','2027-03-10');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000002','N2','N1','2027-03-10');
DO $$
DECLARE s1 record; s2 record;
BEGIN
  IF pg_temp.run() <> 2 THEN RAISE EXCEPTION 'FAIL intra-ciudad no devuelve 2'; END IF;
  SELECT * INTO s1 FROM public.allocation_plan_details WHERE id='d0000000-0000-0000-0000-000000000001';
  SELECT * INTO s2 FROM public.allocation_plan_details WHERE id='d0000000-0000-0000-0000-000000000002';
  IF s1.origin_node_id <> 'b3000000-0000-0000-0000-000000000003' OR s1.destination_node_id <> 'b2000000-0000-0000-0000-000000000002' THEN
    RAISE EXCEPTION 'FAIL intra-ciudad origen % -> %', s1.origin_node_id, s1.destination_node_id; END IF;
  IF s2.destination_node_id <> 'b3000000-0000-0000-0000-000000000003' OR s2.origin_node_id <> 'b2000000-0000-0000-0000-000000000002'
     OR s2.destination_panelist_name IS DISTINCT FROM 'Pan3' THEN
    RAISE EXCEPTION 'FAIL intra-ciudad destino % -> %', s2.origin_node_id, s2.destination_node_id; END IF;
  RAISE NOTICE 'PASS sin origen = destino';
END $$;
ROLLBACK;

-- ===== Reparto entre nodos: 4 muestras -> 2 N2 / 2 N3 =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-31');
SELECT pg_temp.mk(('d0000000-0000-0000-0000-00000000000' || i)::uuid,'N1','N4','2027-03-10') FROM generate_series(1,4) i;
DO $$
DECLARE c2 int; c3 int;
BEGIN
  IF pg_temp.run() <> 4 THEN RAISE EXCEPTION 'FAIL reparto nodos no devuelve 4'; END IF;
  SELECT count(*) FILTER (WHERE final_target_node_id='b2000000-0000-0000-0000-000000000002'),
         count(*) FILTER (WHERE final_target_node_id='b3000000-0000-0000-0000-000000000003')
    INTO c2, c3 FROM public.panelist_reassignment_proposal
   WHERE unavailability_id='f0000000-0000-0000-0000-000000000001' AND final_action='reroute' AND status='auto_resolved';
  IF c2 <> 2 OR c3 <> 2 THEN RAISE EXCEPTION 'FAIL reparto nodos N2=% N3=%', c2, c3; END IF;
  RAISE NOTICE 'PASS reparto entre nodos';
END $$;
ROLLBACK;

-- ===== Saturacion: N2/N3 saturados en la semana -> paso 2b otra semana de marzo =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-31');
SELECT pg_temp.fill('N2','2027-03-08','2027-03-08',8);
SELECT pg_temp.fill('N3','2027-03-08','2027-03-08',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
DO $$
DECLARE l public.panelist_reassignment_proposal; s record;
BEGIN
  IF pg_temp.run() <> 1 THEN RAISE EXCEPTION 'FAIL saturacion no devuelve 1'; END IF;
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  SELECT * INTO s FROM public.allocation_plan_details WHERE id='d0000000-0000-0000-0000-000000000001';
  IF l.status <> 'auto_resolved' OR l.final_action <> 'reroute'
     OR l.final_target_node_id NOT IN ('b2000000-0000-0000-0000-000000000002','b3000000-0000-0000-0000-000000000003')
     OR l.final_date IS NULL OR l.final_date BETWEEN '2027-03-08' AND '2027-03-14'
     OR date_trunc('month', l.final_date) <> '2027-03-01' OR extract(isodow FROM l.final_date) > 5 THEN
    RAISE EXCEPTION 'FAIL saturacion linea % % %', l.final_action, l.final_target_node_id, l.final_date; END IF;
  -- Mas cercana a la original (empate 05 vs 15 -> la mas temprana), menor carga -> N2.
  IF l.final_date <> '2027-03-05' OR l.final_target_node_id <> 'b2000000-0000-0000-0000-000000000002' THEN
    RAISE EXCEPTION 'FAIL saturacion eleccion % %', l.final_date, l.final_target_node_id; END IF;
  IF s.fecha_programada <> l.final_date OR s.origin_node_id <> l.final_target_node_id
     OR s.original_fecha_programada IS DISTINCT FROM '2027-03-10'::date THEN
    RAISE EXCEPTION 'FAIL saturacion muestra'; END IF;
  RAISE NOTICE 'PASS saturacion -> paso 2b';
END $$;
ROLLBACK;

-- ===== Pendiente + propuesta al manager; idempotencia y aditivo sobre pendientes =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-01','2027-03-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10','notified');
DO $$
DECLARE l public.panelist_reassignment_proposal; u public.panelist_unavailability; j jsonb; s record;
BEGIN
  IF pg_temp.run() <> 1 THEN RAISE EXCEPTION 'FAIL pendiente no devuelve 1'; END IF;
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  u := pg_temp.inc();
  SELECT * INTO s FROM public.allocation_plan_details WHERE id='d0000000-0000-0000-0000-000000000001';
  IF l.status <> 'pending' OR l.suggested_action <> 'shift_date' OR l.suggested_date IS DISTINCT FROM '2027-04-01'::date
     OR l.suggested_target_node_id IS NOT NULL OR l.suggested_reason IS DISTINCT FROM 'shift_later_week'
     OR l.final_action IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL pendiente linea % % % %', l.status, l.suggested_action, l.suggested_date, l.suggested_reason; END IF;
  IF s.fecha_programada <> '2027-03-10' OR s.status <> 'notified' THEN RAISE EXCEPTION 'FAIL pendiente toca la muestra'; END IF;
  IF u.incident_status <> 'pending_manager' OR u.review_status <> 'pending_review' OR u.resolved_at IS NOT NULL
     OR u.auto_summary <> 'shift=0;reroute=0;cancel=0;info=0;pending=1' THEN
    RAISE EXCEPTION 'FAIL pendiente incidencia % % %', u.incident_status, u.review_status, u.auto_summary; END IF;

  -- incident_suggest con semana dada (lunes o cualquier dia de la semana).
  j := public.incident_suggest(l.id, '2027-04-12');
  IF NOT (j->>'found')::boolean OR (j->>'date')::date <> '2027-04-12' OR (j->>'node_id')::uuid <> 'b1000000-0000-0000-0000-000000000001'
     OR j->>'node_code' <> 'N1' OR (j->>'load_after')::int <> 1 OR j->>'saturation_level' <> 'normal' THEN
    RAISE EXCEPTION 'FAIL suggest semana dada %', j; END IF;
  j := public.incident_suggest(l.id, '2027-04-14');
  IF (j->>'date')::date <> '2027-04-12' THEN RAISE EXCEPTION 'FAIL suggest semana a mitad %', j; END IF;
  -- Sin semana: misma propuesta que la guardada.
  j := public.incident_suggest(l.id);
  IF (j->>'date')::date <> '2027-04-01' OR (j->>'node_id')::uuid <> 'b1000000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'FAIL suggest sin semana %', j; END IF;
  -- Semana elegida por el manager: sin limite de horizonte.
  j := public.incident_suggest(l.id, '2027-06-07');
  IF (j->>'date')::date IS DISTINCT FROM '2027-06-07'::date THEN RAISE EXCEPTION 'FAIL suggest semana lejana %', j; END IF;
  -- Semana dentro de la baja y del mes de la muestra (ya agotado por el motor) -> found false.
  j := public.incident_suggest(l.id, '2027-03-15');
  IF (j->>'found')::boolean THEN RAISE EXCEPTION 'FAIL suggest semana dentro de la baja %', j; END IF;
  RAISE NOTICE 'PASS pendiente + propuesta + incident_suggest';
END $$;

-- Idempotencia sobre pendientes: misma linea (id) y nada nuevo.
CREATE TEMP TABLE snap AS SELECT id, allocation_plan_detail_id, status, suggested_date FROM public.panelist_reassignment_proposal;
DO $$
BEGIN
  IF pg_temp.run() <> 0 THEN RAISE EXCEPTION 'FAIL idempotencia pendiente devuelve <> 0'; END IF;
  IF EXISTS (SELECT id, allocation_plan_detail_id, status, suggested_date FROM public.panelist_reassignment_proposal
             EXCEPT SELECT * FROM snap)
     OR (SELECT count(*) FROM public.panelist_reassignment_proposal) <> (SELECT count(*) FROM snap) THEN
    RAISE EXCEPTION 'FAIL idempotencia pendiente cambia lineas'; END IF;
  RAISE NOTICE 'PASS idempotencia (pendiente)';
END $$;

-- Aditivo: muestra nueva dentro de la baja -> 1; mover la pendiente fuera -> su linea desaparece.
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000002','N1','N4','2027-03-11');
DO $$
DECLARE old_id uuid := (pg_temp.line('d0000000-0000-0000-0000-000000000001')).id;
BEGIN
  IF pg_temp.run() <> 1 THEN RAISE EXCEPTION 'FAIL aditivo muestra nueva no devuelve 1'; END IF;
  IF (pg_temp.line('d0000000-0000-0000-0000-000000000002')).status <> 'pending' THEN RAISE EXCEPTION 'FAIL aditivo nueva no pendiente'; END IF;
  IF (pg_temp.line('d0000000-0000-0000-0000-000000000001')).id <> old_id THEN RAISE EXCEPTION 'FAIL aditivo cambia id previo'; END IF;
  IF (pg_temp.inc()).auto_summary <> 'shift=0;reroute=0;cancel=0;info=0;pending=2' THEN
    RAISE EXCEPTION 'FAIL aditivo summary %', (pg_temp.inc()).auto_summary; END IF;

  UPDATE public.allocation_plan_details SET fecha_programada='2027-04-06' WHERE id='d0000000-0000-0000-0000-000000000001';
  IF pg_temp.run() <> 0 THEN RAISE EXCEPTION 'FAIL aditivo mover fuera devuelve <> 0'; END IF;
  IF (pg_temp.line('d0000000-0000-0000-0000-000000000001')).id IS NOT NULL THEN RAISE EXCEPTION 'FAIL aditivo linea movida sigue'; END IF;
  IF (pg_temp.inc()).incident_status <> 'pending_manager' THEN RAISE EXCEPTION 'FAIL aditivo estado tras mover'; END IF;

  -- La pendiente que queda sale (sent): su linea pendiente se retira y pasa a informativa.
  UPDATE public.allocation_plan_details SET status='sent' WHERE id='d0000000-0000-0000-0000-000000000002';
  IF pg_temp.run() <> 1 THEN RAISE EXCEPTION 'FAIL aditivo sent no devuelve 1'; END IF;
  IF (pg_temp.line('d0000000-0000-0000-0000-000000000002')).status <> 'info' OR pg_temp.nlines() <> 1 THEN
    RAISE EXCEPTION 'FAIL aditivo sent no queda info'; END IF;
  IF (pg_temp.inc()).incident_status <> 'auto_resolved' OR (pg_temp.inc()).review_status <> 'reviewed'
     OR (pg_temp.inc()).resolved_at IS NULL
     OR (pg_temp.inc()).auto_summary <> 'shift=0;reroute=0;cancel=0;info=1;pending=0' THEN
    RAISE EXCEPTION 'FAIL aditivo transicion a auto_resolved % %', (pg_temp.inc()).incident_status, (pg_temp.inc()).auto_summary; END IF;
  RAISE NOTICE 'PASS aditivo (alta, retirada, sent -> info, transicion de estado)';
END $$;
ROLLBACK;

-- ===== Propuesta en otro nodo (alt_node_later_week) =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-01','2027-03-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N1','2027-04-01','2027-04-01',8);
SELECT pg_temp.fill('N1','2027-04-05','2027-04-05',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
DO $$
DECLARE l public.panelist_reassignment_proposal;
BEGIN
  PERFORM pg_temp.run();
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  IF l.status <> 'pending' OR l.suggested_action <> 'reroute' OR l.suggested_date IS DISTINCT FROM '2027-04-05'::date
     OR l.suggested_target_node_id IS DISTINCT FROM 'b2000000-0000-0000-0000-000000000002'::uuid
     OR l.suggested_reason IS DISTINCT FROM 'alt_node_later_week' THEN
    RAISE EXCEPTION 'FAIL propuesta otro nodo % % % %', l.suggested_action, l.suggested_date, l.suggested_target_node_id, l.suggested_reason; END IF;
  RAISE NOTICE 'PASS propuesta en otro nodo';
END $$;
ROLLBACK;

-- ===== Sin hueco en 8 semanas -> cancel =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-05-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-06-07',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-06-07',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
DO $$
DECLARE l public.panelist_reassignment_proposal;
BEGIN
  IF pg_temp.run() <> 1 THEN RAISE EXCEPTION 'FAIL sin hueco no devuelve 1'; END IF;
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  IF l.status <> 'pending' OR l.suggested_action <> 'cancel' OR l.suggested_reason IS DISTINCT FROM 'no_slot_8_weeks'
     OR l.suggested_date IS NOT NULL OR l.suggested_target_node_id IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL sin hueco % % %', l.suggested_action, l.suggested_reason, l.suggested_date; END IF;
  IF (public.incident_suggest(l.id)->>'found')::boolean THEN RAISE EXCEPTION 'FAIL sin hueco suggest found'; END IF;
  IF (SELECT status FROM public.allocation_plan_details WHERE id='d0000000-0000-0000-0000-000000000001') <> 'pending' THEN
    RAISE EXCEPTION 'FAIL sin hueco anula la muestra (el motor no anula)'; END IF;
  RAISE NOTICE 'PASS sin hueco en 8 semanas';
END $$;
ROLLBACK;

-- ===== Baja larga: la propuesta puede ser otro nodo el mes siguiente aunque siga de baja =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-05-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
DO $$
DECLARE l public.panelist_reassignment_proposal;
BEGIN
  PERFORM pg_temp.run();
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  -- Semana del 29/03 sigue saturada para N2/N3 -> primera semana libre: 05/04, N2.
  IF l.suggested_action <> 'reroute' OR l.suggested_date IS DISTINCT FROM '2027-04-05'::date
     OR l.suggested_target_node_id IS DISTINCT FROM 'b2000000-0000-0000-0000-000000000002'::uuid THEN
    RAISE EXCEPTION 'FAIL baja larga propuesta % % %', l.suggested_action, l.suggested_date, l.suggested_target_node_id; END IF;
  RAISE NOTICE 'PASS baja larga -> otro nodo mes siguiente';
END $$;
ROLLBACK;

-- ===== Recepcion: paso 1 retrasa; baja a fin de mes -> otro destino =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-12');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N4','N1','2027-03-11');
DO $$
DECLARE l public.panelist_reassignment_proposal;
BEGIN
  IF pg_temp.run() <> 1 THEN RAISE EXCEPTION 'FAIL recepcion paso 1 no devuelve 1'; END IF;
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  IF l.affected_role <> 'destination' OR l.final_action <> 'shift_date' OR l.final_date IS DISTINCT FROM '2027-03-15'::date THEN
    RAISE EXCEPTION 'FAIL recepcion paso 1 % % %', l.affected_role, l.final_action, l.final_date; END IF;
  RAISE NOTICE 'PASS recepcion paso 1';
END $$;
ROLLBACK;

BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-31');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N4','N1','2027-03-11');
DO $$
DECLARE s record;
BEGIN
  IF pg_temp.run() <> 1 THEN RAISE EXCEPTION 'FAIL recepcion paso 2 no devuelve 1'; END IF;
  SELECT * INTO s FROM public.allocation_plan_details WHERE id='d0000000-0000-0000-0000-000000000001';
  IF s.destination_node_id <> 'b2000000-0000-0000-0000-000000000002' OR s.destination_panelist_name IS DISTINCT FROM 'Pan2'
     OR s.original_destination_node_id IS DISTINCT FROM 'b1000000-0000-0000-0000-000000000001'::uuid
     OR s.origin_node_id <> 'b4000000-0000-0000-0000-000000000004' THEN
    RAISE EXCEPTION 'FAIL recepcion paso 2 % %', s.destination_node_id, s.destination_panelist_name; END IF;
  IF (pg_temp.line('d0000000-0000-0000-0000-000000000001')).final_action <> 'reroute' THEN RAISE EXCEPTION 'FAIL recepcion paso 2 accion'; END IF;
  RAISE NOTICE 'PASS recepcion paso 2';
END $$;
ROLLBACK;

-- ===== Informativas (sent/received) y sin linea (cancelled/incident); idempotencia con cambios aplicados =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-12');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N4','N1','2027-03-11','sent');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000002','N1','N4','2027-03-10','sent');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000003','N1','N4','2027-03-10','received');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000004','N1','N4','2027-03-10','cancelled');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000005','N1','N4','2027-03-10','incident');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000006','N1','N4','2027-03-11','pending');
DO $$
DECLARE l public.panelist_reassignment_proposal; u public.panelist_unavailability;
BEGIN
  IF pg_temp.run() <> 4 THEN RAISE EXCEPTION 'FAIL informativas no devuelve 4 (3 info + 1 retraso)'; END IF;
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  IF l.status <> 'info' OR l.final_action <> 'none' OR l.suggested_action <> 'none' OR l.suggested_reason <> 'in_transit'
     OR l.affected_role <> 'destination' THEN
    RAISE EXCEPTION 'FAIL recepcion ya salida % % %', l.status, l.final_action, l.suggested_reason; END IF;
  l := pg_temp.line('d0000000-0000-0000-0000-000000000002');
  IF l.status <> 'info' OR l.final_action <> 'none' OR l.suggested_reason <> 'already_sent' OR l.sample_status_at_detection <> 'sent' THEN
    RAISE EXCEPTION 'FAIL origen sent % %', l.status, l.suggested_reason; END IF;
  IF (pg_temp.line('d0000000-0000-0000-0000-000000000003')).status <> 'info' THEN RAISE EXCEPTION 'FAIL received no info'; END IF;
  IF (pg_temp.line('d0000000-0000-0000-0000-000000000004')).id IS NOT NULL
     OR (pg_temp.line('d0000000-0000-0000-0000-000000000005')).id IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL cancelled/incident con linea'; END IF;
  IF (SELECT status FROM public.allocation_plan_details WHERE id='d0000000-0000-0000-0000-000000000001') <> 'sent' THEN
    RAISE EXCEPTION 'FAIL informativa toca la muestra'; END IF;
  u := pg_temp.inc();
  IF u.incident_status <> 'auto_resolved' OR u.auto_summary <> 'shift=1;reroute=0;cancel=0;info=3;pending=0' THEN
    RAISE EXCEPTION 'FAIL informativas incidencia % %', u.incident_status, u.auto_summary; END IF;
  RAISE NOTICE 'PASS informativas y sin linea';
END $$;
CREATE TEMP TABLE snap2 AS
  SELECT p.id, p.status, p.final_date, a.fecha_programada, a.origin_node_id
    FROM public.panelist_reassignment_proposal p JOIN public.allocation_plan_details a ON a.id = p.allocation_plan_detail_id;
DO $$
BEGIN
  IF pg_temp.run() <> 0 THEN RAISE EXCEPTION 'FAIL idempotencia devuelve <> 0'; END IF;
  IF EXISTS (SELECT p.id, p.status, p.final_date, a.fecha_programada, a.origin_node_id
               FROM public.panelist_reassignment_proposal p JOIN public.allocation_plan_details a ON a.id = p.allocation_plan_detail_id
             EXCEPT SELECT * FROM snap2)
     OR pg_temp.nlines() <> (SELECT count(*) FROM snap2) THEN
    RAISE EXCEPTION 'FAIL idempotencia cambia ids/fechas'; END IF;
  RAISE NOTICE 'PASS idempotencia (aplicadas + info)';
END $$;
ROLLBACK;

-- ===== Recompute: alguna manager_resolved y ninguna pendiente -> resolved =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-01','2027-03-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
DO $$
DECLARE r text;
BEGIN
  PERFORM pg_temp.run();
  PERFORM public.incident_apply_cancel((pg_temp.line('d0000000-0000-0000-0000-000000000001')).id, 'manager');
  r := public.incident_recompute_status('f0000000-0000-0000-0000-000000000001');
  IF r <> 'resolved' OR (pg_temp.inc()).incident_status <> 'resolved' OR (pg_temp.inc()).resolved_at IS NULL
     OR (pg_temp.inc()).review_status <> 'reviewed'
     OR (pg_temp.inc()).auto_summary <> 'shift=0;reroute=0;cancel=1;info=0;pending=0' THEN
    RAISE EXCEPTION 'FAIL recompute resolved % %', r, (pg_temp.inc()).auto_summary; END IF;
  RAISE NOTICE 'PASS recompute -> resolved';
END $$;
ROLLBACK;

-- ===== Cross-tenant =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-01','2027-03-31');
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
DO $$
DECLARE v_line uuid;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000098', true);
  BEGIN
    PERFORM pg_temp.run();
    RAISE EXCEPTION 'FAIL actor 98 ejecuta el motor de otra cuenta';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'Cross-tenant access denied%' THEN RAISE; END IF;
  END;
  IF pg_temp.nlines() <> 0 THEN RAISE EXCEPTION 'FAIL actor 98 dejo lineas'; END IF;
  PERFORM set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
  IF pg_temp.run() <> 1 THEN RAISE EXCEPTION 'FAIL actor 99 no ejecuta'; END IF;
  v_line := (pg_temp.line('d0000000-0000-0000-0000-000000000001')).id;
  IF (public.incident_suggest(v_line)->>'found') IS NULL THEN RAISE EXCEPTION 'FAIL actor 99 suggest'; END IF;
  PERFORM set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000098', true);
  BEGIN
    PERFORM public.incident_suggest(v_line);
    RAISE EXCEPTION 'FAIL actor 98 suggest de otra cuenta';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'Cross-tenant access denied%' THEN RAISE; END IF;
  END;
  PERFORM set_config('request.jwt.claim.sub','', true);
  RAISE NOTICE 'PASS cross-tenant';
END $$;
ROLLBACK;
