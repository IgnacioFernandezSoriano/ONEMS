-- Agente de operaciones, mensaje de la mañana: ops_messages_sent (recuento de mensajes automáticos).
-- Cuenta 1 (Acc) cuenta; cuenta 2 (renombrada DEMO2) se excluye por p_exclude.
\set ON_ERROR_STOP on
SET client_min_messages = error;
CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
INSERT INTO ops_test.secret(token_sha256) VALUES (encode(extensions.digest('t0ken-de-prueba','sha256'),'hex'));
UPDATE public.accounts SET name = 'DEMO2' WHERE id = 'a0000000-0000-0000-0000-000000000002';
INSERT INTO public.regions (id, account_id, name, code) VALUES ('e0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','Reg2','R2');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES ('c3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','City9','C9');
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES ('b9000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000002','c3000000-0000-0000-0000-000000000003','N9');
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language) VALUES
  ('e9000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000002','P9','Pan9','p9@t.l','9','b9000000-0000-0000-0000-000000000009','active','en');

-- avisos de la cuenta 1: 3 send_reminder enviados, 1 fallido, 2 plan_change enviados, 1 pendiente (no cuenta),
-- 1 enviado hace 3 dias (fuera de las 24 h)
INSERT INTO public.panelist_notification (account_id, panelist_id, kind, status, created_at, sent_at)
SELECT 'a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001', k, s, now() - c, CASE WHEN s = 'sent' THEN now() - c END
  FROM (VALUES ('send_reminder','sent',interval '1 hour'), ('send_reminder','sent',interval '2 hours'),
               ('send_reminder','sent',interval '3 hours'), ('send_reminder','failed',interval '1 hour'),
               ('plan_change_this_week','sent',interval '5 hours'), ('plan_change_this_week','sent',interval '6 hours'),
               ('broadcast','pending_send',interval '1 hour'), ('send_reminder','sent',interval '3 days')) v(k, s, c);
-- cuenta DEMO2 (excluida)
INSERT INTO public.panelist_notification (account_id, panelist_id, kind, status, created_at, sent_at) VALUES
  ('a0000000-0000-0000-0000-000000000002','e9000000-0000-0000-0000-000000000009','send_reminder','sent', now() - interval '1 minute', now() - interval '1 minute');

-- atascados (cuenta 1): 2 avisos pending_send de hace 2 h, 1 de hace 10 min (aun no), 1 con send_after futuro (no),
-- 1 de hace 3 dias (fuera de las 24 h); 1 mensaje de incidencia pending_send de hace 3 h; DEMO2: 1 (excluido)
INSERT INTO public.panelist_notification (account_id, panelist_id, kind, status, created_at, send_after)
SELECT 'a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','receipt_reminder','pending_send', now() - c, sa
  FROM (VALUES (interval '2 hours', NULL::timestamptz), (interval '2 hours', NULL), (interval '10 minutes', NULL),
               (interval '2 hours', now() + interval '1 hour'), (interval '3 days', NULL)) v(c, sa);
INSERT INTO public.panelist_notification (account_id, panelist_id, kind, status, created_at) VALUES
  ('a0000000-0000-0000-0000-000000000002','e9000000-0000-0000-0000-000000000009','receipt_reminder','pending_send', now() - interval '2 hours');
INSERT INTO public.incident_message (account_id, panelist_id, incident_kind, incident_id, direction, author, body, status, created_at) VALUES
  ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','reported',gen_random_uuid(),'outbound','bot','g','pending_send', now() - interval '3 hours');

-- mensajes de incidencias: cuenta 1 -> 2 bot enviados, 1 bot fallido, 1 manager enviado, 1 inbound (no cuenta)
INSERT INTO public.incident_message (account_id, panelist_id, incident_kind, incident_id, direction, author, body, status, sent_at, created_at) VALUES
  ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','reported',gen_random_uuid(),'outbound','bot','a','sent', now() - interval '1 minute', now() - interval '1 minute'),
  ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','reported',gen_random_uuid(),'outbound','bot','b','sent', now() - interval '1 minute', now() - interval '1 minute'),
  ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','reported',gen_random_uuid(),'outbound','bot','c','failed', NULL, now() - interval '1 minute'),
  ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','reported',gen_random_uuid(),'outbound','manager','d','sent', now() - interval '1 minute', now() - interval '1 minute'),
  ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','reported',gen_random_uuid(),'inbound','panelist','e','received', NULL, now() - interval '1 minute'),
  ('a0000000-0000-0000-0000-000000000002','e9000000-0000-0000-0000-000000000009','reported',gen_random_uuid(),'outbound','bot','f','sent', now() - interval '1 minute', now() - interval '1 minute');

DO $$
DECLARE r jsonb; v_err text; t text := 't0ken-de-prueba';
BEGIN
  r := public.ops_messages_sent(t, now() - interval '24 hours', ARRAY['DEMO2','Agent Test']);
  PERFORM pg_temp.fail_if(r->'notifications' <> '[
      {"kind":"plan_change_this_week","status":"sent","n":2},
      {"kind":"send_reminder","status":"failed","n":1},
      {"kind":"send_reminder","status":"sent","n":3}]'::jsonb, 'notifications: ' || (r->'notifications')::text);
  PERFORM pg_temp.fail_if(r->'incident_messages' <> '[
      {"author":"bot","status":"failed","n":1},
      {"author":"bot","status":"sent","n":2},
      {"author":"manager","status":"sent","n":1}]'::jsonb, 'incident_messages: ' || (r->'incident_messages')::text);
  PERFORM pg_temp.fail_if((r->>'stuck')::int <> 3, 'stuck: ' || r::text);
  r := public.ops_messages_sent(t, now() - interval '24 hours', NULL);
  PERFORM pg_temp.fail_if((r->>'stuck')::int <> 4, 'stuck sin exclusion: ' || r::text);

  -- sin exclusion: DEMO2 tambien cuenta
  r := public.ops_messages_sent(t, now() - interval '24 hours', NULL);
  PERFORM pg_temp.fail_if((SELECT sum((x->>'n')::int) FROM jsonb_array_elements(r->'notifications') x) <> 7, 'sin exclusion notif: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT sum((x->>'n')::int) FROM jsonb_array_elements(r->'incident_messages') x) <> 5, 'sin exclusion msgs: ' || r::text);

  -- 4 dias: entra el de hace 3 dias
  r := public.ops_messages_sent(t, now() - interval '4 days', ARRAY['DEMO2']);
  PERFORM pg_temp.fail_if(NOT r->'notifications' @> '[{"kind":"send_reminder","status":"sent","n":4}]'::jsonb, '4 dias: ' || r::text);

  -- nada en el periodo: listas vacias
  r := public.ops_messages_sent(t, now() - interval '10 seconds', ARRAY['DEMO2']);
  PERFORM pg_temp.fail_if(r <> '{"notifications":[],"incident_messages":[],"stuck":0}'::jsonb, 'vacio: ' || r::text);

  -- periodo no valido (mas de 7 dias, futuro, NULL)
  BEGIN
    PERFORM public.ops_messages_sent(t, now() - interval '8 days', '{}');
    RAISE EXCEPTION 'FAIL: periodo de 8 dias aceptado';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_report: periodo no valido%', 'mensaje periodo: ' || v_err);
  END;
  BEGIN
    PERFORM public.ops_messages_sent(t, now() + interval '1 hour', '{}');
    RAISE EXCEPTION 'FAIL: periodo futuro aceptado';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_report: periodo no valido%', 'mensaje futuro: ' || v_err);
  END;
  BEGIN
    PERFORM public.ops_messages_sent(t, NULL, '{}');
    RAISE EXCEPTION 'FAIL: periodo NULL aceptado';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_report: periodo no valido%', 'mensaje NULL: ' || v_err);
  END;

  -- token erroneo
  BEGIN
    PERFORM public.ops_messages_sent('otro', now() - interval '1 hour', '{}');
    RAISE EXCEPTION 'FAIL: token malo aceptado';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_test: token no valido%', 'mensaje token: ' || v_err);
  END;

  -- permisos: anon ejecuta; authenticated no
  PERFORM pg_temp.fail_if(NOT has_function_privilege('anon', 'public.ops_messages_sent(text,timestamptz,text[])', 'EXECUTE'), 'anon execute');
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.ops_messages_sent(text,timestamptz,text[])', 'EXECUTE'), 'authenticated execute');
END $$;
ROLLBACK;
