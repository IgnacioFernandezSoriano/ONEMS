-- rpc_get_account_balance_policy: lee la politica de la cuenta aunque el SELECT de account_config (RLS) no
-- lo permita (superadmin sin account_id), con el mismo guard que las RPC de escritura.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;

-- Sin fila en account_config: valores por defecto.
SELECT set_config('request.jwt.claim.sub','99000000-0000-0000-0000-000000000099', true);
SELECT pg_temp.fail_if(public.rpc_get_account_balance_policy('a0000000-0000-0000-0000-000000000001')
  IS DISTINCT FROM '{"date_policy":"daily","pobox_enabled":false}'::jsonb, 'defecto sin fila');

-- Tras escribirla (usuario normal de la cuenta 1) se lee lo escrito.
SELECT public.rpc_set_account_balance_policy('a0000000-0000-0000-0000-000000000001', 'weekly', true);
SELECT pg_temp.fail_if(public.rpc_get_account_balance_policy('a0000000-0000-0000-0000-000000000001')
  IS DISTINCT FROM '{"date_policy":"weekly","pobox_enabled":true}'::jsonb, 'lectura tras escritura');

-- Superadmin sin account_id lee la cuenta 1.
INSERT INTO auth.users (id, email) VALUES ('97000000-0000-0000-0000-000000000097','sa@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id)
  VALUES ('97000000-0000-0000-0000-000000000097','sa@t.l','SA','superadmin',NULL);
SELECT set_config('request.jwt.claim.sub','97000000-0000-0000-0000-000000000097', true);
SELECT pg_temp.fail_if((public.rpc_get_account_balance_policy('a0000000-0000-0000-0000-000000000001')->>'pobox_enabled')::boolean
  IS DISTINCT FROM true, 'superadmin lee la cuenta');

-- Un usuario de la cuenta 2 no puede leer la cuenta 1.
SELECT set_config('request.jwt.claim.sub','98000000-0000-0000-0000-000000000098', true);
DO $$ BEGIN
  PERFORM public.rpc_get_account_balance_policy('a0000000-0000-0000-0000-000000000001');
  RAISE EXCEPTION 'FAIL: usuario de otra cuenta pudo leer';
EXCEPTION WHEN insufficient_privilege THEN NULL;
END $$;
ROLLBACK;
