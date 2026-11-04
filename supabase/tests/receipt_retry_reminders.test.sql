-- Errores de recepcion: reintentos de etiquetas no encontradas, recordatorios al panelista y cola de avisos
-- (spec 2026-11-04, tarea 2). Mismo fixture que receipt_cases: C1 (N1,N2,N3), C2 (N4); receptor P4 (telegram '4004')
-- en N4/C2; remitente P1 en N1. Cuenta en Africa/Nairobi (sin festivos: laborables = lunes a viernes).
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;
CREATE FUNCTION pg_temp.setup() RETURNS void LANGUAGE sql AS $$
  UPDATE public.accounts SET timezone = 'Africa/Nairobi' WHERE id = 'a0000000-0000-0000-0000-000000000001';
  UPDATE public.panelists SET telegram_id = ' 4004 ' WHERE id = 'e4000000-0000-0000-0000-000000000004';
$$;
CREATE FUNCTION pg_temp.pobox_on() RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.account_config (account_id, pobox_enabled)
  VALUES ('a0000000-0000-0000-0000-000000000001', true)
  ON CONFLICT (account_id) DO UPDATE SET pobox_enabled = true;
$$;
CREATE FUNCTION pg_temp.mk_det(p_o text, p_d text, p_status text, p_tag text,
                               p_sent timestamptz DEFAULT now() - interval '2 days') RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.allocation_plan_details
    (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, sent_at, tag_id,
     origin_panelist_id, destination_panelist_id)
  SELECT gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001', o.id, d.id,
         p_sent::date, p_status, CASE WHEN p_status = 'sent' THEN p_sent END, p_tag,
         (SELECT id FROM public.panelists WHERE node_id = o.id ORDER BY panelist_code LIMIT 1),
         (SELECT id FROM public.panelists WHERE node_id = d.id ORDER BY panelist_code LIMIT 1)
    FROM public.nodes o, public.nodes d
   WHERE o.auto_id = p_o AND d.auto_id = p_d
  RETURNING id;
$$;
-- Caso not_found del receptor P4 con el primer intento fijado.
CREATE FUNCTION pg_temp.not_found_case(p_tag text, p_first timestamptz) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  r := public.bot_receive_parcel('4004', p_tag);
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'not_found', 'not_found_case ' || r::text);
  UPDATE public.receipt_case SET first_attempt_at = p_first, last_attempt_at = p_first WHERE id = (r->>'case_id')::uuid;
  RETURN (r->>'case_id')::uuid;
END $$;
-- Caso ya resuelto insertado a mano (para probar los recordatorios aislados).
CREATE FUNCTION pg_temp.mk_case(p_reason text, p_status text, p_culprit uuid, p_role text, p_first timestamptz,
                                p_tag text DEFAULT '00012345') RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.receipt_case (account_id, panelist_id, telegram_id, tag_raw, tag_norm, reason, status,
                                   culprit_panelist_id, culprit_role, first_attempt_at, last_attempt_at, resolved_at)
  VALUES ('a0000000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000004', '4004', p_tag, p_tag,
          p_reason, p_status, p_culprit, p_role, p_first, p_first, p_first)
  RETURNING id;
$$;
CREATE FUNCTION pg_temp.n_rem() RETURNS bigint LANGUAGE sql AS $$
  SELECT count(*) FROM public.panelist_notification WHERE kind = 'receipt_reminder' $$;

-- ===== Caso 1: not_found el lunes 10:00+03; despues aparece el envio (declarado antes) -> el reintento lo registra
-- con la fecha del primer intento; caso fixed/ok; sin recordatorio
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v_case uuid; v uuid; n int; c record; d record; v_cases bigint;
BEGIN
  v_case := pg_temp.not_found_case('12345', '2026-11-02 10:00+03');
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345', '2026-11-01 09:00+03');
  v_cases := (SELECT count(*) FROM public.receipt_case);
  n := public.receipt_retry_pending();
  PERFORM pg_temp.fail_if(n IS DISTINCT FROM 1, 'c1 resueltos ' || coalesce(n::text, 'NULL'));
  SELECT * INTO d FROM public.allocation_plan_details WHERE id = v;
  PERFORM pg_temp.fail_if(d.status <> 'received', 'c1 status ' || d.status);
  PERFORM pg_temp.fail_if(d.received_at IS DISTINCT FROM '2026-11-02 10:00+03'::timestamptz, 'c1 received_at = primer intento');
  PERFORM pg_temp.fail_if(d.destination_panelist_id IS DISTINCT FROM 'e4000000-0000-0000-0000-000000000004', 'c1 dest panelist');
  SELECT * INTO c FROM public.receipt_case WHERE id = v_case;
  PERFORM pg_temp.fail_if(c.status <> 'fixed' OR c.reason <> 'ok', 'c1 caso ' || c.status || '/' || c.reason);
  PERFORM pg_temp.fail_if(c.detail_id IS DISTINCT FROM v OR c.resolved_at IS NULL, 'c1 detail/resolved');
  PERFORM pg_temp.fail_if(c.culprit_role IS NOT NULL OR c.culprit_panelist_id IS NOT NULL, 'c1 sin culpable');
  PERFORM pg_temp.fail_if(c.attempts <> 1, 'c1 el reintento no suma intentos');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.receipt_case) <> v_cases, 'c1 sin casos nuevos');
  PERFORM pg_temp.fail_if(pg_temp.n_rem() <> 0, 'c1 sin recordatorio');
  -- un segundo pase no hace nada
  PERFORM pg_temp.fail_if(public.receipt_retry_pending() <> 0, 'c1 segundo pase');
END $$;
ROLLBACK;

-- ===== Caso 1b: el envio se declara DESPUES del primer intento -> not_sent_cancelled, compensado, culpa del
-- remitente y recordatorio al remitente
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v_case uuid; v uuid; n int; c record; m record;
BEGIN
  v_case := pg_temp.not_found_case('12345', '2026-11-02 10:00+03');
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345', '2026-11-03 09:00+03');
  n := public.receipt_retry_pending();
  PERFORM pg_temp.fail_if(n IS DISTINCT FROM 1, 'c1b resueltos ' || coalesce(n::text, 'NULL'));
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v) <> 'cancelled', 'c1b anulado');
  PERFORM pg_temp.fail_if((SELECT cancellation_reason FROM public.allocation_plan_details WHERE id = v)
                          IS DISTINCT FROM 'receipt_before_sent', 'c1b motivo');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.deferred_samples WHERE reason = 'receipt_before_sent') <> 1, 'c1b ds');
  SELECT * INTO c FROM public.receipt_case WHERE id = v_case;
  PERFORM pg_temp.fail_if(c.status <> 'compensated' OR c.reason <> 'not_sent_cancelled', 'c1b caso ' || c.status || '/' || c.reason);
  PERFORM pg_temp.fail_if(c.culprit_role IS DISTINCT FROM 'sender'
                          OR c.culprit_panelist_id IS DISTINCT FROM 'e1000000-0000-0000-0000-000000000001', 'c1b culprit');
  PERFORM pg_temp.fail_if(pg_temp.n_rem() <> 1, 'c1b un recordatorio');
  SELECT * INTO m FROM public.panelist_notification WHERE kind = 'receipt_reminder';
  PERFORM pg_temp.fail_if(m.panelist_id IS DISTINCT FROM 'e1000000-0000-0000-0000-000000000001', 'c1b al remitente');
  PERFORM pg_temp.fail_if(m.payload->>'reason' IS DISTINCT FROM 'not_sent_cancelled', 'c1b payload reason');
  PERFORM pg_temp.fail_if(m.payload->>'local_date' IS DISTINCT FROM ((now() AT TIME ZONE 'Africa/Nairobi')::date)::text,
                          'c1b local_date = dia de envio (hoy)');
  PERFORM pg_temp.fail_if(m.case_id IS DISTINCT FROM v_case OR m.payload->>'case_id' IS DISTINCT FROM v_case::text, 'c1b case_id');
END $$;
ROLLBACK;

-- ===== Caso 1c: la regla POBOX se evalua con la fecha del primer intento (lunes 26/10 -> dia de recogida
-- viernes 23/10, con un envio programado desde N4 sin declarar) -> pobox_absent_no_visit, recordatorio al receptor
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
SELECT pg_temp.pobox_on();
DO $$
DECLARE v_case uuid; v uuid; n int; c record;
BEGIN
  v_case := pg_temp.not_found_case('12345', '2026-10-26 10:00+03');
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345', '2026-10-16 10:00+03');
  INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
  VALUES (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
          'b4000000-0000-0000-0000-000000000004', 'b1000000-0000-0000-0000-000000000001', '2026-10-23', 'pending');
  n := public.receipt_retry_pending();
  PERFORM pg_temp.fail_if(n IS DISTINCT FROM 1, 'c1c resueltos ' || coalesce(n::text, 'NULL'));
  PERFORM pg_temp.fail_if((SELECT cancellation_reason FROM public.allocation_plan_details WHERE id = v)
                          IS DISTINCT FROM 'pobox_absent_no_visit', 'c1c motivo');
  PERFORM pg_temp.fail_if((SELECT received_at FROM public.allocation_plan_details WHERE id = v)
                          IS DISTINCT FROM '2026-10-26 10:00+03'::timestamptz, 'c1c received_at');
  SELECT * INTO c FROM public.receipt_case WHERE id = v_case;
  PERFORM pg_temp.fail_if(c.status <> 'compensated' OR c.reason <> 'pobox_absent_no_visit', 'c1c caso');
  PERFORM pg_temp.fail_if(c.culprit_role IS DISTINCT FROM 'receiver'
                          OR c.culprit_panelist_id IS DISTINCT FROM 'e4000000-0000-0000-0000-000000000004', 'c1c culprit');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_notification WHERE kind = 'receipt_reminder'
                             AND panelist_id = 'e4000000-0000-0000-0000-000000000004') <> 1, 'c1c recordatorio al receptor');
END $$;
ROLLBACK;

-- ===== Caso 2: not_found y nada aparece; primer intento hace 8 dias naturales (>= 5 laborables) -> needs_decision;
-- uno de ayer sigue pending
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v_old uuid; v_new uuid; n int; c record;
BEGIN
  v_old := pg_temp.not_found_case('12345', now() - interval '8 days');
  v_new := pg_temp.not_found_case('22222', now() - interval '1 day');
  n := public.receipt_retry_pending();
  PERFORM pg_temp.fail_if(n IS DISTINCT FROM 0, 'c2 resueltos ' || coalesce(n::text, 'NULL'));
  SELECT * INTO c FROM public.receipt_case WHERE id = v_old;
  PERFORM pg_temp.fail_if(c.status <> 'needs_decision' OR c.reason <> 'not_found', 'c2 caso viejo ' || c.status || '/' || c.reason);
  PERFORM pg_temp.fail_if(c.resolved_at IS NOT NULL, 'c2 sin resolver');
  PERFORM pg_temp.fail_if((SELECT status FROM public.receipt_case WHERE id = v_new) <> 'pending', 'c2 caso reciente');
  PERFORM pg_temp.fail_if(pg_temp.n_rem() <> 0, 'c2 sin recordatorio');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.receipt_case) <> 2, 'c2 sin casos nuevos');
END $$;
ROLLBACK;
-- 2b: festivos cuentan como no laborables (8 dias naturales, pero 4 de los laborables son festivos -> pending)
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v uuid; v_d date; v_today date := (now() AT TIME ZONE 'Africa/Nairobi')::date; k int := 0;
BEGIN
  v := pg_temp.not_found_case('12345', now() - interval '8 days');
  -- deja solo 4 laborables en el tramo (primer dia excluido, hoy incluido)
  FOR v_d IN SELECT g::date FROM generate_series(v_today - 7, v_today, interval '1 day') g ORDER BY 1 LOOP
    IF EXTRACT(isodow FROM v_d) <= 5 THEN
      k := k + 1;
      IF k > 4 THEN
        INSERT INTO public.non_working_days (account_id, date, reason)
        VALUES ('a0000000-0000-0000-0000-000000000001', v_d, 'test');
      END IF;
    END IF;
  END LOOP;
  PERFORM public.receipt_retry_pending();
  PERFORM pg_temp.fail_if((SELECT status FROM public.receipt_case WHERE id = v) <> 'pending', 'c2b festivos');
END $$;
ROLLBACK;

-- ===== Caso 3: not_found y despues un candidato typo unico -> fixed / ok_typo_fixed, 1 recordatorio al remitente
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v_case uuid; v uuid; n int; c record; m record;
BEGIN
  v_case := pg_temp.not_found_case('00012395', now() - interval '1 hour');
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345', now() - interval '2 days');
  n := public.receipt_retry_pending();
  PERFORM pg_temp.fail_if(n IS DISTINCT FROM 1, 'c3 resueltos ' || coalesce(n::text, 'NULL'));
  PERFORM pg_temp.fail_if((SELECT tag_id FROM public.allocation_plan_details WHERE id = v) IS DISTINCT FROM '00012395', 'c3 tag');
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v) <> 'received', 'c3 status');
  SELECT * INTO c FROM public.receipt_case WHERE id = v_case;
  PERFORM pg_temp.fail_if(c.status <> 'fixed' OR c.reason <> 'ok_typo_fixed', 'c3 caso ' || c.status || '/' || c.reason);
  PERFORM pg_temp.fail_if(c.original_tag IS DISTINCT FROM '00012345', 'c3 original_tag ' || coalesce(c.original_tag, 'NULL'));
  PERFORM pg_temp.fail_if((SELECT idtag FROM public.allocation_plan_details WHERE id = v) IS DISTINCT FROM '00012395', 'c3 idtag');
  PERFORM pg_temp.fail_if(c.culprit_role IS DISTINCT FROM 'sender'
                          OR c.culprit_panelist_id IS DISTINCT FROM 'e1000000-0000-0000-0000-000000000001', 'c3 culprit');
  PERFORM pg_temp.fail_if(pg_temp.n_rem() <> 1, 'c3 un recordatorio');
  SELECT * INTO m FROM public.panelist_notification WHERE kind = 'receipt_reminder';
  PERFORM pg_temp.fail_if(m.panelist_id IS DISTINCT FROM 'e1000000-0000-0000-0000-000000000001', 'c3 al remitente');
  PERFORM pg_temp.fail_if(m.account_id IS DISTINCT FROM 'a0000000-0000-0000-0000-000000000001', 'c3 cuenta');
  PERFORM pg_temp.fail_if(m.status <> 'pending_send', 'c3 pending_send');
  PERFORM pg_temp.fail_if(m.payload->>'reason' IS DISTINCT FROM 'ok_typo_fixed'
                          OR m.payload->>'tag' IS DISTINCT FROM '00012395'
                          OR (m.payload->>'escalated')::boolean IS DISTINCT FROM false
                          OR m.payload->>'local_date' IS DISTINCT FROM ((now() AT TIME ZONE 'Africa/Nairobi')::date)::text,
                          'c3 payload ' || m.payload::text);
  PERFORM pg_temp.fail_if(m.send_after IS NULL, 'c3 send_after');
END $$;
ROLLBACK;
-- 3b: dos candidatos en el reintento -> ambiguous_typo / needs_decision, nada cambia
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v_case uuid; c record;
BEGIN
  v_case := pg_temp.not_found_case('00012346', now() - interval '1 hour');
  PERFORM pg_temp.mk_det('N1', 'N4', 'sent', '00012345');
  PERFORM pg_temp.mk_det('N2', 'N4', 'sent', '00012347');
  PERFORM pg_temp.fail_if(public.receipt_retry_pending() <> 0, 'c3b resueltos');
  SELECT * INTO c FROM public.receipt_case WHERE id = v_case;
  PERFORM pg_temp.fail_if(c.status <> 'needs_decision' OR c.reason <> 'ambiguous_typo', 'c3b caso ' || c.status || '/' || c.reason);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.allocation_plan_details WHERE status <> 'sent'
                                     OR tag_id NOT IN ('00012345', '00012347')), 'c3b nada cambia');
  PERFORM pg_temp.fail_if(pg_temp.n_rem() <> 0, 'c3b sin recordatorio');
END $$;
ROLLBACK;

-- ===== Caso 4: receipt_send_after (Nairobi): 23:30 -> 08:00 dia siguiente; 07:00 -> 08:00 mismo dia; 10:00 igual
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.setup();
DO $$
DECLARE a uuid := 'a0000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM pg_temp.fail_if(public.receipt_send_after(a, '2026-11-04 23:30+03') IS DISTINCT FROM '2026-11-05 08:00+03'::timestamptz, 'c4 23:30');
  PERFORM pg_temp.fail_if(public.receipt_send_after(a, '2026-11-04 07:00+03') IS DISTINCT FROM '2026-11-04 08:00+03'::timestamptz, 'c4 07:00');
  PERFORM pg_temp.fail_if(public.receipt_send_after(a, '2026-11-04 10:00+03') IS DISTINCT FROM '2026-11-04 10:00+03'::timestamptz, 'c4 10:00');
  PERFORM pg_temp.fail_if(public.receipt_send_after(a, '2026-11-04 08:00+03') IS DISTINCT FROM '2026-11-04 08:00+03'::timestamptz, 'c4 08:00');
  PERFORM pg_temp.fail_if(public.receipt_send_after(a, '2026-11-04 20:00+03') IS DISTINCT FROM '2026-11-05 08:00+03'::timestamptz, 'c4 20:00');
  -- cuenta sin zona horaria -> UTC
  PERFORM pg_temp.fail_if(public.receipt_send_after('a0000000-0000-0000-0000-000000000002', '2026-11-04 21:00+00')
                          IS DISTINCT FROM '2026-11-05 08:00+00'::timestamptz, 'c4 UTC');
END $$;
ROLLBACK;

-- ===== Caso 5: tres pobox_absent_no_visit del mismo receptor resueltos en 3 dias -> 3 recordatorios; el 3.o escalated
-- (los dos primeros se dan por encolados los dias anteriores ajustando su local_date)
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE p4 uuid := 'e4000000-0000-0000-0000-000000000004'; c1 uuid; c2 uuid; c3 uuid; c4 uuid; r1 uuid; r2 uuid; r3 uuid;
BEGIN
  c1 := pg_temp.mk_case('pobox_absent_no_visit', 'compensated', p4, 'receiver', now() - interval '2 days', '00011111');
  r1 := public.enqueue_receipt_reminder(c1);
  UPDATE public.panelist_notification
     SET payload = jsonb_set(payload, '{local_date}', to_jsonb(((now() AT TIME ZONE 'Africa/Nairobi')::date - 2)::text))
   WHERE id = r1;
  c2 := pg_temp.mk_case('pobox_absent_no_visit', 'compensated', p4, 'receiver', now() - interval '1 day', '00022222');
  r2 := public.enqueue_receipt_reminder(c2);
  UPDATE public.panelist_notification
     SET payload = jsonb_set(payload, '{local_date}', to_jsonb(((now() AT TIME ZONE 'Africa/Nairobi')::date - 1)::text))
   WHERE id = r2;
  c3 := pg_temp.mk_case('pobox_absent_no_visit', 'compensated', p4, 'receiver', now(), '00033333');
  r3 := public.enqueue_receipt_reminder(c3);
  PERFORM pg_temp.fail_if(r1 IS NULL OR r2 IS NULL OR r3 IS NULL, 'c5 ids');
  PERFORM pg_temp.fail_if(pg_temp.n_rem() <> 3, 'c5 tres recordatorios ' || pg_temp.n_rem());
  PERFORM pg_temp.fail_if((SELECT (payload->>'escalated')::boolean FROM public.panelist_notification WHERE id = r1), 'c5 1.o no escalado');
  PERFORM pg_temp.fail_if((SELECT (payload->>'escalated')::boolean FROM public.panelist_notification WHERE id = r2), 'c5 2.o no escalado');
  PERFORM pg_temp.fail_if(NOT (SELECT (payload->>'escalated')::boolean FROM public.panelist_notification WHERE id = r3), 'c5 3.o escalado');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_notification WHERE kind = 'receipt_reminder' AND panelist_id <> p4),
                          'c5 todos al receptor');
  -- otro motivo del mismo panelista no cuenta para la escalada; un caso de hace 8 dias tampoco
  c4 := pg_temp.mk_case('wrong_city_cancelled', 'compensated', p4, 'sender', now(), '00044444');
  PERFORM pg_temp.fail_if((SELECT (payload->>'escalated')::boolean FROM public.panelist_notification
                            WHERE id = public.enqueue_receipt_reminder(c4)), 'c5 otro motivo');
  -- encolar dos veces el mismo caso: uno solo
  PERFORM pg_temp.fail_if(public.enqueue_receipt_reminder(c3) IS NOT NULL, 'c5 duplicado devuelve NULL');
  PERFORM pg_temp.fail_if(pg_temp.n_rem() <> 4, 'c5 sin duplicados');
END $$;
ROLLBACK;
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE p4 uuid := 'e4000000-0000-0000-0000-000000000004'; c uuid;
BEGIN
  PERFORM pg_temp.mk_case('pobox_absent_no_visit', 'compensated', p4, 'receiver', now() - interval '9 days', '00011111');
  PERFORM pg_temp.mk_case('pobox_absent_no_visit', 'compensated', p4, 'receiver', now() - interval '8 days', '00022222');
  c := pg_temp.mk_case('pobox_absent_no_visit', 'compensated', p4, 'receiver', now(), '00033333');
  PERFORM pg_temp.fail_if((SELECT (payload->>'escalated')::boolean FROM public.panelist_notification
                            WHERE id = public.enqueue_receipt_reminder(c)), 'c5b fuera de los 7 dias');
END $$;
ROLLBACK;

-- ===== Caso 6: dos not_sent_cancelled del mismo remitente el mismo dia (por el bot) -> 1 solo recordatorio
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE r1 jsonb; r2 jsonb; m record;
BEGIN
  PERFORM pg_temp.mk_det('N1', 'N4', 'pending', '00012345');
  PERFORM pg_temp.mk_det('N1', 'N4', 'pending', '00022222');
  r1 := public.bot_receive_parcel('4004', '12345');
  r2 := public.bot_receive_parcel('4004', '22222');
  PERFORM pg_temp.fail_if(r1->>'outcome' IS DISTINCT FROM 'not_sent_cancelled'
                          OR r2->>'outcome' IS DISTINCT FROM 'not_sent_cancelled', 'c6 outcomes');
  PERFORM pg_temp.fail_if(r1->>'case_id' IS NULL OR r2->>'case_id' IS NULL OR r1->>'case_id' = r2->>'case_id', 'c6 dos casos');
  PERFORM pg_temp.fail_if(pg_temp.n_rem() <> 1, 'c6 un recordatorio ' || pg_temp.n_rem());
  SELECT * INTO m FROM public.panelist_notification WHERE kind = 'receipt_reminder';
  PERFORM pg_temp.fail_if(m.panelist_id IS DISTINCT FROM 'e1000000-0000-0000-0000-000000000001', 'c6 al remitente');
  PERFORM pg_temp.fail_if(m.case_id::text IS DISTINCT FROM r1->>'case_id', 'c6 el primero');
  PERFORM pg_temp.fail_if(m.send_after IS DISTINCT FROM public.receipt_send_after('a0000000-0000-0000-0000-000000000001', now()),
                          'c6 send_after');
END $$;
ROLLBACK;

-- ===== Caso 7: pobox_absent_unavailable (por el bot) -> 0 recordatorios; tampoco para informative / needs_decision / ok
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid; v_d date; r jsonb; p4 uuid := 'e4000000-0000-0000-0000-000000000004';
BEGIN
  v_d := public.pobox_previous_collection_day('a0000000-0000-0000-0000-000000000001', (now() AT TIME ZONE 'Africa/Nairobi')::date);
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345', ((v_d - 7)::text || ' 10:00+03')::timestamptz);
  INSERT INTO public.panelist_unavailability (panelist_id, start_date, end_date, reason, status, account_id)
  VALUES (p4, v_d, v_d, 'vacation', 'active', 'a0000000-0000-0000-0000-000000000001');
  r := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'pobox_absent_unavailable', 'c7 outcome ' || r::text);
  PERFORM pg_temp.fail_if(r->>'case_id' IS NULL, 'c7 caso');
  PERFORM pg_temp.fail_if(public.enqueue_receipt_reminder((r->>'case_id')::uuid) IS NOT NULL, 'c7 enqueue directo');
  PERFORM pg_temp.fail_if(public.enqueue_receipt_reminder(pg_temp.mk_case('already_received', 'informative', NULL, NULL, now(), '1'))
                          IS NOT NULL, 'c7 informative');
  PERFORM pg_temp.fail_if(public.enqueue_receipt_reminder(pg_temp.mk_case('ambiguous_typo', 'needs_decision', NULL, NULL, now(), '2'))
                          IS NOT NULL, 'c7 needs_decision');
  PERFORM pg_temp.fail_if(public.enqueue_receipt_reminder(pg_temp.mk_case('ok_same_city', 'fixed', p4, 'sender', now(), '3'))
                          IS NOT NULL, 'c7 ok_same_city');
  PERFORM pg_temp.fail_if(public.enqueue_receipt_reminder(gen_random_uuid()) IS NOT NULL, 'c7 caso inexistente');
  PERFORM pg_temp.fail_if(pg_temp.n_rem() <> 0, 'c7 sin recordatorios');
END $$;
ROLLBACK;

-- ===== Caso 8: fail-open: si el recordatorio falla, el bot contesta y el caso queda registrado
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
ALTER TABLE public.panelist_notification ADD CONSTRAINT x CHECK (false) NOT VALID;
DO $$
DECLARE v uuid; r jsonb;
BEGIN
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345');
  r := public.bot_receive_parcel('4004', '00012354');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'ok_typo_fixed', 'c8 outcome ' || r::text);
  PERFORM pg_temp.fail_if(r->>'case_id' IS NULL, 'c8 el caso sobrevive');
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v) <> 'received', 'c8 status');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_notification) <> 0, 'c8 sin aviso');
END $$;
ROLLBACK;
-- 8b: un fallo en un caso no detiene el reintento de los demas
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
ALTER TABLE public.panelist_notification ADD CONSTRAINT x CHECK (false) NOT VALID;
DO $$
DECLARE v_a uuid; v_b uuid;
BEGIN
  v_a := pg_temp.not_found_case('00012395', now() - interval '2 hours');
  v_b := pg_temp.not_found_case('00055555', now() - interval '1 hour');
  PERFORM pg_temp.mk_det('N1', 'N4', 'sent', '00012345');
  PERFORM pg_temp.mk_det('N1', 'N4', 'sent', '00055555');
  PERFORM pg_temp.fail_if(public.receipt_retry_pending() <> 2, 'c8b resueltos');
  PERFORM pg_temp.fail_if((SELECT status FROM public.receipt_case WHERE id = v_a) <> 'fixed', 'c8b a (recordatorio fallido)');
  PERFORM pg_temp.fail_if((SELECT status FROM public.receipt_case WHERE id = v_b) <> 'fixed', 'c8b b');
END $$;
ROLLBACK;

-- ===== Caso 9: esquema de la cola, cron y permisos
BEGIN;
\ir fixtures/incident_city.sql
DO $$
BEGIN
  INSERT INTO public.panelist_notification (account_id, panelist_id, kind)
  VALUES ('a0000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'manager_notice'),
         ('a0000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'broadcast'),
         ('a0000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'material_pending_released');
  BEGIN
    INSERT INTO public.panelist_notification (account_id, panelist_id, kind)
    VALUES ('a0000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'xxx');
    RAISE EXCEPTION 'FAIL c9 kind invalido aceptado';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'receipt-retry' AND schedule = '*/30 * * * *'
                                        AND command ILIKE '%receipt_retry_pending()%'), 'c9 cron');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM cron.job WHERE jobname = 'receipt-retry') <> 1, 'c9 cron unico');
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.receipt_retry_pending()', 'EXECUTE'), 'c9 retry authenticated');
  PERFORM pg_temp.fail_if(has_function_privilege('anon', 'public.receipt_retry_pending()', 'EXECUTE'), 'c9 retry anon');
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.enqueue_receipt_reminder(uuid)', 'EXECUTE'), 'c9 enqueue authenticated');
  PERFORM pg_temp.fail_if(has_function_privilege('anon', 'public.enqueue_receipt_reminder(uuid)', 'EXECUTE'), 'c9 enqueue anon');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('service_role', 'public.receipt_retry_pending()', 'EXECUTE'), 'c9 retry service_role');
  PERFORM pg_temp.fail_if(has_table_privilege('authenticated', 'public.panelist_notification', 'INSERT'), 'c9 insert directo');
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.bot_receive_parcel(text,text)', 'EXECUTE'), 'c9 bot authenticated');
END $$;
ROLLBACK;

-- ===== Caso 10 (M6): tres casos del mismo remitente con primer intento en 3 dias distintos, resueltos juntos por el
-- reintento -> 1 solo recordatorio (clave = dia de envio)
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE m record;
BEGIN
  PERFORM pg_temp.not_found_case('00011111', now() - interval '3 days');
  PERFORM pg_temp.not_found_case('00022222', now() - interval '2 days');
  PERFORM pg_temp.not_found_case('00033333', now() - interval '1 day');
  PERFORM pg_temp.mk_det('N1', 'N4', 'sent', '00011112', now() - interval '6 days');
  PERFORM pg_temp.mk_det('N1', 'N4', 'sent', '00022223', now() - interval '6 days');
  PERFORM pg_temp.mk_det('N1', 'N4', 'sent', '00033334', now() - interval '6 days');
  PERFORM pg_temp.fail_if(public.receipt_retry_pending() <> 3, 'c10 resueltos');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.receipt_case WHERE status = 'fixed' AND reason = 'ok_typo_fixed') <> 3, 'c10 casos');
  PERFORM pg_temp.fail_if(pg_temp.n_rem() <> 1, 'c10 un recordatorio ' || pg_temp.n_rem());
  SELECT * INTO m FROM public.panelist_notification WHERE kind = 'receipt_reminder';
  PERFORM pg_temp.fail_if(m.panelist_id IS DISTINCT FROM 'e1000000-0000-0000-0000-000000000001', 'c10 al remitente');
  PERFORM pg_temp.fail_if(m.payload->>'local_date' IS DISTINCT FROM ((now() AT TIME ZONE 'Africa/Nairobi')::date)::text, 'c10 local_date');
END $$;
ROLLBACK;

-- ===== Caso 11 (I1): not_found y despues aparece un envio con etiqueta casi igual (1 cifra) declarado DESPUES del
-- primer intento -> el reintento no lo toca (etiqueta, destino y estado intactos; el caso sigue pendiente)
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v_case uuid; v uuid; d record; c record;
BEGIN
  v_case := pg_temp.not_found_case('00012395', now() - interval '2 days');
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345', now() - interval '1 day');
  PERFORM pg_temp.fail_if(public.receipt_retry_pending() <> 0, 'c11 resueltos');
  SELECT * INTO d FROM public.allocation_plan_details WHERE id = v;
  PERFORM pg_temp.fail_if(d.tag_id <> '00012345' OR d.status <> 'sent' OR d.received_at IS NOT NULL
                          OR d.destination_node_id IS DISTINCT FROM 'b4000000-0000-0000-0000-000000000004', 'c11 envio intacto');
  SELECT * INTO c FROM public.receipt_case WHERE id = v_case;
  PERFORM pg_temp.fail_if(c.status <> 'pending' OR c.reason <> 'not_found' OR c.detail_id IS NOT NULL OR c.original_tag IS NOT NULL,
                          'c11 caso ' || c.status || '/' || c.reason);
  PERFORM pg_temp.fail_if(pg_temp.n_rem() <> 0, 'c11 sin recordatorio');
END $$;
ROLLBACK;

-- ===== Caso 12 (T2-42): el reintento encuentra el envio ya recibido -> caso informativo (already_received), cerrado
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v_case uuid; v uuid; c record;
BEGIN
  v_case := pg_temp.not_found_case('12345', now() - interval '1 day');
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345', now() - interval '3 days');
  UPDATE public.allocation_plan_details SET status = 'received', received_at = now() - interval '2 hours' WHERE id = v;
  PERFORM pg_temp.fail_if(public.receipt_retry_pending() <> 1, 'c12 cerrados');
  SELECT * INTO c FROM public.receipt_case WHERE id = v_case;
  PERFORM pg_temp.fail_if(c.status <> 'informative' OR c.reason <> 'already_received', 'c12 caso ' || c.status || '/' || c.reason);
  PERFORM pg_temp.fail_if(c.detail_id IS DISTINCT FROM v OR c.resolved_at IS NULL, 'c12 detail/resolved');
  PERFORM pg_temp.fail_if(c.culprit_role IS NOT NULL, 'c12 sin culpable');
  PERFORM pg_temp.fail_if((SELECT received_at FROM public.allocation_plan_details WHERE id = v)
                          IS DISTINCT FROM now() - interval '2 hours', 'c12 envio intacto');
  PERFORM pg_temp.fail_if(pg_temp.n_rem() <> 0, 'c12 sin recordatorio');
  PERFORM pg_temp.fail_if(public.receipt_retry_pending() <> 0, 'c12 segundo pase');
END $$;
ROLLBACK;

-- ===== Caso 13: not_found abierto; despues aparece un envio 'sent' con esa etiqueta EXACTA pero hacia otra ciudad ->
-- el reintento lo deja en needs_decision / other_city_tag, sin tocar el envio, sin compensar ni recordatorio
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v_case uuid; v uuid; d0 record; d record; c record;
BEGIN
  v_case := pg_temp.not_found_case('12345', now() - interval '1 day');
  v := pg_temp.mk_det('N4', 'N1', 'sent', '00012345', now() - interval '3 days');
  SELECT * INTO d0 FROM public.allocation_plan_details WHERE id = v;
  PERFORM pg_temp.fail_if(public.receipt_retry_pending() <> 0, 'c13 no cierra el caso');
  SELECT * INTO d FROM public.allocation_plan_details WHERE id = v;
  PERFORM pg_temp.fail_if(d.status <> 'sent' OR d.cancellation_reason IS NOT NULL OR d.received_at IS NOT NULL
                          OR d.destination_node_id IS DISTINCT FROM d0.destination_node_id
                          OR d.original_destination_node_id IS NOT NULL
                          OR d.tag_id IS DISTINCT FROM '00012345', 'c13 envio intacto');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.deferred_samples) <> 0, 'c13 sin deferred');
  SELECT * INTO c FROM public.receipt_case WHERE id = v_case;
  PERFORM pg_temp.fail_if(c.status <> 'needs_decision' OR c.reason <> 'other_city_tag', 'c13 caso ' || c.status || '/' || c.reason);
  PERFORM pg_temp.fail_if(c.detail_id IS NOT NULL OR c.culprit_role IS NOT NULL OR c.culprit_panelist_id IS NOT NULL
                          OR c.resolved_at IS NOT NULL, 'c13 sin envio ni culpable');
  PERFORM pg_temp.fail_if(pg_temp.n_rem() <> 0, 'c13 sin recordatorio');
  -- ya no es not_found/pending: un segundo pase no lo vuelve a tocar
  PERFORM pg_temp.fail_if(public.receipt_retry_pending() <> 0, 'c13 segundo pase');
  PERFORM pg_temp.fail_if((SELECT reason FROM public.receipt_case WHERE id = v_case) <> 'other_city_tag', 'c13 estable');
END $$;
ROLLBACK;
