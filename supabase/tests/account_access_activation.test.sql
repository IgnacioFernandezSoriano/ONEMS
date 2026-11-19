-- Activación de roles por cuenta (20261119100100_account_access_activation.sql).
-- La migración corre en el replay sin datos; aquí se re-ejecuta su cuerpo con fixtures.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT FALSE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
-- A1: contactos (con mayúsculas) para PM y MS = mismo correo; UPU para un user. El perfil PM lleva espacios.
UPDATE public.accounts SET email_panelist_manager = 'Pm@T.L', email_materials_supplier = 'pm@t.l',
  email_upu_account_manager = 'upu@t.l',
  email_allocation_plan_manager = 'super@t.l'   -- coincide con un superadmin: no se asigna
 WHERE id = 'a0000000-0000-0000-0000-000000000001';
INSERT INTO auth.users (id, email) VALUES
  ('91000000-0000-0000-0000-000000000091','pm@t.l'),
  ('92000000-0000-0000-0000-000000000092','admin2@t.l'),
  ('93000000-0000-0000-0000-000000000093','super@t.l'),
  ('90000000-0000-0000-0000-000000000090','upu@t.l'),
  ('8f000000-0000-0000-0000-00000000008f','empty@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('91000000-0000-0000-0000-000000000091',' PM@t.l ','PM','admin','a0000000-0000-0000-0000-000000000001'),
  ('92000000-0000-0000-0000-000000000092','admin2@t.l','Adm2','admin','a0000000-0000-0000-0000-000000000001'),
  ('93000000-0000-0000-0000-000000000093','super@t.l','Super','superadmin',NULL),
  ('90000000-0000-0000-0000-000000000090','upu@t.l','UPU','user','a0000000-0000-0000-0000-000000000001'),
  ('8f000000-0000-0000-0000-00000000008f','empty@t.l','Empty','admin','a0000000-0000-0000-0000-000000000002');

\ir ../migrations/20261119100100_account_access_activation.sql

DO $$
DECLARE n int;
  A1 constant uuid := 'a0000000-0000-0000-0000-000000000001';
  A2 constant uuid := 'a0000000-0000-0000-0000-000000000002';
BEGIN
  -- PM (correo en dos contactos): dos roles, no provisionales, y nada más.
  SELECT count(*) INTO n FROM public.account_user_role
   WHERE user_id = '91000000-0000-0000-0000-000000000091' AND account_id = A1
     AND role IN ('panelist_manager','materials_supplier') AND NOT provisional;
  PERFORM pg_temp.fail_if(n <> 2, 'PM roles: ' || n);
  SELECT count(*) INTO n FROM public.account_user_role WHERE user_id = '91000000-0000-0000-0000-000000000091';
  PERFORM pg_temp.fail_if(n <> 2, 'PM sin extras: ' || n);
  -- Admin sin coincidencia: account_manager provisional (una sola fila).
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.account_user_role
     WHERE user_id = '92000000-0000-0000-0000-000000000092' AND account_id = A1
       AND role = 'account_manager' AND provisional) <> 1, 'admin provisional');
  SELECT count(*) INTO n FROM public.account_user_role WHERE user_id = '92000000-0000-0000-0000-000000000092';
  PERFORM pg_temp.fail_if(n <> 1, 'admin una fila: ' || n);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.account_user_role
     WHERE user_id = '8f000000-0000-0000-0000-00000000008f' AND account_id = A2
       AND role = 'account_manager' AND provisional) <> 1, 'admin A2 provisional');
  -- Usuario con coincidencia (UPU): recibe el rol aunque sea user, no provisional.
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.account_user_role
     WHERE user_id = '90000000-0000-0000-0000-000000000090' AND role = 'upu_account_manager' AND NOT provisional) <> 1, 'user con contacto');
  -- Usuarios sin coincidencia (fixture 99 y 98) y superadmin: sin filas.
  SELECT count(*) INTO n FROM public.account_user_role
   WHERE user_id IN ('99000000-0000-0000-0000-000000000099','98000000-0000-0000-0000-000000000098','93000000-0000-0000-0000-000000000093');
  PERFORM pg_temp.fail_if(n <> 0, 'user/superadmin sin filas: ' || n);
  SELECT count(*) INTO n FROM public.account_user_role;
  PERFORM pg_temp.fail_if(n <> 5, 'total filas: ' || n);
  -- Log: una fila por cuenta con asignaciones, sin autor.
  SELECT count(*) INTO n FROM public.account_access_log WHERE kind = 'activation' AND changed_by IS NULL;
  PERFORM pg_temp.fail_if(n <> 2, 'logs activation: ' || n);
  PERFORM pg_temp.fail_if((SELECT jsonb_array_length(detail->'assignments') FROM public.account_access_log
     WHERE kind = 'activation' AND account_id = A1) <> 4, 'detalle A1');
END $$;

-- Segunda ejecución: idempotente (ni filas ni logs nuevos).
\ir ../migrations/20261119100100_account_access_activation.sql
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM public.account_user_role;
  PERFORM pg_temp.fail_if(n <> 5, 'idempotencia filas: ' || n);
  SELECT count(*) INTO n FROM public.account_access_log WHERE kind = 'activation';
  PERFORM pg_temp.fail_if(n <> 2, 'idempotencia logs: ' || n);
END $$;
ROLLBACK;
\echo 'account_access_activation: OK'
