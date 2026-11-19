-- Claves de API hasheadas (20261120100000_api_keys_hash.sql):
--   filas heredadas (solo hash) resuelven; sin columna api_key (20261120100100); api_key_issue/api_key_deactivate (solo superadmin o UPU Account Manager de la cuenta)
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

-- AM 93 de A1 (Edit en e2e_db_api, NO UPU); UPU AM 94 de A1; X 91 sin rol en A1; superadmin 97.
INSERT INTO auth.users (id, email) VALUES
  ('93000000-0000-0000-0000-000000000093','am@t.l'),
  ('91000000-0000-0000-0000-000000000091','x@t.l'),
  ('94000000-0000-0000-0000-000000000094','upu@t.l'),
  ('97000000-0000-0000-0000-000000000097','super@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('93000000-0000-0000-0000-000000000093','am@t.l','AM','user','a0000000-0000-0000-0000-000000000001'),
  ('91000000-0000-0000-0000-000000000091','x@t.l','X','user','a0000000-0000-0000-0000-000000000001'),
  ('94000000-0000-0000-0000-000000000094','upu@t.l','UPU','user','a0000000-0000-0000-0000-000000000001'),
  ('97000000-0000-0000-0000-000000000097','super@t.l','Super','superadmin',NULL);
INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000093','account_manager'),
  ('a0000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000094','upu_account_manager');
INSERT INTO public.account_access (account_id, role, option, level) VALUES
  ('a0000000-0000-0000-0000-000000000001','account_manager','e2e_db_api','edit')
ON CONFLICT (account_id, role, option) DO UPDATE SET level = EXCLUDED.level;

-- Fila heredada: solo hash (la columna en claro ya no existe).
INSERT INTO public.api_keys (id, account_id, key_hash, key_prefix, name)
VALUES ('b1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',
        encode(extensions.digest('legacy-key-1','sha256'),'hex'),'legacy-key-1','Clave legacy-key-1');

INSERT INTO public.api_keys (id, account_id, key_hash, key_prefix, name)
VALUES ('b2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002',
        encode(extensions.digest('legacy-key-2','sha256'),'hex'),'legacy-key-2','Clave legacy-key-2');

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

-- Retirada del texto en claro.
DO $$
BEGIN
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM information_schema.columns
                                  WHERE table_schema='public' AND table_name='api_keys' AND column_name='api_key'),
                     'columna api_key eliminada');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                                  WHERE n.nspname='public' AND p.proname='api_keys_backfill_hash'),
                     'api_keys_backfill_hash eliminada');
  PERFORM pg_temp.ok(pg_temp.raises($q$INSERT INTO public.api_keys (account_id, key_hash) VALUES ('a0000000-0000-0000-0000-000000000001', NULL)$q$),
                     'key_hash NULL falla');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname='api_keys_sync_hash' AND NOT tgisinternal),
                     'trigger api_keys_sync_hash eliminado');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
                                  WHERE n.nspname='public' AND p.proname='api_keys_sync_hash'),
                     'api_keys_sync_hash eliminada');
END $$;

-- Emisión como UPU AM de A1.
SET ROLE authenticated;
SELECT pg_temp.as_user('94000000-0000-0000-0000-000000000094', 'authenticated');
CREATE TEMP TABLE issued AS
  SELECT * FROM public.api_key_issue('a0000000-0000-0000-0000-000000000001', 'Mi clave');
GRANT SELECT ON issued TO service_role;
DO $$
DECLARE i record; r record;
BEGIN
  SELECT * INTO i FROM issued;
  PERFORM pg_temp.ok(i.api_key LIKE 'onems\_%', 'clave empieza por onems_');
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.api_key_issue('a0000000-0000-0000-0000-000000000002','x')$q$),
                          'UPU AM de A1 no emite en A2');
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.api_key_issue('a0000000-0000-0000-0000-000000000001','x','otro')$q$),
                          'ámbito inválido falla');
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.api_key_issue('a0000000-0000-0000-0000-000000000001', NULL)$q$),
                          'nombre NULL falla');
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.api_key_issue('a0000000-0000-0000-0000-000000000001', '   ')$q$),
                          'nombre en blanco falla');
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.api_key_issue('a0000000-0000-0000-0000-000000000001', repeat('x', 81))$q$),
                          'nombre > 80 falla');
  PERFORM pg_temp.ok(NOT pg_temp.raises($q$SELECT * FROM public.api_key_issue('a0000000-0000-0000-0000-000000000001', repeat('x', 80))$q$),
                          'nombre de 80 vale');
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.api_key_issue('a0000000-0000-0000-0000-000000000001', 'c', 'onedb_read', NULL, now())$q$),
                          'caducidad no futura falla');
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.api_key_issue('a0000000-0000-0000-0000-000000000001', 'c', 'onedb_read', NULL, now() - interval '1 day')$q$),
                          'caducidad pasada falla');
  PERFORM pg_temp.ok(NOT pg_temp.raises($q$SELECT * FROM public.api_key_issue('a0000000-0000-0000-0000-000000000001', 'c', 'onedb_read', NULL, now() + interval '1 day')$q$),
                          'caducidad futura vale');
  -- Escrituras directas cerradas: INSERT y UPDATE de scope fallan; UPDATE de is_active en cuenta propia vale.
  PERFORM pg_temp.ok(pg_temp.raises($q$INSERT INTO public.api_keys (account_id, key_hash, scope) VALUES ('a0000000-0000-0000-0000-000000000001', repeat('a', 64), 'carrier_feed')$q$),
                          'INSERT directo en api_keys falla');
  PERFORM pg_temp.ok(pg_temp.raises($q$UPDATE public.api_keys SET scope = 'carrier_feed' WHERE id = 'b1000000-0000-0000-0000-000000000001'$q$),
                          'UPDATE de scope falla');
  PERFORM pg_temp.ok(pg_temp.raises($q$UPDATE public.api_keys SET key_hash = repeat('b', 64) WHERE id = 'b1000000-0000-0000-0000-000000000001'$q$),
                          'UPDATE de key_hash falla');
  PERFORM pg_temp.ok(pg_temp.raises($q$DELETE FROM public.api_keys WHERE id = 'b1000000-0000-0000-0000-000000000001'$q$),
                          'DELETE directo falla');
  PERFORM pg_temp.ok(pg_temp.raises($q$UPDATE public.api_keys SET is_active = false WHERE id = 'b1000000-0000-0000-0000-000000000001'$q$),
                          'UPDATE directo de is_active falla (solo api_key_deactivate)');
  -- UPU AM de A1: desactiva clave de A1, no la de A2.
  PERFORM public.api_key_deactivate('b1000000-0000-0000-0000-000000000001');
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT public.api_key_deactivate('b2000000-0000-0000-0000-000000000002')$q$),
                          'UPU AM de A1 no desactiva clave de A2');
END $$;
RESET ROLE;

DO $$
DECLARE i record; r record;
BEGIN
  SELECT * INTO i FROM issued;
  SELECT * INTO r FROM public.api_keys WHERE id = i.id;
  PERFORM pg_temp.ok(length(r.key_hash) = 64, 'hash de 64');
  PERFORM pg_temp.ok(r.key_prefix = left(i.api_key, 12), 'prefix');
  PERFORM pg_temp.ok(r.created_by = '94000000-0000-0000-0000-000000000094', 'created_by');
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

-- AM (account_manager, no UPU) con Edit en e2e_db_api: ya no gestiona claves.
SET ROLE authenticated;
SELECT pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.api_key_issue('a0000000-0000-0000-0000-000000000001','x')$q$),
                          'AM no UPU no emite');
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT public.api_key_deactivate((SELECT id FROM issued))$q$),
                          'AM no UPU no desactiva');
END $$;
-- Superadmin: emite y desactiva en cualquier cuenta.
SELECT pg_temp.as_user('97000000-0000-0000-0000-000000000097', 'authenticated');
DO $$
BEGIN
  PERFORM pg_temp.ok(NOT pg_temp.raises($q$SELECT * FROM public.api_key_issue('a0000000-0000-0000-0000-000000000002','super')$q$),
                          'superadmin emite en A2');
  PERFORM public.api_key_deactivate('b2000000-0000-0000-0000-000000000002');
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
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT public.api_key_deactivate('b1000000-0000-0000-0000-000000000001')$q$),
                          'sin rol no desactiva');
  PERFORM pg_temp.ok(pg_temp.raises($q$SELECT * FROM public.api_key_resolve('legacy-key-1')$q$),
                          'authenticated no resuelve');
END $$;
RESET ROLE;

ROLLBACK;
