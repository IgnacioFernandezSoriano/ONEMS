-- Errores de recepcion: RPCs de la pantalla del admin (spec 2026-11-04, tarea 3).
-- Fixture comun: C1 (N1,N2,N3), C2 (N4). Receptor P4 en N4/C2 (telegram '4004'). Cuenta 1 en Africa/Nairobi.
-- Actores: 99 = admin cuenta 1, 98 = admin cuenta 2, 97 = superadmin, 96 = usuario normal cuenta 1.
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;
CREATE FUNCTION pg_temp.setup() RETURNS void LANGUAGE sql AS $$
  UPDATE public.accounts SET timezone = 'Africa/Nairobi' WHERE id = 'a0000000-0000-0000-0000-000000000001';
  UPDATE public.panelists SET telegram_id = ' 4004 ' WHERE id = 'e4000000-0000-0000-0000-000000000004';
  UPDATE public.profiles SET role = 'admin' WHERE id IN ('99000000-0000-0000-0000-000000000099',
                                                         '98000000-0000-0000-0000-000000000098');
  INSERT INTO auth.users (id, email) VALUES ('97000000-0000-0000-0000-000000000097', 'su@t.l'),
                                            ('96000000-0000-0000-0000-000000000096', 'user@t.l');
  INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
    ('97000000-0000-0000-0000-000000000097', 'su@t.l', 'Super', 'superadmin', NULL),
    ('96000000-0000-0000-0000-000000000096', 'user@t.l', 'Normal', 'user', 'a0000000-0000-0000-0000-000000000001');
$$;
CREATE FUNCTION pg_temp.act(p text) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', p, true) $$;
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
-- Caso insertado a mano.
CREATE FUNCTION pg_temp.mk_case(p_panelist uuid, p_culprit uuid, p_reason text, p_status text, p_first timestamptz,
                                p_tag text, p_detail uuid DEFAULT NULL, p_attempts int DEFAULT 1) RETURNS uuid
LANGUAGE sql AS $$
  INSERT INTO public.receipt_case (account_id, panelist_id, telegram_id, tag_raw, tag_norm, detail_id, reason, status,
                                   culprit_panelist_id, culprit_role, attempts, first_attempt_at, last_attempt_at)
  VALUES ('a0000000-0000-0000-0000-000000000001', p_panelist, '4004', p_tag, p_tag, p_detail, p_reason, p_status,
          p_culprit, CASE WHEN p_culprit IS NOT NULL THEN 'sender' END, p_attempts, p_first, p_first)
  RETURNING id;
$$;
-- Ejecuta la sentencia y espera un error con ese SQLSTATE.
CREATE FUNCTION pg_temp.expect_state(p_sql text, p_state text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLSTATE <> p_state THEN
      RAISE EXCEPTION 'FAIL sqlstate % (esperaba %): % en %', SQLSTATE, p_state, SQLERRM, p_sql; END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL no fallo (esperaba %): %', p_state, p_sql;
END $$;

-- ===== Permisos
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.rpc_receipt_day_summary(uuid,date)', 'public.rpc_receipt_trend(uuid,int)',
    'public.rpc_receipt_repeat_panelists(uuid)', 'public.rpc_receipt_cases(uuid,text,date)',
    'public.rpc_receipt_case_fix(uuid,uuid)', 'public.rpc_receipt_case_close(uuid,text)',
    'public.rpc_send_panelist_notice(uuid,text)', 'public.rpc_broadcast_notice(uuid,jsonb)',
    'public.rpc_broadcast_recipients(uuid)', 'public.rpc_broadcast_history(uuid)'] LOOP
    IF NOT has_function_privilege('authenticated', f, 'EXECUTE') OR NOT has_function_privilege('service_role', f, 'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL falta GRANT en %', f; END IF;
    IF has_function_privilege('anon', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL anon con EXECUTE en %', f; END IF;
  END LOOP;
END $$;

-- ===== Caso 1: resumen del dia: 2 recepciones ok + 1 caso fixed (2 intentos) -> attempts 4, ok_first_time 2, fixed 1
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE a uuid; b uuid; c uuid; j jsonb; v_today date;
BEGIN
  PERFORM pg_temp.act('99000000-0000-0000-0000-000000000099');
  a := pg_temp.mk_det('N1', 'N4', 'sent', '00000001');
  b := pg_temp.mk_det('N1', 'N4', 'sent', '00000002');
  c := pg_temp.mk_det('N1', 'N4', 'sent', '00000003');
  PERFORM public.register_receipt_with_rules(a, now(), 'e4000000-0000-0000-0000-000000000004');
  PERFORM public.register_receipt_with_rules(b, now(), 'e4000000-0000-0000-0000-000000000004');
  PERFORM public.register_receipt_with_rules(c, now(), 'e4000000-0000-0000-0000-000000000004');
  PERFORM pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', 'e1000000-0000-0000-0000-000000000001',
                          'ok_typo_fixed', 'fixed', now(), '00000003', c, 2);
  PERFORM pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', NULL, 'invalid_format', 'informative', now(), 'xx');
  v_today := (now() AT TIME ZONE 'Africa/Nairobi')::date;
  j := public.rpc_receipt_day_summary('a0000000-0000-0000-0000-000000000001', v_today);
  PERFORM pg_temp.fail_if((j->>'ok_first_time')::int <> 2, 'c1 ok_first_time ' || j::text);
  PERFORM pg_temp.fail_if((j->>'attempts')::int <> 5, 'c1 attempts ' || j::text);   -- 2 + (2 + 1 informativo)
  PERFORM pg_temp.fail_if((j->>'fixed')::int <> 1 OR (j->>'informative')::int <> 1, 'c1 fixed/inf ' || j::text);
  PERFORM pg_temp.fail_if((j->>'compensated')::int <> 0 OR (j->>'pending')::int <> 0 OR (j->>'needs_decision')::int <> 0, 'c1 ceros');
  PERFORM pg_temp.fail_if((j->'by_reason'->>'ok_typo_fixed')::int <> 1 OR (j->'by_reason'->>'invalid_format')::int <> 1, 'c1 by_reason');
  -- otro dia: vacio
  j := public.rpc_receipt_day_summary('a0000000-0000-0000-0000-000000000001', v_today - 5);
  PERFORM pg_temp.fail_if((j->>'attempts')::int <> 0 OR j->'by_reason' <> '{}'::jsonb, 'c1 otro dia ' || j::text);
  -- tendencia: hoy 2 ok + 1 fixed; ultimo dia = hoy
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.rpc_receipt_trend('a0000000-0000-0000-0000-000000000001', 7)) <> 7, 'c1 trend dias');
  PERFORM pg_temp.fail_if((SELECT t.ok_first_time || '/' || t.fixed || '/' || t.compensated || '/' || t.open
                             FROM public.rpc_receipt_trend('a0000000-0000-0000-0000-000000000001', 7) t
                            WHERE t.day = v_today) <> '2/1/0/0', 'c1 trend hoy');
END $$;
ROLLBACK;

-- Resumen exacto del brief (sin el caso informativo): attempts = 4
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE a uuid; b uuid; c uuid; j jsonb;
BEGIN
  PERFORM pg_temp.act('99000000-0000-0000-0000-000000000099');
  a := pg_temp.mk_det('N1', 'N4', 'sent', '00000001');
  b := pg_temp.mk_det('N1', 'N4', 'sent', '00000002');
  c := pg_temp.mk_det('N1', 'N4', 'sent', '00000003');
  PERFORM public.register_receipt_with_rules(a, now(), 'e4000000-0000-0000-0000-000000000004');
  PERFORM public.register_receipt_with_rules(b, now(), 'e4000000-0000-0000-0000-000000000004');
  PERFORM public.register_receipt_with_rules(c, now(), 'e4000000-0000-0000-0000-000000000004');
  PERFORM pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', 'e1000000-0000-0000-0000-000000000001',
                          'ok_typo_fixed', 'fixed', now(), '00000003', c, 2);
  j := public.rpc_receipt_day_summary('a0000000-0000-0000-0000-000000000001', (now() AT TIME ZONE 'Africa/Nairobi')::date);
  PERFORM pg_temp.fail_if((j->>'attempts')::int <> 4 OR (j->>'ok_first_time')::int <> 2 OR (j->>'fixed')::int <> 1,
                          'c1b ' || j::text);
END $$;
ROLLBACK;

-- ===== Caso 2: reincidentes ordenados por fails_7d; solo con fails_30d > 0; last_notice_at
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE r record; v_names text := '';
BEGIN
  PERFORM pg_temp.act('99000000-0000-0000-0000-000000000099');
  -- P3: 5 fallos pero ninguno en 7 dias; P1: 3 en 7 dias (2 not_sent_cancelled, 1 ok_typo_fixed); P2: 1.
  FOR i IN 1..5 LOOP
    PERFORM pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', 'e3000000-0000-0000-0000-000000000003',
                            'not_sent_cancelled', 'compensated', now() - interval '10 days' - i * interval '1 hour', 'a' || i);
  END LOOP;
  PERFORM pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', 'e1000000-0000-0000-0000-000000000001',
                          'not_sent_cancelled', 'compensated', now() - interval '1 day', 'b1');
  PERFORM pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', 'e1000000-0000-0000-0000-000000000001',
                          'not_sent_cancelled', 'compensated', now() - interval '2 days', 'b2');
  PERFORM pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', 'e1000000-0000-0000-0000-000000000001',
                          'ok_typo_fixed', 'fixed', now() - interval '3 days', 'b3');
  PERFORM pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', 'e2000000-0000-0000-0000-000000000002',
                          'wrong_city_cancelled', 'compensated', now() - interval '4 days', 'c1');
  -- fuera de los 30 dias: P4 no debe aparecer
  PERFORM pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', 'e4000000-0000-0000-0000-000000000004',
                          'pobox_absent_no_visit', 'compensated', now() - interval '40 days', 'd1');
  INSERT INTO public.panelist_notification (account_id, panelist_id, kind, payload, status, sent_at)
  VALUES ('a0000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'manager_notice',
          '{"body":"x"}', 'sent', '2026-11-01 10:00+00'),
         ('a0000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'receipt_reminder',
          '{"reason":"x","local_date":"2026-11-02"}', 'sent', '2026-11-03 10:00+00'),
         ('a0000000-0000-0000-0000-000000000001', 'e1000000-0000-0000-0000-000000000001', 'receipt_reminder',
          '{"reason":"x","local_date":"2026-11-04"}', 'pending_send', NULL);
  FOR r IN SELECT * FROM public.rpc_receipt_repeat_panelists('a0000000-0000-0000-0000-000000000001') LOOP
    v_names := v_names || r.panelist_code || ':' || r.fails_7d || '/' || r.fails_30d || '/' || r.top_reason || ';';
  END LOOP;
  PERFORM pg_temp.fail_if(v_names <> 'P1:3/3/not_sent_cancelled;P2:1/1/wrong_city_cancelled;P3:0/5/not_sent_cancelled;',
                          'c2 orden ' || v_names);
  PERFORM pg_temp.fail_if((SELECT q.last_notice_at FROM public.rpc_receipt_repeat_panelists('a0000000-0000-0000-0000-000000000001') q
                            WHERE q.panelist_code = 'P1') IS DISTINCT FROM '2026-11-03 10:00+00'::timestamptz, 'c2 last_notice_at');
  PERFORM pg_temp.fail_if((SELECT q.last_notice_at FROM public.rpc_receipt_repeat_panelists('a0000000-0000-0000-0000-000000000001') q
                            WHERE q.panelist_code = 'P2') IS NOT NULL, 'c2 last_notice_at null');
END $$;
ROLLBACK;

-- ===== Caso 3: case_fix sobre not_found con detalle de etiqueta distinta (misma ciudad que el receptor)
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v_case uuid; v uuid; r jsonb; res text; d record; c record; v_first timestamptz := now() - interval '3 days';
BEGIN
  -- el panelista declara 12345 (no existe nada aun) -> not_found; despues aparece un envio con otra etiqueta
  r := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r->>'outcome' <> 'not_found', 'c3 not_found ' || r::text);
  v_case := (r->>'case_id')::uuid;
  UPDATE public.receipt_case SET first_attempt_at = v_first, last_attempt_at = v_first WHERE id = v_case;
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00099999', now() - interval '5 days');

  PERFORM pg_temp.act('99000000-0000-0000-0000-000000000099');
  res := public.rpc_receipt_case_fix(v_case, v);
  PERFORM pg_temp.fail_if(res <> 'ok_typo_fixed', 'c3 outcome ' || res);
  SELECT * INTO d FROM public.allocation_plan_details WHERE id = v;
  PERFORM pg_temp.fail_if(d.tag_id <> '00012345', 'c3 etiqueta ' || d.tag_id);
  PERFORM pg_temp.fail_if(d.status <> 'received', 'c3 status ' || d.status);
  PERFORM pg_temp.fail_if(d.received_at IS DISTINCT FROM v_first, 'c3 received_at = primer intento');
  PERFORM pg_temp.fail_if(d.destination_panelist_id IS DISTINCT FROM 'e4000000-0000-0000-0000-000000000004', 'c3 receptor');
  SELECT * INTO c FROM public.receipt_case WHERE id = v_case;
  PERFORM pg_temp.fail_if(c.status <> 'fixed' OR c.reason <> 'ok_typo_fixed', 'c3 caso ' || c.status || '/' || c.reason);
  PERFORM pg_temp.fail_if(c.original_tag IS DISTINCT FROM '00099999', 'c3 original_tag ' || coalesce(c.original_tag, 'NULL'));
  PERFORM pg_temp.fail_if(d.idtag IS DISTINCT FROM '12345', 'c3 idtag ' || coalesce(d.idtag, 'NULL'));
  PERFORM pg_temp.fail_if(c.resolved_by IS DISTINCT FROM '99000000-0000-0000-0000-000000000099', 'c3 resolved_by');
  PERFORM pg_temp.fail_if(c.resolved_at IS NULL OR c.detail_id IS DISTINCT FROM v, 'c3 resolved_at/detail');
  PERFORM pg_temp.fail_if(c.culprit_role IS DISTINCT FROM 'sender'
                          OR c.culprit_panelist_id IS DISTINCT FROM 'e1000000-0000-0000-0000-000000000001', 'c3 culpable');
  -- recordatorio al remitente
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_notification
                            WHERE kind = 'receipt_reminder' AND case_id = v_case
                              AND panelist_id = 'e1000000-0000-0000-0000-000000000001') <> 1, 'c3 recordatorio');
  -- el caso aparece en la lista con nombres
  PERFORM pg_temp.fail_if((SELECT x.resolved_by_name || '/' || x.culprit_name || '/' || x.panelist_name
                             FROM public.rpc_receipt_cases('a0000000-0000-0000-0000-000000000001', 'fixed') x
                            WHERE x.id = v_case) <> 'Actor/Pan1/Pan4', 'c3 lista');
  -- un caso cerrado no se puede volver a arreglar
  PERFORM pg_temp.expect_state(format('SELECT public.rpc_receipt_case_fix(%L,%L)', v_case, v), '22023');
END $$;
ROLLBACK;

-- ===== Caso 3b: misma ciudad, otro nodo, misma etiqueta -> ok_same_city; el destino pasa al nodo del receptor
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b5000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000002', 'N5');
DO $$
DECLARE v_case uuid; v uuid; res text; d record;
BEGIN
  v_case := pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', NULL, 'ambiguous_typo', 'needs_decision',
                            now() - interval '1 day', '00012345');
  v := pg_temp.mk_det('N1', 'N5', 'sent', '00012345');
  PERFORM pg_temp.act('99000000-0000-0000-0000-000000000099');
  res := public.rpc_receipt_case_fix(v_case, v);
  PERFORM pg_temp.fail_if(res <> 'ok_same_city', 'c3b outcome ' || res);
  SELECT * INTO d FROM public.allocation_plan_details WHERE id = v;
  PERFORM pg_temp.fail_if(d.destination_node_id <> 'b4000000-0000-0000-0000-000000000004'
                          OR d.original_destination_node_id <> 'b5000000-0000-0000-0000-000000000005', 'c3b destino');
  PERFORM pg_temp.fail_if(d.status <> 'received', 'c3b status');
END $$;
ROLLBACK;

-- ===== Caso 4: case_fix con un detalle de otra ciudad -> 22023, nada cambia
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v_case uuid; v uuid; v_other uuid;
BEGIN
  v_case := pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', NULL, 'not_found', 'pending',
                            now() - interval '1 day', '00012345');
  v := pg_temp.mk_det('N1', 'N2', 'sent', '00099999');            -- destino en C1; el receptor esta en C2
  PERFORM pg_temp.act('99000000-0000-0000-0000-000000000099');
  PERFORM pg_temp.expect_state(format('SELECT public.rpc_receipt_case_fix(%L,%L)', v_case, v), '22023');
  PERFORM pg_temp.fail_if((SELECT x.tag_id || x.status FROM public.allocation_plan_details x WHERE x.id = v) <> '00099999sent',
                          'c4 el envio no cambia');
  PERFORM pg_temp.fail_if((SELECT status FROM public.receipt_case WHERE id = v_case) <> 'pending', 'c4 caso sigue abierto');
  -- envio que no esta 'sent' -> 22023
  v_other := pg_temp.mk_det('N1', 'N4', 'pending', '00077777');
  PERFORM pg_temp.expect_state(format('SELECT public.rpc_receipt_case_fix(%L,%L)', v_case, v_other), '22023');
  -- envio inexistente / de otra cuenta -> 22023
  PERFORM pg_temp.expect_state(format('SELECT public.rpc_receipt_case_fix(%L,%L)', v_case, gen_random_uuid()), '22023');
END $$;
ROLLBACK;

-- ===== Caso 5: case_close sin detalle -> discarded; con detalle sent -> compensated; con detalle recibido -> discarded
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE c1 uuid; c2 uuid; c3 uuid; v_sent uuid; v_rec uuid; c record;
BEGIN
  PERFORM pg_temp.act('99000000-0000-0000-0000-000000000099');
  c1 := pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', NULL, 'ambiguous_typo', 'needs_decision', now(), '1');
  PERFORM public.rpc_receipt_case_close(c1, 'No era nuestro');
  SELECT * INTO c FROM public.receipt_case WHERE id = c1;
  PERFORM pg_temp.fail_if(c.status <> 'discarded' OR c.resolution_note <> 'No era nuestro'
                          OR c.resolved_by IS DISTINCT FROM '99000000-0000-0000-0000-000000000099' OR c.resolved_at IS NULL, 'c5 discarded');

  v_sent := pg_temp.mk_det('N1', 'N4', 'sent', '00000011');
  c2 := pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', NULL, 'not_found', 'pending', now(), '2', v_sent);
  PERFORM public.rpc_receipt_case_close(c2, 'No llego');
  PERFORM pg_temp.fail_if((SELECT status FROM public.receipt_case WHERE id = c2) <> 'compensated', 'c5 compensated');
  PERFORM pg_temp.fail_if((SELECT status || cancellation_reason FROM public.allocation_plan_details WHERE id = v_sent)
                          <> 'cancelledreceipt_before_sent', 'c5 envio anulado');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.deferred_samples WHERE reason = 'receipt_before_sent') <> 1, 'c5 deferred');

  v_rec := pg_temp.mk_det('N1', 'N4', 'sent', '00000022');
  PERFORM public.register_receipt_with_rules(v_rec, now(), 'e4000000-0000-0000-0000-000000000004');
  c3 := pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', NULL, 'ambiguous_typo', 'needs_decision', now(), '3', v_rec);
  PERFORM public.rpc_receipt_case_close(c3, 'ya estaba');
  PERFORM pg_temp.fail_if((SELECT status FROM public.receipt_case WHERE id = c3) <> 'discarded', 'c5 recibido -> discarded');
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v_rec) <> 'received', 'c5 envio intacto');
  -- cerrado dos veces
  PERFORM pg_temp.expect_state(format('SELECT public.rpc_receipt_case_close(%L,%L)', c3, 'x'), '22023');
END $$;
ROLLBACK;

-- ===== Caso 6: broadcast: 3 activos (en, es, sin telegram) -> 2 filas, cada una en su idioma
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
UPDATE public.panelists SET telegram_id = NULL WHERE id = 'e4000000-0000-0000-0000-000000000004';   -- P4 fuera
UPDATE public.panelists SET telegram_id = '111' WHERE id = 'e1000000-0000-0000-0000-000000000001';
UPDATE public.panelists SET telegram_id = ' 222 ', language = 'es' WHERE id = 'e2000000-0000-0000-0000-000000000002';
UPDATE public.panelists SET telegram_id = NULL WHERE id = 'e3000000-0000-0000-0000-000000000003';
DO $$
DECLARE n int; r record; v_bid text;
BEGIN
  PERFORM pg_temp.act('99000000-0000-0000-0000-000000000099');
  PERFORM pg_temp.fail_if((SELECT string_agg(x.language || x.n, ',' ORDER BY x.language)
                             FROM public.rpc_broadcast_recipients('a0000000-0000-0000-0000-000000000001') x) <> 'en1,es1', 'c6 destinatarios');
  n := public.rpc_broadcast_notice('a0000000-0000-0000-0000-000000000001', '{"en":"Hello","es":"Hola","fr":"Salut"}');
  PERFORM pg_temp.fail_if(n <> 2, 'c6 encoladas ' || n);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_notification WHERE kind = 'broadcast') <> 2, 'c6 filas');
  PERFORM pg_temp.fail_if((SELECT payload->>'body' FROM public.panelist_notification
                            WHERE kind = 'broadcast' AND panelist_id = 'e1000000-0000-0000-0000-000000000001') <> 'Hello', 'c6 en');
  PERFORM pg_temp.fail_if((SELECT payload->>'body' FROM public.panelist_notification
                            WHERE kind = 'broadcast' AND panelist_id = 'e2000000-0000-0000-0000-000000000002') <> 'Hola', 'c6 es');
  PERFORM pg_temp.fail_if((SELECT count(DISTINCT payload->>'broadcast_id') FROM public.panelist_notification WHERE kind = 'broadcast') <> 1, 'c6 id comun');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_notification
                            WHERE kind = 'broadcast' AND (send_after IS NOT NULL
                              OR payload->>'author_user_id' IS DISTINCT FROM '99000000-0000-0000-0000-000000000099')) <> 0, 'c6 send_after/autor');
  -- idioma sin texto -> ingles
  UPDATE public.panelists SET language = 'ar' WHERE id = 'e1000000-0000-0000-0000-000000000001';
  n := public.rpc_broadcast_notice('a0000000-0000-0000-0000-000000000001', '{"en":"Again"}');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_notification WHERE payload->>'body' = 'Again') <> 2, 'c6 fallback en');
  -- sin texto en ingles -> 22023
  PERFORM pg_temp.expect_state(format('SELECT public.rpc_broadcast_notice(%L,%L::jsonb)',
                                      'a0000000-0000-0000-0000-000000000001', '{"es":"Hola"}'), '22023');
  -- historial
  UPDATE public.panelist_notification SET status = 'sent', sent_at = now()
   WHERE kind = 'broadcast' AND panelist_id = 'e2000000-0000-0000-0000-000000000002';
  SELECT * INTO r FROM public.rpc_broadcast_history('a0000000-0000-0000-0000-000000000001')
   WHERE body_en = 'Hello';
  PERFORM pg_temp.fail_if(r.total <> 2 OR r.sent <> 1 OR r.failed <> 0, 'c6 historial ' || r.total || '/' || r.sent);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.rpc_broadcast_history('a0000000-0000-0000-0000-000000000001')) <> 2, 'c6 historial n');
  -- aviso individual
  PERFORM public.rpc_send_panelist_notice('e1000000-0000-0000-0000-000000000001', 'Revisa tus etiquetas');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_notification
                            WHERE kind = 'manager_notice' AND payload->>'body' = 'Revisa tus etiquetas'
                              AND send_after IS NULL AND status = 'pending_send') <> 1, 'c6 notice');
  PERFORM pg_temp.expect_state(format('SELECT public.rpc_send_panelist_notice(%L,%L)', 'e1000000-0000-0000-0000-000000000001', ''), '22023');
  PERFORM pg_temp.expect_state(format('SELECT public.rpc_send_panelist_notice(%L,%L)', 'e1000000-0000-0000-0000-000000000001', repeat('x', 3001)), '22023');
END $$;
ROLLBACK;

-- ===== Caso 7: admin de la cuenta B (y usuario normal) -> 42501 sin datos ni cambios
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
UPDATE public.panelists SET telegram_id = '111' WHERE id = 'e1000000-0000-0000-0000-000000000001';
DO $$
DECLARE v_case uuid; v uuid; a text := 'a0000000-0000-0000-0000-000000000001'; actor text;
BEGIN
  v_case := pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', NULL, 'not_found', 'pending', now() - interval '1 day', '00012345');
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345');
  FOREACH actor IN ARRAY ARRAY['98000000-0000-0000-0000-000000000098', '96000000-0000-0000-0000-000000000096'] LOOP
    PERFORM pg_temp.act(actor);
    PERFORM pg_temp.expect_state(format('SELECT public.rpc_receipt_day_summary(%L, current_date)', a), '42501');
    PERFORM pg_temp.expect_state(format('SELECT * FROM public.rpc_receipt_trend(%L, 7)', a), '42501');
    PERFORM pg_temp.expect_state(format('SELECT * FROM public.rpc_receipt_repeat_panelists(%L)', a), '42501');
    PERFORM pg_temp.expect_state(format('SELECT * FROM public.rpc_receipt_cases(%L)', a), '42501');
    PERFORM pg_temp.expect_state(format('SELECT public.rpc_receipt_case_fix(%L,%L)', v_case, v), '42501');
    PERFORM pg_temp.expect_state(format('SELECT public.rpc_receipt_case_close(%L,%L)', v_case, 'x'), '42501');
    PERFORM pg_temp.expect_state(format('SELECT public.rpc_send_panelist_notice(%L,%L)', 'e1000000-0000-0000-0000-000000000001', 'hola'), '42501');
    PERFORM pg_temp.expect_state(format('SELECT public.rpc_broadcast_notice(%L,%L::jsonb)', a, '{"en":"x"}'), '42501');
    PERFORM pg_temp.expect_state(format('SELECT * FROM public.rpc_broadcast_recipients(%L)', a), '42501');
    PERFORM pg_temp.expect_state(format('SELECT * FROM public.rpc_broadcast_history(%L)', a), '42501');
  END LOOP;
  PERFORM pg_temp.act('');
  PERFORM pg_temp.fail_if((SELECT status FROM public.receipt_case WHERE id = v_case) <> 'pending', 'c7 caso intacto');
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v) <> 'sent', 'c7 envio intacto');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_notification) <> 0, 'c7 sin avisos');
END $$;
ROLLBACK;

-- ===== Caso 8: superadmin accede a cualquier cuenta; sin sesion (service_role) tambien
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
UPDATE public.panelists SET telegram_id = '111' WHERE id = 'e1000000-0000-0000-0000-000000000001';
DO $$
DECLARE j jsonb; n int; v_case uuid;
BEGIN
  v_case := pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', NULL, 'ambiguous_typo', 'needs_decision', now(), '1');
  PERFORM pg_temp.act('97000000-0000-0000-0000-000000000097');
  j := public.rpc_receipt_day_summary('a0000000-0000-0000-0000-000000000001', current_date);
  PERFORM pg_temp.fail_if(j IS NULL, 'c8 summary cuenta 1');
  j := public.rpc_receipt_day_summary('a0000000-0000-0000-0000-000000000002', current_date);
  PERFORM pg_temp.fail_if(j IS NULL, 'c8 summary cuenta 2');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.rpc_receipt_cases('a0000000-0000-0000-0000-000000000001')) <> 1, 'c8 cases');
  n := public.rpc_broadcast_notice('a0000000-0000-0000-0000-000000000001', '{"en":"Hi"}');
  PERFORM pg_temp.fail_if(n <> 2, 'c8 broadcast ' || n);   -- P1 y P4 (setup)
  PERFORM public.rpc_receipt_case_close(v_case, 'su');
  PERFORM pg_temp.fail_if((SELECT status FROM public.receipt_case WHERE id = v_case) <> 'discarded', 'c8 close');
  -- sin sesion
  PERFORM pg_temp.act('');
  PERFORM pg_temp.fail_if(public.rpc_receipt_day_summary('a0000000-0000-0000-0000-000000000001', current_date) IS NULL, 'c8 sin sesion');
END $$;
ROLLBACK;

-- ===== Caso 9 (I1): recepcion ok + caso informativo already_received sobre ese detalle -> sigue contando ok_first_time
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE a uuid; j jsonb; v_today date := (now() AT TIME ZONE 'Africa/Nairobi')::date;
BEGIN
  PERFORM pg_temp.act('99000000-0000-0000-0000-000000000099');
  a := pg_temp.mk_det('N1', 'N4', 'sent', '00000001');
  PERFORM public.register_receipt_with_rules(a, now(), 'e4000000-0000-0000-0000-000000000004');
  PERFORM pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', NULL, 'already_received', 'informative', now(), '00000001', a);
  j := public.rpc_receipt_day_summary('a0000000-0000-0000-0000-000000000001', v_today);
  PERFORM pg_temp.fail_if((j->>'ok_first_time')::int <> 1, 'c9 summary ' || j::text);
  PERFORM pg_temp.fail_if((SELECT t.ok_first_time FROM public.rpc_receipt_trend('a0000000-0000-0000-0000-000000000001', 3) t
                            WHERE t.day = v_today) <> 1, 'c9 trend');
END $$;
ROLLBACK;

-- ===== Caso 10 (I2): reescribir la etiqueta chocaria con otro envio de la cuenta -> 22023, nada cambia
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v_case uuid; v uuid; other uuid;
BEGIN
  v_case := pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', NULL, 'not_found', 'pending', now() - interval '1 day', '00012345');
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00099999');
  other := pg_temp.mk_det('N2', 'N3', 'received', '00012345');
  PERFORM pg_temp.act('99000000-0000-0000-0000-000000000099');
  PERFORM pg_temp.expect_state(format('SELECT public.rpc_receipt_case_fix(%L,%L)', v_case, v), '22023');
  PERFORM pg_temp.fail_if((SELECT tag_id || status FROM public.allocation_plan_details WHERE id = v) <> '00099999sent', 'c10 intacto');
  PERFORM pg_temp.fail_if((SELECT status FROM public.receipt_case WHERE id = v_case) <> 'pending', 'c10 caso abierto');
END $$;
ROLLBACK;

-- ===== Caso 11: case_fix anulado por la regla POBOX -> compensated, culpable receptor
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
INSERT INTO public.account_config (account_id, pobox_enabled) VALUES ('a0000000-0000-0000-0000-000000000001', true)
  ON CONFLICT (account_id) DO UPDATE SET pobox_enabled = true;
DO $$
DECLARE v uuid; v_d date; v_case uuid; res text; c record;
BEGIN
  v_d := public.pobox_previous_collection_day('a0000000-0000-0000-0000-000000000001', (now() AT TIME ZONE 'Africa/Nairobi')::date);
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345', ((v_d - 7)::text || ' 10:00+03')::timestamptz);
  INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
  VALUES (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
          'b4000000-0000-0000-0000-000000000004', 'b1000000-0000-0000-0000-000000000001', v_d, 'pending');
  v_case := pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', NULL, 'ambiguous_typo', 'needs_decision', now(), '00012345');
  PERFORM pg_temp.act('99000000-0000-0000-0000-000000000099');
  res := public.rpc_receipt_case_fix(v_case, v);
  PERFORM pg_temp.fail_if(res <> 'pobox_absent_no_visit', 'c11 outcome ' || res);
  SELECT * INTO c FROM public.receipt_case WHERE id = v_case;
  PERFORM pg_temp.fail_if(c.status <> 'compensated' OR c.reason <> 'pobox_absent_no_visit', 'c11 caso ' || c.status || '/' || c.reason);
  PERFORM pg_temp.fail_if(c.culprit_role IS DISTINCT FROM 'receiver'
                          OR c.culprit_panelist_id IS DISTINCT FROM 'e4000000-0000-0000-0000-000000000004', 'c11 culpable');
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v) <> 'cancelled', 'c11 envio anulado');
END $$;
ROLLBACK;

-- ===== Caso 12 (M8): case_fix con sent_at posterior al primer intento -> 22023 (arreglar nunca anula); nada cambia
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v uuid; v_case uuid; c record;
BEGIN
  v_case := pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', NULL, 'not_found', 'pending', now() - interval '3 days', '00012345');
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345', now() - interval '1 day');
  PERFORM pg_temp.act('99000000-0000-0000-0000-000000000099');
  PERFORM pg_temp.expect_state(format('SELECT public.rpc_receipt_case_fix(%L,%L)', v_case, v), '22023');
  SELECT * INTO c FROM public.receipt_case WHERE id = v_case;
  PERFORM pg_temp.fail_if(c.status <> 'pending' OR c.reason <> 'not_found' OR c.resolved_at IS NOT NULL, 'c12 caso abierto');
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v) <> 'sent', 'c12 envio intacto');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.deferred_samples) <> 0, 'c12 sin compensacion');
END $$;
ROLLBACK;

-- ===== Caso 13: aviso individual solo a panelista activo con Telegram numerico
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
BEGIN
  PERFORM pg_temp.act('99000000-0000-0000-0000-000000000099');
  PERFORM pg_temp.expect_state(format('SELECT public.rpc_send_panelist_notice(%L,%L)', 'e1000000-0000-0000-0000-000000000001', 'hola'), '22023'); -- sin telegram
  PERFORM public.rpc_send_panelist_notice('e4000000-0000-0000-0000-000000000004', 'hola');                                                      -- activo con telegram
  UPDATE public.panelists SET status = 'inactive' WHERE id = 'e4000000-0000-0000-0000-000000000004';
  PERFORM pg_temp.expect_state(format('SELECT public.rpc_send_panelist_notice(%L,%L)', 'e4000000-0000-0000-0000-000000000004', 'hola'), '22023');
END $$;
ROLLBACK;

-- ===== Caso 14 (M10): la tabla receipt_case solo la leen el admin de la cuenta y el superadmin
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
SELECT pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', NULL, 'not_found', 'pending', now(), '00012345');
SELECT pg_temp.act('99000000-0000-0000-0000-000000000099');
SET LOCAL ROLE authenticated;
SELECT set_config('t.admin', (SELECT count(*) FROM public.receipt_case)::text, true);
RESET ROLE;
SELECT pg_temp.act('96000000-0000-0000-0000-000000000096');
SET LOCAL ROLE authenticated;
SELECT set_config('t.user', (SELECT count(*) FROM public.receipt_case)::text, true);
RESET ROLE;
SELECT pg_temp.act('98000000-0000-0000-0000-000000000098');
SET LOCAL ROLE authenticated;
SELECT set_config('t.other', (SELECT count(*) FROM public.receipt_case)::text, true);
RESET ROLE;
SELECT pg_temp.act('97000000-0000-0000-0000-000000000097');
SET LOCAL ROLE authenticated;
SELECT set_config('t.su', (SELECT count(*) FROM public.receipt_case)::text, true);
RESET ROLE;
DO $$
BEGIN
  PERFORM pg_temp.fail_if(current_setting('t.admin') <> '1', 'c14 admin de la cuenta ' || current_setting('t.admin'));
  PERFORM pg_temp.fail_if(current_setting('t.user') <> '0', 'c14 usuario normal ' || current_setting('t.user'));
  PERFORM pg_temp.fail_if(current_setting('t.other') <> '0', 'c14 admin de otra cuenta ' || current_setting('t.other'));
  PERFORM pg_temp.fail_if(current_setting('t.su') <> '1', 'c14 superadmin ' || current_setting('t.su'));
END $$;
ROLLBACK;
