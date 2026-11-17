-- Registro ligero de interacciones del bot (n8n) en Supabase.
-- Objetivo: que n8n deje de guardar ejecuciones correctas (saveDataSuccessExecution = 'none') sin perder la
-- trazabilidad de que hizo cada panelista. Privacidad: NUNCA se guardan coordenadas (input_type 'location' y
-- sin texto). Retencion: 60 dias (pg_cron diario 03:15 UTC).
-- El bot escribe con UN nodo Postgres dentro de la ejecucion principal llamando a bot_log_interaction(),
-- que nunca lanza: un fallo del registro jamas afecta a la respuesta del bot.
-- Forward-only. NO toca el baseline.

-- ============================================================================================================
-- 1. Tabla
-- ============================================================================================================
CREATE TABLE IF NOT EXISTS public.bot_interaction_log (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  account_id uuid,
  panelist_id uuid,
  telegram_id text,
  environment text,
  execution_id text,
  action text,
  input_type text,
  input_text text,
  callback_data text,
  CONSTRAINT bot_interaction_log_pkey PRIMARY KEY (id),
  CONSTRAINT bil_environment_check CHECK (environment IN ('dev','prod')),
  CONSTRAINT bil_input_type_check CHECK (input_type IN ('text','photo','location','callback','command','other')),
  CONSTRAINT bil_input_text_len CHECK (input_text IS NULL OR char_length(input_text) <= 500),
  CONSTRAINT bil_account_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE,
  CONSTRAINT bil_panelist_fkey FOREIGN KEY (panelist_id) REFERENCES public.panelists(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_bil_panelist_created ON public.bot_interaction_log (panelist_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bil_created ON public.bot_interaction_log (created_at);
CREATE INDEX IF NOT EXISTS idx_bil_account_created ON public.bot_interaction_log (account_id, created_at);

-- RLS por account_id (mismo patron que panelist_incident / declaration_location). Solo lectura para la app;
-- escrituras solo via bot_log_interaction (service_role).
ALTER TABLE public.bot_interaction_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS bil_select ON public.bot_interaction_log;
CREATE POLICY bil_select ON public.bot_interaction_log
  FOR SELECT USING (account_id = current_user_account_id() OR is_superadmin());

REVOKE ALL ON public.bot_interaction_log FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.bot_interaction_log TO authenticated;
GRANT ALL ON public.bot_interaction_log TO service_role;

-- ============================================================================================================
-- 2. Escritura desde el bot (nunca lanza)
-- ============================================================================================================
CREATE OR REPLACE FUNCTION public.bot_log_interaction(
  p_telegram_id text, p_environment text, p_execution_id text, p_action text,
  p_input_type text, p_input_text text, p_callback_data text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_panelist uuid; v_account uuid;
  v_type text := lower(nullif(btrim(coalesce(p_input_type,'')),''));
  v_env text := lower(nullif(btrim(coalesce(p_environment,'')),''));
  v_text text;
BEGIN
  IF v_type IS NULL OR v_type NOT IN ('text','photo','location','callback','command','other') THEN
    v_type := 'other';
  END IF;
  IF v_env IS NOT NULL AND v_env NOT IN ('dev','prod') THEN v_env := NULL; END IF;
  -- Privacidad: solo se guarda texto si es texto o comando escrito por el panelista. Jamas coordenadas.
  v_text := CASE WHEN v_type IN ('text','command') THEN left(nullif(p_input_text,''), 500) END;

  IF nullif(btrim(coalesce(p_telegram_id,'')),'') IS NOT NULL THEN
    SELECT id, account_id INTO v_panelist, v_account
      FROM panelists
     WHERE telegram_id = btrim(p_telegram_id)
     ORDER BY (status = 'active') DESC, updated_at DESC NULLS LAST
     LIMIT 1;
  END IF;

  INSERT INTO bot_interaction_log (account_id, panelist_id, telegram_id, environment, execution_id,
                                   action, input_type, input_text, callback_data)
  VALUES (v_account, v_panelist, left(nullif(btrim(coalesce(p_telegram_id,'')),''), 64), v_env,
          left(nullif(p_execution_id,''), 64), left(nullif(p_action,''), 100), v_type, v_text,
          left(nullif(p_callback_data,''), 200));
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'bot_log_interaction failed: % (%)', SQLERRM, SQLSTATE;
  RETURN;
END; $$;

-- ============================================================================================================
-- 3. Retencion: 60 dias
-- ============================================================================================================
CREATE OR REPLACE FUNCTION public.bot_interaction_log_purge()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n integer;
BEGIN
  DELETE FROM bot_interaction_log WHERE created_at < now() - interval '60 days';
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END; $$;

REVOKE ALL ON FUNCTION public.bot_log_interaction(text,text,text,text,text,text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.bot_interaction_log_purge() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bot_log_interaction(text,text,text,text,text,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.bot_interaction_log_purge() TO service_role;

-- ============================================================================================================
-- 4. pg_cron: purga diaria 03:15 UTC (idempotente)
-- ============================================================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'bot-interaction-log-purge') THEN
    PERFORM cron.unschedule('bot-interaction-log-purge');
  END IF;
  PERFORM cron.schedule('bot-interaction-log-purge', '15 3 * * *', 'SELECT public.bot_interaction_log_purge()');
END $$;
