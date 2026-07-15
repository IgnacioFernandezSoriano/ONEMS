-- Verifica las reglas de cambio de rol sobre public.profiles tras aplicar
-- 20260715120000_fix_profiles_role_update_policies.sql.
--   superadmin -> cualquier rol, cualquier cuenta
--   admin      -> sólo admin<->user, sólo en su cuenta
--   user       -> ningún cambio de rol
-- Se ejecuta como `postgres`, cambiando a `authenticated` + request.jwt.claim.sub
-- para suplantar a cada actor y que RLS actúe de verdad.

\set ON_ERROR_STOP on

BEGIN;

-- ---------- fixture ----------
INSERT INTO public.accounts (id, name, slug) VALUES
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Account A', 'acc-a'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'Account B', 'acc-b');

INSERT INTO auth.users (id, email) VALUES
  ('11111111-0000-0000-0000-000000000001', 'super@test.local'),
  ('22222222-0000-0000-0000-000000000002', 'admin.a@test.local'),
  ('33333333-0000-0000-0000-000000000003', 'user.a@test.local'),
  ('44444444-0000-0000-0000-000000000004', 'user.a2@test.local'),
  ('55555555-0000-0000-0000-000000000005', 'user.b@test.local');

INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('11111111-0000-0000-0000-000000000001', 'super@test.local',   'Super',  'superadmin', NULL),
  ('22222222-0000-0000-0000-000000000002', 'admin.a@test.local', 'AdminA', 'admin',  'aaaaaaaa-0000-0000-0000-000000000001'),
  ('33333333-0000-0000-0000-000000000003', 'user.a@test.local',  'UserA',  'user',   'aaaaaaaa-0000-0000-0000-000000000001'),
  ('44444444-0000-0000-0000-000000000004', 'user.a2@test.local', 'UserA2', 'user',   'aaaaaaaa-0000-0000-0000-000000000001'),
  ('55555555-0000-0000-0000-000000000005', 'user.b@test.local',  'UserB',  'user',   'bbbbbbbb-0000-0000-0000-000000000002');

GRANT USAGE ON SCHEMA public TO authenticated;

CREATE OR REPLACE FUNCTION pg_temp.login(p_uid text) RETURNS void
  LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', p_uid, true);
  PERFORM set_config('request.jwt.claim.role', 'authenticated', true);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.role_of(p_uid uuid) RETURNS text
  LANGUAGE sql SECURITY DEFINER AS $$ SELECT role FROM public.profiles WHERE id = p_uid $$;

CREATE OR REPLACE FUNCTION pg_temp.acct_of(p_uid uuid) RETURNS uuid
  LANGUAGE sql SECURITY DEFINER AS $$ SELECT account_id FROM public.profiles WHERE id = p_uid $$;

-- ============================================================
-- Regla 1: superadmin puede cualquier cosa
-- ============================================================
SET ROLE authenticated;
SELECT pg_temp.login('11111111-0000-0000-0000-000000000001');

-- 1a. user -> admin, en la cuenta A (no es su cuenta: el superadmin no tiene)
UPDATE public.profiles SET role = 'admin' WHERE id = '33333333-0000-0000-0000-000000000003';
DO $$ BEGIN
  IF pg_temp.role_of('33333333-0000-0000-0000-000000000003') <> 'admin' THEN
    RAISE EXCEPTION 'FAIL 1a: superadmin no pudo promover user -> admin';
  END IF;
  RAISE NOTICE 'PASS 1a: superadmin promueve user -> admin en cualquier cuenta';
END $$;

-- 1b. admin -> superadmin (la cuenta debe quedar NULL por check_account_role)
UPDATE public.profiles SET role = 'superadmin', account_id = NULL
  WHERE id = '33333333-0000-0000-0000-000000000003';
DO $$ BEGIN
  IF pg_temp.role_of('33333333-0000-0000-0000-000000000003') <> 'superadmin'
     OR pg_temp.acct_of('33333333-0000-0000-0000-000000000003') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL 1b: superadmin no pudo promover a superadmin';
  END IF;
  RAISE NOTICE 'PASS 1b: superadmin promueve a superadmin (cuenta a NULL)';
END $$;

-- 1c. superadmin -> admin devolviéndole cuenta. ESTE ERA IMPOSIBLE antes:
--     el trigger prevent_account_id_change abortaba el NULL -> cuenta.
UPDATE public.profiles SET role = 'admin', account_id = 'bbbbbbbb-0000-0000-0000-000000000002'
  WHERE id = '33333333-0000-0000-0000-000000000003';
DO $$ BEGIN
  IF pg_temp.role_of('33333333-0000-0000-0000-000000000003') <> 'admin'
     OR pg_temp.acct_of('33333333-0000-0000-0000-000000000003') <> 'bbbbbbbb-0000-0000-0000-000000000002' THEN
    RAISE EXCEPTION 'FAIL 1c: superadmin no pudo degradar superadmin -> admin';
  END IF;
  RAISE NOTICE 'PASS 1c: superadmin degrada superadmin -> admin con cuenta (regresion del trigger)';
END $$;

-- ============================================================
-- Regla 2: admin sólo admin<->user y sólo en su cuenta
-- ============================================================
RESET ROLE;
SET ROLE authenticated;
SELECT pg_temp.login('22222222-0000-0000-0000-000000000002');

-- 2a. promueve a un user de SU cuenta -> admin
UPDATE public.profiles SET role = 'admin' WHERE id = '44444444-0000-0000-0000-000000000004';
DO $$ BEGIN
  IF pg_temp.role_of('44444444-0000-0000-0000-000000000004') <> 'admin' THEN
    RAISE EXCEPTION 'FAIL 2a: admin no pudo promover user -> admin en su cuenta';
  END IF;
  RAISE NOTICE 'PASS 2a: admin promueve user -> admin en su cuenta';
END $$;

-- 2b. y lo devuelve a user
UPDATE public.profiles SET role = 'user' WHERE id = '44444444-0000-0000-0000-000000000004';
DO $$ BEGIN
  IF pg_temp.role_of('44444444-0000-0000-0000-000000000004') <> 'user' THEN
    RAISE EXCEPTION 'FAIL 2b: admin no pudo degradar admin -> user en su cuenta';
  END IF;
  RAISE NOTICE 'PASS 2b: admin degrada admin -> user en su cuenta';
END $$;

-- 2c. NO puede tocar a un usuario de OTRA cuenta (RLS filtra: 0 filas, sin error)
UPDATE public.profiles SET role = 'admin' WHERE id = '55555555-0000-0000-0000-000000000005';
DO $$ BEGIN
  IF pg_temp.role_of('55555555-0000-0000-0000-000000000005') <> 'user' THEN
    RAISE EXCEPTION 'FAIL 2c: admin cambio el rol de un usuario de otra cuenta';
  END IF;
  RAISE NOTICE 'PASS 2c: admin no toca usuarios de otra cuenta';
END $$;

-- 2d. NO puede crear un superadmin
DO $$ BEGIN
  BEGIN
    UPDATE public.profiles SET role = 'superadmin', account_id = NULL
      WHERE id = '44444444-0000-0000-0000-000000000004';
    IF pg_temp.role_of('44444444-0000-0000-0000-000000000004') = 'superadmin' THEN
      RAISE EXCEPTION 'FAIL 2d: admin logro promover a superadmin';
    END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    NULL; -- rechazo por RLS: correcto
  END;
  RAISE NOTICE 'PASS 2d: admin no puede promover a superadmin';
END $$;

-- 2e. NO puede auto-promocionarse (el agujero de users_update_own_profile)
DO $$ BEGIN
  BEGIN
    UPDATE public.profiles SET role = 'superadmin', account_id = NULL
      WHERE id = '22222222-0000-0000-0000-000000000002';
    IF pg_temp.role_of('22222222-0000-0000-0000-000000000002') = 'superadmin' THEN
      RAISE EXCEPTION 'FAIL 2e: admin se auto-promociono a superadmin';
    END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  RAISE NOTICE 'PASS 2e: admin no se auto-promociona';
END $$;

-- ============================================================
-- Regla 3: user no cambia ningun rol
-- ============================================================
RESET ROLE;
SET ROLE authenticated;
SELECT pg_temp.login('44444444-0000-0000-0000-000000000004');

-- 3a. auto-promocion a superadmin: el agujero original. Debe fallar.
DO $$ BEGIN
  BEGIN
    UPDATE public.profiles SET role = 'superadmin', account_id = NULL
      WHERE id = '44444444-0000-0000-0000-000000000004';
    IF pg_temp.role_of('44444444-0000-0000-0000-000000000004') = 'superadmin' THEN
      RAISE EXCEPTION 'FAIL 3a: ESCALADA DE PRIVILEGIOS, un user se hizo superadmin';
    END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  RAISE NOTICE 'PASS 3a: user no se auto-promociona a superadmin';
END $$;

-- 3b. auto-promocion a admin. Debe fallar.
DO $$ BEGIN
  BEGIN
    UPDATE public.profiles SET role = 'admin'
      WHERE id = '44444444-0000-0000-0000-000000000004';
    IF pg_temp.role_of('44444444-0000-0000-0000-000000000004') = 'admin' THEN
      RAISE EXCEPTION 'FAIL 3b: un user se hizo admin';
    END IF;
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  RAISE NOTICE 'PASS 3b: user no se auto-promociona a admin';
END $$;

-- 3c. pero SÍ puede editar sus propios datos
UPDATE public.profiles SET full_name = 'Nuevo Nombre'
  WHERE id = '44444444-0000-0000-0000-000000000004';
DO $$ BEGIN
  IF (SELECT full_name FROM public.profiles WHERE id = '44444444-0000-0000-0000-000000000004') <> 'Nuevo Nombre' THEN
    RAISE EXCEPTION 'FAIL 3c: user no pudo editar su propio nombre';
  END IF;
  RAISE NOTICE 'PASS 3c: user sigue editando sus propios datos';
END $$;

RESET ROLE;
ROLLBACK;
