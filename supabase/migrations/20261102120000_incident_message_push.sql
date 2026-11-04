-- Aviso inmediato a n8n cuando un manager escribe a un panelista.
-- Hasta ahora "Deliver incident messages" solo consultaba la cola por reloj, asi que un mensaje del manager
-- tardaba hasta un intervalo completo en salir por Telegram. Con este trigger, al guardarse un mensaje
-- outbound en pending_send la BD llama al webhook "Push from ONEMS" de n8n y el mensaje sale en segundos.
-- La consulta por reloj se queda como red de seguridad (reclamos caducados, fallos del aviso).
--
-- Secretos en Vault (NO en el repo), se cargan aparte:
--   incident_push_webhook_url     -> URL de produccion del webhook de n8n (path deliver-incident-messages)
--   incident_push_webhook_secret  -> valor de la cabecera X-ONEMS-Push (credencial Header Auth en n8n)
-- Sin alguno de los dos, el trigger no llama a nadie.
--
-- Fail-open: un fallo del aviso NUNCA debe impedir que el manager envie su mensaje. pg_net es asincrono
-- y solo sale al confirmarse la transaccion, de modo que un rollback tampoco dispara nada.

CREATE OR REPLACE FUNCTION public.tg_incident_message_push()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_url    text;
  v_secret text;
BEGIN
  SELECT decrypted_secret INTO v_url    FROM vault.decrypted_secrets WHERE name = 'incident_push_webhook_url';
  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'incident_push_webhook_secret';
  IF v_url IS NULL OR v_secret IS NULL THEN
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url     := v_url,
    body    := jsonb_build_object('message_id', NEW.id),
    headers := jsonb_build_object('Content-Type', 'application/json', 'X-ONEMS-Push', v_secret),
    timeout_milliseconds := 5000
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'tg_incident_message_push: %', SQLERRM;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.tg_incident_message_push() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS incident_message_push ON public.incident_message;
CREATE TRIGGER incident_message_push
  AFTER INSERT ON public.incident_message
  FOR EACH ROW
  WHEN (NEW.direction = 'outbound' AND NEW.status = 'pending_send')
  EXECUTE FUNCTION public.tg_incident_message_push();
