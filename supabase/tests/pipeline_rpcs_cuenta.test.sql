-- Pipeline Monitor y conversaciones sin leer usan la cuenta elegida (20261118160000_pipeline_rpcs_cuenta.sql).
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT FALSE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid text, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  PERFORM set_config('request.jwt.claim.role', coalesce(p_role, ''), true);
END $$;

BEGIN;
\ir fixtures/incident_city.sql
INSERT INTO auth.users (id, email) VALUES ('97000000-0000-0000-0000-000000000097','super@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('97000000-0000-0000-0000-000000000097','super@t.l','Super','superadmin',NULL);

DO $$
DECLARE r jsonb; n int;
  A1 constant uuid := 'a0000000-0000-0000-0000-000000000001';
  A2 constant uuid := 'a0000000-0000-0000-0000-000000000002';
  U1 constant text := '99000000-0000-0000-0000-000000000099';
  SA constant text := '97000000-0000-0000-0000-000000000097';
BEGIN
  -- Sin sesión: rechazado (nunca la cuenta fija).
  PERFORM pg_temp.as_user(NULL, NULL);
  r := public.rpc_get_pipeline_status();
  PERFORM pg_temp.fail_if((r->>'success')::boolean OR r->>'error' <> 'Not authenticated', 'anon: ' || r::text);
  r := public.rpc_execute_pipeline_phase('all');
  PERFORM pg_temp.fail_if((r->>'success')::boolean, 'anon execute: ' || r::text);

  -- Usuario normal sin parámetro: su cuenta.
  PERFORM pg_temp.as_user(U1, 'authenticated');
  r := public.rpc_get_pipeline_status();
  PERFORM pg_temp.fail_if(NOT (r->>'success')::boolean OR (r->>'account_id')::uuid <> A1, 'usuario propio: ' || r::text);
  r := public.rpc_get_pipeline_status(A1);
  PERFORM pg_temp.fail_if((r->>'account_id')::uuid <> A1, 'usuario pide su cuenta: ' || r::text);
  -- Usuario normal pidiendo otra cuenta: prohibido.
  r := public.rpc_get_pipeline_status(A2);
  PERFORM pg_temp.fail_if((r->>'success')::boolean OR r->>'error' <> 'Forbidden account', 'usuario otra cuenta: ' || r::text);
  r := public.rpc_execute_pipeline_phase('aggregation', A2);
  PERFORM pg_temp.fail_if((r->>'success')::boolean OR r->>'error' <> 'Forbidden account', 'usuario ejecuta otra: ' || r::text);
  r := public.rpc_get_recent_incidents(5, A2);
  PERFORM pg_temp.fail_if((r->>'success')::boolean, 'recent otra cuenta: ' || r::text);

  -- Superadmin: sin cuenta elegida -> error; con cuenta -> esa cuenta.
  PERFORM pg_temp.as_user(SA, 'authenticated');
  r := public.rpc_get_pipeline_status();
  PERFORM pg_temp.fail_if((r->>'success')::boolean OR r->>'error' <> 'No account selected', 'super sin cuenta: ' || r::text);
  r := public.rpc_get_pipeline_status(A2);
  PERFORM pg_temp.fail_if(NOT (r->>'success')::boolean OR (r->>'account_id')::uuid <> A2, 'super A2: ' || r::text);
  r := public.rpc_get_recent_incidents(5, A2);
  PERFORM pg_temp.fail_if(NOT (r->>'success')::boolean OR (r->>'account_id')::uuid <> A2, 'super recent A2: ' || r::text);
  r := public.rpc_execute_pipeline_phase('bogus', A2);
  PERFORM pg_temp.fail_if(r->>'error' <> 'Invalid phase', 'fase invalida tras autorizar: ' || r::text);

  -- service_role con cuenta explícita.
  PERFORM pg_temp.as_user(NULL, 'service_role');
  r := public.rpc_get_pipeline_status(A1);
  PERFORM pg_temp.fail_if(NOT (r->>'success')::boolean OR (r->>'account_id')::uuid <> A1, 'service_role: ' || r::text);
END $$;

-- Conversaciones sin leer: el superadmin filtra por la cuenta elegida.
INSERT INTO public.incident_message (account_id, panelist_id, incident_kind, incident_id, direction, author, body, meta, status)
SELECT a, 'e1000000-0000-0000-0000-000000000001', 'reported', gen_random_uuid(), 'inbound', 'panelist', 'hola', '{}'::jsonb, 'received'
FROM (VALUES ('a0000000-0000-0000-0000-000000000001'::uuid), ('a0000000-0000-0000-0000-000000000002'::uuid)) v(a);

DO $$
DECLARE n int;
  A1 constant uuid := 'a0000000-0000-0000-0000-000000000001';
  A2 constant uuid := 'a0000000-0000-0000-0000-000000000002';
BEGIN
  PERFORM pg_temp.as_user('97000000-0000-0000-0000-000000000097', 'authenticated');
  SELECT count(*) INTO n FROM public.unread_incident_conversations();
  PERFORM pg_temp.fail_if(n <> 2, 'super todas: ' || n);
  SELECT count(*) INTO n FROM public.unread_incident_conversations(A2);
  PERFORM pg_temp.fail_if(n <> 1, 'super A2: ' || n);
  -- Usuario normal: solo la suya, aunque pida otra.
  PERFORM pg_temp.as_user('99000000-0000-0000-0000-000000000099', 'authenticated');
  SELECT count(*) INTO n FROM public.unread_incident_conversations();
  PERFORM pg_temp.fail_if(n <> 1, 'usuario propia: ' || n);
  SELECT count(*) INTO n FROM public.unread_incident_conversations(A2);
  PERFORM pg_temp.fail_if(n <> 0, 'usuario pide A2: ' || n);
END $$;
ROLLBACK;

-- Permisos: sin anon/PUBLIC; el helper interno no es ejecutable desde la API.
DO $$
BEGIN
  PERFORM pg_temp.fail_if(has_function_privilege('anon', 'public.rpc_get_pipeline_status(uuid)', 'EXECUTE'), 'anon status');
  PERFORM pg_temp.fail_if(has_function_privilege('anon', 'public.rpc_execute_pipeline_phase(text, uuid)', 'EXECUTE'), 'anon execute');
  PERFORM pg_temp.fail_if(has_function_privilege('anon', 'public.rpc_get_recent_incidents(integer, uuid)', 'EXECUTE'), 'anon recent');
  PERFORM pg_temp.fail_if(has_function_privilege('anon', 'public.unread_incident_conversations(uuid)', 'EXECUTE'), 'anon unread');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('authenticated', 'public.rpc_execute_pipeline_phase(text, uuid)', 'EXECUTE'), 'auth execute');
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.pipeline_resolve_account(uuid)', 'EXECUTE'), 'helper interno');
  PERFORM pg_temp.fail_if(to_regprocedure('public.rpc_get_pipeline_status()') IS NOT NULL, 'firma vieja status');
  PERFORM pg_temp.fail_if(to_regprocedure('public.rpc_execute_pipeline_phase(text)') IS NOT NULL, 'firma vieja execute');
END $$;
\echo 'pipeline_rpcs_cuenta: OK'
