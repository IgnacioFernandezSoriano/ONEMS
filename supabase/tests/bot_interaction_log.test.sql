-- Registro de interacciones del bot (20261117180000_bot_interaction_log.sql).
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT FALSE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

-- ===== 1) Resuelve panelista/cuenta, trunca texto, nunca guarda texto de ubicacion/foto/callback =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$
DECLARE c record; n int; P constant uuid := 'e2000000-0000-0000-0000-000000000002';
BEGIN
  UPDATE public.panelists SET telegram_id = '2002' WHERE id = P;

  PERFORM public.bot_log_interaction('2002', 'dev', '123', 'free_text', 'text', repeat('x', 800), NULL);
  SELECT * INTO c FROM public.bot_interaction_log WHERE execution_id = '123';
  PERFORM pg_temp.fail_if(c.panelist_id IS DISTINCT FROM P, 'panelista resuelto');
  PERFORM pg_temp.fail_if(c.account_id IS DISTINCT FROM 'a0000000-0000-0000-0000-000000000001'::uuid, 'cuenta resuelta');
  PERFORM pg_temp.fail_if(char_length(c.input_text) <> 500, 'texto truncado a 500: ' || char_length(c.input_text));
  PERFORM pg_temp.fail_if(c.environment IS DISTINCT FROM 'dev' OR c.action IS DISTINCT FROM 'free_text', 'env/action');

  PERFORM public.bot_log_interaction('2002', 'prod', '124', 'gps_location', 'location', '-1.2921,36.8219', NULL);
  SELECT * INTO c FROM public.bot_interaction_log WHERE execution_id = '124';
  PERFORM pg_temp.fail_if(c.input_type IS DISTINCT FROM 'location' OR c.input_text IS NOT NULL, 'ubicacion sin texto');

  PERFORM public.bot_log_interaction('2002', 'prod', '125', 'photo', 'photo', 'caption', NULL);
  PERFORM public.bot_log_interaction('2002', 'prod', '126', 'cb', 'callback', 'Boton', 'gps_yes');
  SELECT count(*) INTO n FROM public.bot_interaction_log WHERE execution_id IN ('125','126') AND input_text IS NOT NULL;
  PERFORM pg_temp.fail_if(n <> 0, 'foto/callback sin texto');
  PERFORM pg_temp.fail_if((SELECT callback_data FROM public.bot_interaction_log WHERE execution_id = '126')
    IS DISTINCT FROM 'gps_yes', 'callback_data guardado');

  PERFORM public.bot_log_interaction('2002', 'dev', '127', 'command', 'command', '/start', NULL);
  PERFORM pg_temp.fail_if((SELECT input_text FROM public.bot_interaction_log WHERE execution_id = '127')
    IS DISTINCT FROM '/start', 'comando con texto');

  -- telegram_id desconocido: fila sin panelista; tipo/entorno raros normalizados, sin error
  PERFORM public.bot_log_interaction('9999', 'staging', '128', NULL, 'sticker', 'hola', NULL);
  SELECT * INTO c FROM public.bot_interaction_log WHERE execution_id = '128';
  PERFORM pg_temp.fail_if(c.panelist_id IS NOT NULL OR c.account_id IS NOT NULL, 'desconocido sin panelista');
  PERFORM pg_temp.fail_if(c.input_type IS DISTINCT FROM 'other' OR c.input_text IS NOT NULL, 'tipo raro -> other');
  PERFORM pg_temp.fail_if(c.environment IS NOT NULL, 'entorno raro -> NULL');

  -- todo NULL: no lanza
  PERFORM public.bot_log_interaction(NULL, NULL, NULL, NULL, NULL, NULL, NULL);

  -- borrar el panelista deja la fila con panelist_id NULL
  DELETE FROM public.panelist_context WHERE context_data->>'panelist_id' = P::text;
  DELETE FROM public.panelists WHERE id = P;
  SELECT count(*) INTO n FROM public.bot_interaction_log WHERE execution_id = '123' AND panelist_id IS NULL;
  PERFORM pg_temp.fail_if(n <> 1, 'ON DELETE SET NULL');
END $$;
ROLLBACK;

-- ===== 2) Nunca lanza aunque el INSERT falle =====
BEGIN;
DO $$
BEGIN
  ALTER TABLE public.bot_interaction_log ADD CONSTRAINT tmp_block CHECK (false) NOT VALID;
  PERFORM public.bot_log_interaction('1', 'dev', 'x', 'a', 'text', 't', NULL);  -- debe tragar el error
END $$;
ROLLBACK;

-- ===== 3) Purga a 60 dias =====
BEGIN;
DO $$
DECLARE n int;
BEGIN
  INSERT INTO public.bot_interaction_log (created_at, input_type, execution_id) VALUES
    (now() - interval '61 days', 'other', 'old'), (now() - interval '59 days', 'other', 'new');
  n := public.bot_interaction_log_purge();
  PERFORM pg_temp.fail_if(n <> 1, 'purga borra 1: ' || n);
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.bot_interaction_log WHERE execution_id = 'new'), 'conserva 59 dias');
END $$;
ROLLBACK;

-- ===== 4) Esquema, RLS, permisos, cron =====
DO $$
DECLARE n int;
BEGIN
  PERFORM pg_temp.fail_if(NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.bot_interaction_log'::regclass), 'RLS activa');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'bot_interaction_log'
    AND policyname = 'bil_select' AND cmd = 'SELECT'), 'politica SELECT');
  SELECT count(*) INTO n FROM pg_policies WHERE tablename = 'bot_interaction_log';
  PERFORM pg_temp.fail_if(n <> 1, 'solo una politica: ' || n);

  PERFORM pg_temp.fail_if(has_table_privilege('authenticated', 'public.bot_interaction_log', 'INSERT'), 'authenticated sin INSERT');
  PERFORM pg_temp.fail_if(has_table_privilege('anon', 'public.bot_interaction_log', 'SELECT'), 'anon sin SELECT');
  PERFORM pg_temp.fail_if(NOT has_table_privilege('service_role', 'public.bot_interaction_log', 'INSERT'), 'service_role INSERT');

  PERFORM pg_temp.fail_if(has_function_privilege('authenticated',
    'public.bot_log_interaction(text,text,text,text,text,text,text)', 'EXECUTE'), 'authenticated sin EXECUTE');
  PERFORM pg_temp.fail_if(has_function_privilege('anon',
    'public.bot_log_interaction(text,text,text,text,text,text,text)', 'EXECUTE'), 'anon sin EXECUTE');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('service_role',
    'public.bot_log_interaction(text,text,text,text,text,text,text)', 'EXECUTE'), 'service_role EXECUTE');
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.bot_interaction_log_purge()', 'EXECUTE'),
    'purga sin EXECUTE para authenticated');

  SELECT count(*) INTO n FROM cron.job WHERE jobname = 'bot-interaction-log-purge' AND schedule = '15 3 * * *';
  PERFORM pg_temp.fail_if(n <> 1, 'cron diario 03:15: ' || n);

  SELECT count(*) INTO n FROM pg_indexes WHERE tablename = 'bot_interaction_log'
     AND indexname IN ('idx_bil_panelist_created','idx_bil_created','idx_bil_account_created');
  PERFORM pg_temp.fail_if(n <> 3, 'indices: ' || n);
END $$;
