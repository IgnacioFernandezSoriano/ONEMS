-- Errores de recepcion: etiqueta de un envio hacia OTRA ciudad -> pendiente de decision (ya no se anula).
-- Spec: docs/superpowers/specs/2026-11-04-errores-recepcion-design.md. Tarea 9 (decision del usuario 2026-11-04 tras
-- la prueba real en DEMO2).
--
-- Antes: si la etiqueta declarada coincidia exactamente con un envio hacia otra ciudad, el envio se anulaba para
-- compensar (received_wrong_city / wrong_city_cancelled). Pero puede ser un error de tecleo que acierta un envio sano
-- que sigue en transito. Ahora:
--   * outcome nuevo 'other_city_tag': el envio NO se toca (ni estado, ni destino, ni etiqueta) y no hay
--     deferred_samples;
--   * el caso queda en 'needs_decision' con detail_id NULL y sin culpable (Compensar / Descartar del responsable lo
--     descarta sin tocar el envio) y sin recordatorio;
--   * igual en el bot y en el reintento (ambos usan receipt_match_tag).
-- 'wrong_city_cancelled' / 'received_wrong_city' se mantienen en los CHECK y mapeos por compatibilidad con los casos
-- ya registrados, pero dejan de producirse automaticamente.
--
-- Re-emite completas: receipt_match_tag, receipt_outcome_status y receipt_retry_pending (ultima version en
-- 20261104121000). bot_receive_parcel no cambia: con detail_id NULL y estado needs_decision ya registra el caso como
-- se pide y enqueue_receipt_reminder no encola nada (sin culpable). receipt_outcome_culprit no cambia: para
-- other_city_tag ya devuelve NULL / NULL.

SET lock_timeout = '5s';

-- ============================================================================================================
-- 1. CHECK de receipt_case.reason con el motivo nuevo
-- ============================================================================================================
ALTER TABLE public.receipt_case DROP CONSTRAINT IF EXISTS receipt_case_reason_check;
ALTER TABLE public.receipt_case ADD CONSTRAINT receipt_case_reason_check
  CHECK (reason IN ('ok', 'ok_typo_fixed', 'ok_same_city',
                    'pobox_absent_unavailable', 'pobox_absent_no_visit',
                    'not_sent_cancelled', 'wrong_city_cancelled', 'other_city_tag',
                    'already_received', 'blocked', 'not_found', 'ambiguous_typo',
                    'invalid_format', 'no_panelist', 'no_node')) NOT VALID;
ALTER TABLE public.receipt_case VALIDATE CONSTRAINT receipt_case_reason_check;

-- ============================================================================================================
-- 2. Tabla de codigos: other_city_tag -> needs_decision
-- ============================================================================================================
CREATE OR REPLACE FUNCTION public.receipt_outcome_status(p_outcome text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    -- 'ok' solo deja huella si cierra un caso abierto (reintento que ahora si encuentra el envio)
    WHEN p_outcome IN ('ok', 'ok_typo_fixed', 'ok_same_city') THEN 'fixed'
    -- wrong_city_cancelled ya no se produce; se mantiene por compatibilidad con casos antiguos
    WHEN p_outcome IN ('pobox_absent_no_visit', 'pobox_absent_unavailable', 'not_sent_cancelled',
                       'wrong_city_cancelled') THEN 'compensated'
    WHEN p_outcome IN ('already_received', 'blocked', 'invalid_format') THEN 'informative'
    WHEN p_outcome = 'not_found' THEN 'pending'
    WHEN p_outcome IN ('ambiguous_typo', 'other_city_tag', 'no_panelist', 'no_node') THEN 'needs_decision'
  END;
$$;

-- ============================================================================================================
-- 3. Busqueda de la etiqueta (compartida por el bot y el reintento)
-- ============================================================================================================
-- Para un receptor con nodo y una etiqueta normalizada: busca el envio, lo registra con p_recv_at (regla POBOX
-- incluida), lo arregla (misma ciudad / tecleo) o lo anula para compensar. Devuelve el outcome, el detalle tocado y,
-- si un arreglo por tecleo reescribio la etiqueta del envio, la que tenia (original_tag).
-- Un envio declarado (sent_at) despues de p_recv_at nunca se arregla: ni es candidato por tecleo ni se le mueve el
-- destino; con la etiqueta exacta se anula como receipt_before_sent.
-- Etiqueta exacta de un envio hacia OTRA ciudad (sent / pending / notified): other_city_tag, el envio no se toca y
-- detail_id sale NULL (el caso queda para decision del responsable, sin envio asociado).
-- Para not_found / ambiguous_typo / other_city_tag no cambia nada.
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
  v_det_dest uuid;
  v_det_city uuid;
  v_det_sent timestamptz;
  v_res text;
  v_cancel_reason text;
  v_n int;
BEGIN
  SELECT n.city_id INTO v_city FROM public.nodes n WHERE n.id = p_node_id;

  -- 1. Envio con esa etiqueta hacia su nodo ('sent' primero, el mas antiguo; si no, el no-sent mas reciente).
  SELECT x.id, x.status INTO v_det_id, v_det_status
    FROM public.allocation_plan_details x
   WHERE x.account_id = p_account_id AND x.destination_node_id = p_node_id AND x.tag_id = p_tag_norm
   ORDER BY (x.status = 'sent') DESC,
            CASE WHEN x.status = 'sent' THEN x.fecha_programada END ASC,
            x.fecha_programada DESC
   LIMIT 1;

  IF FOUND THEN
    detail_id := v_det_id;
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
    SELECT x.id, x.status, x.destination_node_id, n.city_id, x.sent_at
      INTO v_det_id, v_det_status, v_det_dest, v_det_city, v_det_sent
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
      ELSIF v_det_status NOT IN ('sent', 'pending', 'notified') THEN
        outcome := 'blocked';
      ELSIF v_city IS NOT NULL AND v_det_city = v_city THEN
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
      ELSE
        -- Otra ciudad: puede ser un tecleo que acierta un envio sano en transito. No se toca el envio; el caso
        -- queda para decision del responsable, sin envio asociado.
        outcome := 'other_city_tag';
        detail_id := NULL;
      END IF;
    ELSE
      -- 3. No existe: error de tecleo con un unico candidato en su ciudad.
      SELECT count(*), min(c.id::text)::uuid INTO v_n, v_det_id
        FROM public.receipt_typo_candidates(p_account_id, v_city, p_tag_norm, p_recv_at) c(id);
      IF v_n = 1 THEN
        SELECT x.tag_id INTO original_tag FROM public.allocation_plan_details x WHERE x.id = v_det_id FOR UPDATE;
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
-- 4. Reintento de los not_found pendientes
-- ============================================================================================================
-- Para cada caso not_found/pending: repite la busqueda (exacta + tecleo) con la fecha del primer intento, sin crear
-- casos nuevos. Si resuelve (fixed / compensated) actualiza el caso y encola el recordatorio; si el reintento da
-- ambiguous_typo u other_city_tag, pasa a decision con ese motivo (sin envio asociado ni culpable); si el envio ya
-- estaba recibido (already_received) el caso se cierra como informativo (no hay nada que esperar); si no y han pasado
-- >= 5 dias laborables desde el primer intento (contados desde el dia local siguiente hasta hoy, ambos incluidos),
-- pasa a needs_decision.
-- Cada caso en su propio bloque: un fallo en uno no para los demas. Devuelve el numero de casos cerrados
-- (fixed / compensated / informative).
CREATE OR REPLACE FUNCTION public.receipt_retry_pending()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c record;
  v_name text;
  v_node uuid;
  v_outcome text;
  v_detail uuid;
  v_orig_tag text;
  v_status text;
  v_role text;
  v_culprit uuid;
  v_wd int;
  v_n int := 0;
BEGIN
  FOR c IN
    SELECT rc.id, rc.account_id, rc.panelist_id, rc.tag_norm, rc.tag_raw, rc.first_attempt_at,
           COALESCE(a.timezone, 'UTC') AS tz
      FROM public.receipt_case rc
      JOIN public.accounts a ON a.id = rc.account_id
     WHERE rc.reason = 'not_found' AND rc.status = 'pending'
     ORDER BY rc.first_attempt_at
  LOOP
    BEGIN
      -- Bloquea el caso; si el bot lo acaba de cambiar, se salta.
      PERFORM 1 FROM public.receipt_case rc
        WHERE rc.id = c.id AND rc.reason = 'not_found' AND rc.status = 'pending'
        FOR UPDATE SKIP LOCKED;
      CONTINUE WHEN NOT FOUND;

      v_outcome := NULL;
      v_detail := NULL;
      v_orig_tag := NULL;
      SELECT p.name, p.node_id INTO v_name, v_node FROM public.panelists p WHERE p.id = c.panelist_id;
      IF c.panelist_id IS NOT NULL AND v_node IS NOT NULL AND c.tag_norm IS NOT NULL THEN
        SELECT m.outcome, m.detail_id, m.original_tag INTO v_outcome, v_detail, v_orig_tag
          FROM public.receipt_match_tag(c.account_id, c.panelist_id, v_name, v_node, c.tag_norm, c.tag_raw,
                                        c.first_attempt_at) m;
      END IF;
      v_status := public.receipt_outcome_status(v_outcome);

      IF v_status IN ('fixed', 'compensated') THEN
        SELECT k.culprit_role, k.culprit_panelist_id INTO v_role, v_culprit
          FROM public.receipt_outcome_culprit(v_outcome, v_detail, c.panelist_id) k;
        UPDATE public.receipt_case
           SET reason = v_outcome, status = v_status, detail_id = v_detail,
               culprit_role = v_role, culprit_panelist_id = v_culprit, resolved_at = now(),
               original_tag = COALESCE(v_orig_tag, original_tag)
         WHERE id = c.id;
        v_n := v_n + 1;
        BEGIN
          PERFORM public.enqueue_receipt_reminder(c.id);
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'receipt_retry_pending: no se pudo encolar el recordatorio del caso %: %', c.id, SQLERRM;
        END;
      ELSIF v_outcome = 'already_received' THEN
        -- El envio ya estaba recibido: no hay nada que esperar; se cierra como informativo.
        UPDATE public.receipt_case
           SET reason = v_outcome, status = 'informative', detail_id = v_detail, resolved_at = now()
         WHERE id = c.id;
        v_n := v_n + 1;
      ELSIF v_outcome IN ('ambiguous_typo', 'other_city_tag') THEN
        -- Decision del responsable; sin envio asociado ni culpable (el envio no se ha tocado).
        UPDATE public.receipt_case
           SET reason = v_outcome, status = 'needs_decision', detail_id = NULL,
               culprit_role = NULL, culprit_panelist_id = NULL
         WHERE id = c.id;
      ELSE
        SELECT count(*) INTO v_wd
          FROM generate_series((c.first_attempt_at AT TIME ZONE c.tz)::date + 1,
                               (now() AT TIME ZONE c.tz)::date, interval '1 day') g(d)
         WHERE public.is_account_working_day(c.account_id, g.d::date);
        IF v_wd >= 5 THEN
          UPDATE public.receipt_case SET status = 'needs_decision' WHERE id = c.id;
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'receipt_retry_pending: caso %: %', c.id, SQLERRM;
    END;
  END LOOP;
  RETURN v_n;
END;
$$;

-- ============================================================================================================
-- 5. Permisos (CREATE OR REPLACE los conserva; se reafirman igual): solo service_role y llamadas internas.
-- ============================================================================================================
REVOKE EXECUTE ON FUNCTION public.receipt_outcome_status(text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.receipt_match_tag(uuid, uuid, text, uuid, text, text, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.receipt_retry_pending() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.receipt_outcome_status(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.receipt_match_tag(uuid, uuid, text, uuid, text, text, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.receipt_retry_pending() TO service_role;
