-- Auxiliares del motor de incidencias: hoy local, carga semanal, umbral, huecos, nodo, aplicar cambio/anulacion, cola de avisos.
-- Nota: las bajas se insertan ANTES que las muestras de su nodo/fechas (o en fechas sin muestras) para no depender
-- del trigger viejo de propuestas (best-effort; se sustituye en tareas posteriores).
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/incident_city.sql

-- Bajas: P1 en mayo (sin muestras: solo sirve como baja de las lineas), P3 el 2027-03-10 (N3 no tiene muestras).
INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status) VALUES
  ('b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','2027-05-03','2027-05-04','vacation','active');

-- ===== panelist_local_today =====
DO $$
BEGIN
  IF public.panelist_local_today('e1000000-0000-0000-0000-000000000001') IS NULL THEN
    RAISE EXCEPTION 'FAIL panelist_local_today(P1) NULL'; END IF;
  IF public.panelist_local_today('e1000000-0000-0000-0000-000000000001') <> (now() AT TIME ZONE 'Africa/Nairobi')::date THEN
    RAISE EXCEPTION 'FAIL panelist_local_today(P1) no usa Africa/Nairobi'; END IF;
  IF public.panelist_local_today('e4000000-0000-0000-0000-000000000004') <> (now() AT TIME ZONE 'UTC')::date THEN
    RAISE EXCEPTION 'FAIL panelist_local_today(P4) no es UTC'; END IF;
  RAISE NOTICE 'PASS panelist_local_today';
END $$;

-- ===== incident_week_start =====
DO $$
BEGIN
  IF public.incident_week_start('2027-03-10') <> '2027-03-08' THEN RAISE EXCEPTION 'FAIL week_start miercoles'; END IF;
  IF public.incident_week_start('2027-03-08') <> '2027-03-08' THEN RAISE EXCEPTION 'FAIL week_start lunes'; END IF;
  IF public.incident_week_start('2027-03-14') <> '2027-03-08' THEN RAISE EXCEPTION 'FAIL week_start domingo'; END IF;
  RAISE NOTICE 'PASS incident_week_start';
END $$;

-- ===== incident_node_week_load =====
-- N1 origen: 3 muestras en la semana del 08 (una cancelled) + 1 con N1 destino + 1 fuera de semana (15).
INSERT INTO public.allocation_plan_details
  (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status) VALUES
  ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-08',10,3,2027,'pending'),
  ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-10',10,3,2027,'notified'),
  ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-12',10,3,2027,'cancelled'),
  ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','b1000000-0000-0000-0000-000000000001','2027-03-14',10,3,2027,'pending'),
  ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-15',11,3,2027,'pending');

DO $$
DECLARE v int;
BEGIN
  v := public.incident_node_week_load('b1000000-0000-0000-0000-000000000001','2027-03-10');
  IF v IS DISTINCT FROM 3 THEN RAISE EXCEPTION 'FAIL week_load N1 = % (esperado 3)', v; END IF;
  v := public.incident_node_week_load('b2000000-0000-0000-0000-000000000002','2027-03-10');
  IF v IS DISTINCT FROM 0 THEN RAISE EXCEPTION 'FAIL week_load N2 = % (esperado 0)', v; END IF;
  RAISE NOTICE 'PASS incident_node_week_load';
END $$;

-- ===== incident_saturation_threshold / incident_node_fits =====
DO $$
BEGIN
  IF public.incident_saturation_threshold() <> 7.8 THEN
    RAISE EXCEPTION 'FAIL threshold() = %', public.incident_saturation_threshold(); END IF;
  IF public.incident_saturation_threshold(10, 10) <> 11.5 THEN RAISE EXCEPTION 'FAIL threshold(10,10)'; END IF;
  IF NOT public.incident_node_fits('b1000000-0000-0000-0000-000000000001','2027-03-10',6,20) THEN
    RAISE EXCEPTION 'FAIL fits N1 con carga 3'; END IF;
  RAISE NOTICE 'PASS threshold + fits (carga 3)';
END $$;

INSERT INTO public.allocation_plan_details
  (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status)
SELECT 'a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-09',10,3,2027,'pending'
FROM generate_series(1,5);

DO $$
BEGIN
  IF public.incident_node_week_load('b1000000-0000-0000-0000-000000000001','2027-03-10') <> 8 THEN
    RAISE EXCEPTION 'FAIL week_load N1 tras +5'; END IF;
  IF public.incident_node_fits('b1000000-0000-0000-0000-000000000001','2027-03-10',6,20) THEN
    RAISE EXCEPTION 'FAIL fits N1 con carga 8 deberia ser false'; END IF;
  -- Nodo sin panelista activo: no cabe. Fecha NULL: no cabe.
  UPDATE public.panelists SET status='inactive' WHERE id='e4000000-0000-0000-0000-000000000004';
  IF public.incident_node_fits('b4000000-0000-0000-0000-000000000004','2027-04-05',6,20) THEN
    RAISE EXCEPTION 'FAIL fits nodo sin panelista activo'; END IF;
  UPDATE public.panelists SET status='active' WHERE id='e4000000-0000-0000-0000-000000000004';
  IF public.incident_node_fits('b2000000-0000-0000-0000-000000000002', NULL, 6, 20) IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'FAIL fits fecha NULL'; END IF;
  RAISE NOTICE 'PASS fits false (carga 8, sin panelista, fecha NULL)';
END $$;

-- ===== incident_find_shift_date =====
DO $$
DECLARE d date;
BEGIN
  d := public.incident_find_shift_date('b2000000-0000-0000-0000-000000000002','2027-03-12','2027-03-10',6,20);
  IF d IS DISTINCT FROM '2027-03-15'::date THEN RAISE EXCEPTION 'FAIL shift N2 = % (esperado 2027-03-15)', d; END IF;
  RAISE NOTICE 'PASS find_shift_date primer laborable';
END $$;

-- N2 tiene una muestra el 15 y una CANCELADA el 16 (la cancelada no cuenta).
INSERT INTO public.allocation_plan_details
  (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status) VALUES
  ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000002','b4000000-0000-0000-0000-000000000004','2027-03-15',11,3,2027,'pending'),
  ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','b2000000-0000-0000-0000-000000000002','2027-03-16',11,3,2027,'cancelled');

DO $$
DECLARE d date;
BEGIN
  d := public.incident_find_shift_date('b2000000-0000-0000-0000-000000000002','2027-03-12','2027-03-10',6,20);
  IF d IS DISTINCT FROM '2027-03-16'::date THEN RAISE EXCEPTION 'FAIL shift N2 reparto = % (esperado 2027-03-16)', d; END IF;
  d := public.incident_find_shift_date('b2000000-0000-0000-0000-000000000002','2027-03-31','2027-03-10',6,20);
  IF d IS NOT NULL THEN RAISE EXCEPTION 'FAIL shift N2 tras fin de mes = %', d; END IF;
  d := public.incident_find_shift_date('b2000000-0000-0000-0000-000000000002',NULL,'2027-03-10',6,20);
  IF d IS NOT NULL THEN RAISE EXCEPTION 'FAIL shift con p_after NULL = %', d; END IF;
  -- Nodo saturado en todas sus semanas no da hueco: N1 semana del 08 tiene 8 -> si p_after=07 y mes de marzo,
  -- 08..12 no caben y el primero valido es el de menor recuento en semanas libres (16, sin muestras de N1).
  d := public.incident_find_shift_date('b1000000-0000-0000-0000-000000000001','2027-03-07','2027-03-10',6,20);
  IF d IS DISTINCT FROM '2027-03-16'::date THEN RAISE EXCEPTION 'FAIL shift N1 salta semana saturada = %', d; END IF;
  RAISE NOTICE 'PASS find_shift_date reparto/cancelada/fin de mes/NULL/saturada';
END $$;

-- ===== incident_find_node =====
DO $$
DECLARE n uuid;
BEGIN
  n := public.incident_find_node('c1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','2027-03-10',6,20);
  IF n IS DISTINCT FROM 'b2000000-0000-0000-0000-000000000002'::uuid THEN RAISE EXCEPTION 'FAIL find_node empate = %', n; END IF;
  -- Ciudad sin otro nodo (C2 solo tiene N4): NULL
  n := public.incident_find_node('c2000000-0000-0000-0000-000000000002','b4000000-0000-0000-0000-000000000004','2027-03-10',6,20);
  IF n IS NOT NULL THEN RAISE EXCEPTION 'FAIL find_node C2 sin alternativa = %', n; END IF;
  RAISE NOTICE 'PASS find_node empate por auto_id + sin candidato';
END $$;

INSERT INTO public.allocation_plan_details
  (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status)
SELECT 'a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000002','b4000000-0000-0000-0000-000000000004','2027-03-11',10,3,2027,'pending'
FROM generate_series(1,2);

DO $$
DECLARE n uuid;
BEGIN
  n := public.incident_find_node('c1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','2027-03-10',6,20);
  IF n IS DISTINCT FROM 'b3000000-0000-0000-0000-000000000003'::uuid THEN RAISE EXCEPTION 'FAIL find_node menor carga = %', n; END IF;
  RAISE NOTICE 'PASS find_node menor carga';
END $$;

INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status) VALUES
  ('b0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000003','2027-03-10','2027-03-10','vacation','active');

DO $$
DECLARE n uuid;
BEGIN
  n := public.incident_find_node('c1000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','2027-03-10',6,20);
  IF n IS DISTINCT FROM 'b2000000-0000-0000-0000-000000000002'::uuid THEN RAISE EXCEPTION 'FAIL find_node P3 de baja = %', n; END IF;
  RAISE NOTICE 'PASS find_node excluye nodo de baja';
END $$;

-- ===== incident_apply_change =====
-- d1: notified, origen N1, 2027-03-10 -> reroute a N2 (auto). d2: pending, origen N1 -> shift a 2027-03-17 (manager).
INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status, origin_panelist_name, origin_panelist_id) VALUES
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-10',10,3,2027,'notified','Pan1','e1000000-0000-0000-0000-000000000001'),
  ('d2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-10',10,3,2027,'pending','Pan1',NULL),
  ('d3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-10',10,3,2027,'notified','Pan1',NULL),
  ('d4000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-10',10,3,2027,'sent','Pan1',NULL);
INSERT INTO public.panelist_reassignment_proposal
  (id, account_id, unavailability_id, allocation_plan_detail_id, affected_role, sample_status_at_detection, suggested_action, status) VALUES
  ('f1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','origin','notified','reroute','pending'),
  ('f2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000002','origin','pending','shift_date','pending'),
  ('f3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','d3000000-0000-0000-0000-000000000003','origin','notified','cancel','pending'),
  ('f4000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','d4000000-0000-0000-0000-000000000004','origin','sent','reroute','pending');

SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);

DO $$
DECLARE r record; l record;
BEGIN
  PERFORM public.incident_apply_change('f1000000-0000-0000-0000-000000000001', NULL, 'b2000000-0000-0000-0000-000000000002', 'auto');
  SELECT * INTO r FROM allocation_plan_details WHERE id='d1000000-0000-0000-0000-000000000001';
  SELECT * INTO l FROM panelist_reassignment_proposal WHERE id='f1000000-0000-0000-0000-000000000001';
  IF r.origin_node_id <> 'b2000000-0000-0000-0000-000000000002' THEN RAISE EXCEPTION 'FAIL origin_node_id'; END IF;
  IF r.original_origin_node_id IS DISTINCT FROM 'b1000000-0000-0000-0000-000000000001'::uuid THEN RAISE EXCEPTION 'FAIL original_origin_node_id'; END IF;
  IF r.status <> 'pending' THEN RAISE EXCEPTION 'FAIL status notified->pending (%)', r.status; END IF;
  IF r.origin_panelist_name IS DISTINCT FROM 'Pan2' THEN RAISE EXCEPTION 'FAIL origin_panelist_name %', r.origin_panelist_name; END IF;
  IF r.origin_panelist_id IS DISTINCT FROM 'e2000000-0000-0000-0000-000000000002'::uuid THEN RAISE EXCEPTION 'FAIL origin_panelist_id %', r.origin_panelist_id; END IF;
  IF r.fecha_programada <> '2027-03-10' OR r.original_fecha_programada IS NOT NULL THEN RAISE EXCEPTION 'FAIL fecha tocada en reroute'; END IF;
  IF r.reassignment_reason IS DISTINCT FROM 'panelist_unavailable' OR r.reassigned_at IS NULL
     OR r.reassigned_by IS DISTINCT FROM '99000000-0000-0000-0000-000000000099'::uuid THEN RAISE EXCEPTION 'FAIL reassignment_*'; END IF;
  IF l.status <> 'auto_resolved' OR l.final_action IS DISTINCT FROM 'reroute'
     OR l.final_target_node_id IS DISTINCT FROM 'b2000000-0000-0000-0000-000000000002'::uuid
     OR l.applied_at IS NULL THEN RAISE EXCEPTION 'FAIL linea reroute (% %)', l.status, l.final_action; END IF;
  IF l.confirmed_by IS NOT NULL OR l.confirmed_at IS NOT NULL THEN RAISE EXCEPTION 'FAIL confirmed_* en modo auto'; END IF;
  -- Ya resuelta: no se reaplica
  BEGIN
    PERFORM public.incident_apply_change('f1000000-0000-0000-0000-000000000001', NULL, 'b3000000-0000-0000-0000-000000000003', 'auto');
    RAISE EXCEPTION 'FAIL reaplicar linea resuelta aceptado';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'PASS apply_change reroute auto';
END $$;

DO $$
DECLARE r record; l record;
BEGIN
  PERFORM public.incident_apply_change('f2000000-0000-0000-0000-000000000002', '2027-03-17', NULL, 'manager');
  SELECT * INTO r FROM allocation_plan_details WHERE id='d2000000-0000-0000-0000-000000000002';
  SELECT * INTO l FROM panelist_reassignment_proposal WHERE id='f2000000-0000-0000-0000-000000000002';
  IF r.fecha_programada <> '2027-03-17' OR r.original_fecha_programada IS DISTINCT FROM '2027-03-10'::date THEN
    RAISE EXCEPTION 'FAIL shift fecha (% / %)', r.fecha_programada, r.original_fecha_programada; END IF;
  IF r.origin_node_id <> 'b1000000-0000-0000-0000-000000000001' OR r.original_origin_node_id IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL nodo tocado en shift'; END IF;
  IF r.week_number <> 11 THEN RAISE EXCEPTION 'FAIL week_number no recalculado (%)', r.week_number; END IF;
  IF l.status <> 'manager_resolved' OR l.final_action IS DISTINCT FROM 'shift_date' OR l.final_date IS DISTINCT FROM '2027-03-17'::date
     OR l.confirmed_by IS DISTINCT FROM '99000000-0000-0000-0000-000000000099'::uuid OR l.confirmed_at IS NULL OR l.applied_at IS NULL THEN
    RAISE EXCEPTION 'FAIL linea shift manager'; END IF;
  RAISE NOTICE 'PASS apply_change shift manager';
END $$;

DO $$
BEGIN
  -- Muestra ya salida: no se toca
  BEGIN
    PERFORM public.incident_apply_change('f4000000-0000-0000-0000-000000000004', NULL, 'b2000000-0000-0000-0000-000000000002', 'auto');
    RAISE EXCEPTION 'FAIL muestra sent modificada';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
  -- Nodo de otra ciudad: rechazado
  BEGIN
    PERFORM public.incident_apply_change('f3000000-0000-0000-0000-000000000003', NULL, 'b4000000-0000-0000-0000-000000000004', 'auto');
    RAISE EXCEPTION 'FAIL reroute a otra ciudad aceptado';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
  -- Modo invalido / sin cambio
  BEGIN
    PERFORM public.incident_apply_change('f3000000-0000-0000-0000-000000000003', '2027-03-17', NULL, 'bogus');
    RAISE EXCEPTION 'FAIL modo invalido aceptado';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
  BEGIN
    PERFORM public.incident_apply_change('f3000000-0000-0000-0000-000000000003', NULL, NULL, 'auto');
    RAISE EXCEPTION 'FAIL cambio vacio aceptado';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
  IF (SELECT status FROM allocation_plan_details WHERE id='d4000000-0000-0000-0000-000000000004') <> 'sent' THEN
    RAISE EXCEPTION 'FAIL estado de sent alterado'; END IF;
  RAISE NOTICE 'PASS apply_change rechaza sent / otra ciudad / modo / vacio';
END $$;

-- ===== incident_apply_cancel =====
DO $$
DECLARE r record; l record;
BEGIN
  PERFORM public.incident_apply_cancel('f3000000-0000-0000-0000-000000000003', 'auto');
  SELECT * INTO r FROM allocation_plan_details WHERE id='d3000000-0000-0000-0000-000000000003';
  SELECT * INTO l FROM panelist_reassignment_proposal WHERE id='f3000000-0000-0000-0000-000000000003';
  IF r.status <> 'cancelled' OR r.reassignment_reason IS DISTINCT FROM 'panelist_unavailable'
     OR r.reassigned_at IS NULL OR r.reassigned_by IS NULL THEN RAISE EXCEPTION 'FAIL muestra cancel'; END IF;
  IF l.status <> 'auto_resolved' OR l.final_action IS DISTINCT FROM 'cancel' OR l.applied_at IS NULL OR l.confirmed_by IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL linea cancel'; END IF;
  RAISE NOTICE 'PASS apply_cancel auto';
END $$;

-- ===== incident_enqueue_plan_change =====
-- d5: N2 -> N3 en la semana actual. d6: N1 (P1, de baja) -> N3, semana actual, linea destino.
INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status) VALUES
  ('d5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000002','b3000000-0000-0000-0000-000000000003',current_date,1,1,2027,'pending'),
  ('d6000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000003',current_date,1,1,2027,'pending');
UPDATE public.panelists SET address_line1='Calle 3', address_line2='2B', postal_code='28001', address_city='City1'
 WHERE id='e3000000-0000-0000-0000-000000000003';

DO $$
DECLARE n int; p jsonb;
BEGIN
  n := public.incident_enqueue_plan_change('d5000000-0000-0000-0000-000000000005','reroute_destination', current_date, current_date, NULL);
  IF n <> 2 THEN RAISE EXCEPTION 'FAIL enqueue reroute_destination = % (esperado 2)', n; END IF;
  IF (SELECT count(*) FROM panelist_notification WHERE kind='plan_change_this_week'
        AND payload->>'detail_id'='d5000000-0000-0000-0000-000000000005') <> 2 THEN RAISE EXCEPTION 'FAIL filas encoladas'; END IF;
  SELECT payload INTO p FROM panelist_notification
   WHERE payload->>'detail_id'='d5000000-0000-0000-0000-000000000005' AND payload->>'recipient_role'='receiver';
  IF p IS NULL THEN RAISE EXCEPTION 'FAIL sin fila receiver'; END IF;
  IF NOT EXISTS (SELECT 1 FROM panelist_notification WHERE payload->>'detail_id'='d5000000-0000-0000-0000-000000000005'
                  AND payload->>'recipient_role'='receiver' AND panelist_id='e3000000-0000-0000-0000-000000000003') THEN
    RAISE EXCEPTION 'FAIL receiver no es P3'; END IF;
  IF NOT EXISTS (SELECT 1 FROM panelist_notification WHERE payload->>'detail_id'='d5000000-0000-0000-0000-000000000005'
                  AND payload->>'recipient_role'='sender' AND panelist_id='e2000000-0000-0000-0000-000000000002'
                  AND account_id='a0000000-0000-0000-0000-000000000001' AND status='pending_send') THEN
    RAISE EXCEPTION 'FAIL sender no es P2'; END IF;
  IF p->>'change' <> 'reroute_destination' OR p->>'origin_node_code' <> 'N2' OR p->>'destination_node_code' <> 'N3'
     OR p->>'origin_panelist_name' <> 'Pan2' OR p->>'destination_panelist_name' <> 'Pan3'
     OR p->>'product_description' <> 'Prod' OR p->>'carrier_name' <> 'Carrier'
     OR (p->>'scheduled_date')::date <> current_date OR (p->>'old_date')::date <> current_date
     OR p->'destination_address'->>'address_line1' <> 'Calle 3' OR p->'destination_address'->>'city' <> 'City1'
     OR p->'destination_address'->>'postal_code' <> '28001' OR p->'destination_address'->>'address_line2' <> '2B' THEN
    RAISE EXCEPTION 'FAIL payload %', p; END IF;

  n := public.incident_enqueue_plan_change('d5000000-0000-0000-0000-000000000005','reroute_destination', current_date, current_date, 'e2000000-0000-0000-0000-000000000002');
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL exclusion de panelista = %', n; END IF;
  n := public.incident_enqueue_plan_change('d5000000-0000-0000-0000-000000000005','shift_date', current_date - 7, current_date, NULL);
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL shift_date con fecha nueva en semana = %', n; END IF;
  n := public.incident_enqueue_plan_change('d5000000-0000-0000-0000-000000000005','reroute_origin', current_date + 30, current_date + 31, NULL);
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL fuera de semana = %', n; END IF;
  n := public.incident_enqueue_plan_change('d5000000-0000-0000-0000-000000000005','cancel', NULL, NULL, NULL);
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL fechas NULL = %', n; END IF;
  BEGIN
    PERFORM public.incident_enqueue_plan_change('d5000000-0000-0000-0000-000000000005','bogus', current_date, current_date, NULL);
    RAISE EXCEPTION 'FAIL p_change invalido aceptado';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM LIKE 'FAIL%' THEN RAISE; END IF; END;
  PERFORM set_config('onems.suppress_notifications','on',true);
  n := public.incident_enqueue_plan_change('d5000000-0000-0000-0000-000000000005','reroute_destination', current_date, current_date, NULL);
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL suppress = %', n; END IF;
  PERFORM set_config('onems.suppress_notifications','off',true);
  RAISE NOTICE 'PASS enqueue_plan_change';
END $$;

-- apply_change en semana actual: avisa y excluye al panelista de la baja (P1, emisor de d6).
INSERT INTO public.panelist_reassignment_proposal
  (id, account_id, unavailability_id, allocation_plan_detail_id, affected_role, sample_status_at_detection, suggested_action, status) VALUES
  ('f6000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','d6000000-0000-0000-0000-000000000006','destination','pending','reroute','pending');

DO $$
DECLARE r record;
BEGIN
  PERFORM public.incident_apply_change('f6000000-0000-0000-0000-000000000006', NULL, 'b2000000-0000-0000-0000-000000000002', 'manager');
  SELECT * INTO r FROM allocation_plan_details WHERE id='d6000000-0000-0000-0000-000000000006';
  IF r.destination_node_id <> 'b2000000-0000-0000-0000-000000000002' OR r.original_destination_node_id <> 'b3000000-0000-0000-0000-000000000003'
     OR r.destination_panelist_name IS DISTINCT FROM 'Pan2' THEN RAISE EXCEPTION 'FAIL reroute destino'; END IF;
  IF (SELECT count(*) FROM panelist_notification WHERE payload->>'detail_id'='d6000000-0000-0000-0000-000000000006') <> 1 THEN
    RAISE EXCEPTION 'FAIL avisos de apply_change destino (esperado 1: receptor P2, emisor P1 excluido)'; END IF;
  IF NOT EXISTS (SELECT 1 FROM panelist_notification WHERE payload->>'detail_id'='d6000000-0000-0000-0000-000000000006'
                  AND panelist_id='e2000000-0000-0000-0000-000000000002' AND payload->>'recipient_role'='receiver'
                  AND payload->>'change'='reroute_destination') THEN RAISE EXCEPTION 'FAIL aviso receptor P2'; END IF;
  RAISE NOTICE 'PASS apply_change encola aviso excluyendo panelista de baja';
END $$;

-- ===== Permisos =====
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.incident_week_start(date)',
    'public.incident_node_week_load(uuid,date)',
    'public.incident_saturation_threshold(numeric,numeric)',
    'public.incident_node_fits(uuid,date,numeric,numeric)',
    'public.incident_find_shift_date(uuid,date,date,numeric,numeric)',
    'public.incident_find_node(uuid,uuid,date,numeric,numeric)',
    'public.incident_apply_change(uuid,date,uuid,text)',
    'public.incident_apply_cancel(uuid,text)',
    'public.incident_enqueue_plan_change(uuid,text,date,date,uuid)'] LOOP
    IF has_function_privilege('anon', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL anon EXECUTE %', f; END IF;
    IF has_function_privilege('authenticated', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL authenticated EXECUTE %', f; END IF;
  END LOOP;
  IF NOT has_function_privilege('authenticated','public.panelist_local_today(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL authenticated sin EXECUTE panelist_local_today'; END IF;
  IF has_function_privilege('anon','public.panelist_local_today(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'FAIL anon EXECUTE panelist_local_today'; END IF;
  -- Endurecimiento de panelist_notification (arrastrado de la Tarea 2)
  IF NOT has_table_privilege('authenticated','public.panelist_notification','SELECT') THEN RAISE EXCEPTION 'FAIL authenticated sin SELECT'; END IF;
  IF has_table_privilege('authenticated','public.panelist_notification','INSERT') THEN RAISE EXCEPTION 'FAIL authenticated INSERT'; END IF;
  IF has_table_privilege('authenticated','public.panelist_notification','UPDATE') THEN RAISE EXCEPTION 'FAIL authenticated UPDATE'; END IF;
  IF has_table_privilege('authenticated','public.panelist_notification','DELETE') THEN RAISE EXCEPTION 'FAIL authenticated DELETE'; END IF;
  IF has_table_privilege('anon','public.panelist_notification','SELECT') THEN RAISE EXCEPTION 'FAIL anon SELECT'; END IF;
  RAISE NOTICE 'PASS permisos';
END $$;

ROLLBACK;
