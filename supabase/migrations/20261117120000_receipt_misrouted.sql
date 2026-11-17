-- 2026-11-17: reglas de recepcion revisadas con Ignacio (pagina de trabajo "Mensajes de registro del bot", bloque R).
--
-- R1  Lectura mal encaminada: una etiqueta de un envio a OTRA ciudad se aprovecha (se registra en quien lo recibio y
--     cuenta en la ruta origen -> ciudad real) si el remitente lo declaro antes de que llegara, su destinatario aun no lo
--     ha recibido y no es un numero trivial (00000001...). El envio queda marcado misrouted = true y conserva su destino
--     original en original_destination_node_id. La regla del apartado se aplica igual (register_receipt_with_rules).
--     Si despues lo registra tambien su destinatario original -> motivo 'misrouted_dup', decide el gestor.
-- R2  Antes de tratar una etiqueta como mal encaminada se busca si es un numero mal escrito de un paquete que el panelista
--     espera (una cifra distinta o dos adyacentes intercambiadas): un unico candidato -> ok_typo_fixed; varios ->
--     ambiguous_typo. Asi un error de tecleo no le quita la medicion al destinatario real.
-- R3  Panelista sin punto asignado (no_node): se abre sola una incidencia 'other' para el gestor (una por panelista y 24 h).
-- R4  Paquete anulado antes (blocked): sin cambios.

-- 1. Marca de "mal encaminado" en el envio.
ALTER TABLE public.allocation_plan_details
  ADD COLUMN IF NOT EXISTS misrouted boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.allocation_plan_details.misrouted IS
  'Recibido en otra ciudad distinta de su destino (regla R1, 2026-11-17). El destino planificado queda en original_destination_node_id.';
CREATE INDEX IF NOT EXISTS allocation_plan_details_misrouted_idx
  ON public.allocation_plan_details (account_id) WHERE misrouted;

-- 2. Motivos nuevos en los casos de recepcion.
ALTER TABLE public.receipt_case DROP CONSTRAINT IF EXISTS receipt_case_reason_check;
ALTER TABLE public.receipt_case ADD CONSTRAINT receipt_case_reason_check CHECK (reason = ANY (ARRAY[
  'ok', 'ok_typo_fixed', 'ok_same_city', 'ok_misrouted', 'pobox_absent_unavailable', 'pobox_absent_no_visit',
  'not_sent_cancelled', 'wrong_city_cancelled', 'other_city_tag', 'misrouted_dup', 'already_received', 'blocked',
  'not_found', 'ambiguous_typo', 'invalid_format', 'no_panelist', 'no_node']));

CREATE OR REPLACE FUNCTION public.receipt_outcome_status(p_outcome text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  SELECT CASE
    -- 'ok' solo deja huella si cierra un caso abierto (reintento que ahora si encuentra el envio)
    WHEN p_outcome IN ('ok', 'ok_typo_fixed', 'ok_same_city', 'ok_misrouted') THEN 'fixed'
    -- wrong_city_cancelled ya no se produce; se mantiene por compatibilidad con casos antiguos
    WHEN p_outcome IN ('pobox_absent_no_visit', 'pobox_absent_unavailable', 'not_sent_cancelled',
                       'wrong_city_cancelled') THEN 'compensated'
    WHEN p_outcome IN ('already_received', 'blocked', 'invalid_format') THEN 'informative'
    WHEN p_outcome = 'not_found' THEN 'pending'
    WHEN p_outcome IN ('ambiguous_typo', 'other_city_tag', 'misrouted_dup', 'no_panelist', 'no_node') THEN 'needs_decision'
  END;
$function$;

-- 3. Busqueda de la etiqueta con R1 y R2. Mismos pasos que antes; cambia solo la rama "envio hacia otra ciudad".
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

-- 4. Recepcion del bot: 'ok_misrouted' cuenta como registrada; R3 abre la incidencia del panelista sin punto.
CREATE OR REPLACE FUNCTION public.bot_receive_parcel(p_telegram_id text, p_tag_raw text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_now timestamptz := clock_timestamp();
  v_tg text := btrim(COALESCE(p_telegram_id, ''));
  v_raw text := COALESCE(p_tag_raw, '');
  v_norm text := public.normalize_tag(p_tag_raw);
  v_found boolean := false;
  v_pid uuid;
  v_pname text;
  v_pnode uuid;
  v_lang text;
  v_account uuid;
  v_recv_at timestamptz;
  v_detail uuid;
  v_orig_tag text;
  v_outcome text;
  v_status text;
  v_culprit_role text;
  v_culprit uuid;
  v_case_id uuid;
  v_case_status text;
  v_tz text;
  v_origin_name text;
  v_origin_city text;
BEGIN
  -- 1. Panelista (activo primero), como el nodo actual del bot.
  IF v_tg <> '' THEN
    SELECT pa.id, pa.name, pa.node_id, pa.account_id, pa.language
      INTO v_pid, v_pname, v_pnode, v_account, v_lang
      FROM public.panelists pa
     WHERE btrim(pa.telegram_id) = v_tg
     ORDER BY (pa.status = 'active') DESC, pa.id
     LIMIT 1;
    v_found := FOUND;
  END IF;

  IF NOT v_found THEN
    v_outcome := 'no_panelist';
    -- Sin ficha no hay cuenta: se toma la de los envios con esa etiqueta si es una sola (si no, no hay caso).
    IF v_norm IS NOT NULL THEN
      SELECT CASE WHEN count(DISTINCT x.account_id) = 1 THEN min(x.account_id::text)::uuid END
        INTO v_account
        FROM public.allocation_plan_details x
       WHERE x.tag_id = v_norm;
    END IF;
  ELSIF v_pnode IS NULL THEN
    v_outcome := 'no_node';
  ELSIF v_norm IS NULL THEN
    v_outcome := 'invalid_format';
  ELSE
    -- Si ya habia un caso abierto con esta etiqueta, la recepcion cuenta desde el primer intento.
    SELECT rc.first_attempt_at INTO v_recv_at
      FROM public.receipt_case rc
     WHERE rc.account_id = v_account AND rc.telegram_id = v_tg AND rc.tag_norm = v_norm
       AND rc.status IN ('pending', 'needs_decision')
     LIMIT 1;
    v_recv_at := COALESCE(v_recv_at, v_now);

    -- 2-4. Busqueda exacta, otro nodo (misma ciudad / otra ciudad), tecleo; anulacion para compensar.
    SELECT m.outcome, m.detail_id, m.original_tag INTO v_outcome, v_detail, v_orig_tag
      FROM public.receipt_match_tag(v_account, v_pid, v_pname, v_pnode, v_norm, v_raw, v_recv_at) m;
  END IF;

  -- 5. Registro del caso y recordatorio (fail-open: un fallo aqui nunca impide contestar ni deshace la recepcion).
  v_status := public.receipt_outcome_status(v_outcome);
  SELECT k.culprit_role, k.culprit_panelist_id INTO v_culprit_role, v_culprit
    FROM public.receipt_outcome_culprit(v_outcome, v_detail, v_pid) k;

  IF v_account IS NOT NULL THEN
    BEGIN
      SELECT COALESCE(a.timezone, 'UTC') INTO v_tz FROM public.accounts a WHERE a.id = v_account;
      v_tz := COALESCE(v_tz, 'UTC');

      -- a) Caso abierto con la misma etiqueta: un intento mas. Si este intento lo resuelve (arreglo o
      --    compensacion) o lo pasa a decision, el caso toma el nuevo resultado y conserva su primer intento.
      SELECT rc.id, rc.status INTO v_case_id, v_case_status
        FROM public.receipt_case rc
       WHERE rc.account_id = v_account AND rc.telegram_id = v_tg AND v_norm IS NOT NULL AND rc.tag_norm = v_norm
         AND rc.status IN ('pending', 'needs_decision')
       ORDER BY rc.first_attempt_at
       LIMIT 1
       FOR UPDATE;

      IF FOUND THEN
        UPDATE public.receipt_case rc
           SET attempts = rc.attempts + 1,
               last_attempt_at = v_now,
               reason = CASE WHEN v_status IN ('fixed', 'compensated', 'needs_decision') THEN v_outcome ELSE rc.reason END,
               status = CASE WHEN v_status IN ('fixed', 'compensated', 'needs_decision') THEN v_status ELSE rc.status END,
               detail_id = CASE WHEN v_status IN ('fixed', 'compensated') THEN v_detail ELSE rc.detail_id END,
               culprit_role = CASE WHEN v_status IN ('fixed', 'compensated') THEN v_culprit_role ELSE rc.culprit_role END,
               culprit_panelist_id = CASE WHEN v_status IN ('fixed', 'compensated') THEN v_culprit ELSE rc.culprit_panelist_id END,
               panelist_id = COALESCE(rc.panelist_id, v_pid),
               original_tag = COALESCE(v_orig_tag, rc.original_tag),
               resolved_at = CASE WHEN v_status IN ('fixed', 'compensated') THEN v_now ELSE rc.resolved_at END
         WHERE rc.id = v_case_id;
      ELSIF v_outcome <> 'ok' THEN
        -- b) Mismo motivo y etiqueta el mismo dia local: un intento mas.
        SELECT rc.id INTO v_case_id
          FROM public.receipt_case rc
         WHERE rc.account_id = v_account AND rc.telegram_id = v_tg AND rc.reason = v_outcome
           AND (rc.tag_norm = v_norm OR (v_norm IS NULL AND rc.tag_norm IS NULL AND rc.tag_raw = v_raw))
           AND (rc.first_attempt_at AT TIME ZONE v_tz)::date = (v_now AT TIME ZONE v_tz)::date
         ORDER BY rc.first_attempt_at DESC
         LIMIT 1
         FOR UPDATE;

        IF FOUND THEN
          UPDATE public.receipt_case
             SET attempts = attempts + 1, last_attempt_at = v_now
           WHERE id = v_case_id;
        ELSE
          INSERT INTO public.receipt_case
            (account_id, panelist_id, telegram_id, tag_raw, tag_norm, detail_id, reason, status,
             culprit_panelist_id, culprit_role, attempts, first_attempt_at, last_attempt_at, resolved_at, original_tag)
          VALUES
            (v_account, v_pid, v_tg, v_raw, v_norm, v_detail, v_outcome, v_status,
             v_culprit, v_culprit_role, 1, v_now, v_now,
             CASE WHEN v_status IN ('fixed', 'compensated', 'informative') THEN v_now END, v_orig_tag)
          RETURNING id INTO v_case_id;
        END IF;
      END IF;

      -- Recordatorio al culpable (uno al dia por motivo; los que no proceden devuelven NULL). Su propio bloque:
      -- si falla, el caso queda registrado igualmente.
      IF v_case_id IS NOT NULL THEN
        BEGIN
          PERFORM public.enqueue_receipt_reminder(v_case_id);
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'bot_receive_parcel: no se pudo encolar el recordatorio del caso %: %', v_case_id, SQLERRM;
        END;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'bot_receive_parcel: no se pudo registrar el caso (%): %', v_outcome, SQLERRM;
      v_case_id := NULL;
    END;
  END IF;

  -- R3 (2026-11-17): panelista sin punto -> incidencia 'other' para el gestor, una por panelista cada 24 h.
  IF v_outcome = 'no_node' AND v_pid IS NOT NULL THEN
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM public.panelist_incident pi
                      WHERE pi.panelist_id = v_pid AND pi.payload->>'source' = 'no_node'
                        AND pi.created_at > v_now - interval '24 hours') THEN
        PERFORM public.insert_panelist_incident_auto(v_pid, 'other',
          '📍 Panelist without an assigned point tried to register label ' || COALESCE(v_norm, NULLIF(btrim(v_raw), ''), '?'),
          jsonb_build_object('source', 'no_node', 'typed_tag', v_raw, 'tag', v_norm, 'case_id', v_case_id),
          NULL, 'open');
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'bot_receive_parcel: no se pudo abrir la incidencia de panelista sin punto: %', SQLERRM;
    END;
  END IF;

  -- 6. Respuesta.
  IF v_detail IS NOT NULL THEN
    BEGIN
      SELECT v.origin_panelist_name, v.origin_city_name INTO v_origin_name, v_origin_city
        FROM public.v_allocation_details_with_availability v
       WHERE v.id = v_detail
       LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'bot_receive_parcel: origen del envio %: %', v_detail, SQLERRM;
      v_origin_name := NULL;
      v_origin_city := NULL;
    END;
  END IF;

  RETURN jsonb_build_object(
    'outcome', v_outcome,
    'registered', v_outcome IN ('ok', 'ok_typo_fixed', 'ok_same_city', 'ok_misrouted'),
    'language', v_lang,
    'tag', v_norm,
    'origin_name', v_origin_name,
    'origin_city', v_origin_city,
    'case_id', v_case_id);
END;
$function$;

-- 5. Estadistica de mal encaminados: envios recibidos en otra ciudad, con su destino planificado y el real.
--    security_invoker: cada usuario ve solo lo que el RLS de allocation_plan_details le deja ver.
CREATE OR REPLACE VIEW public.v_misrouted_receipts WITH (security_invoker = true) AS
SELECT d.id, d.account_id, d.plan_id, d.tag_id,
       d.origin_node_id, onode.city_id AS origin_city_id,
       d.original_destination_node_id AS planned_destination_node_id, pnode.city_id AS planned_destination_city_id,
       d.destination_node_id AS actual_destination_node_id, anode.city_id AS actual_destination_city_id,
       d.fecha_programada, d.sent_at, d.received_at, d.status
  FROM public.allocation_plan_details d
  LEFT JOIN public.nodes onode ON onode.id = d.origin_node_id
  LEFT JOIN public.nodes pnode ON pnode.id = d.original_destination_node_id
  LEFT JOIN public.nodes anode ON anode.id = d.destination_node_id
 WHERE d.misrouted;
REVOKE ALL ON public.v_misrouted_receipts FROM PUBLIC, anon;
GRANT SELECT ON public.v_misrouted_receipts TO authenticated;

-- 6. Reintento de los no encontrados: 'misrouted_dup' tambien pasa a decision del gestor (como ambiguous/other_city).
CREATE OR REPLACE FUNCTION public.receipt_retry_pending()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      ELSIF v_outcome IN ('ambiguous_typo', 'other_city_tag', 'misrouted_dup') THEN
        -- Decision del responsable; sin culpable. misrouted_dup conserva el envio para que el gestor lo vea.
        UPDATE public.receipt_case
           SET reason = v_outcome, status = 'needs_decision',
               detail_id = CASE WHEN v_outcome = 'misrouted_dup' THEN v_detail END,
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
$function$;
