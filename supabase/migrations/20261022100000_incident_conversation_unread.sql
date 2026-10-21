-- Conversaciones de incidencias: mensajes del panelista sin leer, aviso por email al manager y
-- cierre de la conversacion de Telegram al cerrar la incidencia. Forward-only. NO toca el baseline.
-- Plan 5b, Tarea 0 (docs/superpowers/plans/2026-10-21-incidencias-v2-5b-conversacion-no-leidos.md).

-- ===== 1) Columnas de lectura y aviso =====
ALTER TABLE public.incident_message
  ADD COLUMN read_at     timestamptz,
  ADD COLUMN notified_at timestamptz;

CREATE INDEX incident_message_unread_idx
  ON public.incident_message (incident_kind, incident_id)
  WHERE direction = 'inbound' AND read_at IS NULL;

-- ===== 2) El manager abre la incidencia: marca como leidos los mensajes del panelista =====
CREATE OR REPLACE FUNCTION public.mark_incident_conversation_read(p_incident_kind text, p_incident_id uuid)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid; v_n int;
BEGIN
  IF p_incident_kind = 'reported' THEN
    SELECT account_id INTO v_account FROM panelist_incident WHERE id = p_incident_id;
  ELSIF p_incident_kind = 'unavailability' THEN
    SELECT account_id INTO v_account FROM panelist_unavailability WHERE id = p_incident_id;
  ELSE
    RAISE EXCEPTION 'invalid incident kind';
  END IF;
  IF v_account IS NULL THEN RAISE EXCEPTION 'incident not found'; END IF;
  PERFORM assert_same_account(v_account);
  UPDATE incident_message
     SET read_at = now()
   WHERE incident_kind = p_incident_kind AND incident_id = p_incident_id
     AND account_id = v_account AND direction = 'inbound' AND read_at IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END; $$;

-- ===== 3) Conversaciones con mensajes del panelista sin leer (bandejas y menu) =====
-- Cuenta del usuario; superadmin todas; sin usuario (service role) nada.
CREATE OR REPLACE FUNCTION public.unread_incident_conversations()
RETURNS TABLE (incident_kind text, incident_id uuid, unread int, last_at timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT m.incident_kind, m.incident_id, count(*)::int, max(m.created_at)
    FROM incident_message m
   WHERE m.direction = 'inbound' AND m.read_at IS NULL
     AND auth.uid() IS NOT NULL
     AND (is_superadmin() OR m.account_id = current_user_account_id())
   GROUP BY m.incident_kind, m.incident_id
   ORDER BY max(m.created_at) DESC;
$$;

-- ===== 4) Aviso por email al manager: mensajes sin leer de mas de 1 hora. Solo service_role (n8n) =====
-- Una fila por incidencia y tanda (los ya avisados llevan notified_at y no vuelven a salir).
CREATE OR REPLACE FUNCTION public.due_unread_reply_notifications(p_now timestamptz DEFAULT now())
RETURNS TABLE (incident_kind text, incident_id uuid, account_id uuid, panelist_id uuid, panelist_name text,
               unread int, oldest_at timestamptz, manager_email text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH pend AS (
    SELECT m.incident_kind, m.incident_id, m.account_id,
           (array_agg(m.panelist_id ORDER BY m.created_at))[1] AS panelist_id,
           count(*)::int AS unread, min(m.created_at) AS oldest_at
      FROM incident_message m
     WHERE m.direction = 'inbound' AND m.read_at IS NULL AND m.notified_at IS NULL
     GROUP BY m.incident_kind, m.incident_id, m.account_id
    HAVING min(m.created_at) < p_now - interval '1 hour'
  )
  SELECT p.incident_kind, p.incident_id, p.account_id, p.panelist_id, pa.name, p.unread, p.oldest_at,
         COALESCE(NULLIF(btrim(a.email_panelist_manager), ''), NULLIF(btrim(a.admin_email), ''))
    FROM pend p
    JOIN accounts a ON a.id = p.account_id
    LEFT JOIN panelists pa ON pa.id = p.panelist_id AND pa.account_id = p.account_id
   WHERE COALESCE(NULLIF(btrim(a.email_panelist_manager), ''), NULLIF(btrim(a.admin_email), '')) IS NOT NULL
   ORDER BY p.oldest_at, p.incident_id;
$$;

-- n8n confirma que envio el email de esa tanda. Solo service_role.
CREATE OR REPLACE FUNCTION public.mark_unread_reply_notified(p_incident_kind text, p_incident_id uuid)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  UPDATE incident_message
     SET notified_at = now()
   WHERE incident_kind = p_incident_kind AND incident_id = p_incident_id
     AND direction = 'inbound' AND read_at IS NULL AND notified_at IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END; $$;

REVOKE ALL ON FUNCTION public.mark_incident_conversation_read(text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_incident_conversation_read(text,uuid) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.unread_incident_conversations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unread_incident_conversations() TO authenticated;
REVOKE ALL ON FUNCTION public.due_unread_reply_notifications(timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.due_unread_reply_notifications(timestamptz) TO service_role;
REVOKE ALL ON FUNCTION public.mark_unread_reply_notified(text,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_unread_reply_notified(text,uuid) TO service_role;

-- ===== 5) Cerrar la incidencia cierra la conversacion abierta de Telegram =====
-- Borra el contexto pending_incident_reply del panelista que apunta a esa incidencia. Nunca aborta el UPDATE.
CREATE OR REPLACE FUNCTION public.tg_close_reported_incident_conversation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  BEGIN
    DELETE FROM panelist_context
     WHERE telegram_id = (SELECT telegram_id FROM panelists WHERE id = NEW.panelist_id)
       AND context_type = 'pending_incident_reply'
       AND context_data->>'incident_kind' = 'reported'
       AND context_data->>'incident_id' = NEW.id::text;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'tg_close_reported_incident_conversation: conversacion de la incidencia % no cerrada: %', NEW.id, SQLERRM;
  END;
  RETURN NULL;
END; $$;

DROP TRIGGER IF EXISTS close_reported_incident_conversation ON public.panelist_incident;
CREATE TRIGGER close_reported_incident_conversation
  AFTER UPDATE OF status ON public.panelist_incident
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status
                     AND NEW.status IN ('resolved','dismissed','auto_resolved'))
  EXECUTE FUNCTION public.tg_close_reported_incident_conversation();

CREATE OR REPLACE FUNCTION public.tg_close_unavailability_conversation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  BEGIN
    DELETE FROM panelist_context
     WHERE telegram_id = (SELECT telegram_id FROM panelists WHERE id = NEW.panelist_id)
       AND context_type = 'pending_incident_reply'
       AND context_data->>'incident_kind' = 'unavailability'
       AND context_data->>'incident_id' = NEW.id::text;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'tg_close_unavailability_conversation: conversacion de la baja % no cerrada: %', NEW.id, SQLERRM;
  END;
  RETURN NULL;
END; $$;

DROP TRIGGER IF EXISTS close_unavailability_conversation ON public.panelist_unavailability;
CREATE TRIGGER close_unavailability_conversation
  AFTER UPDATE OF incident_status ON public.panelist_unavailability
  FOR EACH ROW WHEN (OLD.incident_status IS DISTINCT FROM NEW.incident_status
                     AND NEW.incident_status = 'resolved')
  EXECUTE FUNCTION public.tg_close_unavailability_conversation();

REVOKE ALL ON FUNCTION public.tg_close_reported_incident_conversation() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.tg_close_unavailability_conversation() FROM PUBLIC, anon, authenticated;
