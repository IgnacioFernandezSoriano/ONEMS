-- 20261119100160_profiles_users_view.sql: quien tiene 'users' view en su cuenta ve los perfiles de la cuenta.
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
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
INSERT INTO auth.users (id, email) VALUES
  ('96000000-0000-0000-0000-000000000096','am@t.l'),
  ('95000000-0000-0000-0000-000000000095','norole@t.l'),
  ('94000000-0000-0000-0000-000000000094','pm@t.l'),
  ('93000000-0000-0000-0000-000000000093','a2user@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('96000000-0000-0000-0000-000000000096','am@t.l','AM','user','a0000000-0000-0000-0000-000000000001'),
  ('95000000-0000-0000-0000-000000000095','norole@t.l','NoRole','user','a0000000-0000-0000-0000-000000000001'),
  ('94000000-0000-0000-0000-000000000094','pm@t.l','PM','user','a0000000-0000-0000-0000-000000000001'),
  ('93000000-0000-0000-0000-000000000093','a2user@t.l','A2','user','a0000000-0000-0000-0000-000000000002');
INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000096','account_manager'),
  ('a0000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000094','panelist_manager');

SET LOCAL ROLE authenticated;

-- account_manager (profiles.role = 'user') ve todos los perfiles de A1 y ninguno de A2.
SELECT pg_temp.as_user('96000000-0000-0000-0000-000000000096', 'authenticated');
DO $$ DECLARE n int; m int; BEGIN
  SELECT count(*) INTO n FROM public.profiles WHERE account_id = 'a0000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.fail_if(n < 4, 'AM ve A1: ' || n);
  SELECT count(*) INTO m FROM public.profiles WHERE account_id = 'a0000000-0000-0000-0000-000000000002';
  PERFORM pg_temp.fail_if(m <> 0, 'AM ve A2: ' || m);
END $$;

-- sin rol: solo el propio.
SELECT pg_temp.as_user('95000000-0000-0000-0000-000000000095', 'authenticated');
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.profiles;
  PERFORM pg_temp.fail_if(n <> 1, 'sin rol ve: ' || n);
END $$;

-- panelist_manager (sin derecho users): solo el propio.
SELECT pg_temp.as_user('94000000-0000-0000-0000-000000000094', 'authenticated');
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.profiles;
  PERFORM pg_temp.fail_if(n <> 1, 'PM ve: ' || n);
END $$;

-- usuario de A2: solo el propio, nunca A1.
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$ DECLARE n int; BEGIN
  SELECT count(*) INTO n FROM public.profiles;
  PERFORM pg_temp.fail_if(n <> 1, 'A2 ve: ' || n);
END $$;
ROLLBACK;
\echo 'profiles_users_view: OK'
