-- Aviso inmediato a n8n para los mensajes del responsable y los avisos generales (panelist_notification).
-- El flujo "Deliver panelist notifications" sigue con su reloj de cada 6 horas (creditos de n8n): los
-- recordatorios automaticos salen en esa ronda. Para 'manager_notice' y 'broadcast' la BD llama al webhook
-- de n8n en cuanto se insertan: UNA llamada por sentencia (un aviso general a 100 panelistas = 1 ejecucion).
--
-- Reserva de filas: pending_panelist_notifications() marca claimed_at con FOR UPDATE SKIP LOCKED para que la
-- ronda del reloj y la del aviso inmediato no envien la misma fila dos veces. Una reserva caduca a los 10 min
-- (si n8n falla a mitad, la fila vuelve a salir en la siguiente ronda).
--
-- Secretos en Vault (NO en el repo), se cargan aparte:
--   panelist_notice_push_webhook_url -> URL de produccion del webhook (path deliver-panelist-notifications)
--   incident_push_webhook_secret     -> el mismo valor de cabecera X-ONEMS-Push que ya usa incident_message_push
-- Sin alguno de los dos, el trigger no llama a nadie. Fail-open: nunca impide guardar el aviso.

SET lock_timeout = '5s';

ALTER TABLE public.panelist_notification ADD COLUMN IF NOT EXISTS claimed_at timestamptz NULL;

CREATE OR REPLACE FUNCTION public.pending_panelist_notifications(p_limit int DEFAULT 50)
RETURNS TABLE(id uuid, kind text, payload jsonb, telegram_id text, language text, entregable boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH claimed AS (
    UPDATE public.panelist_notification u
       SET claimed_at = now()
     WHERE u.id IN (
       SELECT n.id
         FROM public.panelist_notification n
        WHERE n.status = 'pending_send'
          AND n.created_at > now() - interval '7 days'
          AND (n.send_after IS NULL OR n.send_after <= now())
          AND (n.claimed_at IS NULL OR n.claimed_at < now() - interval '10 minutes')
        ORDER BY n.created_at
        LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 200))
        FOR UPDATE OF n SKIP LOCKED)
    RETURNING u.id, u.kind, u.payload, u.panelist_id, u.account_id, u.created_at
  )
  SELECT c.id, c.kind, c.payload, p.telegram_id, COALESCE(p.language, 'en')::text,
         (COALESCE(btrim(p.telegram_id), '') ~ '^[0-9]+$')
    FROM claimed c
    JOIN public.panelists p ON p.id = c.panelist_id AND p.account_id = c.account_id
   ORDER BY c.created_at;
END;
$$;

REVOKE ALL ON FUNCTION public.pending_panelist_notifications(int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pending_panelist_notifications(int) TO service_role;

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
                  WHERE r.kind IN ('manager_notice', 'broadcast') AND r.status = 'pending_send'
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

DROP TRIGGER IF EXISTS panelist_notice_push ON public.panelist_notification;
CREATE TRIGGER panelist_notice_push
  AFTER INSERT ON public.panelist_notification
  REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.tg_panelist_notice_push();
