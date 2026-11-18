-- GPS: el historico de permisos sobrevive al borrado del panelista (20261117170000_gps_consent_keep.sql).
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT FALSE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

-- ===== 1) Filas nuevas guardan la instantanea; borrar el panelista conserva sus filas =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$
DECLARE r jsonb; n int; c record; P constant uuid := 'e4000000-0000-0000-0000-000000000004';
BEGIN
  UPDATE public.panelists SET telegram_id = '1004' WHERE id = P;
  PERFORM public.gps_record_consent(P, 'granted', 'es', 'v1', 'texto v1', 'm1');
  r := public.gps_record_consent(P, 'granted', 'en', 'v2', 'text v2', 'm2');

  SELECT * INTO c FROM public.panelist_location_consent WHERE id = (r->>'consent_id')::uuid;
  PERFORM pg_temp.fail_if(c.panelist_code IS DISTINCT FROM 'P4' OR c.panelist_name IS DISTINCT FROM 'Pan4',
    'instantanea en fila nueva: ' || coalesce(c.panelist_code,'NULL') || '/' || coalesce(c.panelist_name,'NULL'));
  PERFORM pg_temp.fail_if(c.consent_text_version IS DISTINCT FROM 'v2', 'version v2');
  PERFORM pg_temp.fail_if(public.gps_current_consent(P) IS DISTINCT FROM 'granted', 'consentimiento vigente por panelist_id');

  -- dependencias del panelista que no son objeto de este test
  DELETE FROM public.panelist_context WHERE context_data->>'panelist_id' = P::text;
  DELETE FROM public.panelists WHERE id = P;

  SELECT count(*) INTO n FROM public.panelist_location_consent
   WHERE panelist_id IS NULL AND panelist_code = 'P4' AND panelist_name = 'Pan4'
     AND account_id = 'a0000000-0000-0000-0000-000000000001' AND telegram_id = '1004';
  PERFORM pg_temp.fail_if(n <> 2, 'filas conservadas tras borrar el panelista: ' || n);
  PERFORM pg_temp.fail_if(public.gps_current_consent(P) IS NOT NULL, 'panelista borrado: sin decision vigente');
END $$;
ROLLBACK;

-- ===== 2) Backfill: filas anteriores a la migracion sin instantanea se rellenan con el mismo UPDATE =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$
DECLARE c record; P constant uuid := 'e3000000-0000-0000-0000-000000000003';
BEGIN
  INSERT INTO public.panelist_location_consent (account_id, panelist_id, decision, consent_text_version)
  VALUES ('a0000000-0000-0000-0000-000000000001', P, 'granted', 'v1');
  UPDATE public.panelist_location_consent pc
     SET panelist_code = p.panelist_code, panelist_name = p.name
    FROM public.panelists p
   WHERE p.id = pc.panelist_id AND (pc.panelist_code IS NULL OR pc.panelist_name IS NULL);
  SELECT * INTO c FROM public.panelist_location_consent WHERE panelist_id = P;
  PERFORM pg_temp.fail_if(c.panelist_code IS DISTINCT FROM 'P3' OR c.panelist_name IS DISTINCT FROM 'Pan3', 'backfill');
END $$;
ROLLBACK;

-- ===== 3) Esquema: columnas NULLables, FKs ON DELETE SET NULL, cron diario, permisos de la funcion =====
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = 'panelist_location_consent'
     AND column_name IN ('panelist_id','account_id') AND is_nullable = 'YES';
  PERFORM pg_temp.fail_if(n <> 2, 'panelist_id/account_id NULLables: ' || n);

  SELECT count(*) INTO n FROM pg_constraint
   WHERE conrelid = 'public.panelist_location_consent'::regclass AND contype = 'f'
     AND conname IN ('plc_panelist_fkey','plc_account_fkey') AND confdeltype = 'n';
  PERFORM pg_temp.fail_if(n <> 2, 'FKs ON DELETE SET NULL: ' || n);

  SELECT count(*) INTO n FROM cron.job WHERE jobname = 'gps-purge-coordinates';
  PERFORM pg_temp.fail_if(n <> 1, 'un solo job de purga: ' || n);
  PERFORM pg_temp.fail_if((SELECT schedule FROM cron.job WHERE jobname = 'gps-purge-coordinates') IS DISTINCT FROM '0 3 * * *',
    'purga diaria');

  PERFORM pg_temp.fail_if(has_function_privilege('authenticated',
    'public.gps_record_consent(uuid,text,text,text,text,text)', 'EXECUTE'), 'authenticated sin EXECUTE');
  PERFORM pg_temp.fail_if(has_function_privilege('anon',
    'public.gps_record_consent(uuid,text,text,text,text,text)', 'EXECUTE'), 'anon sin EXECUTE');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('service_role',
    'public.gps_record_consent(uuid,text,text,text,text,text)', 'EXECUTE'), 'service_role con EXECUTE');
END $$;
