-- Los casos de recepcion (receipt_case) tienen conversacion en incident_message, y el manager puede
-- escribir a otro panelista del caso. Forward-only. NO toca el baseline.
-- Plan agente de analisis de casos, Tarea 1.

-- ===== 1) incident_kind admite 'receipt' (incident_id = receipt_case.id) =====
ALTER TABLE public.incident_message DROP CONSTRAINT incident_message_incident_kind_check;
ALTER TABLE public.incident_message
  ADD CONSTRAINT incident_message_incident_kind_check
  CHECK (incident_kind IN ('reported','unavailability','receipt'));

-- ===== 2) Un mismo borrador del agente solo puede enviarse una vez =====
CREATE UNIQUE INDEX incident_message_case_draft_key_uq
  ON public.incident_message ((meta->>'case_draft_key'))
  WHERE meta ? 'case_draft_key' AND meta->>'case_draft_key' IS NOT NULL;

-- ===== 3) Helper: cuenta y panelista de una incidencia segun su tipo =====
-- Tipo desconocido o id inexistente: sin filas. Solo service_role y las funciones definer.
CREATE OR REPLACE FUNCTION public.incident_owner(p_kind text, p_id uuid)
RETURNS TABLE (account_id uuid, panelist_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT i.account_id, i.panelist_id FROM panelist_incident i
   WHERE p_kind = 'reported' AND i.id = p_id
  UNION ALL
  SELECT u.account_id, u.panelist_id FROM panelist_unavailability u
   WHERE p_kind = 'unavailability' AND u.id = p_id
  UNION ALL
  SELECT c.account_id, c.panelist_id FROM receipt_case c
   WHERE p_kind = 'receipt' AND c.id = p_id;
$$;
REVOKE ALL ON FUNCTION public.incident_owner(text,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.incident_owner(text,uuid) TO service_role;

-- ===== 4) log_incident_message: 8 argumentos (p_panelist_id opcional) =====
-- Sustituye a la de 7 argumentos; las llamadas posicionales de n8n con 7 siguen valiendo.
DROP FUNCTION public.log_incident_message(text, uuid, text, text, text, jsonb, text);
CREATE FUNCTION public.log_incident_message(
  p_incident_kind text, p_incident_id uuid, p_direction text, p_author text,
  p_body text, p_meta jsonb DEFAULT '{}'::jsonb, p_status text DEFAULT NULL,
  p_panelist_id uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid; v_panelist uuid; v_status text; v_new uuid;
BEGIN
  IF p_incident_kind NOT IN ('reported','unavailability','receipt') THEN
    RAISE EXCEPTION 'invalid incident kind'; END IF;
  SELECT o.account_id, o.panelist_id INTO v_account, v_panelist
    FROM public.incident_owner(p_incident_kind, p_incident_id) o;
  IF v_account IS NULL THEN RAISE EXCEPTION 'incident not found'; END IF;
  PERFORM assert_same_account(v_account);
  v_panelist := COALESCE(p_panelist_id, v_panelist);
  IF v_panelist IS NULL THEN RAISE EXCEPTION 'incident not found'; END IF;
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
REVOKE ALL ON FUNCTION public.log_incident_message(text,uuid,text,text,text,jsonb,text,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.log_incident_message(text,uuid,text,text,text,jsonb,text,uuid) TO service_role;

-- ===== 5) send_case_message: como send_manager_message, con destinatario explicito =====
-- Sale por Telegram via la cola pending_send. p_draft_key (opcional) impide enviar dos veces el mismo borrador.
CREATE FUNCTION public.send_case_message(
  p_incident_kind text, p_incident_id uuid, p_panelist_id uuid, p_body text, p_draft_key text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid; v_new uuid;
BEGIN
  IF p_incident_kind NOT IN ('reported','unavailability','receipt') THEN
    RAISE EXCEPTION 'invalid incident kind'; END IF;
  SELECT o.account_id INTO v_account FROM public.incident_owner(p_incident_kind, p_incident_id) o;
  IF v_account IS NULL THEN RAISE EXCEPTION 'incident not found'; END IF;
  PERFORM assert_same_account(v_account);
  -- la pantalla de errores de recepcion es solo para admins de la cuenta
  IF p_incident_kind = 'receipt' THEN PERFORM public.receipt_mgr_check(v_account); END IF;
  IF p_panelist_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM panelists WHERE id = p_panelist_id AND account_id = v_account) THEN
    RAISE EXCEPTION 'Cross-tenant access denied'; END IF;
  IF NULLIF(btrim(p_body), '') IS NULL THEN RAISE EXCEPTION 'empty message'; END IF;
  IF NOT EXISTS (SELECT 1 FROM panelists WHERE id = p_panelist_id AND NULLIF(btrim(telegram_id), '') IS NOT NULL) THEN
    RAISE EXCEPTION 'panelist has no telegram'; END IF;
  INSERT INTO incident_message (account_id, panelist_id, incident_kind, incident_id,
                                direction, author, body, meta, status)
  VALUES (v_account, p_panelist_id, p_incident_kind, p_incident_id,
          'outbound', 'manager', btrim(p_body),
          jsonb_build_object('manager_user_id', auth.uid(), 'case_draft_key', p_draft_key), 'pending_send')
  RETURNING id INTO v_new;
  RETURN v_new;
END; $$;
REVOKE ALL ON FUNCTION public.send_case_message(text,uuid,uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_case_message(text,uuid,uuid,text,text) TO authenticated;

-- ===== 6) mark_incident_conversation_read admite 'receipt' =====
CREATE OR REPLACE FUNCTION public.mark_incident_conversation_read(p_incident_kind text, p_incident_id uuid)
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid; v_n int;
BEGIN
  IF p_incident_kind NOT IN ('reported','unavailability','receipt') THEN
    RAISE EXCEPTION 'invalid incident kind'; END IF;
  SELECT o.account_id INTO v_account FROM public.incident_owner(p_incident_kind, p_incident_id) o;
  IF v_account IS NULL THEN RAISE EXCEPTION 'incident not found'; END IF;
  PERFORM assert_same_account(v_account);
  UPDATE incident_message
     SET read_at = now()
   WHERE incident_kind = p_incident_kind AND incident_id = p_incident_id
     AND account_id = v_account AND direction = 'inbound' AND read_at IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END; $$;
REVOKE ALL ON FUNCTION public.mark_incident_conversation_read(text,uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_incident_conversation_read(text,uuid) TO authenticated, service_role;

-- ===== 7) RLS: paridad con receipt_case (solo admins de la cuenta o superadmin ven los casos de recepcion) =====
-- Sin esto, un usuario normal de la cuenta podria leer los mensajes de los casos de recepcion.
DROP POLICY IF EXISTS incident_message_select ON public.incident_message;
CREATE POLICY incident_message_select ON public.incident_message
  FOR SELECT TO authenticated
  USING (
    is_superadmin()
    OR (incident_kind <> 'receipt' AND account_id = current_user_account_id())
    OR (incident_kind = 'receipt' AND current_user_role() = 'admin' AND account_id = current_user_account_id())
  );
