-- Recordatorio de las 13:00 (hora local de la cuenta): "tienes envios sin declarar" (2026-11-05).
-- 2027-03-10 es miercoles; 10:00 UTC = 13:00 en Africa/Nairobi.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

BEGIN;
\ir fixtures/incident_city.sql
UPDATE public.accounts SET timezone = 'Africa/Nairobi' WHERE id = 'a0000000-0000-0000-0000-000000000001';
UPDATE public.panelists SET telegram_id = '1001' WHERE id = 'e1000000-0000-0000-0000-000000000001';
UPDATE public.panelists SET telegram_id = '1002' WHERE id = 'e2000000-0000-0000-0000-000000000002';
UPDATE public.panelists SET telegram_id = '1003' WHERE id = 'e3000000-0000-0000-0000-000000000003';
-- P4 sin telegram

INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status) VALUES
  -- P1: uno de hoy y uno atrasado (ayer, ya avisado por la lista)
  ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-10','pending'),
  ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-09','notified'),
  -- P1: uno de mañana (no cuenta)
  ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-11','pending'),
  -- P2: el de hoy ya enviado
  ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000002','b4000000-0000-0000-0000-000000000004','2027-03-10','sent'),
  -- P3: tiene uno hoy pero esta de baja hoy
  ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000003','b4000000-0000-0000-0000-000000000004','2027-03-10','pending'),
  -- P4: tiene uno hoy pero no tiene telegram
  ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','b1000000-0000-0000-0000-000000000001','2027-03-10','pending');
SET LOCAL session_replication_role = replica;  -- sin el motor de incidencias: solo importa la baja como dato
INSERT INTO public.panelist_unavailability (account_id, panelist_id, start_date, end_date, reason, status)
VALUES ('a0000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000003','2027-03-10','2027-03-10','vacation','active');
SET LOCAL session_replication_role = origin;

DO $$
DECLARE n int; p jsonb;
BEGIN
  -- 12:00 local: aun no
  n := public.enqueue_send_reminders('2027-03-10 09:00+00');
  PERFORM pg_temp.fail_if(n <> 0 OR EXISTS (SELECT 1 FROM public.panelist_notification WHERE kind = 'send_reminder'), '12:00 no debe avisar');

  -- 13:00 local: solo P1, con 1 de hoy y 1 atrasado
  n := public.enqueue_send_reminders('2027-03-10 10:00+00');
  PERFORM pg_temp.fail_if(n <> 1, 'a las 13:00 debe avisar a 1 panelista, avisa a ' || n);
  SELECT payload INTO p FROM public.panelist_notification
   WHERE kind = 'send_reminder' AND panelist_id = 'e1000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.fail_if(p IS NULL, 'P1 sin aviso');
  PERFORM pg_temp.fail_if((p->>'today')::int <> 1 OR (p->>'overdue')::int <> 1 OR p->>'local_date' <> '2027-03-10', 'payload: ' || p::text);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_notification WHERE kind = 'send_reminder'
                                    AND panelist_id <> 'e1000000-0000-0000-0000-000000000001'), 'avisa a quien no debe');

  -- repetir la misma hora (o el mismo dia): sin duplicado
  n := public.enqueue_send_reminders('2027-03-10 10:30+00');
  PERFORM pg_temp.fail_if(n <> 0 OR (SELECT count(*) FROM public.panelist_notification WHERE kind = 'send_reminder') <> 1, 'duplicado');

  -- sabado a las 13:00: no es dia laborable
  n := public.enqueue_send_reminders('2027-03-13 10:00+00');
  PERFORM pg_temp.fail_if(n <> 0, 'sabado no debe avisar');

  -- otra cuenta sin tocar
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_notification WHERE account_id <> 'a0000000-0000-0000-0000-000000000001'), 'otra cuenta');
END $$;
ROLLBACK;

-- permisos y cron
DO $$
BEGIN
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.enqueue_send_reminders(timestamptz)', 'EXECUTE'), 'authenticated no debe poder lanzar avisos');
  PERFORM pg_temp.fail_if(has_function_privilege('anon', 'public.enqueue_send_reminders(timestamptz)', 'EXECUTE'), 'anon no debe poder lanzar avisos');
END $$;

SELECT 'send_reminder OK';
