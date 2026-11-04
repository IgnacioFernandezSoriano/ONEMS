-- Envios no recibidos a tiempo: plazo de 7 -> 15 dias y rescate de entregas tardias.
-- Decision del usuario 2026-11-04 (casos de Patrick Kyalo, Kenya: 4 paquetes en mano rechazados por el bot).
--
-- Antes: el flujo n8n "On parcel not received, notify Manager" anulaba cada dia los envios 'sent' con mas de 7 dias
-- (status 'cancelled', sin motivo ni fecha). Si el paquete llegaba despues, el bot lo rechazaba como 'blocked' y la
-- muestra se perdia sin compensar. Ahora:
--   * el flujo n8n usa 15 dias y marca cancellation_reason = 'not_received_timeout' + cancelled_at (cambio en n8n);
--   * los anulados por plazo que hoy estan dentro de 15 dias vuelven a 'sent' (siguen en transito); los demas quedan
--     marcados con el motivo nuevo;
--   * un envio anulado SOLO por plazo se reactiva si el panelista declara su recepcion (entrega tardia, con la fecha
--     del intento), tanto con la etiqueta exacta como por la regla de tecleo o misma ciudad.
-- Copia de seguridad del estado anterior: tabla backup_timeout_cancel_20261104.
--
-- Re-emite completas receipt_typo_candidates y receipt_match_tag (ultima version en 20261104124000).

SET lock_timeout = '5s';

-- ============================================================================================================
-- 1. Motivo nuevo de anulacion
-- ============================================================================================================
ALTER TABLE public.allocation_plan_details DROP CONSTRAINT IF EXISTS allocation_plan_details_cancellation_reason_check;
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT allocation_plan_details_cancellation_reason_check
  CHECK (cancellation_reason IS NULL OR cancellation_reason IN
         ('pobox_absent_unavailable', 'pobox_absent_no_visit', 'receipt_before_sent', 'received_wrong_city',
          'not_received_timeout')) NOT VALID;
ALTER TABLE public.allocation_plan_details VALIDATE CONSTRAINT allocation_plan_details_cancellation_reason_check;

-- ============================================================================================================
-- 2. Anulaciones antiguas por plazo: copia, vuelta a 'sent' si estan dentro de 15 dias, motivo si no
-- ============================================================================================================
-- Firma de la anulacion por plazo (unico camino que anula un envio declarado sin motivo): cancelled, sin motivo,
-- declarado, no recibido y sin muestra por compensar.
CREATE TABLE IF NOT EXISTS public.backup_timeout_cancel_20261104 AS
SELECT d.id, d.status, d.cancellation_reason, d.cancelled_at, d.updated_at, d.sent_at, now() AS backed_up_at
  FROM public.allocation_plan_details d
 WHERE d.status = 'cancelled' AND d.cancellation_reason IS NULL AND d.sent_at IS NOT NULL AND d.received_at IS NULL
   AND NOT EXISTS (SELECT 1 FROM public.deferred_samples ds WHERE ds.row_snapshot->>'id' = d.id::text);
ALTER TABLE public.backup_timeout_cancel_20261104 ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.backup_timeout_cancel_20261104 FROM PUBLIC, anon, authenticated;

UPDATE public.allocation_plan_details d
   SET status = 'sent', cancellation_reason = NULL, cancelled_at = NULL
  FROM public.backup_timeout_cancel_20261104 b
 WHERE d.id = b.id AND d.status = 'cancelled' AND d.cancellation_reason IS NULL
   AND d.sent_at > now() - interval '15 days';

UPDATE public.allocation_plan_details d
   SET cancellation_reason = 'not_received_timeout', cancelled_at = COALESCE(d.cancelled_at, b.updated_at)
  FROM public.backup_timeout_cancel_20261104 b
 WHERE d.id = b.id AND d.status = 'cancelled' AND d.cancellation_reason IS NULL;

-- ============================================================================================================
-- 3. Reactivar un envio anulado solo por plazo (entrega tardia)
-- ============================================================================================================
-- Vuelve a 'sent' si estaba anulado por plazo, sin recepcion y sin muestra por compensar. Devuelve si lo reactivo.
CREATE OR REPLACE FUNCTION public.revive_timeout_detail(p_detail_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.allocation_plan_details d
     SET status = 'sent', cancellation_reason = NULL, cancelled_at = NULL
   WHERE d.id = p_detail_id
     AND d.status = 'cancelled' AND d.cancellation_reason = 'not_received_timeout' AND d.received_at IS NULL
     AND NOT EXISTS (SELECT 1 FROM public.deferred_samples ds WHERE ds.row_snapshot->>'id' = d.id::text);
  RETURN FOUND;
END;
$$;

-- ============================================================================================================
-- 4. Candidatos por tecleo: tambien los anulados por plazo
-- ============================================================================================================
CREATE OR REPLACE FUNCTION public.receipt_typo_candidates(p_account_id uuid, p_city_id uuid, p_tag text,
                                                          p_max_sent_at timestamptz)
RETURNS SETOF uuid
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT x.id
    FROM public.allocation_plan_details x
    JOIN public.nodes n ON n.id = x.destination_node_id
   WHERE x.account_id = p_account_id
     AND n.city_id = p_city_id
     AND (x.status = 'sent' OR (x.status = 'cancelled' AND x.cancellation_reason = 'not_received_timeout'
                                AND x.received_at IS NULL))
     AND x.sent_at IS NOT NULL
     AND x.sent_at <= p_max_sent_at
     AND p_tag ~ '^[0-9]+$'
     AND x.tag_id ~ '^[0-9]+$'
     AND length(x.tag_id) = length(p_tag)
     AND x.tag_id <> p_tag
     AND (SELECT CASE WHEN count(*) = 1 THEN true
                      WHEN count(*) = 2 THEN max(g.i) - min(g.i) = 1
                                         AND substr(x.tag_id, min(g.i), 1) = substr(p_tag, max(g.i), 1)
                                         AND substr(x.tag_id, max(g.i), 1) = substr(p_tag, min(g.i), 1)
                      ELSE false END
            FROM generate_series(1, length(p_tag)) g(i)
           WHERE substr(x.tag_id, g.i, 1) <> substr(p_tag, g.i, 1));
$$;

-- ============================================================================================================
-- 5. Busqueda de la etiqueta: un anulado por plazo cuenta como 'sent' (se reactiva antes de registrar)
-- ============================================================================================================
-- Igual que 20261104124000 salvo: en los pasos 1 y 2 (misma ciudad) un envio anulado por plazo se reactiva y se
-- registra; en el paso 3 el candidato por tecleo se reactiva antes de corregir su etiqueta. Un anulado por plazo
-- hacia OTRA ciudad sigue siendo other_city_tag (no se toca).
CREATE OR REPLACE FUNCTION public.receipt_match_tag(p_account_id uuid, p_panelist_id uuid, p_panelist_name text,
                                                    p_node_id uuid, p_tag_norm text, p_tag_raw text,
                                                    p_recv_at timestamptz,
                                                    OUT outcome text, OUT detail_id uuid, OUT original_tag text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_city uuid;
  v_det_id uuid;
  v_det_status text;
  v_det_reason text;
  v_det_dest uuid;
  v_det_city uuid;
  v_det_sent timestamptz;
  v_res text;
  v_cancel_reason text;
  v_n int;
BEGIN
  SELECT n.city_id INTO v_city FROM public.nodes n WHERE n.id = p_node_id;

  -- 1. Envio con esa etiqueta hacia su nodo ('sent' primero, el mas antiguo; si no, el no-sent mas reciente).
  SELECT x.id, x.status, x.cancellation_reason INTO v_det_id, v_det_status, v_det_reason
    FROM public.allocation_plan_details x
   WHERE x.account_id = p_account_id AND x.destination_node_id = p_node_id AND x.tag_id = p_tag_norm
   ORDER BY (x.status = 'sent') DESC,
            CASE WHEN x.status = 'sent' THEN x.fecha_programada END ASC,
            x.fecha_programada DESC
   LIMIT 1;

  IF FOUND THEN
    detail_id := v_det_id;
    IF v_det_status = 'cancelled' AND v_det_reason = 'not_received_timeout'
       AND public.revive_timeout_detail(v_det_id) THEN
      v_det_status := 'sent';
    END IF;
    IF v_det_status = 'sent' THEN
      -- 'ok', el motivo POBOX, o already_received / blocked / not_sent_cancelled tras bloquear la fila
      outcome := public.register_receipt_with_rules(v_det_id, p_recv_at, p_panelist_id);
    ELSIF v_det_status = 'received' THEN
      outcome := 'already_received';
    ELSIF v_det_status IN ('pending', 'notified') THEN
      v_cancel_reason := 'receipt_before_sent';
    ELSE
      outcome := 'blocked';
    END IF;
  ELSE
    -- 2. Envio con esa etiqueta hacia otro nodo: misma ciudad antes que otra ciudad; dentro, como en 1.
    SELECT x.id, x.status, x.cancellation_reason, x.destination_node_id, n.city_id, x.sent_at
      INTO v_det_id, v_det_status, v_det_reason, v_det_dest, v_det_city, v_det_sent
      FROM public.allocation_plan_details x
      JOIN public.nodes n ON n.id = x.destination_node_id
     WHERE x.account_id = p_account_id AND x.tag_id = p_tag_norm AND x.destination_node_id <> p_node_id
     ORDER BY (v_city IS NOT NULL AND n.city_id = v_city) DESC,
              (x.status = 'sent') DESC,
              CASE WHEN x.status = 'sent' THEN x.fecha_programada END ASC,
              x.fecha_programada DESC
     LIMIT 1;

    IF FOUND THEN
      detail_id := v_det_id;
      IF v_det_status = 'received' THEN
        outcome := 'already_received';
      ELSIF v_det_status NOT IN ('sent', 'pending', 'notified')
            AND NOT (v_det_status = 'cancelled' AND v_det_reason = 'not_received_timeout') THEN
        outcome := 'blocked';
      ELSIF v_city IS NOT NULL AND v_det_city = v_city THEN
        IF v_det_status = 'cancelled' THEN
          -- Anulado por plazo: si ya no se puede reactivar (p. ej. ya esta por compensar), queda bloqueado.
          IF public.revive_timeout_detail(v_det_id) THEN
            v_det_status := 'sent';
          ELSE
            outcome := 'blocked';
          END IF;
        END IF;
        IF outcome IS NULL THEN
          -- Declarado despues de la recepcion: no se mueve el destino; se anula como receipt_before_sent.
          IF v_det_status = 'sent' AND (v_det_sent IS NULL OR v_det_sent <= p_recv_at) THEN
            UPDATE public.allocation_plan_details
               SET original_destination_node_id = COALESCE(original_destination_node_id, destination_node_id),
                   destination_node_id = p_node_id,
                   destination_panelist_id = p_panelist_id,
                   destination_panelist_name = p_panelist_name
             WHERE id = v_det_id AND status = 'sent';
            -- Si ya no estaba 'sent', register no toca la fila y devuelve already_received / blocked.
            v_res := public.register_receipt_with_rules(v_det_id, p_recv_at, p_panelist_id);
            outcome := CASE WHEN v_res = 'ok' THEN 'ok_same_city' ELSE v_res END;
          ELSE
            v_cancel_reason := 'receipt_before_sent';
          END IF;
        END IF;
      ELSE
        -- Otra ciudad: puede ser un tecleo que acierta un envio sano en transito. No se toca el envio; el caso
        -- queda para decision del responsable, sin envio asociado.
        outcome := 'other_city_tag';
        detail_id := NULL;
      END IF;
    ELSE
      -- 3. No existe: error de tecleo con un unico candidato en su ciudad (incluye anulados por plazo).
      SELECT count(*), min(c.id::text)::uuid INTO v_n, v_det_id
        FROM public.receipt_typo_candidates(p_account_id, v_city, p_tag_norm, p_recv_at) c(id);
      IF v_n = 1 THEN
        SELECT x.tag_id INTO original_tag FROM public.allocation_plan_details x WHERE x.id = v_det_id FOR UPDATE;
        PERFORM public.revive_timeout_detail(v_det_id);
        UPDATE public.allocation_plan_details
           SET tag_id = p_tag_norm, idtag = COALESCE(NULLIF(btrim(COALESCE(p_tag_raw, '')), ''), p_tag_norm)
         WHERE id = v_det_id AND status = 'sent'
        RETURNING destination_node_id INTO v_det_dest;
        IF NOT FOUND THEN
          original_tag := NULL;
          outcome := 'not_found';   -- el candidato dejo de estar 'sent' entretanto
        ELSE
          detail_id := v_det_id;
          IF v_det_dest <> p_node_id THEN
            UPDATE public.allocation_plan_details
               SET original_destination_node_id = COALESCE(original_destination_node_id, destination_node_id),
                   destination_node_id = p_node_id,
                   destination_panelist_id = p_panelist_id,
                   destination_panelist_name = p_panelist_name
             WHERE id = v_det_id AND status = 'sent';
          END IF;
          v_res := public.register_receipt_with_rules(v_det_id, p_recv_at, p_panelist_id);
          outcome := CASE WHEN v_res = 'ok' THEN 'ok_typo_fixed' ELSE v_res END;
        END IF;
      ELSIF v_n > 1 THEN
        outcome := 'ambiguous_typo';
      ELSE
        outcome := 'not_found';
      END IF;
    END IF;
  END IF;

  -- Anulacion para compensar (solo receipt_before_sent); si la fila (ya bloqueada) cambio de estado, no se toca.
  IF v_cancel_reason IS NOT NULL THEN
    IF public.cancel_detail_for_compensation(detail_id, v_cancel_reason) THEN
      outcome := 'not_sent_cancelled';
    ELSE
      outcome := CASE WHEN (SELECT x.status FROM public.allocation_plan_details x WHERE x.id = detail_id) = 'received'
                      THEN 'already_received' ELSE 'blocked' END;
    END IF;
  END IF;
END;
$$;

-- ============================================================================================================
-- 6. Permisos: solo service_role y llamadas internas.
-- ============================================================================================================
REVOKE EXECUTE ON FUNCTION public.revive_timeout_detail(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.receipt_typo_candidates(uuid, uuid, text, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.receipt_match_tag(uuid, uuid, text, uuid, text, text, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.revive_timeout_detail(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.receipt_typo_candidates(uuid, uuid, text, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.receipt_match_tag(uuid, uuid, text, uuid, text, text, timestamptz) TO service_role;
