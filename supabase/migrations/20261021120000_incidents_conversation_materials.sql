-- Conversacion registrada de incidencias + materiales. Forward-only. NO toca el baseline.
-- Cada seccion la anade una tarea del plan; ver docs/superpowers/plans/ (plan 4, BD materiales y conversacion).

-- ===== 1) incident_message: conversacion registrada de todas las incidencias =====
CREATE TABLE public.incident_message (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id          uuid NOT NULL,
  panelist_id         uuid NOT NULL,
  incident_kind       text NOT NULL CHECK (incident_kind IN ('reported','unavailability')),
  incident_id         uuid NOT NULL,
  direction           text NOT NULL CHECK (direction IN ('outbound','inbound','internal')),
  author              text NOT NULL CHECK (author IN ('bot','panelist','manager','system')),
  body                text NOT NULL DEFAULT '',
  meta                jsonb NOT NULL DEFAULT '{}'::jsonb,
  status              text NOT NULL CHECK (status IN ('pending_send','sent','failed','received')),
  sent_at             timestamptz,
  error               text,
  telegram_message_id text,
  created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX incident_message_incident_idx
  ON public.incident_message (incident_kind, incident_id, created_at);
CREATE INDEX incident_message_pending_idx
  ON public.incident_message (status) WHERE status = 'pending_send';

ALTER TABLE public.incident_message ENABLE ROW LEVEL SECURITY;
CREATE POLICY incident_message_select ON public.incident_message
  FOR SELECT TO authenticated
  USING (account_id = current_user_account_id() OR is_superadmin());
REVOKE ALL ON public.incident_message FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.incident_message TO authenticated;
GRANT ALL ON public.incident_message TO service_role;

-- Registra un mensaje de la conversacion. Deriva account_id y panelist_id de la incidencia.
-- p_status NULL: outbound -> pending_send, inbound -> received, internal -> sent.
CREATE OR REPLACE FUNCTION public.log_incident_message(
  p_incident_kind text, p_incident_id uuid, p_direction text, p_author text,
  p_body text, p_meta jsonb DEFAULT '{}'::jsonb, p_status text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid; v_panelist uuid; v_status text; v_new uuid;
BEGIN
  IF p_incident_kind = 'reported' THEN
    SELECT account_id, panelist_id INTO v_account, v_panelist
      FROM panelist_incident WHERE id = p_incident_id;
  ELSIF p_incident_kind = 'unavailability' THEN
    SELECT account_id, panelist_id INTO v_account, v_panelist
      FROM panelist_unavailability WHERE id = p_incident_id;
  ELSE
    RAISE EXCEPTION 'invalid incident kind';
  END IF;
  IF v_account IS NULL THEN RAISE EXCEPTION 'incident not found'; END IF;
  PERFORM assert_same_account(v_account);
  IF NOT EXISTS (SELECT 1 FROM panelists WHERE id = v_panelist AND account_id = v_account) THEN
    RAISE EXCEPTION 'Cross-tenant access denied'; END IF;
  v_status := COALESCE(p_status, CASE p_direction
    WHEN 'outbound' THEN 'pending_send'
    WHEN 'inbound'  THEN 'received'
    ELSE 'sent' END);
  INSERT INTO incident_message (account_id, panelist_id, incident_kind, incident_id,
                                direction, author, body, meta, status)
  VALUES (v_account, v_panelist, p_incident_kind, p_incident_id,
          p_direction, p_author, COALESCE(p_body, ''), COALESCE(p_meta, '{}'::jsonb), v_status)
  RETURNING id INTO v_new;
  RETURN v_new;
END; $$;

-- Mensaje del manager desde la web: sale por Telegram via la cola pending_send.
CREATE OR REPLACE FUNCTION public.send_manager_message(
  p_incident_kind text, p_incident_id uuid, p_body text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid; v_panelist uuid; v_new uuid;
BEGIN
  IF p_incident_kind = 'reported' THEN
    SELECT account_id, panelist_id INTO v_account, v_panelist
      FROM panelist_incident WHERE id = p_incident_id;
  ELSIF p_incident_kind = 'unavailability' THEN
    SELECT account_id, panelist_id INTO v_account, v_panelist
      FROM panelist_unavailability WHERE id = p_incident_id;
  ELSE
    RAISE EXCEPTION 'invalid incident kind';
  END IF;
  IF v_account IS NULL THEN RAISE EXCEPTION 'incident not found'; END IF;
  PERFORM assert_same_account(v_account);
  IF NOT EXISTS (SELECT 1 FROM panelists WHERE id = v_panelist AND account_id = v_account) THEN
    RAISE EXCEPTION 'Cross-tenant access denied'; END IF;
  IF NULLIF(btrim(p_body), '') IS NULL THEN RAISE EXCEPTION 'empty message'; END IF;
  INSERT INTO incident_message (account_id, panelist_id, incident_kind, incident_id,
                                direction, author, body, meta, status)
  VALUES (v_account, v_panelist, p_incident_kind, p_incident_id,
          'outbound', 'manager', btrim(p_body),
          jsonb_build_object('manager_user_id', auth.uid()), 'pending_send')
  RETURNING id INTO v_new;
  RETURN v_new;
END; $$;

-- n8n confirma el resultado del envio por Telegram. Solo service_role.
CREATE OR REPLACE FUNCTION public.mark_incident_message_sent(
  p_id uuid, p_ok boolean, p_error text DEFAULT NULL, p_telegram_message_id text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE incident_message
     SET status = CASE WHEN p_ok THEN 'sent' ELSE 'failed' END,
         sent_at = CASE WHEN p_ok THEN now() ELSE sent_at END,
         error = CASE WHEN p_ok THEN NULL ELSE p_error END,
         telegram_message_id = COALESCE(p_telegram_message_id, telegram_message_id)
   WHERE id = p_id AND direction = 'outbound';
  IF NOT FOUND THEN RAISE EXCEPTION 'message not found'; END IF;
END; $$;

-- Cola de salida para n8n: reclama de forma atomica los outbound pending_send de panelistas con
-- telegram_id (marca meta.claimed_at; un reclamo caduca a los 10 min). Solo service_role.
CREATE OR REPLACE FUNCTION public.pending_incident_messages(p_limit int DEFAULT 50)
RETURNS TABLE (id uuid, account_id uuid, panelist_id uuid, incident_kind text, incident_id uuid,
               body text, meta jsonb, created_at timestamptz, telegram_id text, language text)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path = public AS $$
  WITH claimed AS (
    UPDATE incident_message u
       SET meta = u.meta || jsonb_build_object('claimed_at', now())
     WHERE u.id IN (
       SELECT m.id FROM incident_message m
         JOIN panelists p ON p.id = m.panelist_id AND p.account_id = m.account_id
        WHERE m.direction = 'outbound' AND m.status = 'pending_send'
          AND NULLIF(btrim(p.telegram_id), '') IS NOT NULL
          AND (m.meta->>'claimed_at' IS NULL
               OR (m.meta->>'claimed_at')::timestamptz < now() - interval '10 minutes')
        ORDER BY m.created_at, m.id
        LIMIT p_limit
        FOR UPDATE OF m SKIP LOCKED)
    RETURNING u.id, u.account_id, u.panelist_id, u.incident_kind, u.incident_id,
              u.body, u.meta, u.created_at
  )
  SELECT c.id, c.account_id, c.panelist_id, c.incident_kind, c.incident_id,
         c.body, c.meta, c.created_at, p.telegram_id, p.language
    FROM claimed c JOIN panelists p ON p.id = c.panelist_id
   ORDER BY c.created_at, c.id;
$$;

-- El panelista de una incidencia debe ser de la misma cuenta (RLS de panelist_incident solo mira account_id).
CREATE OR REPLACE FUNCTION public.panelist_incident_same_account_check()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF (SELECT account_id FROM panelists WHERE id = NEW.panelist_id) IS DISTINCT FROM NEW.account_id THEN
    RAISE EXCEPTION 'panelist belongs to another account'; END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER panelist_incident_same_account
  BEFORE INSERT OR UPDATE OF panelist_id, account_id ON public.panelist_incident
  FOR EACH ROW EXECUTE FUNCTION public.panelist_incident_same_account_check();

REVOKE ALL ON FUNCTION public.log_incident_message(text,uuid,text,text,text,jsonb,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.log_incident_message(text,uuid,text,text,text,jsonb,text) TO service_role;
REVOKE ALL ON FUNCTION public.send_manager_message(text,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_manager_message(text,uuid,text) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.mark_incident_message_sent(uuid,boolean,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mark_incident_message_sent(uuid,boolean,text,text) TO service_role;
REVOKE ALL ON FUNCTION public.pending_incident_messages(int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pending_incident_messages(int) TO service_role;
