-- Recordatorio de las 13:00 (hora local de la cuenta): "tienes envios sin declarar" (2026-11-05).
--
-- Regla de negocio: cada panelista (sobre todo en ciudades POBOX) envia algo cada dia laborable y lo declara
-- ese mismo dia; el envio declarado es la prueba de que fue al apartado. Si a las 13:00 locales tiene envios
-- de hoy (o atrasados) sin declarar, se le avisa por el bot. Decision del usuario: TODOS los panelistas de
-- todas las cuentas, a las 13:00.
--
-- * enqueue_send_reminders(p_now): pg_cron cada hora en punto; solo actua en las cuentas cuya hora local es 13
--   y el dia es laborable. Un aviso por panelista y dia local (no duplica aunque se llame varias veces).
--   Cuenta lo mismo que la lista del bot: origen = su nodo, pending/notified, fecha <= hoy (atrasados de los
--   ultimos 14 dias), destino con panelista activo. No avisa a quien esta de baja hoy ni a quien no tiene
--   telegram.
-- * El aviso sale enseguida: el trigger de aviso inmediato (20261104123000) incluye ahora 'send_reminder'.
-- * El texto lo pinta el flujo de n8n "Deliver panelist notifications" (nodo Build message).

SET lock_timeout = '5s';

ALTER TABLE public.panelist_notification DROP CONSTRAINT IF EXISTS panelist_notification_kind_check;
ALTER TABLE public.panelist_notification ADD CONSTRAINT panelist_notification_kind_check
  CHECK (kind IN ('unavailability_received', 'plan_change_this_week', 'material_pending_released',
                  'receipt_reminder', 'manager_notice', 'broadcast', 'send_reminder'));

CREATE OR REPLACE FUNCTION public.enqueue_send_reminders(p_now timestamptz DEFAULT now())
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_n int := 0;
  v_add int;
  a record;
  v_today date;
BEGIN
  FOR a IN SELECT ac.id, COALESCE(ac.timezone, 'UTC') AS tz FROM public.accounts ac LOOP
    IF extract(hour FROM (p_now AT TIME ZONE a.tz)) <> 13 THEN CONTINUE; END IF;
    v_today := (p_now AT TIME ZONE a.tz)::date;
    IF NOT public.is_account_working_day(a.id, v_today) THEN CONTINUE; END IF;

    WITH due AS (
      SELECT p.id AS panelist_id,
             count(*) FILTER (WHERE d.fecha_programada = v_today) AS today,
             count(*) FILTER (WHERE d.fecha_programada < v_today) AS overdue
        FROM public.panelists p
        JOIN public.allocation_plan_details d
          ON d.account_id = a.id AND d.origin_node_id = p.node_id
         AND d.status IN ('pending', 'notified')
         AND d.fecha_programada BETWEEN v_today - 14 AND v_today
       WHERE p.account_id = a.id AND p.status = 'active'
         AND COALESCE(btrim(p.telegram_id), '') ~ '^[0-9]+$'
         AND EXISTS (SELECT 1 FROM public.panelists q
                      WHERE q.node_id = d.destination_node_id AND q.account_id = a.id AND q.status = 'active')
         AND NOT EXISTS (SELECT 1 FROM public.panelist_unavailability u
                          WHERE u.panelist_id = p.id AND u.status = 'active'
                            AND v_today BETWEEN u.start_date AND u.end_date)
         AND NOT EXISTS (SELECT 1 FROM public.panelist_notification x
                          WHERE x.panelist_id = p.id AND x.kind = 'send_reminder'
                            AND x.payload->>'local_date' = v_today::text)
       GROUP BY p.id)
    INSERT INTO public.panelist_notification (account_id, panelist_id, kind, payload)
    SELECT a.id, due.panelist_id, 'send_reminder',
           jsonb_build_object('local_date', v_today::text, 'today', due.today, 'overdue', due.overdue)
      FROM due;
    GET DIAGNOSTICS v_add = ROW_COUNT;
    v_n := v_n + v_add;
  END LOOP;
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_send_reminders(timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enqueue_send_reminders(timestamptz) TO service_role;

-- Aviso inmediato: re-emitida de 20261104123000 con 'send_reminder' en la lista de tipos.
CREATE OR REPLACE FUNCTION public.tg_panelist_notice_push()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_url    text;
  v_secret text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM new_rows r
                  WHERE r.kind IN ('manager_notice', 'broadcast', 'send_reminder') AND r.status = 'pending_send'
                    AND (r.send_after IS NULL OR r.send_after <= now())) THEN
    RETURN NULL;
  END IF;
  SELECT decrypted_secret INTO v_url    FROM vault.decrypted_secrets WHERE name = 'panelist_notice_push_webhook_url';
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'incident_push_webhook_secret';
  IF v_url IS NULL OR v_secret IS NULL THEN
    RETURN NULL;
  END IF;
  PERFORM net.http_post(
    url     := v_url,
    body    := jsonb_build_object('source', 'panelist_notification'),
    headers := jsonb_build_object('Content-Type', 'application/json', 'X-ONEMS-Push', v_secret),
    timeout_milliseconds := 5000
  );
  RETURN NULL;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'tg_panelist_notice_push: %', SQLERRM;
  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.tg_panelist_notice_push() FROM PUBLIC, anon, authenticated;

-- pg_cron cada hora en punto (idempotente).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'send-reminder-hourly') THEN
    PERFORM cron.unschedule('send-reminder-hourly');
  END IF;
  PERFORM cron.schedule('send-reminder-hourly', '0 * * * *', 'SELECT public.enqueue_send_reminders()');
END $$;
