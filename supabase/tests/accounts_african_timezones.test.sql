-- accounts.timezone admite las zonas africanas (Nairobi, Dakar...) y sigue rechazando valores inventados.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/incident_city.sql

CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;

-- Zonas africanas y una de las originales: se aceptan
UPDATE public.accounts SET timezone = 'Africa/Nairobi' WHERE id = 'a0000000-0000-0000-0000-000000000001';
UPDATE public.accounts SET timezone = 'Africa/Dakar' WHERE id = 'a0000000-0000-0000-0000-000000000001';
UPDATE public.accounts SET timezone = 'Indian/Mauritius' WHERE id = 'a0000000-0000-0000-0000-000000000001';
UPDATE public.accounts SET timezone = 'Europe/Madrid' WHERE id = 'a0000000-0000-0000-0000-000000000001';

-- Todas las zonas de la lista existen en Postgres (un nombre mal escrito haria fallar el "hoy" del bot)
DO $$
DECLARE v_def text; v_bad text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_def FROM pg_constraint WHERE conname = 'accounts_valid_timezone';
  SELECT string_agg(z, ',') INTO v_bad
    FROM (SELECT (regexp_matches(v_def, '''([^'']+)''', 'g'))[1] AS z) s
   WHERE z NOT IN (SELECT name FROM pg_timezone_names);
  PERFORM pg_temp.fail_if(v_bad IS NOT NULL, 'zonas desconocidas: ' || v_bad);
END $$;

-- Un valor inventado se sigue rechazando
DO $$
BEGIN
  UPDATE public.accounts SET timezone = 'Africa/Atlantis' WHERE id = 'a0000000-0000-0000-0000-000000000001';
  RAISE EXCEPTION 'FAIL Africa/Atlantis aceptada';
EXCEPTION WHEN check_violation THEN NULL;
END $$;
ROLLBACK;
