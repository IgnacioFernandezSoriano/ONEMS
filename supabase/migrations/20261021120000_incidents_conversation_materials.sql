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

-- ===== 2) Envios de material enlazados a la incidencia + agenda de preguntas por Telegram =====
ALTER TABLE public.material_shipments
  ADD COLUMN panelist_incident_id uuid REFERENCES public.panelist_incident(id) ON DELETE SET NULL,
  ADD COLUMN source_notified_at   timestamptz,
  ADD COLUMN ask_count            int NOT NULL DEFAULT 0,
  ADD COLUMN last_asked_at        timestamptz,
  ADD COLUMN next_ask_at          timestamptz;

ALTER TABLE public.material_shipments DROP CONSTRAINT IF EXISTS material_shipments_status_check;
ALTER TABLE public.material_shipments ADD CONSTRAINT material_shipments_status_check
  CHECK (status IN ('pending','sent','partially_received','received','cancelled'));

CREATE INDEX material_shipments_next_ask_idx
  ON public.material_shipments (next_ask_at) WHERE status IN ('pending','sent','partially_received');
CREATE INDEX material_shipments_incident_idx
  ON public.material_shipments (panelist_incident_id) WHERE panelist_incident_id IS NOT NULL;

-- Relleno: enlace inverso de los envios ya creados por el tratamiento de incidencias.
UPDATE public.material_shipments s
   SET panelist_incident_id = i.id
  FROM public.panelist_incident i
 WHERE i.linked_material_shipment_id = s.id AND s.panelist_incident_id IS NULL;

-- Preguntas de Telegram vencidas. El destinatario es el donante (donor_send_request) o el receptor
-- (receipt_question); debe tener telegram_id y ser de la misma cuenta que el envio. Solo service_role.
CREATE OR REPLACE FUNCTION public.due_material_questions(p_now timestamptz DEFAULT now())
RETURNS TABLE (shipment_id uuid, kind text, panelist_id uuid, telegram_id text, language text, ask_count int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT s.id, 'donor_send_request', p.id, p.telegram_id, p.language, s.ask_count
    FROM material_shipments s
    JOIN panelists p ON p.id = s.source_panelist_id AND p.account_id = s.account_id
   WHERE s.source_panelist_id IS NOT NULL AND s.status = 'pending' AND s.panelist_incident_id IS NOT NULL
     AND (s.source_notified_at IS NULL OR s.next_ask_at <= p_now)
     AND NULLIF(btrim(p.telegram_id), '') IS NOT NULL
  UNION ALL
  SELECT s.id, 'receipt_question', p.id, p.telegram_id, p.language, s.ask_count
    FROM material_shipments s
    JOIN panelists p ON p.id = s.panelist_id AND p.account_id = s.account_id
   WHERE s.status IN ('sent','partially_received') AND s.next_ask_at <= p_now
     AND NULLIF(btrim(p.telegram_id), '') IS NOT NULL
   ORDER BY 1, 2;
$$;

-- Registra que se hizo una pregunta: cuenta, marca y agenda la siguiente a 2 dias. Solo service_role.
CREATE OR REPLACE FUNCTION public.record_material_question(p_shipment_id uuid, p_kind text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_kind NOT IN ('donor_send_request','receipt_question') THEN
    RAISE EXCEPTION 'invalid question kind'; END IF;
  UPDATE material_shipments
     SET ask_count = ask_count + 1, last_asked_at = now(), next_ask_at = now() + interval '2 days',
         source_notified_at = CASE WHEN p_kind = 'donor_send_request'
                                   THEN COALESCE(source_notified_at, now()) ELSE source_notified_at END
   WHERE id = p_shipment_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'shipment not found'; END IF;
END; $$;

-- send_material_shipment: mismo cuerpo que 20260807100100 + agenda de la primera pregunta de recepcion.
CREATE OR REPLACE FUNCTION public.send_material_shipment(p_shipment_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ship   public.material_shipments%rowtype;
  v_item   record;
BEGIN
  SELECT * INTO v_ship FROM public.material_shipments WHERE id = p_shipment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'shipment % not found', p_shipment_id; END IF;
  PERFORM public.assert_same_account(v_ship.account_id);

  IF v_ship.status <> 'pending' THEN
    RETURN; -- idempotente: ya enviado/recibido/cancelado
  END IF;

  FOR v_item IN
    SELECT material_id, quantity_sent
      FROM public.material_shipment_items
     WHERE material_shipment_id = p_shipment_id
  LOOP
    IF v_ship.source_panelist_id IS NULL THEN
      -- Origen: almacen central del regulador.
      UPDATE public.material_stocks
         SET quantity = greatest(0, quantity - v_item.quantity_sent),
             last_updated = now()
       WHERE account_id = v_ship.account_id
         AND material_id = v_item.material_id;
    ELSE
      -- Origen: panelista donante.
      UPDATE public.panelist_material_stocks
         SET quantity = greatest(0, quantity - v_item.quantity_sent),
             last_updated = now()
       WHERE account_id = v_ship.account_id
         AND panelist_id = v_ship.source_panelist_id
         AND material_id = v_item.material_id;
    END IF;

    INSERT INTO public.material_movements
      (account_id, material_id, movement_type, quantity, reference_id, notes, created_by)
    VALUES
      (v_ship.account_id, v_item.material_id, 'dispatch', v_item.quantity_sent,
       p_shipment_id,
       CASE WHEN v_ship.source_panelist_id IS NULL
            THEN 'Dispatch central -> panelista'
            ELSE 'Dispatch donante -> panelista' END,
       auth.uid());
  END LOOP;

  UPDATE public.material_shipments
     SET status = 'sent', shipment_date = coalesce(shipment_date, now()),
         ask_count = 0,
         next_ask_at = CASE WHEN v_ship.source_panelist_id IS NULL
                            THEN COALESCE(v_ship.expected_date::timestamptz, now() + interval '2 days')
                            ELSE now() + interval '2 days' END
   WHERE id = p_shipment_id;
END;
$$;

REVOKE ALL ON FUNCTION public.due_material_questions(timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.due_material_questions(timestamptz) TO service_role;
REVOKE ALL ON FUNCTION public.record_material_question(uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_material_question(uuid,text) TO service_role;
REVOKE ALL ON FUNCTION public.send_material_shipment(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_material_shipment(uuid) TO authenticated, service_role;

-- ============================================================================
-- 3. Recepcion parcial de material y cierre de la incidencia SIN cancelar la baja
-- ============================================================================

-- Stub: la Tarea 4 lo sustituye por la liberacion real de envios retenidos.
CREATE OR REPLACE FUNCTION public.refresh_material_hold(p_panelist_id uuid)
RETURNS uuid[] LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT '{}'::uuid[];
$$;
REVOKE ALL ON FUNCTION public.refresh_material_hold(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_material_hold(uuid) TO service_role;

-- p_items = [{material_id, quantity}] con lo recibido en ESTA confirmacion.
CREATE OR REPLACE FUNCTION public.receive_material_shipment_items(p_shipment_id uuid, p_items jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ship      public.material_shipments%rowtype;
  v_el        jsonb;
  v_mat       uuid;
  v_qty       numeric;
  v_item      public.material_shipment_items%rowtype;
  v_incident  uuid;
  v_summary   text := '';
  v_name      text;
  v_complete  boolean;
  v_resolved  boolean := false;
  v_released  uuid[];
BEGIN
  SELECT * INTO v_ship FROM public.material_shipments WHERE id = p_shipment_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'shipment % not found', p_shipment_id; END IF;
  PERFORM public.assert_same_account(v_ship.account_id);

  IF v_ship.status = 'received' THEN
    RETURN jsonb_build_object('status','received','incident_resolved',false,'released_detail_ids','[]'::jsonb);
  END IF;
  IF v_ship.status NOT IN ('sent','partially_received') THEN
    RAISE EXCEPTION 'shipment % in status % cannot be received', p_shipment_id, v_ship.status;
  END IF;

  FOR v_el IN SELECT * FROM jsonb_array_elements(coalesce(p_items, '[]'::jsonb)) LOOP
    v_mat := (v_el->>'material_id')::uuid;
    v_qty := (v_el->>'quantity')::numeric;
    IF v_qty IS NULL OR v_qty < 0 THEN RAISE EXCEPTION 'invalid quantity'; END IF;

    SELECT * INTO v_item FROM public.material_shipment_items
     WHERE material_shipment_id = p_shipment_id AND material_id = v_mat
     FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'material not in shipment'; END IF;
    IF coalesce(v_item.quantity_received, 0) + v_qty > v_item.quantity_sent THEN
      RAISE EXCEPTION 'quantity exceeds sent'; END IF;

    IF v_qty > 0 THEN
      INSERT INTO public.panelist_material_stocks
        (account_id, panelist_id, material_id, quantity, last_updated)
      VALUES (v_ship.account_id, v_ship.panelist_id, v_mat, v_qty, now())
      ON CONFLICT (account_id, panelist_id, material_id)
      DO UPDATE SET quantity = public.panelist_material_stocks.quantity + excluded.quantity,
                    last_updated = now();

      UPDATE public.material_shipment_items
         SET quantity_received = coalesce(quantity_received, 0) + v_qty, updated_at = now()
       WHERE id = v_item.id;

      INSERT INTO public.material_movements
        (account_id, material_id, movement_type, quantity, reference_id, notes, created_by)
      VALUES (v_ship.account_id, v_mat, 'receipt', v_qty, p_shipment_id,
              'Recepcion confirmada por panelista', auth.uid());

      SELECT name INTO v_name FROM public.material_catalog WHERE id = v_mat;
      v_summary := v_summary || CASE WHEN v_summary = '' THEN '' ELSE ', ' END
                   || coalesce(v_name, v_mat::text) || ' ' || v_qty::text;
    END IF;
  END LOOP;

  SELECT NOT EXISTS (SELECT 1 FROM public.material_shipment_items
                      WHERE material_shipment_id = p_shipment_id
                        AND coalesce(quantity_received, 0) < quantity_sent)
    INTO v_complete;

  IF v_complete THEN
    UPDATE public.material_shipments
       SET status = 'received', received_date = now()
     WHERE id = p_shipment_id;
  ELSE
    UPDATE public.material_shipments
       SET status = 'partially_received', ask_count = 0, next_ask_at = now() + interval '2 days'
     WHERE id = p_shipment_id;
  END IF;

  -- Incidencia enlazada (o, por compatibilidad, la que apunta a este envio).
  v_incident := v_ship.panelist_incident_id;
  IF v_incident IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM public.panelist_incident
        WHERE id = v_incident AND account_id = v_ship.account_id AND panelist_id = v_ship.panelist_id) THEN
    v_incident := NULL;
  END IF;
  IF v_incident IS NULL THEN
    SELECT id INTO v_incident FROM public.panelist_incident
     WHERE linked_material_shipment_id = p_shipment_id
       AND account_id = v_ship.account_id AND panelist_id = v_ship.panelist_id
     ORDER BY created_at LIMIT 1;
  END IF;

  IF v_incident IS NOT NULL THEN
    IF v_summary <> '' THEN
      PERFORM public.log_incident_message('reported', v_incident, 'internal', 'system',
        'Recibido: ' || v_summary, jsonb_build_object('shipment_id', p_shipment_id));
    END IF;

    IF v_complete AND NOT EXISTS (
         SELECT 1 FROM public.material_shipments s
          WHERE s.status NOT IN ('cancelled', 'received')
            AND s.account_id = v_ship.account_id AND s.panelist_id = v_ship.panelist_id
            AND (s.panelist_incident_id = v_incident
                 OR s.id IN (SELECT linked_material_shipment_id FROM public.panelist_incident WHERE id = v_incident))
       ) THEN
      -- NO se toca panelist_unavailability: la baja sigue su curso.
      PERFORM public.resolve_panelist_incident(
        v_incident, 'resolved', 'Material recibido; disponibilidad restaurada.', NULL);
      PERFORM public.log_incident_message('reported', v_incident, 'internal', 'system',
        'Material recibido completo', jsonb_build_object('shipment_id', p_shipment_id));
      v_resolved := true;
    END IF;
  END IF;

  v_released := public.refresh_material_hold(v_ship.panelist_id);

  RETURN jsonb_build_object(
    'status', CASE WHEN v_complete THEN 'received' ELSE 'partially_received' END,
    'incident_resolved', v_resolved,
    'released_detail_ids', coalesce(to_jsonb(v_released), '[]'::jsonb));
END;
$$;

-- Boton antiguo: recibe todo lo pendiente; ya no cancela la baja.
CREATE OR REPLACE FUNCTION public.receive_material_shipment(p_shipment_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ship  public.material_shipments%rowtype;
  v_items jsonb;
BEGIN
  SELECT * INTO v_ship FROM public.material_shipments WHERE id = p_shipment_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'shipment % not found', p_shipment_id; END IF;
  PERFORM public.assert_same_account(v_ship.account_id);
  IF v_ship.status = 'received' THEN RETURN; END IF;
  IF v_ship.status NOT IN ('sent','partially_received') THEN
    RAISE EXCEPTION 'shipment % in status % cannot be received', p_shipment_id, v_ship.status;
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'material_id', material_id,
           'quantity', quantity_sent - coalesce(quantity_received, 0))), '[]'::jsonb)
    INTO v_items
    FROM public.material_shipment_items
   WHERE material_shipment_id = p_shipment_id;

  PERFORM public.receive_material_shipment_items(p_shipment_id, v_items);
END;
$$;

CREATE OR REPLACE FUNCTION public.material_shipment_incident_same_account_check()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.panelist_incident_id IS NOT NULL AND
     (SELECT account_id FROM public.panelist_incident WHERE id = NEW.panelist_incident_id) IS DISTINCT FROM NEW.account_id THEN
    RAISE EXCEPTION 'incident belongs to another account'; END IF;
  RETURN NEW;
END; $$;
CREATE TRIGGER material_shipment_incident_same_account
  BEFORE INSERT OR UPDATE OF panelist_incident_id, account_id ON public.material_shipments
  FOR EACH ROW EXECUTE FUNCTION public.material_shipment_incident_same_account_check();

REVOKE ALL ON FUNCTION public.receive_material_shipment_items(uuid,jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.receive_material_shipment_items(uuid,jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.receive_material_shipment(uuid) TO authenticated, service_role;

-- ============================================================================
-- 4. Envios parados por falta de material (material_hold)
-- ============================================================================
CREATE TABLE public.material_hold (
  allocation_plan_detail_id uuid PRIMARY KEY REFERENCES public.allocation_plan_details(id) ON DELETE CASCADE,
  account_id  uuid NOT NULL,
  panelist_id uuid NOT NULL,
  held_since  timestamptz NOT NULL DEFAULT now(),
  released_at timestamptz
);
CREATE INDEX material_hold_panelist_idx ON public.material_hold (panelist_id) WHERE released_at IS NULL;

ALTER TABLE public.material_hold ENABLE ROW LEVEL SECURITY;
CREATE POLICY material_hold_select ON public.material_hold
  FOR SELECT TO authenticated
  USING (account_id = current_user_account_id() OR is_superadmin());
REVOKE ALL ON public.material_hold FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.material_hold TO authenticated;
GRANT ALL ON public.material_hold TO service_role;

-- Recalcula que envios del panelista (como emisor) quedan retenidos por falta de stock.
-- Sin incidencia missing_materials abierta, libera todo. Devuelve los ids recien liberados
-- que siguen en el conjunto actual de envios del panelista.
CREATE OR REPLACE FUNCTION public.refresh_material_hold(p_panelist_id uuid)
RETURNS uuid[] LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_acc      uuid;
  v_node     uuid;
  v_open     boolean;
  v_set      uuid[];
  v_stock    jsonb;
  v_det      record;
  v_req      record;
  v_held     boolean;
  v_rem      numeric;
  v_released uuid[] := '{}';
  v_id       uuid;
BEGIN
  SELECT account_id, node_id INTO v_acc, v_node FROM panelists WHERE id = p_panelist_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'panelist not found'; END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended(p_panelist_id::text, 0));

  SELECT coalesce(array_agg(d.id), '{}') INTO v_set
    FROM allocation_plan_details d
   WHERE d.origin_node_id = v_node AND d.account_id = v_acc
     AND d.status IN ('pending','notified') AND d.fecha_programada >= current_date;

  -- Retenciones de envios que ya no estan en el conjunto (movidos, cancelados, pasados): se cierran sin devolverse.
  UPDATE material_hold SET released_at = now()
   WHERE panelist_id = p_panelist_id AND released_at IS NULL AND NOT (allocation_plan_detail_id = ANY (v_set));

  SELECT EXISTS (SELECT 1 FROM panelist_incident
                  WHERE panelist_id = p_panelist_id AND category = 'missing_materials'
                    AND status IN ('open','in_progress'))
    INTO v_open;

  IF NOT v_open THEN
    WITH r AS (
      UPDATE material_hold SET released_at = now()
       WHERE panelist_id = p_panelist_id AND released_at IS NULL
       RETURNING allocation_plan_detail_id)
    SELECT coalesce(array_agg(r.allocation_plan_detail_id ORDER BY d.fecha_programada, d.id), '{}') INTO v_released
      FROM r JOIN allocation_plan_details d ON d.id = r.allocation_plan_detail_id
     WHERE r.allocation_plan_detail_id = ANY (v_set);
    RETURN v_released;
  END IF;

  SELECT coalesce(jsonb_object_agg(material_id::text, quantity), '{}'::jsonb) INTO v_stock
    FROM panelist_material_stocks WHERE panelist_id = p_panelist_id AND account_id = v_acc;

  FOR v_det IN
    SELECT d.id, p.product_id
      FROM allocation_plan_details d
      JOIN allocation_plans p ON p.id = d.plan_id
     WHERE d.id = ANY (v_set)
     ORDER BY d.fecha_programada, d.id
  LOOP
    v_held := false;
    FOR v_req IN SELECT material_id, sum(coalesce(quantity, 0)) AS qty FROM product_materials WHERE product_id = v_det.product_id GROUP BY material_id LOOP
      IF coalesce((v_stock->>v_req.material_id::text)::numeric, 0) < v_req.qty THEN
        v_held := true; EXIT;
      END IF;
    END LOOP;

    IF v_held THEN
      INSERT INTO material_hold (allocation_plan_detail_id, account_id, panelist_id)
      VALUES (v_det.id, v_acc, p_panelist_id)
      ON CONFLICT (allocation_plan_detail_id) DO UPDATE
        SET held_since  = CASE WHEN material_hold.released_at IS NULL THEN material_hold.held_since ELSE now() END,
            released_at = NULL,
            panelist_id = excluded.panelist_id;
    ELSE
      FOR v_req IN SELECT material_id, sum(coalesce(quantity, 0)) AS qty FROM product_materials WHERE product_id = v_det.product_id GROUP BY material_id LOOP
        v_rem := coalesce((v_stock->>v_req.material_id::text)::numeric, 0) - v_req.qty;
        v_stock := jsonb_set(v_stock, ARRAY[v_req.material_id::text], to_jsonb(v_rem), true);
      END LOOP;
      v_id := NULL;
      UPDATE material_hold SET released_at = now()
       WHERE allocation_plan_detail_id = v_det.id AND released_at IS NULL
       RETURNING allocation_plan_detail_id INTO v_id;
      IF v_id IS NOT NULL THEN v_released := v_released || v_id; END IF;
    END IF;
  END LOOP;

  RETURN v_released;
END; $$;

CREATE OR REPLACE FUNCTION public.panelist_held_detail_ids(p_panelist_id uuid)
RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT allocation_plan_detail_id FROM material_hold
   WHERE panelist_id = p_panelist_id AND released_at IS NULL;
$$;

REVOKE ALL ON FUNCTION public.refresh_material_hold(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_material_hold(uuid) TO service_role;
REVOKE ALL ON FUNCTION public.panelist_held_detail_ids(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.panelist_held_detail_ids(uuid) TO service_role;

-- ===== 5) avisos y respuestas a la conversacion =====
-- Nueva clase de aviso: el material retenido de una incidencia vuelve a estar disponible.
ALTER TABLE public.panelist_notification DROP CONSTRAINT IF EXISTS panelist_notification_kind_check;
ALTER TABLE public.panelist_notification ADD CONSTRAINT panelist_notification_kind_check
  CHECK (kind IN ('unavailability_received','plan_change_this_week','material_pending_released'));

-- Al pasar un aviso a 'sent' se deja en la conversacion de su incidencia. Nunca aborta el UPDATE.
CREATE OR REPLACE FUNCTION public.tg_log_notification_to_conversation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_kind text; v_id uuid;
BEGIN
  BEGIN
    IF NEW.payload ? 'incident_kind' AND NEW.payload ? 'incident_id' THEN
      v_kind := NEW.payload->>'incident_kind';
      v_id := (NEW.payload->>'incident_id')::uuid;
    ELSIF NEW.kind IN ('unavailability_received','plan_change_this_week') AND NEW.payload ? 'unavailability_id' THEN
      v_kind := 'unavailability';
      v_id := (NEW.payload->>'unavailability_id')::uuid;
    END IF;
    IF v_kind IS NOT NULL AND v_id IS NOT NULL THEN
      PERFORM public.log_incident_message(v_kind, v_id, 'outbound', 'bot',
        COALESCE(NEW.payload->>'text', NEW.kind),
        jsonb_build_object('notification_id', NEW.id, 'kind', NEW.kind), 'sent');
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'tg_log_notification_to_conversation: aviso % no registrado: %', NEW.id, SQLERRM;
  END;
  RETURN NULL;
END; $$;

DROP TRIGGER IF EXISTS log_notification_to_conversation ON public.panelist_notification;
CREATE TRIGGER log_notification_to_conversation
  AFTER UPDATE OF status ON public.panelist_notification
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'sent')
  EXECUTE FUNCTION public.tg_log_notification_to_conversation();

-- Respuesta del manager entregada por el flujo antiguo (reply_status -> 'sent'): queda en la conversacion.
CREATE OR REPLACE FUNCTION public.tg_log_reply_to_conversation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  BEGIN
    PERFORM public.log_incident_message('reported', NEW.id, 'outbound', 'manager', NEW.reply_to_panelist,
      jsonb_build_object('via', 'legacy_reply', 'manager_user_id', NEW.resolved_by), 'sent');
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'tg_log_reply_to_conversation: respuesta de la incidencia % no registrada: %', NEW.id, SQLERRM;
  END;
  RETURN NULL;
END; $$;

DROP TRIGGER IF EXISTS log_reply_to_conversation ON public.panelist_incident;
CREATE TRIGGER log_reply_to_conversation
  AFTER UPDATE OF reply_status ON public.panelist_incident
  FOR EACH ROW WHEN (OLD.reply_status IS DISTINCT FROM NEW.reply_status AND NEW.reply_status = 'sent'
                     AND NEW.reply_to_panelist IS NOT NULL)
  EXECUTE FUNCTION public.tg_log_reply_to_conversation();

REVOKE ALL ON FUNCTION public.tg_log_notification_to_conversation() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.tg_log_reply_to_conversation() FROM PUBLIC, anon, authenticated;

-- Mismo cuerpo y permisos que antes; ademas deja el cambio de estado en la conversacion.
CREATE OR REPLACE FUNCTION public.resolve_panelist_incident(
  p_incident_id uuid, p_status text,
  p_resolution_note text DEFAULT NULL, p_reply_text text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid; v_old text;
BEGIN
  SELECT account_id, status INTO v_account, v_old FROM panelist_incident WHERE id = p_incident_id;
  PERFORM assert_same_account(v_account);
  IF p_status NOT IN ('open','in_progress','resolved','dismissed') THEN
    RAISE EXCEPTION 'invalid status %', p_status; END IF;
  UPDATE panelist_incident SET
    status = p_status,
    resolution_note = COALESCE(p_resolution_note, resolution_note),
    reply_to_panelist = COALESCE(p_reply_text, reply_to_panelist),
    reply_status = CASE WHEN p_reply_text IS NOT NULL THEN 'pending_send' ELSE reply_status END,
    resolved_by = CASE WHEN p_status IN ('resolved','dismissed') THEN auth.uid() ELSE resolved_by END,
    resolved_at = CASE WHEN p_status IN ('resolved','dismissed') THEN now() ELSE resolved_at END,
    updated_at = now()
  WHERE id = p_incident_id;
  IF v_old IS DISTINCT FROM p_status THEN
    BEGIN
      PERFORM public.log_incident_message('reported', p_incident_id, 'internal', 'system',
        'Estado: ' || p_status || COALESCE(' — ' || p_resolution_note, ''),
        jsonb_build_object('status', p_status), 'sent');
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'resolve_panelist_incident: estado de la incidencia % no registrado: %', p_incident_id, SQLERRM;
    END;
  END IF;
END; $$;
