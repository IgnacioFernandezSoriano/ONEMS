-- Conversaciones sin leer, aviso al manager y cierre de la conversacion al resolver.
-- Cada escenario en su propia transaccion.
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

-- ===== Escenario 1: marcar leido, lista de no leidos, avisos por email =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
UPDATE public.panelists SET telegram_id = 'tg-p1' WHERE id = 'e1000000-0000-0000-0000-000000000001';
UPDATE public.accounts SET email_panelist_manager = 'mgr@t.l', admin_email = 'adm@t.l'
 WHERE id = 'a0000000-0000-0000-0000-000000000001';
-- superadmin (sin cuenta)
INSERT INTO auth.users (id, email) VALUES ('97000000-0000-0000-0000-000000000097','super@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('97000000-0000-0000-0000-000000000097','super@t.l','Super','superadmin',NULL);
-- panelista de la cuenta 2
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, status, language) VALUES
  ('e9000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000002','P9','Pan9','p9@t.l','9','active','en');
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v uuid);
WITH x AS (
  INSERT INTO public.panelist_incident (account_id, panelist_id, category, status)
  VALUES ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','other','open')
  RETURNING id)
INSERT INTO t_ids SELECT 'inc', id FROM x;
WITH x AS (
  INSERT INTO public.panelist_unavailability (panelist_id, account_id, start_date, end_date, reason, status)
  VALUES ('e2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001',
          current_date + 1, current_date + 5, 'vacation', 'active')
  RETURNING id)
INSERT INTO t_ids SELECT 'unav', id FROM x;
WITH x AS (
  INSERT INTO public.panelist_incident (account_id, panelist_id, category, status)
  VALUES ('a0000000-0000-0000-0000-000000000002','e9000000-0000-0000-0000-000000000009','other','open')
  RETURNING id)
INSERT INTO t_ids SELECT 'inc2', id FROM x;

-- mensajes: inc (2 inbound viejos, 1 outbound, 1 inbound ya leido), unav (1 inbound reciente), inc2 (1 inbound viejo)
DO $$
DECLARE v_inc uuid := (SELECT v FROM t_ids WHERE k='inc'); v_un uuid := (SELECT v FROM t_ids WHERE k='unav');
        v_inc2 uuid := (SELECT v FROM t_ids WHERE k='inc2'); m uuid;
BEGIN
  m := public.log_incident_message('reported', v_inc, 'inbound', 'panelist', 'r1');
  UPDATE public.incident_message SET created_at = now() - interval '3 hours' WHERE id = m;
  m := public.log_incident_message('reported', v_inc, 'inbound', 'panelist', 'r2');
  UPDATE public.incident_message SET created_at = now() - interval '2 hours' WHERE id = m;
  m := public.log_incident_message('reported', v_inc, 'outbound', 'manager', 'o1');
  m := public.log_incident_message('reported', v_inc, 'inbound', 'panelist', 'leido');
  UPDATE public.incident_message SET created_at = now() - interval '5 hours', read_at = now() - interval '4 hours' WHERE id = m;
  m := public.log_incident_message('unavailability', v_un, 'inbound', 'panelist', 'u1');
  UPDATE public.incident_message SET created_at = now() - interval '10 minutes' WHERE id = m;
  m := public.log_incident_message('reported', v_inc2, 'inbound', 'panelist', 'x1');
  UPDATE public.incident_message SET created_at = now() - interval '2 hours' WHERE id = m;
END $$;

-- unread_incident_conversations: cuenta 1 ve inc (2) y unav (1); cuenta 2 ve inc2; superadmin ve las 3; service role nada
DO $$
DECLARE v_inc uuid := (SELECT v FROM t_ids WHERE k='inc'); v_un uuid := (SELECT v FROM t_ids WHERE k='unav');
        v_inc2 uuid := (SELECT v FROM t_ids WHERE k='inc2'); r record; n int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
  SELECT count(*) INTO n FROM public.unread_incident_conversations();
  IF n <> 2 THEN RAISE EXCEPTION 'FAIL cuenta 1 ve % conversaciones (esperaba 2)', n; END IF;
  SELECT * INTO r FROM public.unread_incident_conversations() WHERE incident_id = v_inc;
  IF r.incident_kind <> 'reported' OR r.unread <> 2
     OR r.last_at < now() - interval '2 hours 1 minute' OR r.last_at > now() - interval '1 hour 59 minutes' THEN
    RAISE EXCEPTION 'FAIL fila inc: %', row_to_json(r); END IF;
  SELECT * INTO r FROM public.unread_incident_conversations() WHERE incident_id = v_un;
  IF r.incident_kind <> 'unavailability' OR r.unread <> 1 THEN RAISE EXCEPTION 'FAIL fila unav: %', row_to_json(r); END IF;
  IF EXISTS (SELECT 1 FROM public.unread_incident_conversations() WHERE incident_id = v_inc2) THEN
    RAISE EXCEPTION 'FAIL cuenta 1 ve la cuenta 2'; END IF;

  PERFORM set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000098', true);
  SELECT count(*) INTO n FROM public.unread_incident_conversations();
  IF n <> 1 OR NOT EXISTS (SELECT 1 FROM public.unread_incident_conversations() WHERE incident_id = v_inc2 AND unread = 1) THEN
    RAISE EXCEPTION 'FAIL cuenta 2 ve % conversaciones', n; END IF;

  PERFORM set_config('request.jwt.claim.sub','97000000-0000-0000-0000-000000000097', true);
  SELECT count(*) INTO n FROM public.unread_incident_conversations();
  IF n <> 3 THEN RAISE EXCEPTION 'FAIL superadmin ve % (esperaba 3)', n; END IF;

  PERFORM set_config('request.jwt.claim.sub','', true);
  SELECT count(*) INTO n FROM public.unread_incident_conversations();
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL sin usuario ve % (esperaba 0)', n; END IF;
END $$;

-- due_unread_reply_notifications: inc (viejo, manager mgr@) e inc2 no (cuenta 2 sin email); unav reciente no
DO $$
DECLARE v_inc uuid := (SELECT v FROM t_ids WHERE k='inc'); r record; n int; m uuid;
BEGIN
  SELECT count(*) INTO n FROM public.due_unread_reply_notifications();
  IF n <> 1 THEN RAISE EXCEPTION 'FAIL avisos=% (esperaba 1)', n; END IF;
  SELECT * INTO r FROM public.due_unread_reply_notifications();
  IF r.incident_kind <> 'reported' OR r.incident_id <> v_inc OR r.account_id <> 'a0000000-0000-0000-0000-000000000001'
     OR r.panelist_id <> 'e1000000-0000-0000-0000-000000000001' OR r.panelist_name <> 'Pan1'
     OR r.unread <> 2 OR r.manager_email <> 'mgr@t.l'
     OR r.oldest_at > now() - interval '2 hours 59 minutes' OR r.oldest_at < now() - interval '3 hours 1 minute' THEN
    RAISE EXCEPTION 'FAIL fila aviso: %', row_to_json(r); END IF;
  -- dentro de 1 h el de unav (10 min) ya vence
  IF NOT EXISTS (SELECT 1 FROM public.due_unread_reply_notifications(now() + interval '1 hour')
                  WHERE incident_kind = 'unavailability' AND manager_email = 'mgr@t.l') THEN
    RAISE EXCEPTION 'FAIL unav no vence a la hora'; END IF;
  -- sin email_panelist_manager se usa admin_email
  UPDATE public.accounts SET email_panelist_manager = '' WHERE id = 'a0000000-0000-0000-0000-000000000001';
  IF (SELECT manager_email FROM public.due_unread_reply_notifications() WHERE incident_id = v_inc) IS DISTINCT FROM 'adm@t.l' THEN
    RAISE EXCEPTION 'FAIL fallback admin_email'; END IF;
  -- cuenta 2 con email: aparece inc2
  UPDATE public.accounts SET admin_email = 'adm2@t.l' WHERE id = 'a0000000-0000-0000-0000-000000000002';
  IF NOT EXISTS (SELECT 1 FROM public.due_unread_reply_notifications()
                  WHERE incident_id = (SELECT v FROM t_ids WHERE k='inc2') AND manager_email = 'adm2@t.l') THEN
    RAISE EXCEPTION 'FAIL inc2 con admin_email no aparece'; END IF;
  UPDATE public.accounts SET admin_email = NULL WHERE id = 'a0000000-0000-0000-0000-000000000002';

  -- mark_unread_reply_notified: marca los 2 sin leer de inc; deja de aparecer
  n := public.mark_unread_reply_notified('reported', v_inc);
  IF n <> 2 THEN RAISE EXCEPTION 'FAIL notified marco % (esperaba 2)', n; END IF;
  IF EXISTS (SELECT 1 FROM public.due_unread_reply_notifications(now() + interval '1 day') WHERE incident_id = v_inc) THEN
    RAISE EXCEPTION 'FAIL ya notificado reaparece'; END IF;
  IF EXISTS (SELECT 1 FROM public.incident_message WHERE incident_id = v_inc AND direction <> 'inbound' AND notified_at IS NOT NULL)
     OR EXISTS (SELECT 1 FROM public.incident_message WHERE incident_id = v_inc AND read_at IS NOT NULL AND notified_at IS NOT NULL) THEN
    RAISE EXCEPTION 'FAIL notified marco filas indebidas'; END IF;
  IF public.mark_unread_reply_notified('reported', v_inc) <> 0 THEN RAISE EXCEPTION 'FAIL notified no idempotente'; END IF;
  -- un mensaje nuevo tras el aviso abre otra tanda
  m := public.log_incident_message('reported', v_inc, 'inbound', 'panelist', 'r3');
  UPDATE public.incident_message SET created_at = now() - interval '90 minutes' WHERE id = m;
  SELECT * INTO r FROM public.due_unread_reply_notifications() WHERE incident_id = v_inc;
  IF r.unread IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'FAIL nueva tanda: %', row_to_json(r); END IF;
END $$;

-- mark_incident_conversation_read
DO $$
DECLARE v_inc uuid := (SELECT v FROM t_ids WHERE k='inc'); v_un uuid := (SELECT v FROM t_ids WHERE k='unav'); n int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000098', true);
  PERFORM pg_temp.expect_err(format($q$SELECT public.mark_incident_conversation_read('reported', %L)$q$, v_inc), 'Cross-tenant access denied');
  PERFORM pg_temp.expect_err(format($q$SELECT public.mark_incident_conversation_read('unavailability', %L)$q$, v_un), 'Cross-tenant access denied');
  PERFORM set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
  n := public.mark_incident_conversation_read('reported', v_inc);
  IF n <> 3 THEN RAISE EXCEPTION 'FAIL leidos=% (esperaba 3)', n; END IF;
  IF EXISTS (SELECT 1 FROM public.incident_message WHERE incident_id = v_inc AND direction = 'inbound' AND read_at IS NULL) THEN
    RAISE EXCEPTION 'FAIL quedan inbound sin leer'; END IF;
  IF EXISTS (SELECT 1 FROM public.incident_message WHERE incident_id = v_inc AND direction = 'outbound' AND read_at IS NOT NULL) THEN
    RAISE EXCEPTION 'FAIL marco outbound como leido'; END IF;
  IF (SELECT read_at FROM public.incident_message WHERE body = 'leido') > now() - interval '3 hours' THEN
    RAISE EXCEPTION 'FAIL piso read_at ya puesto'; END IF;
  IF public.mark_incident_conversation_read('reported', v_inc) <> 0 THEN RAISE EXCEPTION 'FAIL leer dos veces'; END IF;
  IF EXISTS (SELECT 1 FROM public.unread_incident_conversations() WHERE incident_id = v_inc) THEN
    RAISE EXCEPTION 'FAIL sigue en no leidos'; END IF;
  IF public.mark_incident_conversation_read('unavailability', v_un) <> 1 THEN RAISE EXCEPTION 'FAIL leer unav'; END IF;
  IF (SELECT count(*) FROM public.unread_incident_conversations()) <> 0 THEN RAISE EXCEPTION 'FAIL cuenta 1 aun con no leidos'; END IF;
  IF EXISTS (SELECT 1 FROM public.due_unread_reply_notifications(now() + interval '1 day')
              WHERE account_id = 'a0000000-0000-0000-0000-000000000001') THEN
    RAISE EXCEPTION 'FAIL leidos siguen avisandose'; END IF;
  PERFORM pg_temp.expect_err(format($q$SELECT public.mark_incident_conversation_read('bad', %L)$q$, v_inc), 'invalid incident kind');
  PERFORM pg_temp.expect_err($q$SELECT public.mark_incident_conversation_read('reported', '00000000-0000-0000-0000-000000000000')$q$, 'incident not found');
  PERFORM pg_temp.expect_err($q$SELECT public.mark_incident_conversation_read('unavailability', '00000000-0000-0000-0000-000000000000')$q$, 'incident not found');
  PERFORM set_config('request.jwt.claim.sub','', true);
  -- inc2 sigue sin leer (cuenta 2)
  IF (SELECT count(*) FROM public.incident_message WHERE incident_id = (SELECT v FROM t_ids WHERE k='inc2') AND read_at IS NULL) <> 1 THEN
    RAISE EXCEPTION 'FAIL toco la cuenta 2'; END IF;
END $$;

-- indice parcial de no leidos
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'incident_message'
                  AND indexdef ILIKE '%(incident_kind, incident_id)%' AND indexdef ILIKE '%read_at IS NULL%') THEN
    RAISE EXCEPTION 'FAIL falta indice parcial de no leidos'; END IF;
END $$;
ROLLBACK;

-- ===== Escenario 2: cerrar la incidencia cierra la conversacion de Telegram =====
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
UPDATE public.panelists SET telegram_id = 'tg-p1' WHERE id = 'e1000000-0000-0000-0000-000000000001';
UPDATE public.panelists SET telegram_id = 'tg-p2' WHERE id = 'e2000000-0000-0000-0000-000000000002';
CREATE TEMP TABLE t_ids (k text PRIMARY KEY, v uuid);
WITH x AS (
  INSERT INTO public.panelist_incident (account_id, panelist_id, category, status)
  VALUES ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','other','open')
  RETURNING id)
INSERT INTO t_ids SELECT 'inc', id FROM x;
WITH x AS (
  INSERT INTO public.panelist_incident (account_id, panelist_id, category, status)
  VALUES ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','other','open')
  RETURNING id)
INSERT INTO t_ids SELECT 'incb', id FROM x;
WITH x AS (
  INSERT INTO public.panelist_incident (account_id, panelist_id, category, status)
  VALUES ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','other','open')
  RETURNING id)
INSERT INTO t_ids SELECT 'incc', id FROM x;
WITH x AS (
  INSERT INTO public.panelist_unavailability (panelist_id, account_id, start_date, end_date, reason, status)
  VALUES ('e1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',
          current_date + 1, current_date + 5, 'vacation', 'active')
  RETURNING id)
INSERT INTO t_ids SELECT 'unav', id FROM x;

INSERT INTO public.panelist_context (telegram_id, context_type, context_data)
SELECT 'tg-p1', 'pending_incident_reply', jsonb_build_object('incident_kind','reported','incident_id',v) FROM t_ids WHERE k IN ('inc','incb','incc')
UNION ALL
SELECT 'tg-p1', 'pending_incident_reply', jsonb_build_object('incident_kind','unavailability','incident_id',v) FROM t_ids WHERE k = 'unav'
UNION ALL
-- mismo id pero otro tipo de contexto, otro kind y otro panelista: no se tocan
SELECT 'tg-p1', 'other_context', jsonb_build_object('incident_kind','reported','incident_id',v) FROM t_ids WHERE k = 'inc'
UNION ALL
SELECT 'tg-p1', 'pending_incident_reply', jsonb_build_object('incident_kind','unavailability','incident_id',v) FROM t_ids WHERE k = 'inc'
UNION ALL
SELECT 'tg-p2', 'pending_incident_reply', jsonb_build_object('incident_kind','reported','incident_id',v) FROM t_ids WHERE k = 'inc';

DO $$
DECLARE v_inc uuid := (SELECT v FROM t_ids WHERE k='inc'); v_b uuid := (SELECT v FROM t_ids WHERE k='incb');
        v_c uuid := (SELECT v FROM t_ids WHERE k='incc'); v_un uuid := (SELECT v FROM t_ids WHERE k='unav'); n int;
BEGIN
  -- pasar a in_progress no cierra
  UPDATE public.panelist_incident SET status = 'in_progress' WHERE id = v_inc;
  IF (SELECT count(*) FROM public.panelist_context) <> 7 THEN RAISE EXCEPTION 'FAIL in_progress borro contexto'; END IF;
  -- resolved: borra solo el contexto reported/inc de tg-p1
  UPDATE public.panelist_incident SET status = 'resolved' WHERE id = v_inc;
  IF EXISTS (SELECT 1 FROM public.panelist_context WHERE telegram_id = 'tg-p1' AND context_type = 'pending_incident_reply'
              AND context_data->>'incident_kind' = 'reported' AND context_data->>'incident_id' = v_inc::text) THEN
    RAISE EXCEPTION 'FAIL resolved no borro su contexto'; END IF;
  SELECT count(*) INTO n FROM public.panelist_context;
  IF n <> 6 THEN RAISE EXCEPTION 'FAIL resolved borro % filas (esperaba 1)', 7 - n; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.panelist_context WHERE context_type = 'other_context')
     OR NOT EXISTS (SELECT 1 FROM public.panelist_context WHERE telegram_id = 'tg-p2')
     OR NOT EXISTS (SELECT 1 FROM public.panelist_context WHERE context_data->>'incident_kind' = 'unavailability'
                     AND context_data->>'incident_id' = v_inc::text) THEN
    RAISE EXCEPTION 'FAIL resolved borro contextos ajenos'; END IF;
  -- dismissed y auto_resolved tambien cierran
  UPDATE public.panelist_incident SET status = 'dismissed' WHERE id = v_b;
  UPDATE public.panelist_incident SET status = 'auto_resolved' WHERE id = v_c;
  IF EXISTS (SELECT 1 FROM public.panelist_context WHERE context_data->>'incident_id' IN (v_b::text, v_c::text)) THEN
    RAISE EXCEPTION 'FAIL dismissed/auto_resolved no borran'; END IF;
  IF (SELECT count(*) FROM public.panelist_context) <> 4 THEN RAISE EXCEPTION 'FAIL dismissed/auto_resolved borraron de mas'; END IF;
  -- baja: pending_manager no cierra; resolved si, y solo la suya
  UPDATE public.panelist_unavailability SET incident_status = 'pending_manager' WHERE id = v_un;
  IF NOT EXISTS (SELECT 1 FROM public.panelist_context WHERE context_data->>'incident_id' = v_un::text) THEN
    RAISE EXCEPTION 'FAIL pending_manager borro'; END IF;
  UPDATE public.panelist_unavailability SET incident_status = 'resolved' WHERE id = v_un;
  IF EXISTS (SELECT 1 FROM public.panelist_context WHERE context_data->>'incident_id' = v_un::text) THEN
    RAISE EXCEPTION 'FAIL baja resuelta no borro su contexto'; END IF;
  IF (SELECT count(*) FROM public.panelist_context) <> 3 THEN RAISE EXCEPTION 'FAIL baja borro de mas'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.panelist_context WHERE context_data->>'incident_kind' = 'unavailability'
                  AND context_data->>'incident_id' = v_inc::text) THEN
    RAISE EXCEPTION 'FAIL baja borro contexto de otro kind'; END IF;
  -- panelista sin telegram: la actualizacion no falla
  UPDATE public.panelists SET telegram_id = NULL WHERE id = 'e1000000-0000-0000-0000-000000000001';
  UPDATE public.panelist_incident SET status = 'open' WHERE id = v_inc;
  UPDATE public.panelist_incident SET status = 'resolved' WHERE id = v_inc;
  IF (SELECT status FROM public.panelist_incident WHERE id = v_inc) <> 'resolved' THEN RAISE EXCEPTION 'FAIL update sin telegram'; END IF;
END $$;
ROLLBACK;

-- ===== Escenario 3: privilegios =====
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.mark_incident_conversation_read(text,uuid)'] LOOP
    IF has_function_privilege('anon', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL anon con EXECUTE en %', f; END IF;
    IF NOT has_function_privilege('authenticated', f, 'EXECUTE') OR NOT has_function_privilege('service_role', f, 'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL falta GRANT en %', f; END IF;
  END LOOP;
  f := 'public.unread_incident_conversations()';
  IF has_function_privilege('anon', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL anon con EXECUTE en %', f; END IF;
  IF NOT has_function_privilege('authenticated', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL falta GRANT en %', f; END IF;
  FOREACH f IN ARRAY ARRAY['public.due_unread_reply_notifications(timestamp with time zone)',
                           'public.mark_unread_reply_notified(text,uuid)'] LOOP
    IF has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL anon/authenticated con EXECUTE en %', f; END IF;
    IF NOT has_function_privilege('service_role', f, 'EXECUTE') THEN RAISE EXCEPTION 'FAIL service_role sin EXECUTE en %', f; END IF;
  END LOOP;
  FOREACH f IN ARRAY ARRAY['public.tg_close_reported_incident_conversation()',
                           'public.tg_close_unavailability_conversation()'] LOOP
    IF has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE') THEN
      RAISE EXCEPTION 'FAIL anon/authenticated con EXECUTE en %', f; END IF;
  END LOOP;
  IF has_table_privilege('authenticated', 'public.incident_message', 'UPDATE') THEN
    RAISE EXCEPTION 'FAIL authenticated con UPDATE directo'; END IF;
END $$;
