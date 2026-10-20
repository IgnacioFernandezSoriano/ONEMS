-- Puesta al dia (migracion 20261020130600_incident_backfill.sql): bajas activas vigentes se resuelven
-- sin avisos (suppress_notifications dentro del DO), bajas canceladas/pasadas pasan a 'resolved'.
-- La migracion se incluye con \ir (ruta relativa a ESTE fichero, funciona con cualquier cwd).
-- Los triggers de incidencias se desactivan para dejar las bajas en 'new', como estaban antes de desplegar.
-- Se usan fechas relativas a current_date porque la puesta al dia filtra por end_date >= current_date.
\set ON_ERROR_STOP on

-- Control: sin la supresion, el mismo escenario SI genera avisos (el test discrimina).
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
CREATE FUNCTION pg_temp.mk(p_o text, p_d text, p_date date) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.allocation_plan_details
    (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
  SELECT 'a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001', o.id, d.id, p_date, 'pending'
    FROM public.nodes o, public.nodes d
   WHERE o.auto_id = p_o AND d.auto_id = p_d
     AND o.account_id = 'a0000000-0000-0000-0000-000000000001' AND d.account_id = 'a0000000-0000-0000-0000-000000000001';
$$;
-- Una muestra N4->N1 (P1 es el receptor, de baja) el LUNES de la semana en curso. La baja empieza ese
-- lunes y acaba current_date+20, asi que la muestra queda dentro de la baja y en la semana en curso
-- cualquier dia de la semana (el motor retrasa la muestra; la fecha antigua esta en la semana en
-- curso y el emisor P4 recibe el aviso). Independiente del dia en que se ejecute el test.
SELECT pg_temp.mk('N4','N1', date_trunc('week', current_date)::date);
INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status)
VALUES ('f0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',
        'e1000000-0000-0000-0000-000000000001', date_trunc('week', current_date)::date, current_date + 20, 'vacation', 'active');
DO $$
DECLARE n int;
BEGIN
  PERFORM public.resolve_unavailability_incident('f0000000-0000-0000-0000-000000000001');
  SELECT count(*) INTO n FROM public.panelist_notification;
  RAISE NOTICE 'control sin supresion: % avisos', n;
  IF n = 0 THEN RAISE EXCEPTION 'FAIL control: el escenario no genera avisos, el test no discrimina'; END IF;
END $$;
ROLLBACK;

-- Puesta al dia
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
CREATE FUNCTION pg_temp.mk(p_o text, p_d text, p_date date) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.allocation_plan_details
    (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
  SELECT 'a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001', o.id, d.id, p_date, 'pending'
    FROM public.nodes o, public.nodes d
   WHERE o.auto_id = p_o AND d.auto_id = p_d
     AND o.account_id = 'a0000000-0000-0000-0000-000000000001' AND d.account_id = 'a0000000-0000-0000-0000-000000000001';
$$;
SELECT pg_temp.mk('N4','N1', date_trunc('week', current_date)::date);
-- Baja activa vigente (P1), baja cancelada (P2) y baja pasada (P3): las tres 'new'.
INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status) VALUES
 ('f0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001', date_trunc('week', current_date)::date, current_date + 20, 'vacation', 'active'),
 ('f0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000002', current_date, current_date + 5, 'vacation', 'cancelled'),
 ('f0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000003', current_date - 30, current_date - 10, 'vacation', 'active');
UPDATE public.panelist_unavailability SET incident_status = 'new', resolved_at = NULL;
\ir ../migrations/20261020130600_incident_backfill.sql
DO $$
DECLARE s text; n int;
BEGIN
  SELECT incident_status INTO s FROM public.panelist_unavailability WHERE id = 'f0000000-0000-0000-0000-000000000001';
  IF s = 'new' THEN RAISE EXCEPTION 'FAIL baja vigente sigue en new'; END IF;
  SELECT count(*) INTO n FROM public.panelist_reassignment_proposal WHERE unavailability_id = 'f0000000-0000-0000-0000-000000000001';
  IF n = 0 THEN RAISE EXCEPTION 'FAIL no se crearon lineas'; END IF;
  SELECT incident_status INTO s FROM public.panelist_unavailability WHERE id = 'f0000000-0000-0000-0000-000000000002';
  IF s <> 'resolved' THEN RAISE EXCEPTION 'FAIL baja cancelada: %', s; END IF;
  SELECT incident_status INTO s FROM public.panelist_unavailability WHERE id = 'f0000000-0000-0000-0000-000000000003';
  IF s <> 'resolved' THEN RAISE EXCEPTION 'FAIL baja pasada: %', s; END IF;
  SELECT count(*) INTO n FROM public.panelist_reassignment_proposal WHERE unavailability_id <> 'f0000000-0000-0000-0000-000000000001';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL se crearon lineas para bajas no vigentes'; END IF;
  SELECT count(*) INTO n FROM public.panelist_notification;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL la puesta al dia genero % avisos', n; END IF;
  RAISE NOTICE 'PASS puesta al dia (lineas creadas, cancelada/pasada resolved, 0 avisos)';
END $$;
ROLLBACK;
