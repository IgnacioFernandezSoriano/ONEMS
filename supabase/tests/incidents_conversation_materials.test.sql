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
-- sin telegram_id el manager ve el error en vez de un mensaje atascado
DO $$
DECLARE v_inc uuid := (SELECT v FROM t_ids WHERE k='inc');
BEGIN
  PERFORM set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
  PERFORM pg_temp.expect_err(format($q$SELECT public.send_manager_message('reported', %L, 'hola')$q$, v_inc), 'panelist has no telegram');
  PERFORM set_config('request.jwt.claim.sub','', true);
END $$;
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

-- envio fuera de una incidencia: no se pregunta
INSERT INTO public.material_shipments (account_id, panelist_id, status, next_ask_at)
VALUES ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','sent', now() - interval '1 day');
DO $$ BEGIN
  IF (SELECT count(*) FROM public.due_material_questions()) <> 1
     OR EXISTS (SELECT 1 FROM public.due_material_questions() q JOIN public.material_shipments m ON m.id = q.shipment_id
                 WHERE m.panelist_incident_id IS NULL) THEN
    RAISE EXCEPTION 'FAIL pregunta de envio sin incidencia: % filas', (SELECT count(*) FROM public.due_material_questions()); END IF;
END $$;

-- una sola linea por material en cada envio
DO $$ BEGIN
  BEGIN
    INSERT INTO public.material_shipment_items (account_id, material_shipment_id, material_id, quantity_sent)
    VALUES ('a0000000-0000-0000-0000-000000000001',(SELECT v FROM t_ids WHERE k='s1'),(SELECT v FROM t_ids WHERE k='mat'), 1);
  EXCEPTION WHEN unique_violation THEN
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL linea duplicada aceptada';
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

-- ===== Escenario 3: recepcion parcial y cierre de incidencia sin cancelar la baja =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v uuid);
WITH x AS (
  INSERT INTO public.panelist_incident (account_id, panelist_id, category, status)
  VALUES ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','missing_materials','open')
  RETURNING id)
INSERT INTO t_ids SELECT 'inc', id FROM x;
WITH x AS (
  INSERT INTO public.panelist_unavailability (panelist_id, account_id, start_date, end_date, reason, status)
  VALUES ('e1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',
          current_date + 1, current_date + 5, 'vacation', 'active')
  RETURNING id)
INSERT INTO t_ids SELECT 'unav', id FROM x;
UPDATE public.panelist_incident SET linked_unavailability_id = (SELECT v FROM t_ids WHERE k='unav')
 WHERE id = (SELECT v FROM t_ids WHERE k='inc');
WITH x AS (INSERT INTO public.material_catalog (account_id, code, name)
  VALUES ('a0000000-0000-0000-0000-000000000001','M1','Etiquetas') RETURNING id)
INSERT INTO t_ids SELECT 'm1', id FROM x;
WITH x AS (INSERT INTO public.material_catalog (account_id, code, name)
  VALUES ('a0000000-0000-0000-0000-000000000001','M2','Bolsas') RETURNING id)
INSERT INTO t_ids SELECT 'm2', id FROM x;
-- s1 central (M1 x10, M2 x4), s2 donante (M1 x5), ambos enviados y enlazados a la incidencia
WITH x AS (
  INSERT INTO public.material_shipments (account_id, panelist_id, status, panelist_incident_id)
  VALUES ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','sent',(SELECT v FROM t_ids WHERE k='inc'))
  RETURNING id)
INSERT INTO t_ids SELECT 's1', id FROM x;
WITH x AS (
  INSERT INTO public.material_shipments (account_id, panelist_id, source_panelist_id, status, panelist_incident_id)
  VALUES ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000002','sent',(SELECT v FROM t_ids WHERE k='inc'))
  RETURNING id)
INSERT INTO t_ids SELECT 's2', id FROM x;
INSERT INTO public.material_shipment_items (account_id, material_shipment_id, material_id, quantity_sent) VALUES
  ('a0000000-0000-0000-0000-000000000001',(SELECT v FROM t_ids WHERE k='s1'),(SELECT v FROM t_ids WHERE k='m1'),10),
  ('a0000000-0000-0000-0000-000000000001',(SELECT v FROM t_ids WHERE k='s1'),(SELECT v FROM t_ids WHERE k='m2'),4),
  ('a0000000-0000-0000-0000-000000000001',(SELECT v FROM t_ids WHERE k='s2'),(SELECT v FROM t_ids WHERE k='m1'),5);

-- errores
DO $$
DECLARE s1 uuid := (SELECT v FROM t_ids WHERE k='s1'); m1 uuid := (SELECT v FROM t_ids WHERE k='m1');
BEGIN
  PERFORM set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
  PERFORM pg_temp.expect_err(format($q$SELECT public.receive_material_shipment_items(%L, %L::jsonb)$q$,
    s1, format('[{"material_id":"%s","quantity":11}]', m1)), 'quantity exceeds sent');
  PERFORM pg_temp.expect_err(format($q$SELECT public.receive_material_shipment_items(%L, %L::jsonb)$q$,
    s1, format('[{"material_id":"%s","quantity":-1}]', m1)), 'invalid quantity');
  PERFORM pg_temp.expect_err(format($q$SELECT public.receive_material_shipment_items(%L, %L::jsonb)$q$,
    s1, '[{"material_id":"00000000-0000-0000-0000-000000000000","quantity":1}]'), 'material not in shipment');
  PERFORM set_config('request.jwt.claim.sub','', true);
END $$;

-- parcial, luego el resto
DO $$
DECLARE s1 uuid := (SELECT v FROM t_ids WHERE k='s1'); m1 uuid := (SELECT v FROM t_ids WHERE k='m1'); m2 uuid := (SELECT v FROM t_ids WHERE k='m2');
        inc uuid := (SELECT v FROM t_ids WHERE k='inc'); r jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
  r := public.receive_material_shipment_items(s1, format('[{"material_id":"%s","quantity":6},{"material_id":"%s","quantity":0}]', m1, m2)::jsonb);
  IF r->>'status' <> 'partially_received' OR (r->>'incident_resolved')::boolean OR jsonb_array_length(r->'released_detail_ids') <> 0 THEN
    RAISE EXCEPTION 'FAIL parcial 1: %', r; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.material_shipments WHERE id = s1 AND status='partially_received' AND ask_count = 0
                 AND next_ask_at > now() + interval '1 day 23 hours' AND received_date IS NULL) THEN
    RAISE EXCEPTION 'FAIL estado parcial'; END IF;
  IF (SELECT quantity FROM public.panelist_material_stocks WHERE panelist_id='e1000000-0000-0000-0000-000000000001' AND material_id=m1) <> 6 THEN
    RAISE EXCEPTION 'FAIL stock tras parcial'; END IF;
  IF (SELECT count(*) FROM public.material_movements WHERE reference_id = s1 AND movement_type='receipt') <> 1 THEN
    RAISE EXCEPTION 'FAIL movimientos tras parcial'; END IF;
  r := public.receive_material_shipment_items(s1, format('[{"material_id":"%s","quantity":4}]', m1)::jsonb);
  IF r->>'status' <> 'partially_received' THEN RAISE EXCEPTION 'FAIL parcial 2: %', r; END IF;
  PERFORM pg_temp.expect_err(format($q$SELECT public.receive_material_shipment_items(%L, %L::jsonb)$q$, s1,
    format('[{"material_id":"%s","quantity":5}]', m2)), 'quantity exceeds sent');
  r := public.receive_material_shipment_items(s1, format('[{"material_id":"%s","quantity":4}]', m2)::jsonb);
  IF r->>'status' <> 'received' OR (r->>'incident_resolved')::boolean THEN RAISE EXCEPTION 'FAIL completo s1: %', r; END IF;
  IF (SELECT quantity FROM public.panelist_material_stocks WHERE panelist_id='e1000000-0000-0000-0000-000000000001' AND material_id=m1) <> 10
     OR (SELECT quantity FROM public.panelist_material_stocks WHERE panelist_id='e1000000-0000-0000-0000-000000000001' AND material_id=m2) <> 4 THEN
    RAISE EXCEPTION 'FAIL stock final s1'; END IF;
  IF (SELECT count(*) FROM public.material_movements WHERE reference_id = s1 AND movement_type='receipt') <> 3 THEN
    RAISE EXCEPTION 'FAIL movimientos s1'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.material_shipments WHERE id = s1 AND status='received' AND received_date IS NOT NULL) THEN
    RAISE EXCEPTION 'FAIL s1 received'; END IF;
  IF (SELECT status FROM public.panelist_incident WHERE id = inc) <> 'open' THEN RAISE EXCEPTION 'FAIL incidencia resuelta antes de tiempo'; END IF;
  r := public.receive_material_shipment_items(s1, '[]'::jsonb);
  IF r->>'status' <> 'received' THEN RAISE EXCEPTION 'FAIL idempotencia'; END IF;
  PERFORM set_config('request.jwt.claim.sub','', true);
END $$;

-- el ultimo envio cierra la incidencia pero NO la baja
DO $$
DECLARE s2 uuid := (SELECT v FROM t_ids WHERE k='s2'); m1 uuid := (SELECT v FROM t_ids WHERE k='m1');
        inc uuid := (SELECT v FROM t_ids WHERE k='inc'); r jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
  r := public.receive_material_shipment_items(s2, format('[{"material_id":"%s","quantity":5}]', m1)::jsonb);
  PERFORM set_config('request.jwt.claim.sub','', true);
  IF r->>'status' <> 'received' OR NOT (r->>'incident_resolved')::boolean THEN RAISE EXCEPTION 'FAIL cierre: %', r; END IF;
  IF (SELECT status FROM public.panelist_incident WHERE id = inc) <> 'resolved' THEN RAISE EXCEPTION 'FAIL incidencia no resuelta'; END IF;
  IF (SELECT status FROM public.panelist_unavailability WHERE id = (SELECT v FROM t_ids WHERE k='unav')) <> 'active' THEN
    RAISE EXCEPTION 'FAIL la baja ya no esta active'; END IF;
  IF (SELECT quantity FROM public.panelist_material_stocks WHERE panelist_id='e1000000-0000-0000-0000-000000000001' AND material_id=m1) <> 15 THEN
    RAISE EXCEPTION 'FAIL stock acumulado'; END IF;
  IF (SELECT count(*) FROM public.incident_message WHERE incident_id = inc AND direction='internal' AND body LIKE 'Recibido:%') <> 4 THEN
    RAISE EXCEPTION 'FAIL mensajes Recibido: %', (SELECT count(*) FROM public.incident_message WHERE incident_id = inc AND body LIKE 'Recibido:%'); END IF;
  IF NOT EXISTS (SELECT 1 FROM public.incident_message WHERE incident_id = inc AND body = 'Material recibido completo') THEN
    RAISE EXCEPTION 'FAIL mensaje cierre'; END IF;
  IF (SELECT resolution_note FROM public.panelist_incident WHERE id = inc) <> 'Material recibido.' THEN
    RAISE EXCEPTION 'FAIL nota de resolucion: %', (SELECT resolution_note FROM public.panelist_incident WHERE id = inc); END IF;
END $$;

-- una incidencia ya resuelta no se vuelve a resolver al recibir otro envio enlazado
INSERT INTO public.material_shipments (id, account_id, panelist_id, status, panelist_incident_id)
VALUES ('f0000000-0000-0000-0000-0000000000b9','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','sent',(SELECT v FROM t_ids WHERE k='inc'));
INSERT INTO public.material_shipment_items (account_id, material_shipment_id, material_id, quantity_sent)
VALUES ('a0000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-0000000000b9',(SELECT v FROM t_ids WHERE k='m1'),2);
DO $$
DECLARE inc uuid := (SELECT v FROM t_ids WHERE k='inc'); r jsonb; v_at timestamptz;
BEGIN
  SELECT resolved_at INTO v_at FROM public.panelist_incident WHERE id = inc;
  PERFORM set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
  r := public.receive_material_shipment_items('f0000000-0000-0000-0000-0000000000b9',
         format('[{"material_id":"%s","quantity":2}]', (SELECT v FROM t_ids WHERE k='m1'))::jsonb);
  PERFORM set_config('request.jwt.claim.sub','', true);
  IF r->>'status' <> 'received' OR (r->>'incident_resolved')::boolean THEN RAISE EXCEPTION 'FAIL re-resuelve: %', r; END IF;
  IF (SELECT resolved_at FROM public.panelist_incident WHERE id = inc) IS DISTINCT FROM v_at THEN
    RAISE EXCEPTION 'FAIL resolved_at cambiado'; END IF;
  IF (SELECT count(*) FROM public.incident_message WHERE incident_id = inc AND body = 'Material recibido completo') <> 1 THEN
    RAISE EXCEPTION 'FAIL segundo mensaje de cierre'; END IF;
  IF (SELECT count(*) FROM public.incident_message WHERE incident_id = inc AND body LIKE 'Estado:%') <> 1 THEN
    RAISE EXCEPTION 'FAIL segundo cambio de estado'; END IF;
END $$;

-- boton antiguo (incidencia enlazada por linked_material_shipment_id): recibe lo pendiente y la baja sigue active
INSERT INTO public.panelist_incident (id, account_id, panelist_id, category, status, linked_unavailability_id)
VALUES ('f0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','missing_materials','open',(SELECT v FROM t_ids WHERE k='unav'));
INSERT INTO public.material_shipments (id, account_id, panelist_id, status)
VALUES ('f0000000-0000-0000-0000-0000000000b1','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','sent');
UPDATE public.panelist_incident SET linked_material_shipment_id = 'f0000000-0000-0000-0000-0000000000b1' WHERE id = 'f0000000-0000-0000-0000-0000000000a1';
INSERT INTO public.material_shipment_items (account_id, material_shipment_id, material_id, quantity_sent, quantity_received)
VALUES ('a0000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-0000000000b1',(SELECT v FROM t_ids WHERE k='m2'),3,1);
DO $$ BEGIN
  PERFORM set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
  PERFORM public.receive_material_shipment('f0000000-0000-0000-0000-0000000000b1');
  PERFORM public.receive_material_shipment('f0000000-0000-0000-0000-0000000000b1');
  PERFORM set_config('request.jwt.claim.sub','', true);
  IF NOT EXISTS (SELECT 1 FROM public.material_shipments WHERE id='f0000000-0000-0000-0000-0000000000b1' AND status='received') THEN
    RAISE EXCEPTION 'FAIL boton antiguo no recibe'; END IF;
  IF (SELECT quantity_received FROM public.material_shipment_items WHERE material_shipment_id='f0000000-0000-0000-0000-0000000000b1') <> 3 THEN
    RAISE EXCEPTION 'FAIL cantidad restante'; END IF;
  IF (SELECT quantity FROM public.panelist_material_stocks WHERE panelist_id='e1000000-0000-0000-0000-000000000001'
        AND material_id=(SELECT v FROM t_ids WHERE k='m2')) <> 6 THEN RAISE EXCEPTION 'FAIL stock boton antiguo'; END IF;
  IF (SELECT status FROM public.panelist_incident WHERE id='f0000000-0000-0000-0000-0000000000a1') <> 'resolved' THEN
    RAISE EXCEPTION 'FAIL back-compat incidencia'; END IF;
  IF (SELECT status FROM public.panelist_unavailability WHERE id = (SELECT v FROM t_ids WHERE k='unav')) <> 'active' THEN
    RAISE EXCEPTION 'FAIL boton antiguo cancelo la baja'; END IF;
END $$;

-- envio pendiente no se recibe; privilegios
UPDATE public.material_shipments SET status = 'pending' WHERE id = (SELECT v FROM t_ids WHERE k='s2');
DO $$ BEGIN
  PERFORM set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
  PERFORM pg_temp.expect_err(format($q$SELECT public.receive_material_shipment_items(%L, '[]')$q$, (SELECT v FROM t_ids WHERE k='s2')), 'shipment');
  PERFORM set_config('request.jwt.claim.sub','', true);
END $$;
DO $$
DECLARE f text := 'public.receive_material_shipment_items(uuid,jsonb)';
BEGIN
  IF has_function_privilege('anon', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL anon con EXECUTE'; END IF;
  IF NOT has_function_privilege('authenticated', f, 'EXECUTE') OR NOT has_function_privilege('service_role', f, 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL falta GRANT'; END IF;
  f := 'public.refresh_material_hold(uuid)';
  IF has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE')
     OR NOT has_function_privilege('service_role', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL privilegios hold'; END IF;
END $$;
ROLLBACK;

-- ===== Escenario 4: envios retenidos por falta de material =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v uuid);
WITH x AS (INSERT INTO public.material_catalog (account_id, code, name)
  VALUES ('a0000000-0000-0000-0000-000000000001','M1','Etiquetas') RETURNING id)
INSERT INTO t_ids SELECT 'm1', id FROM x;
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','PR2','Prod2',48);
INSERT INTO public.product_materials (account_id, product_id, material_id, quantity)
VALUES ('a0000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000002',(SELECT v FROM t_ids WHERE k='m1'),10);
INSERT INTO public.allocation_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date) VALUES
  ('cc000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','Mat','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000002',10,'2027-03-01','2027-03-31');
-- 3 envios de P1 (nodo N1) en +1, +2, +3 dias
WITH x AS (
  INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status)
  SELECT 'a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000003',
         'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004', current_date + n, 1, 1, 2027, 'pending'
    FROM generate_series(1,3) n RETURNING id, fecha_programada)
INSERT INTO t_ids SELECT 'd' || (fecha_programada - current_date), id FROM x;
INSERT INTO public.panelist_incident (id, account_id, panelist_id, category, status)
VALUES ('f0000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','missing_materials','open');
CREATE FUNCTION pg_temp.set_stock(q numeric) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.panelist_material_stocks (account_id, panelist_id, material_id, quantity)
  VALUES ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',(SELECT v FROM t_ids WHERE k='m1'), q)
  ON CONFLICT (account_id, panelist_id, material_id) DO UPDATE SET quantity = excluded.quantity;
$$;
CREATE FUNCTION pg_temp.held() RETURNS uuid[] LANGUAGE sql AS $$
  SELECT coalesce(array_agg(x ORDER BY x), '{}') FROM public.panelist_held_detail_ids('e1000000-0000-0000-0000-000000000001') x;
$$;

-- stock 15: el primero (dia +1) libre; segundo y tercero retenidos
DO $$
DECLARE d1 uuid := (SELECT v FROM t_ids WHERE k='d1'); d2 uuid := (SELECT v FROM t_ids WHERE k='d2'); d3 uuid := (SELECT v FROM t_ids WHERE k='d3'); r uuid[];
BEGIN
  PERFORM pg_temp.set_stock(15);
  r := public.refresh_material_hold('e1000000-0000-0000-0000-000000000001');
  IF r <> '{}' THEN RAISE EXCEPTION 'FAIL nada que liberar aun: %', r; END IF;
  IF pg_temp.held() <> (SELECT array_agg(x ORDER BY x) FROM unnest(ARRAY[d2,d3]) x) THEN RAISE EXCEPTION 'FAIL retenidos stock 15: %', pg_temp.held(); END IF;
  -- idempotente
  r := public.refresh_material_hold('e1000000-0000-0000-0000-000000000001');
  IF r <> '{}' OR (SELECT count(*) FROM public.material_hold WHERE released_at IS NULL) <> 2 THEN RAISE EXCEPTION 'FAIL idempotencia'; END IF;
  -- stock 20: se libera el segundo (por fecha), el tercero sigue retenido
  PERFORM pg_temp.set_stock(20);
  r := public.refresh_material_hold('e1000000-0000-0000-0000-000000000001');
  IF r <> ARRAY[d2] THEN RAISE EXCEPTION 'FAIL liberado stock 20: %', r; END IF;
  IF pg_temp.held() <> ARRAY[d3] THEN RAISE EXCEPTION 'FAIL retenido stock 20: %', pg_temp.held(); END IF;
  IF (SELECT released_at FROM public.material_hold WHERE allocation_plan_detail_id = d2) IS NULL THEN RAISE EXCEPTION 'FAIL released_at d2'; END IF;
  -- incidencia resuelta: libera el resto
  UPDATE public.panelist_incident SET status = 'resolved' WHERE id = 'f0000000-0000-0000-0000-0000000000c1';
  r := public.refresh_material_hold('e1000000-0000-0000-0000-000000000001');
  IF r <> ARRAY[d3] OR pg_temp.held() <> '{}' THEN RAISE EXCEPTION 'FAIL sin incidencia abierta: %', r; END IF;
  -- sin incidencia abierta y sin stock: nada retenido
  PERFORM pg_temp.set_stock(0);
  r := public.refresh_material_hold('e1000000-0000-0000-0000-000000000001');
  IF r <> '{}' OR pg_temp.held() <> '{}' THEN RAISE EXCEPTION 'FAIL retiene sin incidencia'; END IF;
  -- reabierta y sin stock: todo retenido; un envio cancelado se cierra sin devolverse
  UPDATE public.panelist_incident SET status = 'in_progress' WHERE id = 'f0000000-0000-0000-0000-0000000000c1';
  r := public.refresh_material_hold('e1000000-0000-0000-0000-000000000001');
  IF r <> '{}' OR cardinality(pg_temp.held()) <> 3 THEN RAISE EXCEPTION 'FAIL todo retenido'; END IF;
  UPDATE public.allocation_plan_details SET status = 'cancelled' WHERE id = d3;
  r := public.refresh_material_hold('e1000000-0000-0000-0000-000000000001');
  IF r <> '{}' OR cardinality(pg_temp.held()) <> 2
     OR (SELECT released_at FROM public.material_hold WHERE allocation_plan_detail_id = d3) IS NULL THEN
    RAISE EXCEPTION 'FAIL cancelado: % %', r, pg_temp.held(); END IF;
  UPDATE public.allocation_plan_details SET status = 'pending' WHERE id = d3;
  r := public.refresh_material_hold('e1000000-0000-0000-0000-000000000001');
  IF cardinality(pg_temp.held()) <> 3 THEN RAISE EXCEPTION 'FAIL re-retenido'; END IF;
  -- stock suficiente para todo: nada retenido y se libera
  PERFORM pg_temp.set_stock(100);
  r := public.refresh_material_hold('e1000000-0000-0000-0000-000000000001');
  IF r <> ARRAY[d1,d2,d3] OR pg_temp.held() <> '{}' THEN RAISE EXCEPTION 'FAIL stock suficiente: %', r; END IF;
  -- producto sin materiales: libre
  PERFORM pg_temp.set_stock(0);
  DELETE FROM public.product_materials WHERE product_id = 'cb000000-0000-0000-0000-000000000002';
  r := public.refresh_material_hold('e1000000-0000-0000-0000-000000000001');
  IF pg_temp.held() <> '{}' THEN RAISE EXCEPTION 'FAIL producto sin materiales retenido'; END IF;
  INSERT INTO public.product_materials (account_id, product_id, material_id, quantity)
  VALUES ('a0000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000002',(SELECT v FROM t_ids WHERE k='m1'),10);
END $$;

-- cierre manual de la incidencia: los retenidos se ocultan y se liberan
DO $$
DECLARE d1 uuid := (SELECT v FROM t_ids WHERE k='d1'); d2 uuid := (SELECT v FROM t_ids WHERE k='d2'); d3 uuid := (SELECT v FROM t_ids WHERE k='d3');
        r uuid[]; p constant uuid := 'e1000000-0000-0000-0000-000000000001'; i constant uuid := 'f0000000-0000-0000-0000-0000000000c1';
BEGIN
  PERFORM pg_temp.set_stock(0);
  r := public.refresh_material_hold(p);
  IF cardinality(pg_temp.held()) <> 3 THEN RAISE EXCEPTION 'FAIL previo cierre manual: %', pg_temp.held(); END IF;
  -- sin refresh, una incidencia cerrada no devuelve retenidos
  UPDATE public.panelist_incident SET status = 'resolved' WHERE id = i;
  IF pg_temp.held() <> '{}' THEN RAISE EXCEPTION 'FAIL retenidos visibles con incidencia cerrada'; END IF;
  UPDATE public.panelist_incident SET status = 'in_progress' WHERE id = i;
  IF cardinality(pg_temp.held()) <> 3 THEN RAISE EXCEPTION 'FAIL retenidos no vuelven al reabrir'; END IF;
  -- resolve_panelist_incident libera
  PERFORM set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
  PERFORM public.resolve_panelist_incident(i, 'dismissed', 'Descartada', NULL);
  PERFORM set_config('request.jwt.claim.sub','', true);
  IF pg_temp.held() <> '{}' THEN RAISE EXCEPTION 'FAIL retenidos tras cierre manual'; END IF;
  IF (SELECT count(*) FROM public.material_hold WHERE panelist_id = p AND released_at IS NULL) <> 0
     OR (SELECT count(*) FROM public.material_hold WHERE panelist_id = p AND released_at IS NOT NULL) <> 3 THEN
    RAISE EXCEPTION 'FAIL material_hold sin released_at tras cierre manual'; END IF;
  UPDATE public.panelist_incident SET status = 'in_progress' WHERE id = i;
  -- panelista inactivo: no retiene, se libera todo y se devuelven los del conjunto
  r := public.refresh_material_hold(p);
  IF cardinality(pg_temp.held()) <> 3 THEN RAISE EXCEPTION 'FAIL previo inactivo'; END IF;
  UPDATE public.panelists SET status = 'inactive' WHERE id = p;
  r := public.refresh_material_hold(p);
  IF r <> ARRAY[d1,d2,d3] OR (SELECT count(*) FROM public.material_hold WHERE panelist_id = p AND released_at IS NULL) <> 0 THEN
    RAISE EXCEPTION 'FAIL inactivo retiene: %', r; END IF;
  UPDATE public.panelists SET status = 'active' WHERE id = p;
  r := public.refresh_material_hold(p);
  IF cardinality(pg_temp.held()) <> 3 THEN RAISE EXCEPTION 'FAIL reactivado no retiene'; END IF;
END $$;

SELECT pg_temp.expect_err($$SELECT public.refresh_material_hold('00000000-0000-0000-0000-000000000000')$$, 'panelist not found');

-- integracion con la recepcion: el stock recibido libera los envios (en orden de fecha)
DO $$
DECLARE d1 uuid := (SELECT v FROM t_ids WHERE k='d1'); d2 uuid := (SELECT v FROM t_ids WHERE k='d2'); m1 uuid := (SELECT v FROM t_ids WHERE k='m1');
        s uuid; r jsonb;
BEGIN
  PERFORM public.refresh_material_hold('e1000000-0000-0000-0000-000000000001');
  IF cardinality(pg_temp.held()) <> 3 THEN RAISE EXCEPTION 'FAIL previo integracion'; END IF;
  INSERT INTO public.material_shipments (account_id, panelist_id, status)
  VALUES ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','sent') RETURNING id INTO s;
  INSERT INTO public.material_shipment_items (account_id, material_shipment_id, material_id, quantity_sent)
  VALUES ('a0000000-0000-0000-0000-000000000001', s, m1, 20);
  PERFORM set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
  r := public.receive_material_shipment_items(s, format('[{"material_id":"%s","quantity":20}]', m1)::jsonb);
  PERFORM set_config('request.jwt.claim.sub','', true);
  IF r->'released_detail_ids' <> to_jsonb(ARRAY[d1,d2]) THEN RAISE EXCEPTION 'FAIL released_detail_ids: %', r; END IF;
  IF cardinality(pg_temp.held()) <> 1 THEN RAISE EXCEPTION 'FAIL retenidos tras recepcion'; END IF;
END $$;

-- privilegios
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.refresh_material_hold(uuid)','public.panelist_held_detail_ids(uuid)'] LOOP
    IF has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL anon/authenticated con EXECUTE en %', f; END IF;
    IF NOT has_function_privilege('service_role', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL service_role sin EXECUTE en %', f; END IF;
  END LOOP;
  IF has_table_privilege('anon', 'public.material_hold', 'SELECT') THEN RAISE EXCEPTION 'FAIL anon SELECT hold'; END IF;
  IF NOT has_table_privilege('authenticated', 'public.material_hold', 'SELECT') THEN RAISE EXCEPTION 'FAIL authenticated sin SELECT hold'; END IF;
  IF has_table_privilege('authenticated', 'public.material_hold', 'INSERT') OR has_table_privilege('authenticated', 'public.material_hold', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.material_hold', 'DELETE') THEN RAISE EXCEPTION 'FAIL authenticated escribe hold'; END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.material_hold'::regclass) THEN RAISE EXCEPTION 'FAIL hold sin RLS'; END IF;
END $$;
ROLLBACK;

-- ===== Escenario 5: agregacion de materiales, aislamiento de cuenta y enlace de incidencia =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v uuid);
WITH x AS (INSERT INTO public.material_catalog (account_id, code, name)
  VALUES ('a0000000-0000-0000-0000-000000000001','M1','Etiquetas') RETURNING id)
INSERT INTO t_ids SELECT 'm1', id FROM x;
WITH x AS (INSERT INTO public.material_catalog (account_id, code, name)
  VALUES ('a0000000-0000-0000-0000-000000000001','M2','Bolsas') RETURNING id)
INSERT INTO t_ids SELECT 'm2', id FROM x;
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','PR2','Prod2',48);
INSERT INTO public.product_materials (account_id, product_id, material_id, quantity) VALUES
  ('a0000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000002',(SELECT v FROM t_ids WHERE k='m1'),10),
  ('a0000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000002',(SELECT v FROM t_ids WHERE k='m2'),5);
INSERT INTO public.allocation_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date) VALUES
  ('cc000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','Mat','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000002',10,'2027-03-01','2027-03-31');
WITH x AS (
  INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status)
  VALUES ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000003',
          'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004', current_date + 1, 1, 1, 2027, 'pending')
  RETURNING id)
INSERT INTO t_ids SELECT 'd1', id FROM x;
-- envio de OTRA cuenta con el mismo nodo origen: no cuenta
WITH x AS (
  INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status)
  VALUES ('a0000000-0000-0000-0000-000000000002','cc000000-0000-0000-0000-000000000003',
          'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004', current_date + 1, 1, 1, 2027, 'pending')
  RETURNING id)
INSERT INTO t_ids SELECT 'dx', id FROM x;
INSERT INTO public.panelist_incident (id, account_id, panelist_id, category, status)
VALUES ('f0000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','missing_materials','open');
CREATE FUNCTION pg_temp.set_stock(m text, q numeric) RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.panelist_material_stocks (account_id, panelist_id, material_id, quantity)
  VALUES ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001',(SELECT v FROM t_ids WHERE k=m), q)
  ON CONFLICT (account_id, panelist_id, material_id) DO UPDATE SET quantity = excluded.quantity;
$$;

DO $$
DECLARE d1 uuid := (SELECT v FROM t_ids WHERE k='d1'); r uuid[]; p constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  -- dos materiales, uno corto: retenido
  PERFORM pg_temp.set_stock('m1', 100); PERFORM pg_temp.set_stock('m2', 2);
  r := public.refresh_material_hold(p);
  IF NOT EXISTS (SELECT 1 FROM public.material_hold WHERE allocation_plan_detail_id = d1 AND released_at IS NULL) THEN
    RAISE EXCEPTION 'FAIL material corto no retiene'; END IF;
  -- el envio de otra cuenta no se considera
  IF EXISTS (SELECT 1 FROM public.material_hold WHERE allocation_plan_detail_id = (SELECT v FROM t_ids WHERE k='dx')) THEN
    RAISE EXCEPTION 'FAIL considera envio de otra cuenta'; END IF;
  PERFORM pg_temp.set_stock('m2', 5);
  r := public.refresh_material_hold(p);
  IF r <> ARRAY[d1] THEN RAISE EXCEPTION 'FAIL liberado con ambos materiales: %', r; END IF;
  -- material duplicado (se quita la unicidad solo en esta transaccion): se suma
  ALTER TABLE public.product_materials DROP CONSTRAINT product_materials_unique;
  INSERT INTO public.product_materials (account_id, product_id, material_id, quantity)
  VALUES ('a0000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000002',(SELECT v FROM t_ids WHERE k='m1'),10);
  PERFORM pg_temp.set_stock('m1', 15);
  r := public.refresh_material_hold(p);
  IF r <> '{}' OR NOT EXISTS (SELECT 1 FROM public.material_hold WHERE allocation_plan_detail_id = d1 AND released_at IS NULL) THEN
    RAISE EXCEPTION 'FAIL duplicado no suma'; END IF;
  PERFORM pg_temp.set_stock('m1', 20);
  r := public.refresh_material_hold(p);
  IF r <> ARRAY[d1] THEN RAISE EXCEPTION 'FAIL duplicado suficiente: %', r; END IF;
END $$;

-- enlace de incidencia limitado a la cuenta/panelista del envio
ALTER TABLE public.panelist_incident DISABLE TRIGGER panelist_incident_same_account;
INSERT INTO public.panelist_incident (id, account_id, panelist_id, category, status) VALUES
  ('f0000000-0000-0000-0000-0000000000c2','a0000000-0000-0000-0000-000000000002','e1000000-0000-0000-0000-000000000001','missing_materials','open');
ALTER TABLE public.panelist_incident ENABLE TRIGGER panelist_incident_same_account;
INSERT INTO public.panelist_incident (id, account_id, panelist_id, category, status) VALUES
  ('f0000000-0000-0000-0000-0000000000c3','a0000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000002','missing_materials','open');
SELECT pg_temp.expect_err($$INSERT INTO public.material_shipments (account_id, panelist_id, status, panelist_incident_id)
  VALUES ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','sent','f0000000-0000-0000-0000-0000000000c2')$$,
  'incident belongs to another account');
-- envio de P1 enlazado a incidencia de otro panelista (misma cuenta) y referenciado desde la incidencia de otra cuenta
INSERT INTO public.material_shipments (id, account_id, panelist_id, status, panelist_incident_id)
VALUES ('f0000000-0000-0000-0000-0000000000b1','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','sent','f0000000-0000-0000-0000-0000000000c3');
UPDATE public.panelist_incident SET linked_material_shipment_id = 'f0000000-0000-0000-0000-0000000000b1'
 WHERE id = 'f0000000-0000-0000-0000-0000000000c2';
INSERT INTO public.material_shipment_items (account_id, material_shipment_id, material_id, quantity_sent)
VALUES ('a0000000-0000-0000-0000-000000000001','f0000000-0000-0000-0000-0000000000b1',(SELECT v FROM t_ids WHERE k='m1'),3);
DO $$ BEGIN
  PERFORM set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
  PERFORM public.receive_material_shipment('f0000000-0000-0000-0000-0000000000b1');
  PERFORM set_config('request.jwt.claim.sub','', true);
  IF (SELECT status FROM public.panelist_incident WHERE id = 'f0000000-0000-0000-0000-0000000000c2') <> 'open'
     OR (SELECT status FROM public.panelist_incident WHERE id = 'f0000000-0000-0000-0000-0000000000c3') <> 'open' THEN
    RAISE EXCEPTION 'FAIL resolvio una incidencia ajena'; END IF;
END $$;
ROLLBACK;

-- ===== Escenario 6: avisos y respuestas del manager quedan en la conversacion =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
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

INSERT INTO public.panelist_notification (id, account_id, panelist_id, kind, payload) VALUES
  ('f1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','material_pending_released',
   jsonb_build_object('incident_kind','reported','incident_id',(SELECT v FROM t_ids WHERE k='inc'),'text','Ya tienes material')),
  ('f1000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','plan_change_this_week','{}'),
  ('f1000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','unavailability_received',
   jsonb_build_object('unavailability_id',(SELECT v FROM t_ids WHERE k='unav'))),
  ('f1000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','material_pending_released',
   jsonb_build_object('incident_kind','reported','incident_id',(SELECT v FROM t_ids WHERE k='inc'),'text','no enviado')),
  ('f1000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','material_pending_released',
   '{"incident_kind":"reported","incident_id":"no-es-uuid"}');

DO $$
DECLARE v_inc uuid := (SELECT v FROM t_ids WHERE k='inc'); v_un uuid := (SELECT v FROM t_ids WHERE k='unav'); r public.incident_message;
BEGIN
  IF (SELECT count(*) FROM public.incident_message) <> 0 THEN RAISE EXCEPTION 'FAIL se registra al insertar'; END IF;
  UPDATE public.panelist_notification SET status = 'sent' WHERE id = 'f1000000-0000-0000-0000-000000000001';
  SELECT * INTO r FROM public.incident_message WHERE incident_id = v_inc;
  IF r.body <> 'Ya tienes material' OR r.direction <> 'outbound' OR r.author <> 'bot' OR r.status <> 'sent'
     OR r.meta->>'notification_id' <> 'f1000000-0000-0000-0000-000000000001' OR r.meta->>'kind' <> 'material_pending_released' THEN
    RAISE EXCEPTION 'FAIL aviso con incidencia: %', row_to_json(r); END IF;
  -- sin claves ni baja: nada
  UPDATE public.panelist_notification SET status = 'sent' WHERE id = 'f1000000-0000-0000-0000-000000000002';
  IF (SELECT count(*) FROM public.incident_message) <> 1 THEN RAISE EXCEPTION 'FAIL registro aviso sin incidencia'; END IF;
  -- baja: se registra contra la baja (sin texto -> kind)
  UPDATE public.panelist_notification SET status = 'sent' WHERE id = 'f1000000-0000-0000-0000-000000000003';
  SELECT * INTO r FROM public.incident_message WHERE incident_kind = 'unavailability' AND incident_id = v_un;
  IF r.id IS NULL OR r.body <> 'unavailability_received' OR r.status <> 'sent' THEN RAISE EXCEPTION 'FAIL aviso de baja: %', row_to_json(r); END IF;
  -- failed: nada
  UPDATE public.panelist_notification SET status = 'failed' WHERE id = 'f1000000-0000-0000-0000-000000000004';
  IF (SELECT count(*) FROM public.incident_message) <> 2 THEN RAISE EXCEPTION 'FAIL registro en failed'; END IF;
  -- payload roto: la notificacion se actualiza igualmente y no se registra nada
  UPDATE public.panelist_notification SET status = 'sent' WHERE id = 'f1000000-0000-0000-0000-000000000005';
  IF (SELECT status FROM public.panelist_notification WHERE id = 'f1000000-0000-0000-0000-000000000005') <> 'sent'
     OR (SELECT count(*) FROM public.incident_message) <> 2 THEN RAISE EXCEPTION 'FAIL payload roto'; END IF;
  -- re-actualizar sin cambiar de estado: no duplica
  UPDATE public.panelist_notification SET status = 'sent', error = 'x' WHERE id = 'f1000000-0000-0000-0000-000000000001';
  IF (SELECT count(*) FROM public.incident_message) <> 2 THEN RAISE EXCEPTION 'FAIL duplicado aviso'; END IF;
END $$;

-- respuesta del manager (flujo antiguo) y cambio de estado
DO $$
DECLARE v_inc uuid := (SELECT v FROM t_ids WHERE k='inc'); r public.incident_message;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
  PERFORM public.resolve_panelist_incident(v_inc, 'in_progress', NULL, 'Lo miramos');
  IF (SELECT reply_status FROM public.panelist_incident WHERE id = v_inc) <> 'pending_send' THEN
    RAISE EXCEPTION 'FAIL reply_status cambiado'; END IF;
  IF EXISTS (SELECT 1 FROM public.incident_message WHERE incident_id = v_inc AND author = 'manager') THEN
    RAISE EXCEPTION 'FAIL registra respuesta aun pendiente'; END IF;
  SELECT * INTO r FROM public.incident_message WHERE incident_id = v_inc AND author = 'system';
  IF r.body <> 'Estado: in_progress' OR r.direction <> 'internal' OR r.meta->>'status' <> 'in_progress' THEN
    RAISE EXCEPTION 'FAIL estado: %', row_to_json(r); END IF;
  -- mismo estado: no se registra de nuevo
  PERFORM public.resolve_panelist_incident(v_inc, 'in_progress', NULL, NULL);
  IF (SELECT count(*) FROM public.incident_message WHERE incident_id = v_inc AND author = 'system') <> 1 THEN
    RAISE EXCEPTION 'FAIL duplica estado'; END IF;
  PERFORM public.resolve_panelist_incident(v_inc, 'resolved', 'Hecho', NULL);
  IF NOT EXISTS (SELECT 1 FROM public.incident_message WHERE incident_id = v_inc AND body = 'Estado: resolved - Hecho') THEN
    RAISE EXCEPTION 'FAIL estado resolved'; END IF;
  PERFORM set_config('request.jwt.claim.sub','', true);
  -- el envio de la respuesta (n8n) la deja en la conversacion una sola vez
  UPDATE public.panelist_incident SET reply_status = 'sent' WHERE id = v_inc;
  UPDATE public.panelist_incident SET reply_status = 'sent', updated_at = now() WHERE id = v_inc;
  SELECT * INTO r FROM public.incident_message WHERE incident_id = v_inc AND author = 'manager';
  IF r.body <> 'Lo miramos' OR r.direction <> 'outbound' OR r.status <> 'sent' OR r.meta->>'via' <> 'legacy_reply' THEN
    RAISE EXCEPTION 'FAIL respuesta manager: %', row_to_json(r); END IF;
  IF (SELECT count(*) FROM public.incident_message WHERE incident_id = v_inc AND author = 'manager') <> 1 THEN
    RAISE EXCEPTION 'FAIL duplica respuesta'; END IF;
END $$;
ROLLBACK;
