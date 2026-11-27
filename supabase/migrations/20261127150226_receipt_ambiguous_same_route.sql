-- 2026-11-27  Recepcion: etiqueta parecida a VARIOS envios del mismo remitente al mismo receptor.
--
-- Caso real (Kenya, 27/11): el receptor escribe bien 00010255 (lo confirma la foto); el remitente declaro
-- 00010256 y 00010265, ambos hacia el. Hasta ahora salia 'ambiguous_typo' y al receptor se le pedia repetir.
-- Ahora, si todos los candidatos de tecleo van a su propio nodo y salen de un mismo origen, se elige el enviado
-- mas antiguo y se registra como 'ok_typo_fixed' (caso 'fixed', culpable el remitente, etiqueta original guardada).
-- Si hay candidatos de otros receptores u otros origenes, sigue siendo 'ambiguous_typo' (decide el gestor).
-- Solo cambia receipt_match_tag; el resto de la funcion es identico a 20261117120000_receipt_misrouted.sql.

CREATE OR REPLACE FUNCTION public.receipt_match_tag(p_account_id uuid, p_panelist_id uuid, p_panelist_name text,
  p_node_id uuid, p_tag_norm text, p_tag_raw text, p_recv_at timestamp with time zone,
  OUT outcome text, OUT detail_id uuid, OUT original_tag text)
 RETURNS record
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_city uuid;
  v_det_id uuid;
  v_det_status text;
  v_det_reason text;
  v_det_dest uuid;
  v_det_city uuid;
  v_det_sent timestamptz;
  v_det_misrouted boolean;
  v_det_orig_dest uuid;
  v_res text;
  v_cancel_reason text;
  v_n int;
  v_found_other boolean := false;
  v_misroute_id uuid;           -- envio sano hacia otra ciudad con esta etiqueta (candidato a mal encaminado)
  v_misroute_status text;
  v_misroute_sent timestamptz;
  v_k int;                      -- candidatos de tecleo que van a su propio nodo
  v_orig_n int;                 -- origenes distintos entre esos candidatos
  v_pick uuid;                  -- el enviado mas antiguo de esos candidatos
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
    SELECT x.id, x.status, x.cancellation_reason, x.destination_node_id, n.city_id, x.sent_at,
           x.misrouted, x.original_destination_node_id
      INTO v_det_id, v_det_status, v_det_reason, v_det_dest, v_det_city, v_det_sent,
           v_det_misrouted, v_det_orig_dest
      FROM public.allocation_plan_details x
      JOIN public.nodes n ON n.id = x.destination_node_id
     WHERE x.account_id = p_account_id AND x.tag_id = p_tag_norm AND x.destination_node_id <> p_node_id
     ORDER BY (v_city IS NOT NULL AND n.city_id = v_city) DESC,
              (x.status = 'sent') DESC,
              CASE WHEN x.status = 'sent' THEN x.fecha_programada END ASC,
              x.fecha_programada DESC
     LIMIT 1;
    v_found_other := FOUND;

    IF v_found_other THEN
      detail_id := v_det_id;
      IF v_det_status = 'received' THEN
        -- R1: si lo recibio otro como mal encaminado y quien escribe ahora era su destinatario, decide el gestor.
        outcome := CASE WHEN v_det_misrouted AND v_det_orig_dest = p_node_id THEN 'misrouted_dup'
                        ELSE 'already_received' END;
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
        -- Otra ciudad. No se decide aqui: primero se mira si es un numero mal escrito (R2, paso 3); si no, R1.
        v_misroute_id := v_det_id;
        v_misroute_status := v_det_status;
        v_misroute_sent := v_det_sent;
        detail_id := NULL;
      END IF;
    END IF;

    IF NOT v_found_other OR v_misroute_id IS NOT NULL THEN
      -- 3. Error de tecleo con un unico candidato en su ciudad (incluye anulados por plazo).
      SELECT count(*), min(c.id::text)::uuid INTO v_n, v_det_id
        FROM public.receipt_typo_candidates(p_account_id, v_city, p_tag_norm, p_recv_at) c(id);
      -- 2026-11-27: varios candidatos, pero TODOS hacia su propio nodo y desde un mismo origen (misma ruta): el
      -- remitente tecleo mal uno de sus numeros. Se toma el enviado mas antiguo (el que antes debia llegar); el
      -- otro se registrara con su numero cuando llegue. La medicion solo puede variar en la fecha de envio.
      IF v_n > 1 THEN
        SELECT count(*), count(DISTINCT x.origin_node_id),
               (array_agg(x.id ORDER BY x.sent_at, x.fecha_programada, x.id))[1]
          INTO v_k, v_orig_n, v_pick
          FROM public.receipt_typo_candidates(p_account_id, v_city, p_tag_norm, p_recv_at) c(id)
          JOIN public.allocation_plan_details x ON x.id = c.id
         WHERE x.destination_node_id = p_node_id AND x.origin_node_id IS NOT NULL;
        IF v_k = v_n AND v_orig_n = 1 THEN
          v_n := 1;
          v_det_id := v_pick;
        END IF;
      END IF;
      IF v_n = 1 THEN
        SELECT x.tag_id INTO original_tag FROM public.allocation_plan_details x WHERE x.id = v_det_id FOR UPDATE;
        PERFORM public.revive_timeout_detail(v_det_id);
        UPDATE public.allocation_plan_details
           SET tag_id = p_tag_norm, idtag = COALESCE(NULLIF(btrim(COALESCE(p_tag_raw, '')), ''), p_tag_norm)
         WHERE id = v_det_id AND status = 'sent'
        RETURNING destination_node_id INTO v_det_dest;
        IF NOT FOUND THEN
          original_tag := NULL;
          outcome := CASE WHEN v_misroute_id IS NOT NULL THEN 'other_city_tag' ELSE 'not_found' END;
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
      ELSIF v_misroute_id IS NULL THEN
        outcome := 'not_found';
      ELSE
        -- 4. R1: mal encaminado. Declarado antes de llegar, aun sin recibir, numero no trivial.
        --    IF anidados a proposito: SQL no garantiza el orden del AND y revive_timeout_detail escribe.
        outcome := 'other_city_tag';
        IF v_misroute_status IN ('sent', 'cancelled')
           AND v_misroute_sent IS NOT NULL AND v_misroute_sent <= p_recv_at
           AND NOT (p_tag_norm ~ '^[0-9]+$' AND length(ltrim(p_tag_norm, '0')) < 4) THEN
          IF v_misroute_status = 'cancelled' AND public.revive_timeout_detail(v_misroute_id) THEN
            v_misroute_status := 'sent';
          END IF;
        END IF;
        IF outcome = 'other_city_tag' AND v_misroute_status = 'sent'
           AND v_misroute_sent IS NOT NULL AND v_misroute_sent <= p_recv_at
           AND NOT (p_tag_norm ~ '^[0-9]+$' AND length(ltrim(p_tag_norm, '0')) < 4) THEN
          UPDATE public.allocation_plan_details
             SET original_destination_node_id = COALESCE(original_destination_node_id, destination_node_id),
                 destination_node_id = p_node_id,
                 destination_panelist_id = p_panelist_id,
                 destination_panelist_name = p_panelist_name,
                 misrouted = true
           WHERE id = v_misroute_id AND status = 'sent';
          IF FOUND THEN
            detail_id := v_misroute_id;
            v_res := public.register_receipt_with_rules(v_misroute_id, p_recv_at, p_panelist_id);
            outcome := CASE WHEN v_res = 'ok' THEN 'ok_misrouted' ELSE v_res END;
          END IF;
        END IF;
        -- Si no se cumplio (sin declarar, declarado despues, numero trivial o ya no reactivable) queda
        -- 'other_city_tag': decide el gestor y el envio no se toca.
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
$function$;
