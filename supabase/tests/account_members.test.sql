-- Miembros de la cuenta para la pestaña de roles (20261119100150_account_members.sql).
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
-- A1: AM con profiles.role='user' (como los usuarios nuevos), usuario sin rol, PM+MS (99 del fixture).
-- Multi: cuenta activa A2, rol en A1 (titular de rol de otra cuenta). Superadmin. 98: usuario de A2.
INSERT INTO auth.users (id, email) VALUES
  ('97000000-0000-0000-0000-000000000097','super@t.l'),
  ('96000000-0000-0000-0000-000000000096','am@t.l'),
  ('95000000-0000-0000-0000-000000000095','norole@t.l'),
  ('94000000-0000-0000-0000-000000000094','multi@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('97000000-0000-0000-0000-000000000097','super@t.l','Super','superadmin',NULL),
  ('96000000-0000-0000-0000-000000000096','am@t.l','AM','user','a0000000-0000-0000-0000-000000000001'),
  ('95000000-0000-0000-0000-000000000095','norole@t.l','NoRole','user','a0000000-0000-0000-0000-000000000001'),
  ('94000000-0000-0000-0000-000000000094','multi@t.l','Multi','user','a0000000-0000-0000-0000-000000000002');
INSERT INTO public.account_user_role (account_id, user_id, role, provisional) VALUES
  ('a0000000-0000-0000-0000-000000000001','99000000-0000-0000-0000-000000000099','panelist_manager', false),
  ('a0000000-0000-0000-0000-000000000001','99000000-0000-0000-0000-000000000099','materials_supplier', false),
  ('a0000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000096','account_manager', true),
  ('a0000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000094','upu_account_manager', false),
  ('a0000000-0000-0000-0000-000000000002','94000000-0000-0000-0000-000000000094','do_coordinator', false);
-- Registro: cambio hecho por el superadmin en A1 sobre el usuario 99; y uno en A2 hecho por 98.
INSERT INTO public.account_access_log (account_id, changed_by, kind, detail) VALUES
  ('a0000000-0000-0000-0000-000000000001','97000000-0000-0000-0000-000000000097','user_role_set',
   '{"user_id":"99000000-0000-0000-0000-000000000099","role":"panelist_manager","enabled":true}'),
  ('a0000000-0000-0000-0000-000000000002','98000000-0000-0000-0000-000000000098','access_reset','{}');

SET LOCAL ROLE authenticated;
DO $$
DECLARE n int; r record;
  A1 constant uuid := 'a0000000-0000-0000-0000-000000000001';
  A2 constant uuid := 'a0000000-0000-0000-0000-000000000002';
BEGIN
  -- AM de A1 (profiles.role = 'user'): ve los usuarios de su cuenta y al titular de rol de otra cuenta.
  PERFORM pg_temp.as_user('96000000-0000-0000-0000-000000000096', 'authenticated');
  SELECT count(*) INTO n FROM public.account_members(A1);
  PERFORM pg_temp.fail_if(n <> 4, 'AM ve miembros de A1: ' || n);   -- 99, 96, 95, 94 (sin superadmin)
  SELECT * INTO r FROM public.account_members(A1) WHERE user_id = '94000000-0000-0000-0000-000000000094';
  PERFORM pg_temp.fail_if(r.email <> 'multi@t.l' OR r.active_here OR r.roles <> ARRAY['upu_account_manager'],
                          'titular de otra cuenta: ' || coalesce(r::text, 'null'));
  SELECT * INTO r FROM public.account_members(A1) WHERE user_id = '95000000-0000-0000-0000-000000000095';
  PERFORM pg_temp.fail_if(NOT r.active_here OR cardinality(r.roles) <> 0 OR r.provisional, 'sin rol: ' || r::text);
  SELECT * INTO r FROM public.account_members(A1) WHERE user_id = '96000000-0000-0000-0000-000000000096';
  PERFORM pg_temp.fail_if(NOT r.provisional, 'provisional');
  SELECT * INTO r FROM public.account_members(A1) WHERE user_id = '99000000-0000-0000-0000-000000000099';
  PERFORM pg_temp.fail_if(r.roles <> ARRAY['materials_supplier','panelist_manager'], 'roles 99: ' || r::text);
  SELECT count(*) INTO n FROM public.account_members(A1) WHERE email = 'super@t.l';
  PERFORM pg_temp.fail_if(n <> 0, 'superadmin excluido');
  -- Registro: correo del autor (superadmin) y del usuario citado; nada del registro de A2.
  SELECT count(*) INTO n FROM public.account_log_people(A1);
  PERFORM pg_temp.fail_if(n <> 2, 'log people A1: ' || n);
  -- Y nada de otra cuenta en la que no gestiona.
  SELECT count(*) INTO n FROM public.account_members(A2);
  PERFORM pg_temp.fail_if(n <> 0, 'AM de A1 en A2: ' || n);
  SELECT count(*) INTO n FROM public.account_log_people(A2);
  PERFORM pg_temp.fail_if(n <> 0, 'AM de A1 log A2: ' || n);

  -- Usuario de otra cuenta (98, A2): conjunto vacío en A1.
  PERFORM pg_temp.as_user('98000000-0000-0000-0000-000000000098', 'authenticated');
  SELECT count(*) INTO n FROM public.account_members(A1);
  PERFORM pg_temp.fail_if(n <> 0, 'otra cuenta: ' || n);
  SELECT count(*) INTO n FROM public.account_log_people(A1);
  PERFORM pg_temp.fail_if(n <> 0, 'otra cuenta log: ' || n);

  -- Miembro de A1 sin rol de gestión (decisión: solo gestores): vacío.
  PERFORM pg_temp.as_user('95000000-0000-0000-0000-000000000095', 'authenticated');
  SELECT count(*) INTO n FROM public.account_members(A1);
  PERFORM pg_temp.fail_if(n <> 0, 'miembro sin gestión: ' || n);

  -- UPU AM con cuenta activa A2 gestiona A1: ve A1; en A2 (solo DO coordinator) nada.
  PERFORM pg_temp.as_user('94000000-0000-0000-0000-000000000094', 'authenticated');
  SELECT count(*) INTO n FROM public.account_members(A1);
  PERFORM pg_temp.fail_if(n <> 4, 'UPU AM multi en A1: ' || n);
  SELECT count(*) INTO n FROM public.account_members(A2);
  PERFORM pg_temp.fail_if(n <> 0, 'multi en A2: ' || n);

  -- Superadmin: ve todo, sin incluirse.
  PERFORM pg_temp.as_user('97000000-0000-0000-0000-000000000097', 'authenticated');
  SELECT count(*) INTO n FROM public.account_members(A2);
  PERFORM pg_temp.fail_if(n <> 2, 'superadmin A2: ' || n);   -- 98 y 94

  -- Sin sesión: vacío.
  PERFORM pg_temp.as_user(NULL, NULL);
  SELECT count(*) INTO n FROM public.account_members(A1);
  PERFORM pg_temp.fail_if(n <> 0, 'sin sesión: ' || n);
END $$;
RESET ROLE;
ROLLBACK;

-- Permisos: anon sin EXECUTE; authenticated y service_role sí.
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.account_members(uuid)', 'public.account_log_people(uuid)'] LOOP
    PERFORM pg_temp.fail_if(has_function_privilege('anon', f, 'EXECUTE'), 'anon ' || f);
    PERFORM pg_temp.fail_if(NOT has_function_privilege('authenticated', f, 'EXECUTE'), 'authenticated ' || f);
    PERFORM pg_temp.fail_if(NOT has_function_privilege('service_role', f, 'EXECUTE'), 'service_role ' || f);
  END LOOP;
END $$;
