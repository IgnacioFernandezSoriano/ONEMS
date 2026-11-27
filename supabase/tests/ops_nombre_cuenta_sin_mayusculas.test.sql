-- El nombre de la cuenta se compara sin mayúsculas ni espacios en los extremos (caso real: "KENYA" -> "Kenya"
-- el 24/11 dejó al bot de gestores sin acceso). Cuenta 1 = 'Acc' (a...01), cuenta 2 = 'Acc2' (a...02).
\set ON_ERROR_STOP on
SET client_min_messages = error;
CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;
CREATE OR REPLACE FUNCTION pg_temp.err(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
  EXECUTE p_sql;
  RETURN '';
EXCEPTION WHEN OTHERS THEN
  GET STACKED DIAGNOSTICS v = MESSAGE_TEXT;
  RETURN v;
END $$;

BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
INSERT INTO ops_test.secret(token_sha256) VALUES (encode(extensions.digest('t0ken-de-prueba','sha256'),'hex'));
SELECT ops_test.set_manager_token_hash(encode(extensions.digest('t0ken-managers','sha256'),'hex'));
-- la cuenta 1 se renombra como Kenya; la 2 lleva un espacio al final (como "Tunisia ")
UPDATE public.accounts SET name = 'Kenya', email_panelist_manager = 'pm@x.org' WHERE id = 'a0000000-0000-0000-0000-000000000001';
UPDATE public.accounts SET name = 'Tunisia ' WHERE id = 'a0000000-0000-0000-0000-000000000002';
INSERT INTO auth.users (id, email) VALUES ('97000000-0000-0000-0000-000000000097','boss@x.org');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('97000000-0000-0000-0000-000000000097','boss@x.org','Boss','superadmin',NULL);

DO $$
DECLARE t text := 't0ken-de-prueba'; m text := 't0ken-managers'; r jsonb;
BEGIN
  -- puerta del bot de gestores con el nombre antiguo en mayúsculas (superadmin y gestor de la cuenta)
  PERFORM pg_temp.fail_if(public.ops_case_account_enabled(m, 'KENYA', 'boss@x.org') IS NOT TRUE, 'KENYA superadmin');
  PERFORM pg_temp.fail_if(public.ops_case_account_enabled(m, ' kenya ', 'PM@x.org') IS NOT TRUE, 'kenya gestor');
  PERFORM pg_temp.fail_if(public.ops_case_account_enabled(t, 'KENYA') IS NOT TRUE, 'KENYA owner');
  PERFORM pg_temp.fail_if(public.ops_case_account_enabled(m, 'Tunisia', 'boss@x.org') IS NOT TRUE, 'Tunisia sin espacio');
  -- el gestor sigue sin entrar en otra cuenta, y una inexistente sigue fallando
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_case_account_enabled('t0ken-managers', 'TUNISIA', 'pm@x.org')$q$)
                          <> 'ops_case: sin permiso en esa cuenta', 'gestor en otra cuenta');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_case_account_enabled('t0ken-managers', 'Kenia', 'boss@x.org')$q$)
                          <> 'ops_case: falta cuenta', 'inexistente');
  -- helpers internos
  PERFORM pg_temp.fail_if(ops_case._account('KENYA', 'x') <> 'a0000000-0000-0000-0000-000000000001', '_account');
  PERFORM pg_temp.fail_if(ops_fix._account('kenya') <> 'a0000000-0000-0000-0000-000000000001', 'ops_fix._account');
  PERFORM pg_temp.fail_if(ops_case._actor(m, 'KENYA', 'pm@x.org', 'ops_case', false) <> 'a0000000-0000-0000-0000-000000000001', '_actor');
  -- informe por cuenta
  PERFORM pg_temp.fail_if(public.ops_report_data(t, 'KENYA', current_date - 1, current_date) IS NULL, 'informe KENYA');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_report_data('t0ken-de-prueba', 'Kenia', current_date - 1, current_date)$q$)
                          <> 'ops_report: cuenta no encontrada', 'informe inexistente');
  -- listas: nombres sin espacios y exclusión sin mayúsculas
  PERFORM pg_temp.fail_if(public.ops_manager_accounts(t) <> ARRAY['Kenya','Tunisia'], 'lista: ' || public.ops_manager_accounts(t)::text);
  PERFORM pg_temp.fail_if(public.ops_manager_accounts(t, ARRAY['KENYA']) <> ARRAY['Tunisia'], 'lista sin excluida');
  r := public.ops_manager_lookup(t, 'pm@x.org');
  PERFORM pg_temp.fail_if(r->'accounts'->0->>'account' <> 'Kenya', 'lookup: ' || r::text);
  r := public.ops_manager_lookup(t, 'pm@x.org', ARRAY['kenya']);
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'accounts') <> 0, 'lookup excluida: ' || r::text);
  PERFORM pg_temp.fail_if(public.ops_messages_sent(t, now() - interval '1 day', ARRAY['KENYA','tunisia']) IS NULL, 'mensajes');
  -- dos cuentas que solo se distinguen por mayúsculas: nunca se elige una al azar
  UPDATE public.accounts SET name = 'KENYA' WHERE id = 'a0000000-0000-0000-0000-000000000002';
  PERFORM pg_temp.fail_if(public.ops_case_account_enabled(t, 'Kenya') IS NOT FALSE, 'ambigua');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT ops_fix._account('kenya')$q$) NOT LIKE 'ops_fix:%no es unica', 'ambigua ops_fix');
  PERFORM pg_temp.fail_if(pg_temp.err($q$SELECT public.ops_report_data('t0ken-de-prueba', 'Kenya', current_date - 1, current_date)$q$)
                          <> 'ops_report: cuenta no encontrada', 'ambigua informe');
END $$;
ROLLBACK;
