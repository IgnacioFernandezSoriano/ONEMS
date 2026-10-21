-- Conversacion registrada de incidencias + materiales. Cada escenario en su propia transaccion.
\set ON_ERROR_STOP on

CREATE FUNCTION pg_temp.expect_err(p_sql text, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN raise_exception OR check_violation THEN
    IF SQLERRM NOT LIKE p_msg || '%' THEN
      RAISE EXCEPTION 'FAIL error inesperado "%" (esperaba "%") en %', SQLERRM, p_msg, p_sql; END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL no fallo (esperaba "%"): %', p_msg, p_sql;
END $$;

-- ===== Escenario 1: incident_message y sus RPCs =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
UPDATE public.panelists SET telegram_id = 'tg-p1', language = 'es' WHERE id = 'e1000000-0000-0000-0000-000000000001';
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v uuid);
WITH x AS (
  INSERT INTO public.panelist_incident (account_id, panelist_id, category, status)
  VALUES ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','other','open')
  RETURNING id)
INSERT INTO t_ids SELECT 'inc', id FROM x;
WITH x AS (
  INSERT INTO public.panelist_unavailability (panelist_id, account_id, start_date, end_date, reason, status)
  VALUES ('e1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',
          current_date + 1, current_date + 5, 'vacation', 'active')
  RETURNING id)
INSERT INTO t_ids SELECT 'unav', id FROM x;

-- estados por defecto y derivacion de cuenta/panelista
DO $$
DECLARE v_inc uuid := (SELECT v FROM t_ids WHERE k='inc'); v_un uuid := (SELECT v FROM t_ids WHERE k='unav');
        a uuid; b uuid; c uuid; d uuid; r public.incident_message;
BEGIN
  a := public.log_incident_message('reported', v_inc, 'outbound', 'bot', 'hola');
  b := public.log_incident_message('reported', v_inc, 'inbound', 'panelist', 'respuesta', '{"callback":"x"}'::jsonb);
  c := public.log_incident_message('unavailability', v_un, 'internal', 'system', 'nota');
  d := public.log_incident_message('unavailability', v_un, 'outbound', 'bot', 'ya enviado', '{}'::jsonb, 'sent');
  SELECT * INTO r FROM public.incident_message WHERE id = a;
  IF r.status <> 'pending_send' OR r.account_id <> 'a0000000-0000-0000-0000-000000000001'
     OR r.panelist_id <> 'e1000000-0000-0000-0000-000000000001' THEN RAISE EXCEPTION 'FAIL outbound: %', row_to_json(r); END IF;
  SELECT * INTO r FROM public.incident_message WHERE id = b;
  IF r.status <> 'received' OR r.meta->>'callback' <> 'x' THEN RAISE EXCEPTION 'FAIL inbound: %', row_to_json(r); END IF;
  SELECT * INTO r FROM public.incident_message WHERE id = c;
  IF r.status <> 'sent' OR r.incident_kind <> 'unavailability' OR r.panelist_id <> 'e1000000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'FAIL internal/unav: %', row_to_json(r); END IF;
  SELECT * INTO r FROM public.incident_message WHERE id = d;
  IF r.status <> 'sent' THEN RAISE EXCEPTION 'FAIL status explicito'; END IF;
END $$;

SELECT pg_temp.expect_err($$SELECT public.log_incident_message('reported','00000000-0000-0000-0000-000000000000','outbound','bot','x')$$, 'incident not found');
SELECT pg_temp.expect_err($$SELECT public.log_incident_message('unavailability','00000000-0000-0000-0000-000000000000','outbound','bot','x')$$, 'incident not found');
SELECT pg_temp.expect_err($$SELECT public.log_incident_message('bad',(SELECT v FROM t_ids WHERE k='inc'),'outbound','bot','x')$$, 'invalid incident kind');
SELECT pg_temp.expect_err($$SELECT public.log_incident_message('reported',(SELECT v FROM t_ids WHERE k='inc'),'sideways','bot','x')$$, '');

-- send_manager_message: actor 99 (cuenta 1) OK; actor 98 (cuenta 2) denegado; vacio
DO $$
DECLARE v_inc uuid := (SELECT v FROM t_ids WHERE k='inc'); m uuid; r public.incident_message;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
  m := public.send_manager_message('reported', v_inc, 'mensaje del manager');
  PERFORM set_config('request.jwt.claim.sub','', true);
  SELECT * INTO r FROM public.incident_message WHERE id = m;
  IF r.direction <> 'outbound' OR r.author <> 'manager' OR r.status <> 'pending_send'
     OR r.meta->>'manager_user_id' <> '99000000-0000-0000-0000-000000000099' THEN
    RAISE EXCEPTION 'FAIL manager msg: %', row_to_json(r); END IF;
END $$;
DO $$
DECLARE v_inc uuid := (SELECT v FROM t_ids WHERE k='inc');
BEGIN
  PERFORM set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000098', true);
  PERFORM pg_temp.expect_err(format($q$SELECT public.send_manager_message('reported', %L, 'x')$q$, v_inc), 'Cross-tenant access denied');
  PERFORM set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
  PERFORM pg_temp.expect_err(format($q$SELECT public.send_manager_message('reported', %L, '   ')$q$, v_inc), 'empty message');
  PERFORM set_config('request.jwt.claim.sub','', true);
END $$;

-- pending_incident_messages: reclama solo outbound pending_send con telegram_id; sin duplicados
UPDATE public.panelists SET telegram_id = '' WHERE id = 'e1000000-0000-0000-0000-000000000001';
DO $$ BEGIN
  IF (SELECT count(*) FROM public.pending_incident_messages()) <> 0 THEN RAISE EXCEPTION 'FAIL sin telegram_id aparece'; END IF;
END $$;
UPDATE public.panelists SET telegram_id = 'tg-p1' WHERE id = 'e1000000-0000-0000-0000-000000000001';
DO $$
DECLARE r record; a uuid; b uuid; n int; st text;
BEGIN
  SELECT * INTO r FROM public.pending_incident_messages(1);
  IF r.telegram_id <> 'tg-p1' OR r.language <> 'es' OR r.meta->>'claimed_at' IS NULL THEN RAISE EXCEPTION 'FAIL pending fila: %', row_to_json(r); END IF;
  a := r.id;
  SELECT count(*) INTO n FROM public.pending_incident_messages();
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL segundo reparto=% (esperaba 1, la otra fila)', n; END IF;
  SELECT id INTO b FROM public.incident_message WHERE direction='outbound' AND status='pending_send' AND id <> a;
  IF (SELECT count(*) FROM public.pending_incident_messages()) <> 0 THEN RAISE EXCEPTION 'FAIL reparte duplicados'; END IF;
  PERFORM public.mark_incident_message_sent(a, true, NULL, 'tgm-1');
  IF NOT EXISTS (SELECT 1 FROM public.incident_message WHERE id = a AND status='sent' AND sent_at IS NOT NULL AND telegram_message_id='tgm-1') THEN
    RAISE EXCEPTION 'FAIL sent'; END IF;
  PERFORM public.mark_incident_message_sent(b, false, 'boom');
  SELECT status INTO st FROM public.incident_message WHERE id = b;
  IF st <> 'failed' OR (SELECT error FROM public.incident_message WHERE id = b) <> 'boom' THEN RAISE EXCEPTION 'FAIL failed'; END IF;
  IF (SELECT count(*) FROM public.pending_incident_messages()) <> 0 THEN RAISE EXCEPTION 'FAIL failed se reenvia'; END IF;
  PERFORM pg_temp.expect_err($q$SELECT public.mark_incident_message_sent('00000000-0000-0000-0000-000000000000', true)$q$, 'message not found');
  PERFORM pg_temp.expect_err(format($q$SELECT public.mark_incident_message_sent(%L, true)$q$,
    (SELECT id FROM public.incident_message WHERE direction='inbound' LIMIT 1)), 'message not found');
END $$;
-- un reclamo caducado (>10 min) vuelve a repartirse
DO $$ DECLARE mid uuid;
BEGIN
  mid := public.log_incident_message('reported', (SELECT v FROM t_ids WHERE k='inc'), 'outbound', 'bot', 'reintento');
  PERFORM public.pending_incident_messages();
  UPDATE public.incident_message SET meta = jsonb_set(meta, '{claimed_at}', to_jsonb(now() - interval '11 minutes')) WHERE id = mid;
  IF (SELECT count(*) FROM public.pending_incident_messages()) <> 1 THEN RAISE EXCEPTION 'FAIL reclamo caducado no se reparte'; END IF;
END $$;

-- panelista de otra cuenta: el trigger lo impide; con el trigger apagado, las RPCs lo bloquean
SELECT pg_temp.expect_err($$INSERT INTO public.panelist_incident (account_id, panelist_id, category, status)
  VALUES ('a0000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000001','other','open')$$,
  'panelist belongs to another account');
ALTER TABLE public.panelist_incident DISABLE TRIGGER panelist_incident_same_account;
WITH x AS (
  INSERT INTO public.panelist_incident (account_id, panelist_id, category, status)
  VALUES ('a0000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000001','other','open')
  RETURNING id)
INSERT INTO t_ids SELECT 'bad', id FROM x;
ALTER TABLE public.panelist_incident ENABLE TRIGGER panelist_incident_same_account;
SELECT pg_temp.expect_err($$SELECT public.send_manager_message('reported',(SELECT v FROM t_ids WHERE k='bad'),'x')$$, 'Cross-tenant access denied');
SELECT pg_temp.expect_err($$SELECT public.log_incident_message('reported',(SELECT v FROM t_ids WHERE k='bad'),'outbound','bot','x')$$, 'Cross-tenant access denied');

-- privilegios
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.send_manager_message(text,uuid,text)'] LOOP
    IF has_function_privilege('anon', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL anon con EXECUTE en %', f; END IF;
    IF NOT has_function_privilege('authenticated', f, 'EXECUTE') OR NOT has_function_privilege('service_role', f, 'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL falta GRANT en %', f; END IF;
  END LOOP;
  FOREACH f IN ARRAY ARRAY['public.log_incident_message(text,uuid,text,text,text,jsonb,text)',
                           'public.mark_incident_message_sent(uuid,boolean,text,text)',
                           'public.pending_incident_messages(integer)'] LOOP
    IF has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL anon/authenticated con EXECUTE en %', f; END IF;
    IF NOT has_function_privilege('service_role', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL service_role sin EXECUTE en %', f; END IF;
  END LOOP;
  IF has_table_privilege('anon', 'public.incident_message', 'SELECT') THEN RAISE EXCEPTION 'FAIL anon SELECT tabla'; END IF;
  IF NOT has_table_privilege('authenticated', 'public.incident_message', 'SELECT') THEN RAISE EXCEPTION 'FAIL authenticated sin SELECT'; END IF;
  IF has_table_privilege('authenticated', 'public.incident_message', 'INSERT') OR has_table_privilege('authenticated', 'public.incident_message', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.incident_message', 'DELETE') THEN RAISE EXCEPTION 'FAIL authenticated con escritura directa'; END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.incident_message'::regclass) THEN RAISE EXCEPTION 'FAIL sin RLS'; END IF;
END $$;
ROLLBACK;

-- ===== Escenario 2: envios de material enlazados a la incidencia y agenda de preguntas =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
UPDATE public.panelists SET telegram_id = 'tg-p1', language = 'es' WHERE id = 'e1000000-0000-0000-0000-000000000001';
UPDATE public.panelists SET telegram_id = 'tg-p2', language = 'fr' WHERE id = 'e2000000-0000-0000-0000-000000000002';
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v uuid);
WITH x AS (
  INSERT INTO public.panelist_incident (account_id, panelist_id, category, status)
  VALUES ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','missing_materials','open')
  RETURNING id)
INSERT INTO t_ids SELECT 'inc', id FROM x;
WITH x AS (
  INSERT INTO public.material_catalog (account_id, code, name)
  VALUES ('a0000000-0000-0000-0000-000000000001','M1','Etiquetas') RETURNING id)
INSERT INTO t_ids SELECT 'mat', id FROM x;
-- S1: envio de donante (P2 -> P1) enlazado a la incidencia; S2: envio central a P1 con fecha prevista manana
WITH x AS (
  INSERT INTO public.material_shipments (account_id, panelist_id, source_panelist_id, status, panelist_incident_id)
  VALUES ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',
          'e2000000-0000-0000-0000-000000000002','pending',(SELECT v FROM t_ids WHERE k='inc'))
  RETURNING id)
INSERT INTO t_ids SELECT 's1', id FROM x;
WITH x AS (
  INSERT INTO public.material_shipments (account_id, panelist_id, status, expected_date, panelist_incident_id)
  VALUES ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',
          'pending', current_date + 1,(SELECT v FROM t_ids WHERE k='inc'))
  RETURNING id)
INSERT INTO t_ids SELECT 's2', id FROM x;
INSERT INTO public.material_shipment_items (account_id, material_shipment_id, material_id, quantity_sent)
SELECT 'a0000000-0000-0000-0000-000000000001', v, (SELECT v FROM t_ids WHERE k='mat'), 5 FROM t_ids WHERE k IN ('s1','s2');

-- el donante recibe la peticion de envio; el envio central no genera pregunta aun
DO $$
DECLARE s1 uuid := (SELECT v FROM t_ids WHERE k='s1'); r record;
BEGIN
  IF (SELECT count(*) FROM public.due_material_questions()) <> 1 THEN
    RAISE EXCEPTION 'FAIL esperaba 1 pregunta pendiente, hay %', (SELECT count(*) FROM public.due_material_questions()); END IF;
  SELECT * INTO r FROM public.due_material_questions();
  IF r.shipment_id <> s1 OR r.kind <> 'donor_send_request' OR r.panelist_id <> 'e2000000-0000-0000-0000-000000000002'
     OR r.telegram_id <> 'tg-p2' OR r.language <> 'fr' OR r.ask_count <> 0 THEN
    RAISE EXCEPTION 'FAIL fila donante: %', row_to_json(r); END IF;
  PERFORM public.record_material_question(s1, 'donor_send_request');
  IF NOT EXISTS (SELECT 1 FROM public.material_shipments WHERE id = s1 AND ask_count = 1 AND source_notified_at IS NOT NULL
                  AND last_asked_at IS NOT NULL AND next_ask_at > now() + interval '1 day 23 hours') THEN
    RAISE EXCEPTION 'FAIL record donante'; END IF;
  IF (SELECT count(*) FROM public.due_material_questions()) <> 0 THEN RAISE EXCEPTION 'FAIL reaparece antes de next_ask_at'; END IF;
  SELECT * INTO r FROM public.due_material_questions(now() + interval '3 days');
  IF r.shipment_id IS DISTINCT FROM s1 OR r.kind <> 'donor_send_request' OR r.ask_count <> 1 THEN
    RAISE EXCEPTION 'FAIL no reaparece al vencer: %', row_to_json(r); END IF;
END $$;

-- al enviarse pasa a receipt_question (receptor) y reinicia el contador
DO $$
DECLARE s1 uuid := (SELECT v FROM t_ids WHERE k='s1'); s2 uuid := (SELECT v FROM t_ids WHERE k='s2'); r record;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
  PERFORM public.send_material_shipment(s1);
  PERFORM public.send_material_shipment(s2);
  PERFORM set_config('request.jwt.claim.sub','', true);
  IF NOT EXISTS (SELECT 1 FROM public.material_shipments WHERE id = s1 AND status = 'sent' AND ask_count = 0
                  AND next_ask_at > now() + interval '1 day 23 hours' AND next_ask_at < now() + interval '2 days 1 hour') THEN
    RAISE EXCEPTION 'FAIL send donante: %', (SELECT row_to_json(m) FROM public.material_shipments m WHERE id = s1); END IF;
  IF NOT EXISTS (SELECT 1 FROM public.material_shipments WHERE id = s2 AND status = 'sent' AND ask_count = 0
                  AND next_ask_at = (current_date + 1)::timestamptz) THEN
    RAISE EXCEPTION 'FAIL send central: %', (SELECT row_to_json(m) FROM public.material_shipments m WHERE id = s2); END IF;
  IF (SELECT count(*) FROM public.due_material_questions()) <> 0 THEN RAISE EXCEPTION 'FAIL pregunta antes de tiempo'; END IF;
  SELECT * INTO r FROM public.due_material_questions(now() + interval '3 days') WHERE shipment_id = s1;
  IF r.kind <> 'receipt_question' OR r.panelist_id <> 'e1000000-0000-0000-0000-000000000001'
     OR r.telegram_id <> 'tg-p1' OR r.language <> 'es' THEN RAISE EXCEPTION 'FAIL receipt_question: %', row_to_json(r); END IF;
  IF (SELECT count(*) FROM public.due_material_questions(now() + interval '3 days')) <> 2 THEN
    RAISE EXCEPTION 'FAIL esperaba 2 receipt_question'; END IF;
  PERFORM public.record_material_question(s1, 'receipt_question');
  IF NOT EXISTS (SELECT 1 FROM public.material_shipments WHERE id = s1 AND ask_count = 1) THEN RAISE EXCEPTION 'FAIL record receipt'; END IF;
  IF (SELECT count(*) FROM public.due_material_questions(now() + interval '1 day')) <> 1 THEN
    RAISE EXCEPTION 'FAIL s1 reaparece pronto'; END IF;
  -- recepcion parcial: sigue preguntando
  UPDATE public.material_shipments SET status = 'partially_received', next_ask_at = now() - interval '1 hour' WHERE id = s1;
  SELECT * INTO r FROM public.due_material_questions() WHERE shipment_id = s1;
  IF r.kind <> 'receipt_question' THEN RAISE EXCEPTION 'FAIL partially_received no pregunta'; END IF;
  -- recibido o cancelado: no pregunta
  UPDATE public.material_shipments SET status = 'received' WHERE id = s1;
  UPDATE public.material_shipments SET status = 'cancelled' WHERE id = s2;
  IF (SELECT count(*) FROM public.due_material_questions(now() + interval '30 days')) <> 0 THEN RAISE EXCEPTION 'FAIL pregunta de cerrados'; END IF;
END $$;

-- sin telegram_id no hay pregunta; panelista de otra cuenta tampoco
UPDATE public.material_shipments SET status = 'sent', next_ask_at = now() - interval '1 hour'
 WHERE id = (SELECT v FROM t_ids WHERE k='s1');
UPDATE public.panelists SET telegram_id = '  ' WHERE id = 'e1000000-0000-0000-0000-000000000001';
DO $$ BEGIN
  IF (SELECT count(*) FROM public.due_material_questions()) <> 0 THEN RAISE EXCEPTION 'FAIL pregunta sin telegram_id'; END IF;
END $$;
UPDATE public.panelists SET telegram_id = 'tg-p1' WHERE id = 'e1000000-0000-0000-0000-000000000001';
INSERT INTO public.material_shipments (account_id, panelist_id, status, next_ask_at)
VALUES ('a0000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000001','sent', now() - interval '1 day');
DO $$ BEGIN
  IF (SELECT count(*) FROM public.due_material_questions()) <> 1 THEN
    RAISE EXCEPTION 'FAIL cuenta cruzada: % filas', (SELECT count(*) FROM public.due_material_questions()); END IF;
END $$;

-- estado invalido, kind invalido, envio inexistente, FK SET NULL
SELECT pg_temp.expect_err($$UPDATE public.material_shipments SET status = 'bogus'$$, 'new row for relation');
SELECT pg_temp.expect_err($$SELECT public.record_material_question((SELECT v FROM t_ids WHERE k='s1'), 'bogus')$$, 'invalid question kind');
SELECT pg_temp.expect_err($$SELECT public.record_material_question('00000000-0000-0000-0000-000000000000', 'receipt_question')$$, 'shipment not found');
DELETE FROM public.panelist_incident WHERE id = (SELECT v FROM t_ids WHERE k='inc');
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.material_shipments WHERE panelist_incident_id IS NOT NULL) THEN RAISE EXCEPTION 'FAIL FK no pone NULL'; END IF;
END $$;

-- privilegios
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.due_material_questions(timestamptz)','public.record_material_question(uuid,text)'] LOOP
    IF has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL anon/authenticated con EXECUTE en %', f; END IF;
    IF NOT has_function_privilege('service_role', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL service_role sin EXECUTE en %', f; END IF;
  END LOOP;
  f := 'public.send_material_shipment(uuid)';
  IF has_function_privilege('anon', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL anon con EXECUTE en %', f; END IF;
  IF NOT has_function_privilege('authenticated', f, 'EXECUTE') OR NOT has_function_privilege('service_role', f, 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL falta GRANT en %', f; END IF;
END $$;
ROLLBACK;
