-- Conversacion en casos de recepcion (incident_kind 'receipt') y mensaje a otro panelista del caso.
-- Fixture comun: P1..P4 en cuenta 1 (P4 telegram ' 4004 ', P1 '1001'), 99 = admin cuenta 1, 98 = admin cuenta 2.
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;
CREATE FUNCTION pg_temp.setup() RETURNS void LANGUAGE sql AS $$
  UPDATE public.panelists SET telegram_id = ' 4004 ' WHERE id = 'e4000000-0000-0000-0000-000000000004';
  UPDATE public.panelists SET telegram_id = '1001' WHERE id = 'e1000000-0000-0000-0000-000000000001';
  UPDATE public.profiles SET role = 'admin' WHERE id IN ('99000000-0000-0000-0000-000000000099',
                                                         '98000000-0000-0000-0000-000000000098');
  INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, status, language)
  VALUES ('e5000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000002', 'X1', 'PanX', 'x@t.l', '9', 'active', 'en');
$$;
CREATE FUNCTION pg_temp.act(p text) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', p, true) $$;
CREATE FUNCTION pg_temp.mk_case(p_panelist uuid, p_tag text) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.receipt_case (account_id, panelist_id, telegram_id, tag_raw, tag_norm, reason, status,
                                   attempts, first_attempt_at, last_attempt_at)
  VALUES ('a0000000-0000-0000-0000-000000000001', p_panelist, '4004', p_tag, p_tag, 'not_found', 'pending', 1, now(), now())
  RETURNING id;
$$;
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
CREATE FUNCTION pg_temp.expect_msg(p_sql text, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM NOT LIKE '%' || p_msg || '%' THEN
      RAISE EXCEPTION 'FAIL mensaje % (esperaba %) en %', SQLERRM, p_msg, p_sql; END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL no fallo (esperaba %): %', p_msg, p_sql;
END $$;

-- ===== Permisos y firma unica
DO $$
BEGIN
  IF to_regprocedure('public.log_incident_message(text,uuid,text,text,text,jsonb,text,uuid)') IS NULL THEN
    RAISE EXCEPTION 'FAIL falta la firma de 8 argumentos'; END IF;
  IF has_function_privilege('anon', 'public.log_incident_message(text,uuid,text,text,text,jsonb,text,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.log_incident_message(text,uuid,text,text,text,jsonb,text,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.log_incident_message(text,uuid,text,text,text,jsonb,text,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL grants log_incident_message'; END IF;
  IF to_regprocedure('public.log_incident_message(text,uuid,text,text,text,jsonb,text)') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL sigue la firma de 7 argumentos'; END IF;
  IF has_function_privilege('anon', 'public.send_case_message(text,uuid,uuid,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.send_case_message(text,uuid,uuid,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL grants send_case_message'; END IF;
  IF has_function_privilege('anon', 'public.incident_owner(text,uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.incident_owner(text,uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.incident_owner(text,uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL grants incident_owner'; END IF;
END $$;

-- ===== log_incident_message sobre un caso de recepcion
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v_case uuid; m uuid;
BEGIN
  v_case := pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', '00012345');
  -- 7 argumentos posicionales (n8n hoy) siguen valiendo; panelista = el del caso
  m := public.log_incident_message('receipt', v_case, 'inbound', 'panelist', 'hola', '{}'::jsonb, NULL);
  PERFORM pg_temp.fail_if((SELECT panelist_id FROM public.incident_message WHERE id = m) <> 'e4000000-0000-0000-0000-000000000004',
                          'log panelista del caso');
  PERFORM pg_temp.fail_if((SELECT status FROM public.incident_message WHERE id = m) <> 'received', 'log status');
  m := public.log_incident_message('receipt', v_case, 'inbound', 'panelist', 'hola');
  -- otro panelista de la misma cuenta
  m := public.log_incident_message('receipt', v_case, 'inbound', 'panelist', 'yo soy otro', '{}'::jsonb, NULL,
                                   'e1000000-0000-0000-0000-000000000001');
  PERFORM pg_temp.fail_if((SELECT panelist_id FROM public.incident_message WHERE id = m) <> 'e1000000-0000-0000-0000-000000000001',
                          'log p_panelist_id');
  -- panelista de la cuenta 2
  PERFORM pg_temp.expect_msg(format('SELECT public.log_incident_message(%L,%L,%L,%L,%L,%L::jsonb,NULL,%L)',
    'receipt', v_case, 'inbound', 'panelist', 'x', '{}', 'e5000000-0000-0000-0000-000000000005'), 'Cross-tenant');
  -- caso inexistente
  PERFORM pg_temp.expect_msg(format('SELECT public.log_incident_message(%L,%L,%L,%L,%L)',
    'receipt', gen_random_uuid(), 'inbound', 'panelist', 'x'), 'incident not found');
  -- caso sin panelista y sin p_panelist_id
  v_case := pg_temp.mk_case(NULL, '00099999');
  PERFORM pg_temp.expect_msg(format('SELECT public.log_incident_message(%L,%L,%L,%L,%L)',
    'receipt', v_case, 'inbound', 'panelist', 'x'), 'incident not found');
  -- tipo invalido
  PERFORM pg_temp.expect_msg(format('SELECT public.log_incident_message(%L,%L,%L,%L,%L)',
    'bogus', gen_random_uuid(), 'inbound', 'panelist', 'x'), 'invalid incident kind');
END $$;
ROLLBACK;

-- ===== send_case_message
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v_case uuid; m uuid; r record;
BEGIN
  v_case := pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', '00012345');
  PERFORM pg_temp.act('99000000-0000-0000-0000-000000000099');
  m := public.send_case_message('receipt', v_case, 'e1000000-0000-0000-0000-000000000001', ' x ', 'k1');
  SELECT * INTO r FROM public.incident_message WHERE id = m;
  PERFORM pg_temp.fail_if(r.direction <> 'outbound' OR r.author <> 'manager' OR r.status <> 'pending_send'
                          OR r.panelist_id <> 'e1000000-0000-0000-0000-000000000001' OR r.body <> 'x'
                          OR r.incident_kind <> 'receipt' OR r.incident_id <> v_case, 'scm fila');
  PERFORM pg_temp.fail_if(r.meta->>'case_draft_key' <> 'k1'
                          OR r.meta->>'manager_user_id' <> '99000000-0000-0000-0000-000000000099', 'scm meta');
  -- misma clave -> unicidad
  PERFORM pg_temp.expect_state(format('SELECT public.send_case_message(%L,%L,%L,%L,%L)',
    'receipt', v_case, 'e1000000-0000-0000-0000-000000000001', 'y', 'k1'), '23505');
  -- sin clave: se puede repetir
  PERFORM public.send_case_message('receipt', v_case, 'e4000000-0000-0000-0000-000000000004', 'a');
  PERFORM public.send_case_message('receipt', v_case, 'e4000000-0000-0000-0000-000000000004', 'b');
  -- panelista sin telegram
  PERFORM pg_temp.expect_msg(format('SELECT public.send_case_message(%L,%L,%L,%L,%L)',
    'receipt', v_case, 'e2000000-0000-0000-0000-000000000002', 'x', 'k2'), 'panelist has no telegram');
  -- panelista de la cuenta 2
  PERFORM pg_temp.expect_msg(format('SELECT public.send_case_message(%L,%L,%L,%L,%L)',
    'receipt', v_case, 'e5000000-0000-0000-0000-000000000005', 'x', 'k3'), 'Cross-tenant');
  -- mensaje vacio
  PERFORM pg_temp.expect_msg(format('SELECT public.send_case_message(%L,%L,%L,%L,%L)',
    'receipt', v_case, 'e1000000-0000-0000-0000-000000000001', '  ', 'k4'), 'empty message');
  -- admin de la cuenta 2
  PERFORM pg_temp.act('98000000-0000-0000-0000-000000000098');
  PERFORM pg_temp.expect_msg(format('SELECT public.send_case_message(%L,%L,%L,%L,%L)',
    'receipt', v_case, 'e1000000-0000-0000-0000-000000000001', 'x', 'k5'), 'Cross-tenant');
END $$;
ROLLBACK;

-- ===== mark_incident_conversation_read
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v_case uuid; n int;
BEGIN
  v_case := pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', '00012345');
  PERFORM public.log_incident_message('receipt', v_case, 'inbound', 'panelist', 'hola');
  PERFORM public.log_incident_message('receipt', v_case, 'inbound', 'panelist', 'hola2');
  PERFORM pg_temp.act('99000000-0000-0000-0000-000000000099');
  n := public.mark_incident_conversation_read('receipt', v_case);
  PERFORM pg_temp.fail_if(n <> 2, 'read n ' || n);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.incident_message WHERE read_at IS NULL) <> 0, 'read_at');
  PERFORM pg_temp.act('98000000-0000-0000-0000-000000000098');
  PERFORM pg_temp.expect_msg(format('SELECT public.mark_incident_conversation_read(%L,%L)', 'receipt', v_case), 'Cross-tenant');
END $$;
ROLLBACK;

-- ===== RLS: los mensajes de casos de recepcion solo los ven admins de la cuenta (paridad con receipt_case)
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
INSERT INTO auth.users (id, email) VALUES ('96000000-0000-0000-0000-000000000096','u96@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id)
VALUES ('96000000-0000-0000-0000-000000000096','u96@t.l','Normal','user','a0000000-0000-0000-0000-000000000001');
SELECT pg_temp.mk_case('e4000000-0000-0000-0000-000000000004', '00012345') AS vcase \gset
SELECT public.log_incident_message('receipt', :'vcase', 'inbound', 'panelist', 'hola recepcion');
INSERT INTO public.incident_message (account_id, panelist_id, incident_kind, incident_id, direction, author, body, status)
VALUES ('a0000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000004','reported',gen_random_uuid(),'inbound','panelist','rep','received');
-- usuario normal 96
SELECT set_config('request.jwt.claim.sub','96000000-0000-0000-0000-000000000096', true);
SET LOCAL ROLE authenticated;
SELECT set_config('t.r96', (SELECT count(*) FROM public.incident_message WHERE incident_kind='receipt')::text, true);
SELECT set_config('t.p96', (SELECT count(*) FROM public.incident_message WHERE incident_kind='reported')::text, true);
RESET ROLE;
-- admin 99 (cuenta 1)
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SET LOCAL ROLE authenticated;
SELECT set_config('t.r99', (SELECT count(*) FROM public.incident_message WHERE incident_kind='receipt')::text, true);
RESET ROLE;
-- admin 98 (cuenta 2)
SELECT set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000098', true);
SET LOCAL ROLE authenticated;
SELECT set_config('t.r98', (SELECT count(*) FROM public.incident_message)::text, true);
RESET ROLE;
DO $$
BEGIN
  IF current_setting('t.r96') <> '0' THEN RAISE EXCEPTION 'FAIL usuario normal ve mensajes receipt (%)', current_setting('t.r96'); END IF;
  IF current_setting('t.p96') <> '1' THEN RAISE EXCEPTION 'FAIL usuario normal no ve reported (%)', current_setting('t.p96'); END IF;
  IF current_setting('t.r99') <> '1' THEN RAISE EXCEPTION 'FAIL admin no ve receipt (%)', current_setting('t.r99'); END IF;
  IF current_setting('t.r98') <> '0' THEN RAISE EXCEPTION 'FAIL admin otra cuenta ve mensajes (%)', current_setting('t.r98'); END IF;
  RAISE NOTICE 'PASS RLS mensajes receipt';
END $$;
ROLLBACK;
