-- Regla de recepcion POBOX tras ausencia del panelista (spec 2026-10-30, secciones 3.1-3.4 y 6.1).
-- Fixture comun: C1 (N1,N2,N3) y C2 (N4 unico nodo), plan Mar27. Fechas de 2027: 03-03 miercoles,
-- 03-05 viernes, 03-08 lunes, 03-09 martes, 03-10 miercoles. Cuenta en Africa/Nairobi (+03).
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;
CREATE FUNCTION pg_temp.pobox_on() RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.account_config (account_id, pobox_enabled)
  VALUES ('a0000000-0000-0000-0000-000000000001', true)
  ON CONFLICT (account_id) DO UPDATE SET pobox_enabled = true;
$$;
-- Detalle enviado del plan Mar27 (o otro) con tag, sent_at y panelistas de origen y destino.
CREATE FUNCTION pg_temp.mk_sent(p_o text, p_d text, p_sent timestamptz, p_tag text,
                                p_plan uuid DEFAULT 'cc000000-0000-0000-0000-000000000001') RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.allocation_plan_details
    (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, sent_at, tag_id,
     origin_panelist_id, destination_panelist_id)
  SELECT gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', p_plan, o.id, d.id, p_sent::date, 'sent', p_sent, p_tag,
         (SELECT id FROM public.panelists WHERE node_id = o.id ORDER BY panelist_code LIMIT 1),
         (SELECT id FROM public.panelists WHERE node_id = d.id ORDER BY panelist_code LIMIT 1)
    FROM public.nodes o, public.nodes d
   WHERE o.auto_id = p_o AND d.auto_id = p_d
  RETURNING id;
$$;
-- Detalle programado (pending) sin declarar.
CREATE FUNCTION pg_temp.mk(p_o text, p_date date) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.allocation_plan_details
    (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
  SELECT gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001', o.id, d.id, p_date, 'pending'
    FROM public.nodes o, public.nodes d
   WHERE o.auto_id = p_o AND d.auto_id = CASE WHEN p_o = 'N4' THEN 'N1' ELSE 'N4' END
  RETURNING id;
$$;
-- Misma forma que el bot: sin usuario web (auth.uid() NULL salvo que el test lo fije).
CREATE FUNCTION pg_temp.receive(p_id uuid, p_at timestamptz) RETURNS void LANGUAGE sql AS $$
  UPDATE public.allocation_plan_details SET status = 'received', received_at = p_at WHERE id = p_id AND status = 'sent';
$$;
CREATE FUNCTION pg_temp.unavail(p_pan uuid, p_from date, p_to date) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.panelist_unavailability (panelist_id, start_date, end_date, reason, status, account_id)
  VALUES (p_pan, p_from, p_to, 'vacation', 'active', 'a0000000-0000-0000-0000-000000000001');
$$;
CREATE FUNCTION pg_temp.st(p_id uuid) RETURNS text LANGUAGE sql AS $$
  SELECT status FROM public.allocation_plan_details WHERE id = p_id;
$$;
CREATE FUNCTION pg_temp.n_one_db(p_id uuid) RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM public.one_db WHERE allocation_detail_id = p_id;
$$;
CREATE FUNCTION pg_temp.n_deferred() RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM public.deferred_samples;
$$;
-- Escenario de ausencia: envio N1->N4 enviado el miercoles 03-03 (o p_sent); P4 indisponible el viernes 03-05.
-- Devuelve el id; el test recibe despues.
CREATE FUNCTION pg_temp.sc1(p_sent timestamptz DEFAULT '2027-03-03 10:00+03') RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  UPDATE public.accounts SET timezone = 'Africa/Nairobi' WHERE id = 'a0000000-0000-0000-0000-000000000001';
  v := pg_temp.mk_sent('N1', 'N4', p_sent, 'T1');
  PERFORM pg_temp.unavail('e4000000-0000-0000-0000-000000000004', '2027-03-05', '2027-03-05');
  RETURN v;
END $$;

-- ===== Caso 1: recibe el lunes, viernes indisponible y sin envios -> anulada + anotada
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid; r record; d record;
BEGIN
  v := pg_temp.sc1();
  PERFORM pg_temp.receive(v, '2027-03-08 10:00+03');
  SELECT * INTO r FROM public.allocation_plan_details WHERE id = v;
  PERFORM pg_temp.fail_if(r.status <> 'cancelled', 'c1 status ' || r.status);
  PERFORM pg_temp.fail_if(r.cancellation_reason IS DISTINCT FROM 'pobox_absent_unavailable', 'c1 reason');
  PERFORM pg_temp.fail_if(r.cancelled_at IS NULL, 'c1 cancelled_at');
  PERFORM pg_temp.fail_if(r.received_at IS DISTINCT FROM '2027-03-08 10:00+03'::timestamptz, 'c1 received_at conservado');
  PERFORM pg_temp.fail_if(pg_temp.n_deferred() <> 1, 'c1 anotaciones ' || pg_temp.n_deferred());
  SELECT * INTO d FROM public.deferred_samples;
  PERFORM pg_temp.fail_if(d.reason <> 'pobox_absent_unavailable', 'c1 d.reason');
  PERFORM pg_temp.fail_if(d.plan_id <> 'cc000000-0000-0000-0000-000000000001', 'c1 d.plan');
  PERFORM pg_temp.fail_if(d.origin_city_id <> 'c1000000-0000-0000-0000-000000000001', 'c1 d.origin_city');
  PERFORM pg_temp.fail_if(d.dest_city_id <> 'c2000000-0000-0000-0000-000000000002', 'c1 d.dest_city');
  PERFORM pg_temp.fail_if(d.fecha_programada <> '2027-03-03', 'c1 d.fecha');
  PERFORM pg_temp.fail_if(d.origin_node_id <> 'b1000000-0000-0000-0000-000000000001', 'c1 d.origin_node');
  PERFORM pg_temp.fail_if(d.destination_node_id <> 'b4000000-0000-0000-0000-000000000004', 'c1 d.destination_node');
  PERFORM pg_temp.fail_if(d.row_snapshot->>'status' IS DISTINCT FROM 'received', 'c1 snapshot status ' || (d.row_snapshot->>'status'));
  PERFORM pg_temp.fail_if(d.created_by IS NOT NULL, 'c1 created_by');
  PERFORM pg_temp.fail_if(pg_temp.n_one_db(v) <> 0, 'c1 one_db');
END $$;
ROLLBACK;

-- ===== Caso 2: recibe el martes; el lunes N4 tenia un envio programado sin declarar -> no_visit
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid;
BEGIN
  UPDATE public.accounts SET timezone = 'Africa/Nairobi' WHERE id = 'a0000000-0000-0000-0000-000000000001';
  v := pg_temp.mk_sent('N1', 'N4', '2027-03-03 10:00+03', 'T1');
  PERFORM pg_temp.mk('N4', '2027-03-08');
  PERFORM pg_temp.receive(v, '2027-03-09 10:00+03');
  PERFORM pg_temp.fail_if(pg_temp.st(v) <> 'cancelled', 'c2 status');
  PERFORM pg_temp.fail_if((SELECT cancellation_reason FROM public.allocation_plan_details WHERE id = v) IS DISTINCT FROM 'pobox_absent_no_visit', 'c2 reason');
  PERFORM pg_temp.fail_if(pg_temp.n_deferred() <> 1, 'c2 anotaciones');
  PERFORM pg_temp.fail_if((SELECT reason FROM public.deferred_samples) <> 'pobox_absent_no_visit', 'c2 d.reason');
END $$;
ROLLBACK;

-- ===== Caso 3: como 1 pero N4 declaro un envio el viernes (fue de todos modos) -> valida
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.sc1();
  PERFORM pg_temp.mk_sent('N4', 'N1', '2027-03-05 09:00+03', 'T2');
  PERFORM pg_temp.receive(v, '2027-03-08 10:00+03');
  PERFORM pg_temp.fail_if(pg_temp.st(v) <> 'received', 'c3 status ' || pg_temp.st(v));
  PERFORM pg_temp.fail_if(pg_temp.n_one_db(v) <> 1, 'c3 one_db ' || pg_temp.n_one_db(v));
  PERFORM pg_temp.fail_if(pg_temp.n_deferred() <> 0, 'c3 anotaciones');
END $$;
ROLLBACK;

-- ===== Caso 4: recibe el miercoles, martes festivo de la cuenta, lunes indisponible -> anulada
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid;
BEGIN
  UPDATE public.accounts SET timezone = 'Africa/Nairobi' WHERE id = 'a0000000-0000-0000-0000-000000000001';
  INSERT INTO public.non_working_days (account_id, postal_center_id, date, type)
  VALUES ('a0000000-0000-0000-0000-000000000001', NULL, '2027-03-09', 'holiday');
  v := pg_temp.mk_sent('N1', 'N4', '2027-03-03 10:00+03', 'T1');
  PERFORM pg_temp.unavail('e4000000-0000-0000-0000-000000000004', '2027-03-08', '2027-03-08');
  PERFORM pg_temp.receive(v, '2027-03-10 10:00+03');
  PERFORM pg_temp.fail_if(pg_temp.st(v) <> 'cancelled', 'c4 status');
  PERFORM pg_temp.fail_if((SELECT cancellation_reason FROM public.allocation_plan_details WHERE id = v) IS DISTINCT FROM 'pobox_absent_unavailable', 'c4 reason');
END $$;
ROLLBACK;

-- ===== Caso 5: viernes sin envio programado ni indisponibilidad -> valida (beneficio de la duda)
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid;
BEGIN
  UPDATE public.accounts SET timezone = 'Africa/Nairobi' WHERE id = 'a0000000-0000-0000-0000-000000000001';
  v := pg_temp.mk_sent('N1', 'N4', '2027-03-03 10:00+03', 'T1');
  PERFORM pg_temp.receive(v, '2027-03-08 10:00+03');
  PERFORM pg_temp.fail_if(pg_temp.st(v) <> 'received', 'c5 status');
  PERFORM pg_temp.fail_if(pg_temp.n_one_db(v) <> 1, 'c5 one_db');
END $$;
ROLLBACK;

-- ===== Caso 6: ciudad sin POBOX (no se llama a pobox_on) -> valida
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.sc1();
  PERFORM pg_temp.receive(v, '2027-03-08 10:00+03');
  PERFORM pg_temp.fail_if(pg_temp.st(v) <> 'received', 'c6 status');
  PERFORM pg_temp.fail_if(pg_temp.n_deferred() <> 0, 'c6 anotaciones');
END $$;
ROLLBACK;

-- ===== Caso 6b: POBOX, destino N1 (C1 tiene 3 nodos), P1 indisponible el viernes -> regla no aplicable
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid;
BEGIN
  UPDATE public.accounts SET timezone = 'Africa/Nairobi' WHERE id = 'a0000000-0000-0000-0000-000000000001';
  v := pg_temp.mk_sent('N4', 'N1', '2027-03-03 10:00+03', 'T1');
  PERFORM pg_temp.unavail('e1000000-0000-0000-0000-000000000001', '2027-03-05', '2027-03-05');
  PERFORM pg_temp.receive(v, '2027-03-08 10:00+03');
  PERFORM pg_temp.fail_if(pg_temp.st(v) <> 'received', 'c6b status');
  PERFORM pg_temp.fail_if(pg_temp.n_deferred() <> 0, 'c6b anotaciones');
END $$;
ROLLBACK;

-- ===== Caso 7a: con usuario web (auth.uid() no nulo) -> valida
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.sc1();
  PERFORM set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000099', true);
  PERFORM pg_temp.receive(v, '2027-03-08 10:00+03');
  PERFORM pg_temp.fail_if(pg_temp.st(v) <> 'received', 'c7a status');
  PERFORM pg_temp.fail_if(pg_temp.n_deferred() <> 0, 'c7a anotaciones');
END $$;
ROLLBACK;

-- ===== Caso 7b: sin usuario pero con onems.skip_pobox_receipt_rule = 'on' -> valida
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
SET LOCAL onems.skip_pobox_receipt_rule = 'on';
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.sc1();
  PERFORM pg_temp.receive(v, '2027-03-08 10:00+03');
  PERFORM pg_temp.fail_if(pg_temp.st(v) <> 'received', 'c7b status');
  PERFORM pg_temp.fail_if(pg_temp.n_deferred() <> 0, 'c7b anotaciones');
END $$;
ROLLBACK;

-- ===== Caso 8: sin delivery_standards, salio el viernes 03-05, recibe lunes, P4 indisponible viernes -> valida
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.sc1('2027-03-05 10:00+03');
  PERFORM pg_temp.receive(v, '2027-03-08 10:00+03');
  PERFORM pg_temp.fail_if(pg_temp.st(v) <> 'received', 'c8 status');
END $$;
ROLLBACK;

-- ===== Caso 8b: estandar en horas, salio el viernes -> anulada (pudo llegar el viernes)
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.sc1('2027-03-05 10:00+03');
  INSERT INTO public.delivery_standards (account_id, carrier_id, product_id, origin_city_id, destination_city_id, standard_time, time_unit)
  VALUES ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',
          'c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002', 6, 'hours');
  PERFORM pg_temp.receive(v, '2027-03-08 10:00+03');
  PERFORM pg_temp.fail_if(pg_temp.st(v) <> 'cancelled', 'c8b status');
  PERFORM pg_temp.fail_if((SELECT cancellation_reason FROM public.allocation_plan_details WHERE id = v) IS DISTINCT FROM 'pobox_absent_unavailable', 'c8b reason');
END $$;
ROLLBACK;

-- ===== Caso 8c: estandar en horas, salio el lunes 08:00 y recibe el lunes 15:00 -> valida
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.sc1('2027-03-08 08:00+03');
  INSERT INTO public.delivery_standards (account_id, carrier_id, product_id, origin_city_id, destination_city_id, standard_time, time_unit)
  VALUES ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',
          'c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002', 6, 'hours');
  PERFORM pg_temp.receive(v, '2027-03-08 15:00+03');
  PERFORM pg_temp.fail_if(pg_temp.st(v) <> 'received', 'c8c status');
END $$;
ROLLBACK;

-- ===== Caso 8d: estandar en dias, salio el viernes -> valida
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.sc1('2027-03-05 10:00+03');
  INSERT INTO public.delivery_standards (account_id, carrier_id, product_id, origin_city_id, destination_city_id, standard_time, time_unit)
  VALUES ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',
          'c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002', 2, 'days');
  PERFORM pg_temp.receive(v, '2027-03-08 10:00+03');
  PERFORM pg_temp.fail_if(pg_temp.st(v) <> 'received', 'c8d status');
END $$;
ROLLBACK;

-- ===== Caso 9: la indisponibilidad es de otro panelista activo del nodo N4 (P5) -> cuenta
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid;
BEGIN
  UPDATE public.accounts SET timezone = 'Africa/Nairobi' WHERE id = 'a0000000-0000-0000-0000-000000000001';
  -- Solo puede haber un panelista activo por nodo: P4 pasa a inactivo (titular antiguo) y P5 es el activo.
  UPDATE public.panelists SET status = 'inactive' WHERE id = 'e4000000-0000-0000-0000-000000000004';
  INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language)
  VALUES ('e5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','P5','Pan5','p5@t.l','5',
          'b4000000-0000-0000-0000-000000000004','active','en');
  v := pg_temp.mk_sent('N1', 'N4', '2027-03-03 10:00+03', 'T1');
  PERFORM pg_temp.unavail('e5000000-0000-0000-0000-000000000005', '2027-03-05', '2027-03-05');
  PERFORM pg_temp.receive(v, '2027-03-08 10:00+03');
  PERFORM pg_temp.fail_if(pg_temp.st(v) <> 'cancelled', 'c9 status');
  PERFORM pg_temp.fail_if((SELECT cancellation_reason FROM public.allocation_plan_details WHERE id = v) IS DISTINCT FROM 'pobox_absent_unavailable', 'c9 reason');
END $$;
ROLLBACK;

-- ===== Caso 12: received_at en UTC domingo 22:30 = lunes 01:30 en Nairobi -> R lunes, D viernes -> anulada
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.sc1();
  PERFORM pg_temp.receive(v, '2027-03-07 22:30+00');
  PERFORM pg_temp.fail_if(pg_temp.st(v) <> 'cancelled', 'c12 status ' || pg_temp.st(v));
END $$;
ROLLBACK;

-- ===== Caso 12b: distingue dia local de dia UTC. Recibe '2027-03-08 22:30+00' = martes 01:30 en Nairobi:
-- R = martes, D = lunes 03-08 (P4 indisponible solo ese dia) -> anulada. Con UTC, D seria el viernes sin prueba.
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid;
BEGIN
  UPDATE public.accounts SET timezone = 'Africa/Nairobi' WHERE id = 'a0000000-0000-0000-0000-000000000001';
  v := pg_temp.mk_sent('N1', 'N4', '2027-03-03 10:00+03', 'T1');
  PERFORM pg_temp.unavail('e4000000-0000-0000-0000-000000000004', '2027-03-08', '2027-03-08');
  PERFORM pg_temp.receive(v, '2027-03-08 22:30+00');
  PERFORM pg_temp.fail_if(pg_temp.st(v) <> 'cancelled', 'c12b status ' || pg_temp.st(v));
  PERFORM pg_temp.fail_if((SELECT cancellation_reason FROM public.allocation_plan_details WHERE id = v) IS DISTINCT FROM 'pobox_absent_unavailable', 'c12b reason');
END $$;
ROLLBACK;

-- ===== Caso 13a: received_at NULL -> queda received, sin anotacion
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.sc1();
  UPDATE public.allocation_plan_details SET status = 'received' WHERE id = v;
  PERFORM pg_temp.fail_if(pg_temp.st(v) <> 'received', 'c13a status ' || pg_temp.st(v));
  PERFORM pg_temp.fail_if(pg_temp.n_deferred() <> 0, 'c13a anotaciones');
END $$;
ROLLBACK;

-- ===== Caso 13b: destination_node_id es NOT NULL en la tabla, asi que no se puede provocar por UPDATE;
-- se prueba la defensa de pobox_receipt_check con una fila en memoria sin nodo de destino -> NULL (valida)
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid; r public.allocation_plan_details%ROWTYPE;
BEGIN
  v := pg_temp.sc1();
  UPDATE public.allocation_plan_details SET received_at = '2027-03-08 10:00+03' WHERE id = v;
  SELECT * INTO r FROM public.allocation_plan_details WHERE id = v;
  PERFORM pg_temp.fail_if(public.pobox_receipt_check(r) IS DISTINCT FROM 'pobox_absent_unavailable', 'c13b control: la fila completa debe anularse');
  r.destination_node_id := NULL;
  PERFORM pg_temp.fail_if(public.pobox_receipt_check(r) IS NOT NULL, 'c13b sin nodo destino debe ser valida');
END $$;
ROLLBACK;

-- ===== Caso 14: zona horaria invalida -> received; el trigger solo emite WARNING
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
ALTER TABLE public.accounts DROP CONSTRAINT accounts_valid_timezone;
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.sc1();
  UPDATE public.accounts SET timezone = 'No/Existe' WHERE id = 'a0000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.receive(v, '2027-03-08 10:00+03');
  PERFORM pg_temp.fail_if(pg_temp.st(v) <> 'received', 'c14 status ' || pg_temp.st(v));
  PERFORM pg_temp.fail_if(pg_temp.n_deferred() <> 0, 'c14 anotaciones');
  -- one_db no se asierta: con zona invalida el propio one_db_compute_transit falla (y transfer_to_one_db lo traga).
  PERFORM pg_temp.fail_if((SELECT cancellation_reason IS NOT NULL OR cancelled_at IS NOT NULL FROM public.allocation_plan_details WHERE id = v), 'c14 sin traza de anulacion');
END $$;
ROLLBACK;

-- ===== Parte B (spec 3.4 bis): reintroduccion mas alla del fin del plan y desglose por motivo.
-- Anotacion de la ciudad C1 (plan Mar27) dejada por el escenario del caso 1; despues sesion de usuario 99.
CREATE FUNCTION pg_temp.mk_annotation() RETURNS void LANGUAGE plpgsql AS $$
DECLARE v uuid;
BEGIN
  v := pg_temp.sc1();
  PERFORM pg_temp.receive(v, '2027-03-08 10:00+03');
  IF pg_temp.n_deferred() <> 1 THEN RAISE EXCEPTION 'FAIL mk_annotation %', pg_temp.n_deferred(); END IF;
  PERFORM set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000099', true);
END $$;
-- Copia de la anotacion existente con otro motivo (otra muestra por compensar de la misma ruta).
CREATE FUNCTION pg_temp.copy_annotation(p_reason text) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.deferred_samples
    (account_id, plan_id, origin_city_id, dest_city_id, origin_node_id, destination_node_id, fecha_programada,
     reason, row_snapshot, created_by)
  SELECT account_id, plan_id, origin_city_id, dest_city_id, origin_node_id, destination_node_id, fecha_programada,
         p_reason, jsonb_build_object('id', gen_random_uuid()), created_by
    FROM public.deferred_samples ORDER BY created_at LIMIT 1;
$$;

-- ===== Caso 10: la anotacion del caso 1 se reintroduce en el periodo 03-15..19 (dentro del plan)
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
SELECT pg_temp.mk_annotation();
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-15', '2027-03-19', true);
  PERFORM pg_temp.fail_if((r->>'success')::boolean IS DISTINCT FROM true, 'c10 success: ' || r::text);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 1, 'c10 reintroduced: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details a
        WHERE a.generation_source = 'compensation' AND a.plan_id = 'cc000000-0000-0000-0000-000000000001'
          AND a.destination_node_id = 'b4000000-0000-0000-0000-000000000004'
          AND a.origin_node_id IN (SELECT id FROM public.nodes WHERE city_id = 'c1000000-0000-0000-0000-000000000001')
          AND a.fecha_programada BETWEEN '2027-03-15' AND '2027-03-19') <> 1, 'c10 detalle compensation');
  PERFORM pg_temp.fail_if((SELECT status FROM public.deferred_samples) IS DISTINCT FROM 'reintroduced', 'c10 estado anotacion');
END $$;
ROLLBACK;

-- ===== Caso 11: el plan termino (end_date 03-10) y el periodo es 03-15..19 -> se reintroduce igualmente;
-- despues, con el plan completado, una nueva anotacion espera como plan_inactive
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
SELECT pg_temp.mk_annotation();
UPDATE public.allocation_plans SET end_date = '2027-03-10' WHERE id = 'cc000000-0000-0000-0000-000000000001';
DO $$
DECLARE r jsonb;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-15', '2027-03-19', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 1, 'c11 reintroduced: ' || r::text);
  PERFORM pg_temp.fail_if((r->'deferred'->'waiting_by_reason'->>'outside_period')::int IS DISTINCT FROM 0, 'c11 sin outside_period: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT status FROM public.deferred_samples ORDER BY created_at LIMIT 1) IS DISTINCT FROM 'reintroduced', 'c11 estado');
  PERFORM pg_temp.copy_annotation('pobox_absent_unavailable');
  UPDATE public.allocation_plans SET status = 'completed' WHERE id = 'cc000000-0000-0000-0000-000000000001';
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-15', '2027-03-19', true);
  PERFORM pg_temp.fail_if((r->'deferred'->'waiting_by_reason'->>'plan_inactive')::int IS DISTINCT FROM 1, 'c11 plan_inactive: ' || r::text);
END $$;
ROLLBACK;

-- ===== Caso 11b: el resumen del registro desglosa por motivo (by_city[].by_reason)
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
SELECT pg_temp.mk_annotation();
SELECT pg_temp.copy_annotation('pobox_absent_no_visit');
DO $$
DECLARE s jsonb;
BEGIN
  s := public.rpc_deferred_samples_summary('a0000000-0000-0000-0000-000000000001');
  PERFORM pg_temp.fail_if((s->'by_city'->0->>'count')::int IS DISTINCT FROM 2, 'c11b count: ' || s::text);
  PERFORM pg_temp.fail_if((s->'by_city'->0->'by_reason'->>'pobox_absent_unavailable')::int IS DISTINCT FROM 1, 'c11b unavailable: ' || s::text);
  PERFORM pg_temp.fail_if((s->'by_city'->0->'by_reason'->>'pobox_absent_no_visit')::int IS DISTINCT FROM 1, 'c11b no_visit: ' || s::text);
END $$;
ROLLBACK;

-- ===== Caso 11c: la compensation reintroducida DESPUES del fin del plan queda fija: 3 balanceos seguidos con
-- 6 pendientes mas en su mismo nodo y dia no la mueven y se mantiene el tope 1 compensation por (nodo, dia)
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.pobox_on();
SELECT pg_temp.mk_annotation();
UPDATE public.allocation_plans SET end_date = '2027-03-10' WHERE id = 'cc000000-0000-0000-0000-000000000001';
DO $$
DECLARE r jsonb; v_id uuid; v_node uuid; v_date date; i int;
BEGIN
  r := public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-15', '2027-03-19', true);
  PERFORM pg_temp.fail_if((r->'deferred'->>'reintroduced')::int IS DISTINCT FROM 1, 'c11c reintroduced: ' || r::text);
  SELECT id, origin_node_id, fecha_programada INTO v_id, v_node, v_date
    FROM public.allocation_plan_details WHERE generation_source = 'compensation';
  PERFORM pg_temp.fail_if(v_date <= '2027-03-10', 'c11c fecha posterior al fin del plan ' || v_date);
  INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
  SELECT gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
         v_node, 'b4000000-0000-0000-0000-000000000004', v_date, 'pending' FROM generate_series(1, 6);
  FOR i IN 1..3 LOOP
    PERFORM public.rpc_balance_city_v2('c1000000-0000-0000-0000-000000000001', '2027-03-15', '2027-03-19', true);
    PERFORM pg_temp.fail_if((SELECT origin_node_id IS DISTINCT FROM v_node OR fecha_programada IS DISTINCT FROM v_date
                               FROM public.allocation_plan_details WHERE id = v_id), 'c11c movida en la ejecucion ' || i);
    PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.allocation_plan_details WHERE generation_source = 'compensation'
                                     AND status <> 'cancelled' GROUP BY origin_node_id, fecha_programada HAVING count(*) > 1),
                            'c11c tope origen en la ejecucion ' || i);
  END LOOP;
END $$;
ROLLBACK;
