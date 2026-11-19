-- Claves de API hasheadas (20261120100000_api_keys_hash.sql):
--   backfill de filas antiguas (api_key en claro) -> resuelven por hash; api_key_issue (AM con Edit en e2e_db_api)
--   devuelve 'onems_...' y no guarda la clave; api_key_resolve respeta is_active y expires_at;
--   sin rol / otra cuenta / ámbito inválido -> error.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid text, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  PERFORM set_config('request.jwt.claim.role', coalesce(p_role, ''), true);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.raises(p_sql text) RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
  EXECUTE p_sql;
  RETURN false;
EXCEPTION WHEN OTHERS THEN
  RETURN true;
END $$;

BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- AM 93 de A1 (Edit en e2e_db_api); X 91 sin rol en A1.
INSERT INTO auth.users (id, email) VALUES
  ('93000000-0000-0000-0000-000000000093','am@t.l'),
  ('91000000-0000-0000-0000-000000000091','x@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('93000000-0000-0000-0000-000000000093','am@t.l','AM','user','a0000000-0000-0000-0000-000000000001'),
  ('91000000-0000-0000-0000-000000000091','x@t.l','X','user','a0000000-0000-0000-0000-000000000001');
INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000093','account_manager');
INSERT INTO public.account_access (account_id, role, option, level) VALUES
  ('a0000000-0000-0000-0000-000000000001','account_manager','e2e_db_api','edit')
ON CONFLICT (account_id, role, option) DO UPDATE SET level = EXCLUDED.level;

-- Fila antigua (clave en claro, sin hash) y backfill.
INSERT INTO public.api_keys (id, account_id, api_key)
VALUES ('b1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','legacy-key-1');
SELECT public.api_keys_backfill_hash();
SELECT public.api_keys_backfill_hash();  -- idempotente

SET ROLE service_role;
SELECT pg_temp.as_user('', 'service_role');
DO $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM public.api_key_resolve('legacy-key-1');
  PERFORM pg_temp.ok(r.account_id = 'a0000000-0000-0000-0000-000000000001', 'legacy resuelve a A1');
  PERFORM pg_temp.ok(r.scope = 'onedb_read', 'legacy scope onedb_read');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.api_key_resolve('nope')), 'clave desconocida no resuelve');
END $$;
RESET ROLE;

DO $$
DECLARE r record;
BEGIN
  SELECT * INTO r FROM public.api_keys WHERE id = 'b1000000-0000-0000-0000-000000000001';
  PERFORM pg_temp.ok(r.key_prefix = 'legacy-key-1', 'prefix legacy = left(key,12)');
  PERFORM pg_temp.ok(r.name = 'Clave legacy-key-1', 'name legacy');
END $$;

-- Emisión como AM de A1.
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
CREATE TEMP TABLE issued AS
  SELECT * FROM public.api_key_issue('a0000000-0000-0000-0000-000000000001', 'Mi clave');
GRANT SELECT ON issued TO service_role;
DO $$
DECLARE i record; r record;
BEGIN
  SELECT * INTO i FROM issued;
  PERFORM pg_temp.ok(i.api_key LIKE 'onems\_%', 'clave empieza por onems_');
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.api_key_issue('a0000000-0000-0000-0000-000000000002','x')$q$),
                          'AM de A1 no emite en A2');
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.api_key_issue('a0000000-0000-0000-0000-000000000001','x','otro')$q$),
                          'ámbito inválido falla');
END $$;
RESET ROLE;

DO $$
DECLARE i record; r record;
BEGIN
  SELECT * INTO i FROM issued;
  SELECT * INTO r FROM public.api_keys WHERE id = i.id;
  PERFORM pg_temp.ok(r.api_key IS NULL, 'api_key NULL');
  PERFORM pg_temp.ok(length(r.key_hash) = 64, 'hash de 64');
  PERFORM pg_temp.ok(r.key_prefix = left(i.api_key, 12), 'prefix');
  PERFORM pg_temp.ok(r.created_by = '93000000-0000-0000-0000-000000000093', 'created_by');
  PERFORM pg_temp.ok(r.name = 'Mi clave' AND r.scope = 'onedb_read', 'name y scope');
END $$;

-- Resolver (service_role).
SET ROLE service_role;
SELECT pg_temp.as_user('', 'service_role');
DO $$
DECLARE i record; r record;
BEGIN
  SELECT * INTO i FROM issued;
  SELECT * INTO r FROM public.api_key_resolve(i.api_key);
  PERFORM pg_temp.ok(r.account_id = 'a0000000-0000-0000-0000-000000000001' AND r.scope = 'onedb_read', 'resuelve A1/onedb_read');
END $$;
RESET ROLE;

UPDATE public.api_keys SET is_active = false WHERE id = (SELECT id FROM issued);
SET ROLE service_role;
DO $$
BEGIN
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.api_key_resolve((SELECT api_key FROM issued))), 'inactiva no resuelve');
END $$;
RESET ROLE;

UPDATE public.api_keys SET is_active = true, expires_at = now() - interval '1 minute' WHERE id = (SELECT id FROM issued);
SET ROLE service_role;
DO $$
BEGIN
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.api_key_resolve((SELECT api_key FROM issued))), 'caducada no resuelve');
END $$;
RESET ROLE;

-- Usuario sin rol en A1: no emite; authenticated no puede resolver.
SET ROLE authenticated;
SELECT pg_temp.as_user('91000000-0000-0000-0000-000000000091', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.api_key_issue('a0000000-0000-0000-0000-000000000001','x')$q$),
                          'sin rol no emite');
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.api_key_resolve('legacy-key-1')$q$),
                          'authenticated no resuelve');
END $$;
RESET ROLE;

ROLLBACK;
