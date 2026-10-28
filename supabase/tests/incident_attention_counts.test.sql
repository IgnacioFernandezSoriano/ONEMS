-- Contador del menu de incidencias: nuevas sin abrir + respuestas sin leer, por cuenta (superadmin: la seleccionada).
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;
CREATE FUNCTION pg_temp.as_user(p uuid) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', coalesce(p::text, ''), true); $$;
CREATE FUNCTION pg_temp.cnt(p_acc uuid DEFAULT NULL) RETURNS text LANGUAGE sql AS $$
  SELECT reported || '/' || unavailability FROM public.incident_attention_counts(p_acc); $$;

BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
INSERT INTO auth.users (id, email) VALUES ('97000000-0000-0000-0000-000000000097','super@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('97000000-0000-0000-0000-000000000097','super@t.l','Super','superadmin',NULL);
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, status, language) VALUES
  ('e9000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000002','P9','Pan9','p9@t.l','9','active','en');
-- Cuenta 1: n_open (nueva), seen (abierta y vista), prog (in_progress), res_reply (resuelta con respuesta), res (resuelta)
-- Cuenta 2: n2 (nueva). Bajas cuenta 1: pend (pending_manager), un_reply ('new' con respuesta), quiet ('new').
INSERT INTO public.panelist_incident (id, account_id, panelist_id, category, status, manager_seen_at) VALUES
  ('f1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','other','open',NULL),
  ('f1000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','other','open',now()),
  ('f1000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','other','in_progress',now()),
  ('f1000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','other','resolved',now()),
  ('f1000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','other','resolved',now()),
  ('f2000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000002','e9000000-0000-0000-0000-000000000009','other','open',NULL);
INSERT INTO public.panelist_unavailability (id, panelist_id, account_id, start_date, end_date, reason, status, incident_status) VALUES
  ('f3000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001',current_date+1,current_date+5,'vacation','active','pending_manager'),
  ('f3000000-0000-0000-0000-000000000002','e2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001',current_date+10,current_date+12,'vacation','active','new'),
  ('f3000000-0000-0000-0000-000000000003','e2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001',current_date+20,current_date+22,'vacation','active','new');
DO $$ DECLARE m uuid; BEGIN
  m := public.log_incident_message('reported', 'f1000000-0000-0000-0000-000000000004', 'inbound', 'panelist', 'gracias');
  m := public.log_incident_message('reported', 'f1000000-0000-0000-0000-000000000001', 'inbound', 'panelist', 'mas info');
  m := public.log_incident_message('reported', 'f1000000-0000-0000-0000-000000000002', 'outbound', 'manager', 'hola');
  m := public.log_incident_message('reported', 'f1000000-0000-0000-0000-000000000003', 'inbound', 'panelist', 'boton', '{"callback":"x"}');
  m := public.log_incident_message('unavailability', 'f3000000-0000-0000-0000-000000000002', 'inbound', 'panelist', 'vuelvo antes');
END $$;

DO $$ BEGIN
  -- admin cuenta 1: n_open + res_reply (n_open con respuesta cuenta una vez); bajas: pend + un_reply. El parametro se ignora.
  PERFORM pg_temp.as_user('99000000-0000-0000-0000-000000000099');
  PERFORM pg_temp.fail_if(pg_temp.cnt() <> '2/2', 'cuenta 1: ' || pg_temp.cnt());
  PERFORM pg_temp.fail_if(pg_temp.cnt('a0000000-0000-0000-0000-000000000002') <> '2/2', 'cuenta 1 pidiendo la 2');
  -- admin cuenta 2: n2
  PERFORM pg_temp.as_user('98000000-0000-0000-0000-000000000098');
  PERFORM pg_temp.fail_if(pg_temp.cnt() <> '1/0', 'cuenta 2: ' || pg_temp.cnt());
  -- superadmin: la cuenta seleccionada, o todas si no hay
  PERFORM pg_temp.as_user('97000000-0000-0000-0000-000000000097');
  PERFORM pg_temp.fail_if(pg_temp.cnt('a0000000-0000-0000-0000-000000000001') <> '2/2', 'super cuenta 1');
  PERFORM pg_temp.fail_if(pg_temp.cnt('a0000000-0000-0000-0000-000000000002') <> '1/0', 'super cuenta 2');
  PERFORM pg_temp.fail_if(pg_temp.cnt() <> '3/2', 'super todas: ' || pg_temp.cnt());
  -- sin usuario: nada
  PERFORM pg_temp.as_user(NULL);
  PERFORM pg_temp.fail_if(pg_temp.cnt('a0000000-0000-0000-0000-000000000001') <> '0/0', 'sin usuario');
END $$;

DO $$ BEGIN
  -- otra cuenta no puede marcarla vista
  PERFORM pg_temp.as_user('98000000-0000-0000-0000-000000000098');
  BEGIN
    PERFORM public.mark_panelist_incident_seen('f1000000-0000-0000-0000-000000000001');
    RAISE EXCEPTION 'FAIL cross-tenant marco vista';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'Cross-tenant%' THEN RAISE; END IF;
  END;
  -- abrir n_open: sigue contando por la respuesta sin leer; al leerla deja de contar
  PERFORM pg_temp.as_user('99000000-0000-0000-0000-000000000099');
  PERFORM pg_temp.fail_if(NOT public.mark_panelist_incident_seen('f1000000-0000-0000-0000-000000000001'), 'primera vista');
  PERFORM pg_temp.fail_if(public.mark_panelist_incident_seen('f1000000-0000-0000-0000-000000000001'), 'vista dos veces');
  PERFORM pg_temp.fail_if(pg_temp.cnt() <> '2/2', 'tras abrir: ' || pg_temp.cnt());
  PERFORM public.mark_incident_conversation_read('reported', 'f1000000-0000-0000-0000-000000000001');
  PERFORM public.mark_incident_conversation_read('reported', 'f1000000-0000-0000-0000-000000000004');
  PERFORM public.mark_incident_conversation_read('unavailability', 'f3000000-0000-0000-0000-000000000002');
  PERFORM pg_temp.fail_if(pg_temp.cnt() <> '0/1', 'tras leer: ' || pg_temp.cnt());
  -- el panelista vuelve a escribir en una resuelta: cuenta otra vez
  PERFORM public.log_incident_message('reported', 'f1000000-0000-0000-0000-000000000005', 'inbound', 'panelist', 'otra cosa');
  PERFORM pg_temp.fail_if(pg_temp.cnt() <> '1/1', 'respuesta nueva: ' || pg_temp.cnt());
END $$;
ROLLBACK;

DO $$ DECLARE f text; BEGIN
  FOREACH f IN ARRAY ARRAY['public.mark_panelist_incident_seen(uuid)', 'public.incident_attention_counts(uuid)'] LOOP
    PERFORM pg_temp.fail_if(has_function_privilege('anon', f, 'EXECUTE'), 'anon con EXECUTE en ' || f);
    PERFORM pg_temp.fail_if(NOT has_function_privilege('authenticated', f, 'EXECUTE'), 'falta GRANT en ' || f);
  END LOOP;
END $$;

SELECT 'PASS incident_attention_counts';
