-- ============================================================
-- BOOTSTRAP SHIM — entorno base de Supabase para un Postgres pelado
-- ============================================================
-- El Postgres portable (17.6) NO trae el entorno que Supabase provee en cloud:
-- roles (anon/authenticated/service_role/...), esquemas (auth/storage/extensions/
-- cron/net), la tabla auth.users, ni las funciones auth.uid()/auth.jwt()/auth.role().
-- Tampoco las extensiones pg_cron / pg_net.
--
-- Este script recrea SOLO lo mínimo para que las migraciones del repo puedan
-- reproducirse (replay) y validar su consistencia interna. NO pretende emular el
-- comportamiento en runtime de Supabase; auth.uid() devuelve NULL, cron/net son no-op.
--
-- Se ejecuta UNA vez, ANTES de replicar supabase/migrations/*.sql.
-- ============================================================

-- ---------- Roles que Supabase crea por defecto ----------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN CREATE ROLE anon NOLOGIN NOINHERIT; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN NOINHERIT; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role') THEN CREATE ROLE service_role NOLOGIN NOINHERIT BYPASSRLS; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticator') THEN CREATE ROLE authenticator LOGIN NOINHERIT; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='supabase_admin') THEN CREATE ROLE supabase_admin NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='supabase_auth_admin') THEN CREATE ROLE supabase_auth_admin NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='supabase_storage_admin') THEN CREATE ROLE supabase_storage_admin NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='dashboard_user') THEN CREATE ROLE dashboard_user NOLOGIN; END IF;
END $$;

GRANT anon, authenticated, service_role TO authenticator;
GRANT anon, authenticated, service_role TO postgres;

-- ---------- Esquemas ----------
CREATE SCHEMA IF NOT EXISTS auth        AUTHORIZATION postgres;
CREATE SCHEMA IF NOT EXISTS storage     AUTHORIZATION postgres;
CREATE SCHEMA IF NOT EXISTS extensions  AUTHORIZATION postgres;
CREATE SCHEMA IF NOT EXISTS cron        AUTHORIZATION postgres;
CREATE SCHEMA IF NOT EXISTS net         AUTHORIZATION postgres;
CREATE SCHEMA IF NOT EXISTS graphql_public AUTHORIZATION postgres;
CREATE SCHEMA IF NOT EXISTS realtime    AUTHORIZATION postgres;
CREATE SCHEMA IF NOT EXISTS vault       AUTHORIZATION postgres;

GRANT USAGE ON SCHEMA auth, storage, extensions TO anon, authenticated, service_role;

-- ---------- Extensiones (bundled en el contrib de EDB) ----------
CREATE EXTENSION IF NOT EXISTS pgcrypto      WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp"   WITH SCHEMA extensions;
-- gen_random_uuid() es nativo en PG13+; no requiere extensión.

-- ---------- auth.users (mínima) + funciones auth.* ----------
CREATE TABLE IF NOT EXISTS auth.users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email         text,
  raw_app_meta_data  jsonb DEFAULT '{}'::jsonb,
  raw_user_meta_data jsonb DEFAULT '{}'::jsonb,
  created_at    timestamptz DEFAULT now()
);

-- auth.uid()/role()/jwt(): en Supabase leen el JWT de la request (GUC request.jwt.*).
-- En replay no hay request → devuelven NULL / valores por defecto.
CREATE OR REPLACE FUNCTION auth.uid() RETURNS uuid
  LANGUAGE sql STABLE AS $$
    SELECT nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
  $$;

CREATE OR REPLACE FUNCTION auth.role() RETURNS text
  LANGUAGE sql STABLE AS $$
    SELECT coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), 'anon');
  $$;

CREATE OR REPLACE FUNCTION auth.email() RETURNS text
  LANGUAGE sql STABLE AS $$
    SELECT nullif(current_setting('request.jwt.claim.email', true), '');
  $$;

CREATE OR REPLACE FUNCTION auth.jwt() RETURNS jsonb
  LANGUAGE sql STABLE AS $$
    SELECT coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
  $$;

-- ---------- storage (buckets/objects mínimos) ----------
CREATE TABLE IF NOT EXISTS storage.buckets (
  id     text PRIMARY KEY,
  name   text NOT NULL,
  public boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);
CREATE TABLE IF NOT EXISTS storage.objects (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bucket_id text REFERENCES storage.buckets(id),
  name      text,
  owner     uuid,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
CREATE OR REPLACE FUNCTION storage.foldername(name text) RETURNS text[]
  LANGUAGE sql IMMUTABLE AS $$ SELECT string_to_array(name, '/') $$;

-- ---------- Stubs cron / net (pg_cron y pg_net no están en el binario) ----------
-- Guardan la definición para que la migración no falle; NO ejecutan nada.
CREATE TABLE IF NOT EXISTS cron.job (
  jobid    bigserial PRIMARY KEY,
  schedule text,
  command  text,
  jobname  text UNIQUE
);
CREATE OR REPLACE FUNCTION cron.schedule(job_name text, schedule text, command text)
  RETURNS bigint LANGUAGE sql AS $$
    INSERT INTO cron.job(jobname, schedule, command) VALUES (job_name, schedule, command)
    ON CONFLICT (jobname) DO UPDATE SET schedule=excluded.schedule, command=excluded.command
    RETURNING jobid;
  $$;
CREATE OR REPLACE FUNCTION cron.schedule(schedule text, command text)
  RETURNS bigint LANGUAGE sql AS $$
    INSERT INTO cron.job(jobname, schedule, command)
    VALUES ('job_'||md5(schedule||command), schedule, command)
    ON CONFLICT (jobname) DO UPDATE SET schedule=excluded.schedule, command=excluded.command
    RETURNING jobid;
  $$;
CREATE OR REPLACE FUNCTION cron.unschedule(job_name text)
  RETURNS boolean LANGUAGE sql AS $$
    DELETE FROM cron.job WHERE jobname = job_name; SELECT true;
  $$;
CREATE OR REPLACE FUNCTION cron.unschedule(job_id bigint)
  RETURNS boolean LANGUAGE sql AS $$
    DELETE FROM cron.job WHERE jobid = job_id; SELECT true;
  $$;

CREATE OR REPLACE FUNCTION net.http_post(
  url text, body jsonb DEFAULT '{}'::jsonb, params jsonb DEFAULT '{}'::jsonb,
  headers jsonb DEFAULT '{}'::jsonb, timeout_milliseconds int DEFAULT 5000)
  RETURNS bigint LANGUAGE sql AS $$ SELECT 0::bigint $$;
CREATE OR REPLACE FUNCTION net.http_get(
  url text, params jsonb DEFAULT '{}'::jsonb, headers jsonb DEFAULT '{}'::jsonb,
  timeout_milliseconds int DEFAULT 5000)
  RETURNS bigint LANGUAGE sql AS $$ SELECT 0::bigint $$;

-- ---------- supabase_migrations (registro de migraciones) ----------
CREATE SCHEMA IF NOT EXISTS supabase_migrations;
CREATE TABLE IF NOT EXISTS supabase_migrations.schema_migrations (
  version text PRIMARY KEY,
  name    text,
  statements text[]
);
