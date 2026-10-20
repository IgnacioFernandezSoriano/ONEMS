-- Triggers de incidencias de indisponibilidad (Tarea 6):
--   tg_unavailability_incident      -> alta de baja dispara el motor; cancelacion revierte y cierra.
--   tg_refresh_incidents_on_plan_change -> INSERT/UPDATE (fecha/origen/destino) del plan re-ejecuta el motor
--                                          para las bajas activas tocadas; ignora cambios con reassigned_at
--                                          cambiado y los hechos dentro del motor (guarda de re-entrada).
-- Cada escenario va en su propia transaccion (BEGIN ... ROLLBACK) con la fixture comun.
-- Aqui NO se llama al motor a mano salvo donde se indica: todo lo hacen los triggers.
-- Fechas: 2027-03-08 es lunes; 2027-03-10 miercoles; 2027-04-05 lunes; 2027-04-12 lunes.
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
-- p_n muestras <nodo> -> N4 cada lunes entre p_from y p_to, en UNA sola sentencia.
CREATE FUNCTION pg_temp.fill(p_node text, p_from date, p_to date, p_n int)
RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.allocation_plan_details
    (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
  SELECT gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
         o.id, d.id, w::date, 'pending'
    FROM generate_series(p_from, p_to, interval '7 day') w, generate_series(1, p_n) i,
         public.nodes o, public.nodes d
   WHERE o.auto_id = p_node AND d.auto_id = 'N4'
     AND o.account_id = 'a0000000-0000-0000-0000-000000000001'
     AND d.account_id = 'a0000000-0000-0000-0000-000000000001';
$$;
-- Baja de P1 (id fijo f...01).
CREATE FUNCTION pg_temp.baja(p_start date, p_end date, p_status text DEFAULT 'active')
RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status)
  VALUES ('f0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',
          'e1000000-0000-0000-0000-000000000001', p_start, p_end, 'vacation', p_status);
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
CREATE FUNCTION pg_temp.s(p_id uuid) RETURNS public.allocation_plan_details LANGUAGE sql AS $$
  SELECT * FROM public.allocation_plan_details WHERE id = p_id;
$$;
-- Dia laborable de la semana actual: hoy si es lunes..viernes; si no, el lunes de esta semana.
CREATE FUNCTION pg_temp.dday() RETURNS date LANGUAGE sql AS $$
  SELECT CASE WHEN extract(isodow FROM current_date) <= 5 THEN current_date
              ELSE date_trunc('week', current_date)::date END;
$$;
CREATE FUNCTION pg_temp.eom() RETURNS date LANGUAGE sql AS $$
  SELECT (date_trunc('month', pg_temp.dday()) + interval '1 month - 1 day')::date;
$$;
-- Avisos 'revert' como "Nombre:rol,..." ordenado por nombre (NULL si no hay).
CREATE FUNCTION pg_temp.revert_roles() RETURNS text LANGUAGE sql AS $$
  SELECT string_agg(p.name || ':' || (n.payload->>'recipient_role'), ',' ORDER BY p.name)
    FROM public.panelist_notification n JOIN public.panelists p ON p.id = n.panelist_id
   WHERE n.payload->>'change' = 'revert';
$$;

-- ===== Estructura: trigger viejo fuera, triggers nuevos, permisos =====
DO $$
DECLARE f text;
BEGIN
  IF to_regprocedure('public.tg_generate_proposals_on_unavailability()') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL tg_generate_proposals_on_unavailability sigue existiendo'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_proc p ON p.oid = t.tgfoid
                  WHERE t.tgrelid = 'public.panelist_unavailability'::regclass
                    AND t.tgname = 'generate_proposals_on_unavailability_trigger'
                    AND p.proname = 'tg_unavailability_incident' AND NOT t.tgisinternal) THEN
    RAISE EXCEPTION 'FAIL falta trigger de baja con tg_unavailability_incident'; END IF;
  -- Triggers de sentencia (tgtype bit 0 = ROW; 0 -> STATEMENT) en el plan, con tablas de transicion.
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.allocation_plan_details'::regclass
                    AND t.tgname = 'refresh_incidents_on_plan_insert' AND (t.tgtype & 1) = 0
                    AND t.tgnewtable IS NOT NULL) THEN
    RAISE EXCEPTION 'FAIL falta refresh_incidents_on_plan_insert (sentencia + new table)'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.allocation_plan_details'::regclass
                    AND t.tgname = 'refresh_incidents_on_plan_update' AND (t.tgtype & 1) = 0
                    AND t.tgnewtable IS NOT NULL AND t.tgoldtable IS NOT NULL) THEN
    RAISE EXCEPTION 'FAIL falta refresh_incidents_on_plan_update (sentencia + old/new table)'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.panelist_unavailability'::regclass
                    AND t.tgname = 'check_unavailability_panelist_account' AND NOT t.tgisinternal) THEN
    RAISE EXCEPTION 'FAIL falta check_unavailability_panelist_account'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'revert_on_unavailability_delete' AND NOT tgisinternal)
     OR NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgname = 'recompute_incidents_on_plan_delete'
                       AND (t.tgtype & 1) = 0 AND t.tgoldtable IS NOT NULL) THEN
    RAISE EXCEPTION 'FAIL faltan triggers de borrado'; END IF;
  FOREACH f IN ARRAY ARRAY['public.tg_unavailability_incident()', 'public.tg_refresh_incidents_on_plan_change()',
                           'public.tg_unavailability_check_panelist_account()',
                           'public.incident_enqueue_revert(uuid,date,uuid,uuid)',
                           'public.incident_revert_unavailability(uuid,boolean)', 'public.tg_unavailability_delete()',
                           'public.tg_recompute_incidents_on_plan_delete()'] LOOP
    IF has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL % ejecutable por anon/authenticated', f; END IF;
    IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = f::regprocedure) THEN
      RAISE EXCEPTION 'FAIL % no es SECURITY DEFINER', f; END IF;
  END LOOP;
  RAISE NOTICE 'PASS estructura y permisos';
END $$;

-- ===== Alta dispara el motor (muestra antes que la baja) =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
SELECT pg_temp.baja('2027-03-10','2027-03-12');
DO $$
DECLARE l public.panelist_reassignment_proposal;
BEGIN
  l := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  IF l.id IS NULL OR l.status <> 'auto_resolved' OR l.final_action <> 'shift_date' THEN
    RAISE EXCEPTION 'FAIL alta: linea % %', l.status, l.final_action; END IF;
  IF (pg_temp.s('d0000000-0000-0000-0000-000000000001')).fecha_programada <> '2027-03-15' THEN
    RAISE EXCEPTION 'FAIL alta: muestra no retrasada'; END IF;
  IF (pg_temp.inc()).incident_status <> 'auto_resolved' THEN
    RAISE EXCEPTION 'FAIL alta: estado %', (pg_temp.inc()).incident_status; END IF;
  RAISE NOTICE 'PASS alta dispara el motor';
END $$;
ROLLBACK;

-- ===== Plan despues de la baja: INSERT multi-fila, mover dentro =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-12');
DO $$
BEGIN
  IF pg_temp.nlines() <> 0 OR (pg_temp.inc()).incident_status <> 'auto_resolved' THEN
    RAISE EXCEPTION 'FAIL baja sin muestras: % %', pg_temp.nlines(), (pg_temp.inc()).incident_status; END IF;
END $$;
INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
VALUES
  ('d0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-10','pending'),
  ('d0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
   'b4000000-0000-0000-0000-000000000004','b1000000-0000-0000-0000-000000000001','2027-03-11','pending'),
  ('d0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-20','pending');
DO $$
BEGIN
  IF pg_temp.nlines() <> 2 THEN RAISE EXCEPTION 'FAIL insert multi-fila: % lineas', pg_temp.nlines(); END IF;
  IF (pg_temp.line('d0000000-0000-0000-0000-000000000001','origin')).status <> 'auto_resolved'
     OR (pg_temp.line('d0000000-0000-0000-0000-000000000002','destination')).status <> 'auto_resolved'
     OR (pg_temp.line('d0000000-0000-0000-0000-000000000003')).id IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL insert multi-fila: lineas incorrectas'; END IF;
  IF (pg_temp.inc()).incident_status <> 'auto_resolved'
     OR (pg_temp.inc()).auto_summary <> 'shift=2;reroute=0;cancel=0;info=0;pending=0' THEN
    RAISE EXCEPTION 'FAIL insert multi-fila: estado % %', (pg_temp.inc()).incident_status, (pg_temp.inc()).auto_summary; END IF;
  RAISE NOTICE 'PASS plan despues de la baja (insert multi-fila)';
END $$;
-- Mover la 3a dentro de la baja (cambio del usuario: reassigned_at no cambia).
UPDATE public.allocation_plan_details SET fecha_programada = '2027-03-11' WHERE id = 'd0000000-0000-0000-0000-000000000003';
DO $$
BEGIN
  IF pg_temp.nlines() <> 3 OR (pg_temp.line('d0000000-0000-0000-0000-000000000003')).status <> 'auto_resolved' THEN
    RAISE EXCEPTION 'FAIL mover dentro: % lineas', pg_temp.nlines(); END IF;
  IF (pg_temp.inc()).auto_summary <> 'shift=3;reroute=0;cancel=0;info=0;pending=0' THEN
    RAISE EXCEPTION 'FAIL mover dentro: summary %', (pg_temp.inc()).auto_summary; END IF;
  RAISE NOTICE 'PASS mover muestra dentro';
END $$;
ROLLBACK;

-- ===== Escenario saturado: mover fuera, status solo, reassigned_at cambiado, guarda de re-entrada =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-12');
SELECT pg_temp.fill('N1','2027-03-15','2027-03-29',8);
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
DO $$
BEGIN
  IF pg_temp.nlines() <> 1 OR (pg_temp.line('d0000000-0000-0000-0000-000000000001')).status <> 'pending' THEN
    RAISE EXCEPTION 'FAIL saturado: no queda pendiente (% lineas)', pg_temp.nlines(); END IF;
  IF (pg_temp.inc()).incident_status <> 'pending_manager' THEN
    RAISE EXCEPTION 'FAIL saturado: estado %', (pg_temp.inc()).incident_status; END IF;
END $$;

-- Guarda de re-entrada: con onems.in_incident_engine='on' el trigger del plan no hace nada.
SELECT set_config('onems.in_incident_engine', 'on', true);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000002','N1','N4','2027-03-11');
SELECT set_config('onems.in_incident_engine', '', true);
DO $$
BEGIN
  IF pg_temp.nlines() <> 1 THEN RAISE EXCEPTION 'FAIL guarda re-entrada: el trigger creo lineas (%)', pg_temp.nlines(); END IF;
  RAISE NOTICE 'PASS guarda de re-entrada';
END $$;

-- Cambio de status solo: sin reaccion (la muestra 2 seguiria sin linea si el motor no corre).
UPDATE public.allocation_plan_details SET status = 'notified' WHERE id IN ('d0000000-0000-0000-0000-000000000001','d0000000-0000-0000-0000-000000000002');
DO $$
BEGIN
  IF pg_temp.nlines() <> 1 OR (pg_temp.line('d0000000-0000-0000-0000-000000000002')).id IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL status solo: reaccion (% lineas)', pg_temp.nlines(); END IF;
  RAISE NOTICE 'PASS cambio de status solo sin reaccion';
END $$;

-- UPDATE con reassigned_at cambiado (simula manager/motor): sin reaccion aunque cambie la fecha.
UPDATE public.allocation_plan_details SET fecha_programada = '2027-03-12', reassigned_at = now()
 WHERE id = 'd0000000-0000-0000-0000-000000000002';
DO $$
BEGIN
  IF pg_temp.nlines() <> 1 THEN RAISE EXCEPTION 'FAIL reassigned_at cambiado: reaccion (% lineas)', pg_temp.nlines(); END IF;
  RAISE NOTICE 'PASS reassigned_at cambiado sin reaccion';
END $$;

-- Control positivo: cambio de fecha del usuario (reassigned_at igual) -> el motor si ve la muestra 2.
UPDATE public.allocation_plan_details SET fecha_programada = '2027-03-11' WHERE id = 'd0000000-0000-0000-0000-000000000002';
DO $$
BEGIN
  IF pg_temp.nlines() <> 2 OR (pg_temp.line('d0000000-0000-0000-0000-000000000002')).status <> 'pending' THEN
    RAISE EXCEPTION 'FAIL control positivo: % lineas', pg_temp.nlines(); END IF;
  IF (pg_temp.inc()).auto_summary <> 'shift=0;reroute=0;cancel=0;info=0;pending=2' THEN
    RAISE EXCEPTION 'FAIL control positivo: summary %', (pg_temp.inc()).auto_summary; END IF;
  RAISE NOTICE 'PASS control positivo (cambio del usuario)';
END $$;

-- Mover fuera: la pendiente pasa al 25/03 (fuera de la baja) -> su linea desaparece.
UPDATE public.allocation_plan_details SET fecha_programada = '2027-03-25' WHERE id = 'd0000000-0000-0000-0000-000000000001';
DO $$
BEGIN
  IF (pg_temp.line('d0000000-0000-0000-0000-000000000001')).id IS NOT NULL OR pg_temp.nlines() <> 1 THEN
    RAISE EXCEPTION 'FAIL mover fuera: la linea sigue (% lineas)', pg_temp.nlines(); END IF;
  IF (pg_temp.inc()).auto_summary <> 'shift=0;reroute=0;cancel=0;info=0;pending=1' THEN
    RAISE EXCEPTION 'FAIL mover fuera: summary %', (pg_temp.inc()).auto_summary; END IF;
  RAISE NOTICE 'PASS mover muestra fuera';
END $$;

-- Cambio de nodo del usuario: la pendiente 2 pasa a origen N4 -> ya no es de N1 -> linea retirada.
UPDATE public.allocation_plan_details SET origin_node_id = 'b4000000-0000-0000-0000-000000000004'
 WHERE id = 'd0000000-0000-0000-0000-000000000002';
DO $$
BEGIN
  IF pg_temp.nlines() <> 0 OR (pg_temp.inc()).incident_status <> 'auto_resolved' THEN
    RAISE EXCEPTION 'FAIL cambio de nodo: % lineas, estado %', pg_temp.nlines(), (pg_temp.inc()).incident_status; END IF;
  RAISE NOTICE 'PASS cambio de nodo (posicion antigua) retira la linea';
END $$;
-- (fecha_programada es NOT NULL en el esquema: no hay caso de fecha NULL que probar.)
ROLLBACK;

-- ===== Bajas no vigentes o inactivas no se recalculan =====
BEGIN;
\ir fixtures/incident_city.sql
-- Baja pasada (end_date < hoy): el trigger del plan la ignora.
INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status)
VALUES ('f0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',
        'e1000000-0000-0000-0000-000000000001', current_date - 30, current_date - 20, 'vacation', 'active');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4', current_date - 25);
DO $$
BEGIN
  IF pg_temp.nlines() <> 0 THEN RAISE EXCEPTION 'FAIL baja pasada recalculada (% lineas)', pg_temp.nlines(); END IF;
  RAISE NOTICE 'PASS baja pasada ignorada';
END $$;
ROLLBACK;

-- ===== El trigger nunca bloquea el plan =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-12');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-20');
SAVEPOINT sp1;
DROP FUNCTION public.incident_find_shift_date(uuid, date, date, numeric, numeric);
-- Mover dentro: el motor falla por dentro -> WARNING, la sentencia NO falla.
UPDATE public.allocation_plan_details SET fecha_programada = '2027-03-10' WHERE id = 'd0000000-0000-0000-0000-000000000001';
DO $$
BEGIN
  IF (pg_temp.s('d0000000-0000-0000-0000-000000000001')).fecha_programada <> '2027-03-10' THEN
    RAISE EXCEPTION 'FAIL no bloquea: el UPDATE no se guardo'; END IF;
  RAISE NOTICE 'PASS trigger del plan no bloquea (motor roto)';
END $$;
-- Alta de otra baja con el motor roto: tampoco bloquea.
INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status)
VALUES ('f0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001',
        'e2000000-0000-0000-0000-000000000002', '2027-03-10', '2027-03-12', 'vacation', 'active');
ROLLBACK TO SAVEPOINT sp1;
SAVEPOINT sp2;
-- Fallo fuera del motor (la consulta de seleccion del propio trigger): tampoco bloquea.
ALTER TABLE public.panelist_unavailability RENAME COLUMN end_date TO end_date_x;
UPDATE public.allocation_plan_details SET fecha_programada = '2027-03-11' WHERE id = 'd0000000-0000-0000-0000-000000000001';
INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
VALUES ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-11','pending');
DO $$
BEGIN
  IF (pg_temp.s('d0000000-0000-0000-0000-000000000001')).fecha_programada <> '2027-03-11' THEN
    RAISE EXCEPTION 'FAIL no bloquea (seleccion rota): el UPDATE no se guardo'; END IF;
  RAISE NOTICE 'PASS trigger del plan no bloquea (seleccion rota)';
END $$;
ROLLBACK TO SAVEPOINT sp2;
ROLLBACK;

-- ===== Camino de fallo del motor: una muestra falla, la siguiente sigue =====
BEGIN;
\ir fixtures/incident_city.sql
CREATE FUNCTION public.tg_test_boom() RETURNS trigger LANGUAGE plpgsql AS $f$
BEGIN
  IF NEW.id = 'd0000000-0000-0000-0000-000000000001' THEN RAISE EXCEPTION 'boom'; END IF;
  RETURN NEW;
END $f$;
CREATE TRIGGER test_boom BEFORE UPDATE ON public.allocation_plan_details
  FOR EACH ROW EXECUTE FUNCTION public.tg_test_boom();
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000002','N1','N4','2027-03-10');
SELECT pg_temp.baja('2027-03-10','2027-03-12');
DO $$
DECLARE l1 public.panelist_reassignment_proposal; l2 public.panelist_reassignment_proposal;
BEGIN
  l1 := pg_temp.line('d0000000-0000-0000-0000-000000000001');
  l2 := pg_temp.line('d0000000-0000-0000-0000-000000000002');
  IF l1.status IS DISTINCT FROM 'pending' OR l1.suggested_action IS NULL OR l1.suggested_date IS NULL
     OR l1.suggested_reason IS NULL OR l1.final_action IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL camino de fallo: linea fallida % % %', l1.status, l1.suggested_action, l1.suggested_date; END IF;
  IF (pg_temp.s('d0000000-0000-0000-0000-000000000001')).fecha_programada <> '2027-03-10' THEN
    RAISE EXCEPTION 'FAIL camino de fallo: muestra fallida tocada'; END IF;
  IF l2.status IS DISTINCT FROM 'auto_resolved' OR l2.final_action <> 'shift_date' THEN
    RAISE EXCEPTION 'FAIL camino de fallo: la siguiente no siguio (% %)', l2.status, l2.final_action; END IF;
  IF (pg_temp.inc()).incident_status <> 'pending_manager' THEN
    RAISE EXCEPTION 'FAIL camino de fallo: estado %', (pg_temp.inc()).incident_status; END IF;
  RAISE NOTICE 'PASS camino de fallo del motor (por muestra)';
END $$;
ROLLBACK;

-- ===== Cancelar baja: revierte auto y manager, descarta pendientes, cierra =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-12');
-- A: retraso automatico 10/03 -> 15/03.
SELECT pg_temp.mk('da000000-0000-0000-0000-00000000000a','N1','N4','2027-03-10');
-- N1 saturado el resto de marzo (y la semana del 12/04) -> B: reencaminado automatico N1 -> N2.
SELECT pg_temp.fill('N1','2027-03-15','2027-03-29',8);
SELECT pg_temp.fill('N1','2027-04-12','2027-04-12',8);
SELECT pg_temp.mk('db000000-0000-0000-0000-00000000000b','N1','N4','2027-03-11');
-- N2/N3 saturados todo marzo -> C, D, E, F (una sola sentencia) quedan pendientes.
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
SELECT v.id::uuid, 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
       'b1000000-0000-0000-0000-000000000001', 'b4000000-0000-0000-0000-000000000004', '2027-03-10', 'pending'
  FROM (VALUES ('dc000000-0000-0000-0000-00000000000c'), ('dd000000-0000-0000-0000-00000000000d'),
               ('de000000-0000-0000-0000-00000000000e'), ('df000000-0000-0000-0000-00000000000f')) v(id);
-- G: anulada por otra via (sin reassignment_reason): sin linea, no se toca.
SELECT pg_temp.mk('d9000000-0000-0000-0000-000000000009','N1','N4','2027-03-10','cancelled');
DO $$
DECLARE r record;
BEGIN
  IF (pg_temp.line('da000000-0000-0000-0000-00000000000a')).final_action IS DISTINCT FROM 'shift_date'
     OR (pg_temp.line('db000000-0000-0000-0000-00000000000b')).final_action IS DISTINCT FROM 'reroute'
     OR (pg_temp.line('db000000-0000-0000-0000-00000000000b')).final_target_node_id IS DISTINCT FROM 'b2000000-0000-0000-0000-000000000002'::uuid THEN
    RAISE EXCEPTION 'FAIL preparacion: A/B no resueltas como se esperaba'; END IF;
  FOR r IN SELECT unnest(ARRAY['dc000000-0000-0000-0000-00000000000c','dd000000-0000-0000-0000-00000000000d',
                               'de000000-0000-0000-0000-00000000000e','df000000-0000-0000-0000-00000000000f']::uuid[]) AS id LOOP
    IF (pg_temp.line(r.id)).status IS DISTINCT FROM 'pending' THEN RAISE EXCEPTION 'FAIL preparacion: % no pendiente', r.id; END IF;
  END LOOP;
  IF (pg_temp.line('d9000000-0000-0000-0000-000000000009')).id IS NOT NULL THEN RAISE EXCEPTION 'FAIL preparacion: G con linea'; END IF;
END $$;
-- Manager (actor 99): C acepta (retraso 05/04), D otra semana (12/04: N1 lleno -> N2 el 12/04), E anula.
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT public.apply_manager_decision((pg_temp.line('dc000000-0000-0000-0000-00000000000c')).id, 'accept');
SELECT public.apply_manager_decision((pg_temp.line('dd000000-0000-0000-0000-00000000000d')).id, 'week', '2027-04-12');
SELECT public.apply_manager_decision((pg_temp.line('de000000-0000-0000-0000-00000000000e')).id, 'cancel');
SELECT set_config('request.jwt.claim.sub','', true);
CREATE TEMP TABLE pre_lines AS
  SELECT id, allocation_plan_detail_id, status FROM public.panelist_reassignment_proposal
   WHERE unavailability_id = 'f0000000-0000-0000-0000-000000000001';
DO $$
DECLARE c record; d record; e record;
BEGIN
  c := pg_temp.s('dc000000-0000-0000-0000-00000000000c');
  d := pg_temp.s('dd000000-0000-0000-0000-00000000000d');
  e := pg_temp.s('de000000-0000-0000-0000-00000000000e');
  IF (pg_temp.line(c.id)).status <> 'manager_resolved' OR (pg_temp.line(c.id)).final_action <> 'shift_date'
     OR c.fecha_programada <> '2027-04-05' THEN
    RAISE EXCEPTION 'FAIL preparacion C % %', (pg_temp.line(c.id)).final_action, c.fecha_programada; END IF;
  IF (pg_temp.line(d.id)).status <> 'manager_resolved' OR (pg_temp.line(d.id)).final_action <> 'reroute'
     OR d.origin_node_id <> 'b2000000-0000-0000-0000-000000000002' OR d.fecha_programada <> '2027-04-12' THEN
    RAISE EXCEPTION 'FAIL preparacion D % % %', (pg_temp.line(d.id)).final_action, d.origin_node_id, d.fecha_programada; END IF;
  IF (pg_temp.line(e.id)).status <> 'manager_resolved' OR e.status <> 'cancelled' THEN
    RAISE EXCEPTION 'FAIL preparacion E'; END IF;
  IF (SELECT count(*) FROM pre_lines) <> 6 THEN RAISE EXCEPTION 'FAIL preparacion: % lineas', (SELECT count(*) FROM pre_lines); END IF;
END $$;

-- Cancelar la baja.
UPDATE public.panelist_unavailability SET status = 'cancelled' WHERE id = 'f0000000-0000-0000-0000-000000000001';
DO $$
DECLARE a record; b record; c record; d record; e record; f record; g record; u public.panelist_unavailability;
BEGIN
  a := pg_temp.s('da000000-0000-0000-0000-00000000000a');
  b := pg_temp.s('db000000-0000-0000-0000-00000000000b');
  c := pg_temp.s('dc000000-0000-0000-0000-00000000000c');
  d := pg_temp.s('dd000000-0000-0000-0000-00000000000d');
  e := pg_temp.s('de000000-0000-0000-0000-00000000000e');
  f := pg_temp.s('df000000-0000-0000-0000-00000000000f');
  g := pg_temp.s('d9000000-0000-0000-0000-000000000009');
  u := pg_temp.inc();
  -- A: retraso automatico revertido.
  IF a.fecha_programada <> '2027-03-10' OR a.original_fecha_programada IS NOT NULL
     OR a.reassignment_reason IS NOT NULL OR a.reassigned_at IS NOT NULL OR a.reassigned_by IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL cancelar A % %', a.fecha_programada, a.original_fecha_programada; END IF;
  -- B: reencaminado automatico revertido (nodo, original_* y nombre del panelista).
  IF b.origin_node_id <> 'b1000000-0000-0000-0000-000000000001' OR b.original_origin_node_id IS NOT NULL
     OR b.origin_panelist_name IS DISTINCT FROM 'Pan1' OR b.fecha_programada <> '2027-03-11'
     OR b.reassigned_at IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL cancelar B % % %', b.origin_node_id, b.original_origin_node_id, b.origin_panelist_name; END IF;
  -- C: retraso del manager revertido.
  IF c.fecha_programada <> '2027-03-10' OR c.original_fecha_programada IS NOT NULL OR c.reassigned_by IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL cancelar C % %', c.fecha_programada, c.original_fecha_programada; END IF;
  -- D: reencaminado + cambio de fecha del manager revertidos.
  IF d.origin_node_id <> 'b1000000-0000-0000-0000-000000000001' OR d.original_origin_node_id IS NOT NULL
     OR d.fecha_programada <> '2027-03-10' OR d.original_fecha_programada IS NOT NULL
     OR d.origin_panelist_name IS DISTINCT FROM 'Pan1' THEN
    RAISE EXCEPTION 'FAIL cancelar D % % %', d.origin_node_id, d.fecha_programada, d.origin_panelist_name; END IF;
  -- E: anulacion del manager -> vuelve a pending.
  IF e.status <> 'pending' OR e.reassignment_reason IS NOT NULL OR e.reassigned_at IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL cancelar E % %', e.status, e.reassignment_reason; END IF;
  -- F: pendiente -> linea descartada, muestra intacta.
  IF (pg_temp.line(f.id)).status <> 'dismissed' OR f.fecha_programada <> '2027-03-10' OR f.status <> 'pending' THEN
    RAISE EXCEPTION 'FAIL cancelar F % %', (pg_temp.line(f.id)).status, f.status; END IF;
  -- G: anulada por otra via -> sigue anulada.
  IF g.status <> 'cancelled' THEN RAISE EXCEPTION 'FAIL cancelar G %', g.status; END IF;
  -- Lineas: las resueltas conservan su estado; todas con resolution_note.
  IF EXISTS (SELECT 1 FROM public.panelist_reassignment_proposal
              WHERE unavailability_id = 'f0000000-0000-0000-0000-000000000001'
                AND resolution_note IS DISTINCT FROM 'unavailability_cancelled') THEN
    RAISE EXCEPTION 'FAIL cancelar: lineas sin resolution_note'; END IF;
  IF (pg_temp.line(a.id)).status <> 'auto_resolved' OR (pg_temp.line(b.id)).status <> 'auto_resolved'
     OR (pg_temp.line(c.id)).status <> 'manager_resolved' OR (pg_temp.line(d.id)).status <> 'manager_resolved'
     OR (pg_temp.line(e.id)).status <> 'manager_resolved' THEN
    RAISE EXCEPTION 'FAIL cancelar: estados de lineas resueltas cambiados'; END IF;
  -- Ninguna linea nueva para esta baja (la reversion no re-dispara el motor).
  IF pg_temp.nlines() <> 6 OR EXISTS (SELECT p.id FROM public.panelist_reassignment_proposal p
                                        WHERE p.unavailability_id = 'f0000000-0000-0000-0000-000000000001'
                                       EXCEPT SELECT id FROM pre_lines) THEN
    RAISE EXCEPTION 'FAIL cancelar: lineas nuevas tras cancelar (%)', pg_temp.nlines(); END IF;
  -- Incidencia cerrada.
  IF u.incident_status <> 'resolved' OR u.final_resolution IS NULL OR u.final_resolution NOT LIKE '%unavailability_cancelled%'
     OR u.resolved_at IS NULL OR u.review_status <> 'reviewed' THEN
    RAISE EXCEPTION 'FAIL cancelar: incidencia % % %', u.incident_status, u.final_resolution, u.review_status; END IF;
  -- Fechas de 2027: no hay aviso de reversion.
  IF EXISTS (SELECT 1 FROM public.panelist_notification WHERE payload->>'change' = 'revert') THEN
    RAISE EXCEPTION 'FAIL cancelar: aviso de reversion fuera de la semana actual'; END IF;
  RAISE NOTICE 'PASS cancelar baja (auto + manager, pendientes descartadas, incidencia resuelta)';
END $$;

-- Tocar la baja ya cancelada no repite nada (final_resolution no se duplica).
UPDATE public.panelist_unavailability SET notes = 'x' WHERE id = 'f0000000-0000-0000-0000-000000000001';
DO $$
BEGIN
  IF (SELECT count(*) FROM regexp_matches((pg_temp.inc()).final_resolution, 'unavailability_cancelled', 'g')) <> 1 THEN
    RAISE EXCEPTION 'FAIL final_resolution duplicada: %', (pg_temp.inc()).final_resolution; END IF;
  RAISE NOTICE 'PASS cancelacion no se repite';
END $$;
ROLLBACK;

-- ===== Cancelar baja: final_resolution previa se conserva =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-12');
UPDATE public.panelist_unavailability SET final_resolution = 'nota del manager' WHERE id = 'f0000000-0000-0000-0000-000000000001';
UPDATE public.panelist_unavailability SET status = 'cancelled' WHERE id = 'f0000000-0000-0000-0000-000000000001';
DO $$
BEGIN
  IF (pg_temp.inc()).final_resolution NOT LIKE 'nota del manager%unavailability_cancelled' THEN
    RAISE EXCEPTION 'FAIL final_resolution previa: %', (pg_temp.inc()).final_resolution; END IF;
  RAISE NOTICE 'PASS final_resolution previa conservada';
END $$;
ROLLBACK;

-- ===== Avisos de reversion en la semana actual =====
-- D = dia laborable de esta semana (hoy si es lunes..viernes; si no, el lunes de esta semana).
-- Baja de P1 de D a fin de mes: no hay hueco de retraso en el mes -> el motor reencamina a N2 el dia D.
-- Al cancelar, se avisa a los panelistas de antes y de despues, incluido P1 (vuelve a actuar).

-- (a) Destino: N4 -> N1 reencaminada a N4 -> N2; vuelve a N1.
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N4','N1', pg_temp.dday());
SELECT pg_temp.baja(pg_temp.dday(), pg_temp.eom());
DO $$
BEGIN
  IF (pg_temp.line('d0000000-0000-0000-0000-000000000001')).final_action IS DISTINCT FROM 'reroute'
     OR (pg_temp.s('d0000000-0000-0000-0000-000000000001')).destination_node_id <> 'b2000000-0000-0000-0000-000000000002' THEN
    RAISE EXCEPTION 'FAIL aviso destino: preparacion (%)', (pg_temp.line('d0000000-0000-0000-0000-000000000001')).final_action; END IF;
END $$;
UPDATE public.panelist_unavailability SET status = 'cancelled' WHERE id = 'f0000000-0000-0000-0000-000000000001';
DO $$
DECLARE s record;
BEGIN
  s := pg_temp.s('d0000000-0000-0000-0000-000000000001');
  IF s.fecha_programada <> pg_temp.dday() OR s.destination_node_id <> 'b1000000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'FAIL aviso destino: muestra no revertida % %', s.fecha_programada, s.destination_node_id; END IF;
  IF pg_temp.revert_roles() IS DISTINCT FROM 'Pan1:receiver,Pan2:former_receiver,Pan4:sender' THEN
    RAISE EXCEPTION 'FAIL aviso destino: destinatarios %', pg_temp.revert_roles(); END IF;
  IF EXISTS (SELECT 1 FROM public.panelist_notification
              WHERE payload->>'change' = 'revert'
                AND ((payload->>'detail_id')::uuid <> s.id OR (payload->>'new_date')::date <> pg_temp.dday()
                     OR kind <> 'plan_change_this_week'
                     OR payload->>'destination_node_code' <> 'N1')) THEN
    RAISE EXCEPTION 'FAIL aviso destino: payload incorrecto'; END IF;
  RAISE NOTICE 'PASS aviso de reversion (destino) en la semana actual';
END $$;
ROLLBACK;

-- (b) Origen: N1 -> N4 reencaminada a N2 -> N4; vuelve a N1. El emisor alternativo (P2) recibe 'former_sender'.
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4', pg_temp.dday());
SELECT pg_temp.baja(pg_temp.dday(), pg_temp.eom());
DO $$
BEGIN
  IF (pg_temp.s('d0000000-0000-0000-0000-000000000001')).origin_node_id <> 'b2000000-0000-0000-0000-000000000002' THEN
    RAISE EXCEPTION 'FAIL aviso origen: preparacion'; END IF;
END $$;
UPDATE public.panelist_unavailability SET status = 'cancelled' WHERE id = 'f0000000-0000-0000-0000-000000000001';
DO $$
BEGIN
  IF (pg_temp.s('d0000000-0000-0000-0000-000000000001')).origin_node_id <> 'b1000000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'FAIL aviso origen: muestra no revertida'; END IF;
  IF pg_temp.revert_roles() IS DISTINCT FROM 'Pan1:sender,Pan2:former_sender,Pan4:receiver' THEN
    RAISE EXCEPTION 'FAIL aviso origen: destinatarios %', pg_temp.revert_roles(); END IF;
  RAISE NOTICE 'PASS aviso de reversion (origen) en la semana actual';
END $$;
ROLLBACK;

-- (c) Anulacion del manager de una muestra con P1 de emisor: vuelve a pending y se avisa a emisor y receptor.
--     Con onems.suppress_notifications='on' no se encola nada.
BEGIN;
\ir fixtures/incident_city.sql
-- N2/N3 saturados todas las semanas del mes de D -> la linea queda pendiente.
SELECT pg_temp.fill('N2', date_trunc('week', date_trunc('month', pg_temp.dday()))::date, pg_temp.eom(), 8);
SELECT pg_temp.fill('N3', date_trunc('week', date_trunc('month', pg_temp.dday()))::date, pg_temp.eom(), 8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4', pg_temp.dday());
SELECT pg_temp.baja(pg_temp.dday(), pg_temp.eom());
DO $$
BEGIN
  IF (pg_temp.line('d0000000-0000-0000-0000-000000000001')).status IS DISTINCT FROM 'pending' THEN
    RAISE EXCEPTION 'FAIL aviso anulacion: preparacion (%)', (pg_temp.line('d0000000-0000-0000-0000-000000000001')).status; END IF;
END $$;
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT public.apply_manager_decision((pg_temp.line('d0000000-0000-0000-0000-000000000001')).id, 'cancel');
SELECT set_config('request.jwt.claim.sub','', true);
SAVEPOINT sp_sup;
SELECT set_config('onems.suppress_notifications','on', true);
UPDATE public.panelist_unavailability SET status = 'cancelled' WHERE id = 'f0000000-0000-0000-0000-000000000001';
DO $$
BEGIN
  IF (pg_temp.s('d0000000-0000-0000-0000-000000000001')).status <> 'pending' THEN
    RAISE EXCEPTION 'FAIL aviso anulacion (suprimido): no vuelve a pending'; END IF;
  IF pg_temp.revert_roles() IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL aviso anulacion: supresion ignorada (%)', pg_temp.revert_roles(); END IF;
  RAISE NOTICE 'PASS aviso de reversion suprimido con onems.suppress_notifications';
END $$;
ROLLBACK TO SAVEPOINT sp_sup;
SELECT set_config('onems.suppress_notifications','', true);
UPDATE public.panelist_unavailability SET status = 'cancelled' WHERE id = 'f0000000-0000-0000-0000-000000000001';
DO $$
BEGIN
  IF (pg_temp.s('d0000000-0000-0000-0000-000000000001')).status <> 'pending' THEN
    RAISE EXCEPTION 'FAIL aviso anulacion: no vuelve a pending'; END IF;
  IF pg_temp.revert_roles() IS DISTINCT FROM 'Pan1:sender,Pan4:receiver' THEN
    RAISE EXCEPTION 'FAIL aviso anulacion: destinatarios %', pg_temp.revert_roles(); END IF;
  RAISE NOTICE 'PASS aviso de reversion (anulacion en origen) en la semana actual';
END $$;
ROLLBACK;

-- ===== Cancelar baja: guardas (ya salida, anulada por otra via, ediciones manuales posteriores) =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-12');
-- A y M: retraso automatico (15/03 y 16/03).
INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
VALUES
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-10','pending'),
  ('d2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
   'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-10','pending');
-- R: reencaminado automatico N1 -> N2.
SELECT pg_temp.fill('N1','2027-03-15','2027-03-29',8);
SELECT pg_temp.mk('d3000000-0000-0000-0000-000000000003','N1','N4','2027-03-11');
-- X: pendiente -> anulada por el manager.
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.mk('d4000000-0000-0000-0000-000000000004','N1','N4','2027-03-10');
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT public.apply_manager_decision((pg_temp.line('d4000000-0000-0000-0000-000000000004')).id, 'cancel');
SELECT set_config('request.jwt.claim.sub','', true);
DO $$
BEGIN
  IF (pg_temp.s('d1000000-0000-0000-0000-000000000001')).fecha_programada <> '2027-03-15'
     OR (pg_temp.s('d2000000-0000-0000-0000-000000000002')).fecha_programada <> '2027-03-16'
     OR (pg_temp.s('d3000000-0000-0000-0000-000000000003')).origin_node_id <> 'b2000000-0000-0000-0000-000000000002'
     OR (pg_temp.s('d4000000-0000-0000-0000-000000000004')).status <> 'cancelled' THEN
    RAISE EXCEPTION 'FAIL guardas: preparacion'; END IF;
END $$;
-- Despues de resolver: A sale; M y R se editan a mano; X pasa a anulada por otro motivo.
UPDATE public.allocation_plan_details SET status = 'sent' WHERE id = 'd1000000-0000-0000-0000-000000000001';
UPDATE public.allocation_plan_details SET fecha_programada = '2027-03-18' WHERE id = 'd2000000-0000-0000-0000-000000000002';
UPDATE public.allocation_plan_details SET origin_node_id = 'b3000000-0000-0000-0000-000000000003' WHERE id = 'd3000000-0000-0000-0000-000000000003';
UPDATE public.allocation_plan_details SET reassignment_reason = 'manual' WHERE id = 'd4000000-0000-0000-0000-000000000004';
UPDATE public.panelist_unavailability SET status = 'cancelled' WHERE id = 'f0000000-0000-0000-0000-000000000001';
DO $$
BEGIN
  IF (pg_temp.s('d1000000-0000-0000-0000-000000000001')).fecha_programada <> '2027-03-15'
     OR (pg_temp.s('d1000000-0000-0000-0000-000000000001')).status <> 'sent' THEN
    RAISE EXCEPTION 'FAIL guardas: muestra ya salida revertida'; END IF;
  IF (pg_temp.s('d2000000-0000-0000-0000-000000000002')).fecha_programada <> '2027-03-18' THEN
    RAISE EXCEPTION 'FAIL guardas: fecha editada a mano pisada (%)', (pg_temp.s('d2000000-0000-0000-0000-000000000002')).fecha_programada; END IF;
  IF (pg_temp.s('d3000000-0000-0000-0000-000000000003')).origin_node_id <> 'b3000000-0000-0000-0000-000000000003' THEN
    RAISE EXCEPTION 'FAIL guardas: nodo editado a mano pisado'; END IF;
  IF (pg_temp.s('d4000000-0000-0000-0000-000000000004')).status <> 'cancelled' THEN
    RAISE EXCEPTION 'FAIL guardas: anulada por otro motivo vuelve a pending'; END IF;
  IF EXISTS (SELECT 1 FROM public.panelist_reassignment_proposal
              WHERE unavailability_id = 'f0000000-0000-0000-0000-000000000001'
                AND resolution_note IS DISTINCT FROM 'unavailability_cancelled') THEN
    RAISE EXCEPTION 'FAIL guardas: lineas sin resolution_note'; END IF;
  IF (pg_temp.inc()).incident_status <> 'resolved' THEN RAISE EXCEPTION 'FAIL guardas: incidencia no resuelta'; END IF;
  RAISE NOTICE 'PASS guardas de cancelacion (salida, otra via, ediciones manuales)';
END $$;
ROLLBACK;

-- ===== Seguridad: panelista de otra cuenta =====
BEGIN;
\ir fixtures/incident_city.sql
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language) VALUES
  ('e5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000002','Q5','Pan5','p5@t.l','5',NULL,'active','en');
DO $$
BEGIN
  BEGIN
    INSERT INTO public.panelist_unavailability (account_id, panelist_id, start_date, end_date, reason, status)
    VALUES ('a0000000-0000-0000-0000-000000000001','e5000000-0000-0000-0000-000000000005','2027-03-10','2027-03-12','vacation','active');
    RAISE EXCEPTION 'FAIL baja con panelista de otra cuenta aceptada';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'Panelist does not belong to account%' THEN RAISE; END IF;
  END;
  PERFORM pg_temp.baja('2027-03-10','2027-03-12');
  BEGIN
    UPDATE public.panelist_unavailability SET panelist_id = 'e5000000-0000-0000-0000-000000000005'
     WHERE id = 'f0000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL cambio a panelista de otra cuenta aceptado';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'Panelist does not belong to account%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'PASS baja con panelista de otra cuenta rechazada';
END $$;
ROLLBACK;

-- ===== Seguridad: un cambio del plan de la cuenta 1 nunca dispara el motor de una baja de la cuenta 2 =====
-- Panelista de la cuenta 2 apuntando (mal) al nodo N1 de la cuenta 1, con baja activa en la cuenta 2.
BEGIN;
\ir fixtures/incident_city.sql
-- (node_id es unico en panelists: se libera N1 de P1 para fabricar el caso.)
UPDATE public.panelists SET node_id = NULL WHERE id = 'e1000000-0000-0000-0000-000000000001';
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language) VALUES
  ('e5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000002','Q5','Pan5','p5@t.l','5',
   'b1000000-0000-0000-0000-000000000001','active','en');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status)
VALUES ('f2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002',
        'e5000000-0000-0000-0000-000000000005','2027-03-10','2027-03-12','vacation','active');
DO $$
BEGIN
  -- El motor (alta) no toca muestras de la cuenta 1.
  IF EXISTS (SELECT 1 FROM public.panelist_reassignment_proposal) THEN
    RAISE EXCEPTION 'FAIL cross-tenant: el motor creo lineas sobre la cuenta 1'; END IF;
  IF (pg_temp.s('d0000000-0000-0000-0000-000000000001')).fecha_programada <> '2027-03-10' THEN
    RAISE EXCEPTION 'FAIL cross-tenant: muestra de la cuenta 1 movida'; END IF;
END $$;
-- Marca: si el trigger del plan llamara al motor para esta baja, incident_status volveria a calcularse.
UPDATE public.panelist_unavailability SET incident_status = 'new' WHERE id = 'f2000000-0000-0000-0000-000000000002';
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000002','N1','N4','2027-03-11');
UPDATE public.allocation_plan_details SET fecha_programada = '2027-03-12' WHERE id = 'd0000000-0000-0000-0000-000000000001';
DO $$
BEGIN
  IF (SELECT incident_status FROM public.panelist_unavailability WHERE id = 'f2000000-0000-0000-0000-000000000002') <> 'new' THEN
    RAISE EXCEPTION 'FAIL cross-tenant: el trigger del plan de la cuenta 1 ejecuto el motor de la cuenta 2'; END IF;
  IF EXISTS (SELECT 1 FROM public.panelist_reassignment_proposal) THEN
    RAISE EXCEPTION 'FAIL cross-tenant: lineas creadas'; END IF;
  RAISE NOTICE 'PASS cambios del plan acotados por cuenta';
END $$;
ROLLBACK;

-- ===== Seguridad: los avisos nunca llevan datos de un panelista de otra cuenta =====
-- Muestra de la cuenta 1 cuyo destino (mal) es un nodo de la cuenta 2 con panelista de la cuenta 2.
BEGIN;
\ir fixtures/incident_city.sql
INSERT INTO public.regions (id, account_id, name, code) VALUES
  ('e0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','Reg2','R2');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c6000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','City6','C6');
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b6000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000002','c6000000-0000-0000-0000-000000000006','N6');
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language,
                              address_line1, postal_code, address_city) VALUES
  ('e6000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000002','Q6','SecretName','p6@t.l','6',
   'b6000000-0000-0000-0000-000000000006','active','en','SecretStreet 1','SECRETZIP','SecretCity');
INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
VALUES ('d0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
        'b4000000-0000-0000-0000-000000000004','b6000000-0000-0000-0000-000000000006', pg_temp.dday(), 'pending');
DO $$
BEGIN
  PERFORM public.incident_enqueue_plan_change('d0000000-0000-0000-0000-000000000001', 'reroute_destination',
                                              pg_temp.dday(), pg_temp.dday(), NULL);
  PERFORM public.incident_enqueue_revert('d0000000-0000-0000-0000-000000000001', pg_temp.dday(),
                                         'b4000000-0000-0000-0000-000000000004', 'b6000000-0000-0000-0000-000000000006');
  -- Control: el emisor de la cuenta 1 (P4) si recibe ambos avisos.
  IF (SELECT count(*) FROM public.panelist_notification WHERE panelist_id = 'e4000000-0000-0000-0000-000000000004') <> 2 THEN
    RAISE EXCEPTION 'FAIL fuga: control sin avisos (%)',
      (SELECT count(*) FROM public.panelist_notification WHERE panelist_id = 'e4000000-0000-0000-0000-000000000004'); END IF;
  IF EXISTS (SELECT 1 FROM public.panelist_notification WHERE panelist_id = 'e6000000-0000-0000-0000-000000000006') THEN
    RAISE EXCEPTION 'FAIL fuga: aviso a un panelista de otra cuenta'; END IF;
  IF EXISTS (SELECT 1 FROM public.panelist_notification
              WHERE payload::text LIKE '%Secret%' OR payload::text LIKE '%SECRETZIP%') THEN
    RAISE EXCEPTION 'FAIL fuga: datos de otra cuenta en el payload'; END IF;
  IF EXISTS (SELECT 1 FROM public.panelist_notification WHERE account_id <> 'a0000000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'FAIL fuga: aviso en otra cuenta'; END IF;
  RAISE NOTICE 'PASS avisos sin datos de otra cuenta (plan_change y revert)';
END $$;
ROLLBACK;

-- ===== Guardas de la baja: no se reactiva una cancelada; no se editan fechas de una activa =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-12');
DO $$
BEGIN
  BEGIN
    UPDATE public.panelist_unavailability SET end_date = '2027-03-15' WHERE id = 'f0000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL fechas de baja activa editadas';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'Dates of an active unavailability cannot be edited%' THEN RAISE; END IF;
  END;
  BEGIN
    UPDATE public.panelist_unavailability SET start_date = '2027-03-09' WHERE id = 'f0000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL fecha de inicio de baja activa editada';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'Dates of an active unavailability cannot be edited%' THEN RAISE; END IF;
  END;
  -- Otras columnas si se pueden tocar.
  UPDATE public.panelist_unavailability SET notes = 'ok' WHERE id = 'f0000000-0000-0000-0000-000000000001';
  UPDATE public.panelist_unavailability SET status = 'cancelled' WHERE id = 'f0000000-0000-0000-0000-000000000001';
  BEGIN
    UPDATE public.panelist_unavailability SET status = 'active' WHERE id = 'f0000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL baja cancelada reactivada';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'Reactivating a cancelled unavailability is not supported%' THEN RAISE; END IF;
  END;
  -- Una cancelada si puede cambiar de fechas (ya no actua).
  UPDATE public.panelist_unavailability SET end_date = '2027-03-13' WHERE id = 'f0000000-0000-0000-0000-000000000001';
  RAISE NOTICE 'PASS guardas: reactivar y editar fechas rechazados';
END $$;
ROLLBACK;

-- ===== Borrar una baja activa revierte su impacto =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-12');
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
DO $$
BEGIN
  IF (pg_temp.s('d0000000-0000-0000-0000-000000000001')).fecha_programada <> '2027-03-15' THEN
    RAISE EXCEPTION 'FAIL borrado: preparacion'; END IF;
END $$;
DELETE FROM public.panelist_unavailability WHERE id = 'f0000000-0000-0000-0000-000000000001';
DO $$
DECLARE s record;
BEGIN
  s := pg_temp.s('d0000000-0000-0000-0000-000000000001');
  IF (pg_temp.inc()).id IS NOT NULL THEN RAISE EXCEPTION 'FAIL borrado: la baja sigue'; END IF;
  IF s.fecha_programada <> '2027-03-10' OR s.original_fecha_programada IS NOT NULL OR s.reassigned_at IS NOT NULL
     OR s.origin_node_id <> 'b1000000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'FAIL borrado: muestra no restaurada % %', s.fecha_programada, s.original_fecha_programada; END IF;
  IF pg_temp.nlines() <> 0 THEN RAISE EXCEPTION 'FAIL borrado: lineas siguen'; END IF;
  RAISE NOTICE 'PASS borrar baja activa revierte la muestra';
END $$;
ROLLBACK;

-- ===== Borrar muestras del plan recalcula el estado =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-12');
SELECT pg_temp.fill('N1','2027-03-15','2027-03-29',8);
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
DO $$
BEGIN
  IF (pg_temp.inc()).incident_status <> 'pending_manager' THEN RAISE EXCEPTION 'FAIL borrado plan: preparacion'; END IF;
END $$;
DELETE FROM public.allocation_plan_details WHERE id = 'd0000000-0000-0000-0000-000000000001';
DO $$
BEGIN
  IF pg_temp.nlines() <> 0 OR (pg_temp.inc()).incident_status <> 'auto_resolved'
     OR (pg_temp.inc()).auto_summary <> 'shift=0;reroute=0;cancel=0;info=0;pending=0' THEN
    RAISE EXCEPTION 'FAIL borrado plan: estado % %', (pg_temp.inc()).incident_status, (pg_temp.inc()).auto_summary; END IF;
  RAISE NOTICE 'PASS borrar la unica pendiente deja la incidencia auto_resolved';
END $$;
ROLLBACK;

-- ===== RPC heredada apply_reassignment_proposal: recalcula el estado y su retraso se revierte =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-12');
SELECT pg_temp.fill('N1','2027-03-15','2027-03-29',8);
SELECT pg_temp.fill('N2','2027-03-01','2027-03-29',8);
SELECT pg_temp.fill('N3','2027-03-01','2027-03-29',8);
SELECT pg_temp.mk('d0000000-0000-0000-0000-000000000001','N1','N4','2027-03-10');
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT public.apply_reassignment_proposal((pg_temp.line('d0000000-0000-0000-0000-000000000001')).id, 'shift_date', NULL, '2027-04-05');
SELECT set_config('request.jwt.claim.sub','', true);
DO $$
DECLARE s record;
BEGIN
  s := pg_temp.s('d0000000-0000-0000-0000-000000000001');
  IF (pg_temp.inc()).incident_status <> 'resolved' THEN
    RAISE EXCEPTION 'FAIL heredada: estado %', (pg_temp.inc()).incident_status; END IF;
  IF s.fecha_programada <> '2027-04-05' OR s.original_fecha_programada IS DISTINCT FROM '2027-03-10'::date THEN
    RAISE EXCEPTION 'FAIL heredada: original_fecha % %', s.fecha_programada, s.original_fecha_programada; END IF;
END $$;
UPDATE public.panelist_unavailability SET status = 'cancelled' WHERE id = 'f0000000-0000-0000-0000-000000000001';
DO $$
DECLARE s record;
BEGIN
  s := pg_temp.s('d0000000-0000-0000-0000-000000000001');
  IF s.fecha_programada <> '2027-03-10' OR s.original_fecha_programada IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL heredada: retraso no revertido %', s.fecha_programada; END IF;
  RAISE NOTICE 'PASS RPC heredada: estado recalculado y retraso revertido al cancelar';
END $$;
ROLLBACK;

-- ===== Bulk: un solo INSERT de muchas filas -> una llamada al motor por baja =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.baja('2027-03-10','2027-03-12');
INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status)
VALUES ('f0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001',
        'e3000000-0000-0000-0000-000000000003', '2027-03-10', '2027-03-12', 'vacation', 'active');
-- 2000 muestras N4 -> N4 (ninguna baja) + 1 de N1 y 1 de N3 en la baja.
INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
SELECT 'a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
       CASE WHEN i = 1 THEN 'b1000000-0000-0000-0000-000000000001'::uuid
            WHEN i = 2 THEN 'b3000000-0000-0000-0000-000000000003'::uuid
            ELSE 'b4000000-0000-0000-0000-000000000004'::uuid END,
       'b4000000-0000-0000-0000-000000000004', '2027-03-10'::date + (i % 3), 'pending'
  FROM generate_series(1, 2002) i;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.panelist_reassignment_proposal) <> 2 THEN
    RAISE EXCEPTION 'FAIL bulk: % lineas', (SELECT count(*) FROM public.panelist_reassignment_proposal); END IF;
  RAISE NOTICE 'PASS bulk insert (dos bajas tocadas)';
END $$;
ROLLBACK;
