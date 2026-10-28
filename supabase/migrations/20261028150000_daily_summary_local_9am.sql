-- Resumen diario de envios del bot: a las 09:00 LOCALES de cada cuenta (accounts.timezone).
-- Antes: n8n "On new parcel to send" tenia un Schedule Trigger unico a las 09:00 de Madrid para todas las
-- cuentas y usaba CURRENT_DATE (UTC). Ahora pg_cron comprueba cada hora en punto (gratis, dentro de la BD)
-- y SOLO llama al webhook de n8n para las cuentas que estan a las 09:00 locales y tienen algo que avisar:
-- una ejecucion de n8n por cuenta y dia, ninguna si no hay nada.
--
-- Secretos en Vault (NO en el repo), se cargan aparte:
--   daily_summary_webhook_url     -> URL de produccion del webhook de n8n
--   daily_summary_webhook_secret  -> valor de la cabecera X-Daily-Summary-Secret (credencial Header Auth en n8n)
-- Sin alguno de los dos, dispatch no llama a nadie (RAISE NOTICE).

-- Cuentas que deben recibir el resumen en el instante p_now: hora local = p_hour y al menos un envio a avisar
-- con las mismas reglas que la consulta "Get pending parcels to send" de n8n (hoy pending o atrasado notified,
-- panelista origen con chat de Telegram numerico, panelista activo en destino). Los envios retenidos por falta
-- de material los sigue filtrando n8n: como mucho provocan una llamada que no envia nada.
CREATE OR REPLACE FUNCTION public.daily_summary_due_accounts(
  p_now  timestamptz DEFAULT now(),
  p_hour int         DEFAULT 9
)
RETURNS TABLE (account_id uuid, local_date date)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH a AS (
    SELECT acc.id, (p_now AT TIME ZONE acc.timezone)::date AS local_date
      FROM public.accounts acc
     WHERE acc.timezone IS NOT NULL
       AND extract(hour FROM (p_now AT TIME ZONE acc.timezone))::int = p_hour
  )
  SELECT a.id, a.local_date
    FROM a
   WHERE EXISTS (
     SELECT 1
       FROM public.allocation_plan_details d
       JOIN public.panelists p_orig ON p_orig.node_id = d.origin_node_id
      WHERE d.account_id = a.id
        AND ((d.fecha_programada = a.local_date AND d.status = 'pending')
          OR (d.fecha_programada < a.local_date AND d.status = 'notified'))
        AND p_orig.telegram_id ~ '^-?\d+$'
        AND EXISTS (SELECT 1 FROM public.panelists p_dest
                     WHERE p_dest.node_id = d.destination_node_id AND p_dest.status = 'active')
   )
$$;

-- Llama al webhook de n8n una vez por cuenta debida. Devuelve cuantas llamadas ha encolado (pg_net es asincrono).
CREATE OR REPLACE FUNCTION public.dispatch_daily_parcel_summary(p_now timestamptz DEFAULT now())
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_url    text;
  v_secret text;
  v_n      int := 0;
  r        record;
BEGIN
  SELECT decrypted_secret INTO v_url    FROM vault.decrypted_secrets WHERE name = 'daily_summary_webhook_url';
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'daily_summary_webhook_secret';
  IF v_url IS NULL OR v_secret IS NULL THEN
    RAISE NOTICE 'dispatch_daily_parcel_summary: faltan secretos en Vault, no se llama a n8n';
    RETURN 0;
  END IF;

  FOR r IN SELECT * FROM public.daily_summary_due_accounts(p_now) LOOP
    PERFORM net.http_post(
      url     := v_url,
      body    := jsonb_build_object('account_id', r.account_id, 'local_date', r.local_date::text),
      headers := jsonb_build_object('Content-Type', 'application/json', 'X-Daily-Summary-Secret', v_secret),
      timeout_milliseconds := 30000
    );
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END;
$$;

-- Solo el backend (pg_cron corre como postgres) puede usarlas.
REVOKE ALL ON FUNCTION public.daily_summary_due_accounts(timestamptz, int) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.dispatch_daily_parcel_summary(timestamptz) FROM PUBLIC, anon, authenticated;

-- Cada hora en punto (las zonas con media hora no existen entre las cuentas actuales).
SELECT cron.schedule('daily-parcel-summary-hourly', '0 * * * *', 'SELECT public.dispatch_daily_parcel_summary();');
