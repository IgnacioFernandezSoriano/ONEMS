-- Errores de recepcion: reintentos de etiquetas no encontradas, recordatorios al panelista y cola de avisos.
-- Spec: docs/superpowers/specs/2026-11-04-errores-recepcion-design.md. Tarea 2 del plan.
--
-- Todo es ADITIVO: columnas nuevas NULL en panelist_notification, CHECK de kind ampliado, funciones nuevas y
-- bot_receive_parcel re-emitida con la misma respuesta (la busqueda pasa a una funcion compartida con el reintento
-- y se encola el recordatorio dentro del bloque fail-open).
--
--   * receipt_match_tag: busqueda exacta + arreglo por tecleo + anulacion para compensar (bot y reintento).
--   * receipt_outcome_status / receipt_outcome_culprit: tabla de codigos del plan (estado del caso y culpable).
--   * receipt_send_after: el aviso no sale fuera de [08:00, 20:00) hora local de la cuenta.
--   * enqueue_receipt_reminder: un recordatorio al culpable por dia, motivo y panelista (escalado si se repite).
--   * receipt_retry_pending (pg_cron cada 30 min): reintenta los not_found pendientes; tras 5 laborables, decision.

-- Si una tabla esta ocupada, mejor fallar a los 5 s que dejar en cola a todas las consultas detras del cerrojo.
SET lock_timeout = '5s';

-- ============================================================================================================
-- 1. Cola de avisos: programacion, caso de origen y clases nuevas
-- ============================================================================================================
ALTER TABLE public.panelist_notification ADD COLUMN IF NOT EXISTS send_after timestamptz NULL;
ALTER TABLE public.panelist_notification
  ADD COLUMN IF NOT EXISTS case_id uuid NULL REFERENCES public.receipt_case(id) ON DELETE SET NULL;

ALTER TABLE public.panelist_notification DROP CONSTRAINT IF EXISTS panelist_notification_kind_check;
-- El DROP/ADD toma ACCESS EXCLUSIVE sobre la tabla hasta el final de la transaccion (la migracion entera); NOT VALID +
-- VALIDATE solo acorta el tramo de comprobacion de las filas existentes, no evita el bloqueo (ver lock_timeout).
ALTER TABLE public.panelist_notification ADD CONSTRAINT panelist_notification_kind_check
  CHECK (kind IN ('unavailability_received', 'plan_change_this_week', 'material_pending_released',
                  'receipt_reminder', 'manager_notice', 'broadcast')) NOT VALID;
ALTER TABLE public.panelist_notification VALIDATE CONSTRAINT panelist_notification_kind_check;

-- Un recordatorio por panelista, motivo y dia local de envio (cuando se encola).
CREATE UNIQUE INDEX IF NOT EXISTS panelist_notification_receipt_reminder_uq
  ON public.panelist_notification (panelist_id, (payload->>'reason'), (payload->>'local_date'))
  WHERE kind = 'receipt_reminder';

-- ============================================================================================================
-- 2. Tabla de codigos: estado del caso y culpable
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
    WHEN p_outcome IN ('pobox_absent_no_visit', 'pobox_absent_unavailable', 'not_sent_cancelled',
                       'wrong_city_cancelled') THEN 'compensated'
    WHEN p_outcome IN ('already_received', 'blocked', 'invalid_format') THEN 'informative'
    WHEN p_outcome = 'not_found' THEN 'pending'
    WHEN p_outcome IN ('ambiguous_typo', 'no_panelist', 'no_node') THEN 'needs_decision'
  END;
$$;

-- Receptor para POBOX; remitente (panelista de origen del envio, o el primero activo de su nodo) para arreglos y
-- anulaciones; nadie en los demas casos.
CREATE OR REPLACE FUNCTION public.receipt_outcome_culprit(p_outcome text, p_detail_id uuid, p_receiver_panelist_id uuid,
                                                          OUT culprit_role text, OUT culprit_panelist_id uuid)
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
BEGIN
  IF p_outcome IN ('pobox_absent_no_visit', 'pobox_absent_unavailable') THEN
    culprit_role := 'receiver';
    culprit_panelist_id := p_receiver_panelist_id;
  ELSIF p_outcome IN ('ok_typo_fixed', 'ok_same_city', 'not_sent_cancelled', 'wrong_city_cancelled') THEN
    culprit_role := 'sender';
    SELECT COALESCE(x.origin_panelist_id,
                    (SELECT p.id FROM public.panelists p
                      WHERE p.node_id = x.origin_node_id AND p.account_id = x.account_id
                      ORDER BY (p.status = 'active') DESC, p.id LIMIT 1))
      INTO culprit_panelist_id
      FROM public.allocation_plan_details x WHERE x.id = p_detail_id;
  END IF;
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
-- Para not_found / ambiguous_typo no cambia nada.
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
        v_cancel_reason := 'received_wrong_city';
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

  -- Anulacion para compensar; si la fila (ya bloqueada) cambio de estado, no se toca.
  IF v_cancel_reason IS NOT NULL THEN
    IF public.cancel_detail_for_compensation(detail_id, v_cancel_reason) THEN
      outcome := CASE v_cancel_reason WHEN 'receipt_before_sent' THEN 'not_sent_cancelled'
                                      ELSE 'wrong_city_cancelled' END;
    ELSE
      outcome := CASE WHEN (SELECT x.status FROM public.allocation_plan_details x WHERE x.id = detail_id) = 'received'
                      THEN 'already_received' ELSE 'blocked' END;
    END IF;
  END IF;
END;
$$;

-- ============================================================================================================
-- 4. Hora de envio de un aviso: dentro de [08:00, 20:00) local; si no, a las 08:00 locales siguientes
-- ============================================================================================================
CREATE OR REPLACE FUNCTION public.receipt_send_after(p_account_id uuid, p_at timestamptz)
RETURNS timestamptz
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_tz text;
  v_local timestamp;
BEGIN
  SELECT a.timezone INTO v_tz FROM public.accounts a WHERE a.id = p_account_id;
  v_tz := COALESCE(v_tz, 'UTC');
  v_local := p_at AT TIME ZONE v_tz;
  IF v_local::time >= time '08:00' AND v_local::time < time '20:00' THEN
    RETURN p_at;
  ELSIF v_local::time < time '08:00' THEN
    RETURN (v_local::date + time '08:00') AT TIME ZONE v_tz;
  ELSE
    RETURN ((v_local::date + 1) + time '08:00') AT TIME ZONE v_tz;
  END IF;
END;
$$;

-- ============================================================================================================
-- 5. Recordatorio al culpable
-- ============================================================================================================
-- Solo casos resueltos con culpable y motivo con recordatorio (tabla de codigos): ok_typo_fixed,
-- pobox_absent_no_visit, not_sent_cancelled, wrong_city_cancelled. Uno al dia (local de envio, hoy) por panelista y
-- motivo: si ya existe devuelve NULL (varios casos resueltos a la vez, aunque sean de dias distintos, = 1 aviso). escalated = el culpable acumula >= 3 casos de ese motivo con
-- primer intento en los ultimos 7 dias (este incluido).
CREATE OR REPLACE FUNCTION public.enqueue_receipt_reminder(p_case_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  c public.receipt_case%ROWTYPE;
  v_tz text;
  v_n int;
  v_id uuid;
BEGIN
  SELECT * INTO c FROM public.receipt_case WHERE id = p_case_id;
  IF NOT FOUND OR c.culprit_panelist_id IS NULL
     OR c.reason NOT IN ('ok_typo_fixed', 'pobox_absent_no_visit', 'not_sent_cancelled', 'wrong_city_cancelled')
     OR c.status NOT IN ('fixed', 'compensated') THEN
    RETURN NULL;
  END IF;

  SELECT a.timezone INTO v_tz FROM public.accounts a WHERE a.id = c.account_id;
  v_tz := COALESCE(v_tz, 'UTC');

  SELECT count(*) INTO v_n
    FROM public.receipt_case rc
   WHERE rc.culprit_panelist_id = c.culprit_panelist_id
     AND rc.reason = c.reason
     AND (rc.first_attempt_at >= now() - interval '7 days' OR rc.id = c.id);

  INSERT INTO public.panelist_notification (account_id, panelist_id, kind, payload, send_after, case_id)
  VALUES (c.account_id, c.culprit_panelist_id, 'receipt_reminder',
          jsonb_build_object('reason', c.reason,
                             'tag', COALESCE(c.tag_norm, c.tag_raw),
                             'local_date', ((now() AT TIME ZONE v_tz)::date)::text,
                             'escalated', v_n >= 3,
                             'case_id', c.id),
          public.receipt_send_after(c.account_id, now()),
          c.id)
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- ============================================================================================================
-- 6. Recepcion del bot (re-emitida: busqueda compartida + recordatorio dentro del bloque fail-open)
-- ============================================================================================================
-- Devuelve {outcome, registered, language, tag, origin_name, origin_city, case_id}. Ver la tabla de codigos del plan.
CREATE OR REPLACE FUNCTION public.bot_receive_parcel(p_telegram_id text, p_tag_raw text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
    'registered', v_outcome IN ('ok', 'ok_typo_fixed', 'ok_same_city'),
    'language', v_lang,
    'tag', v_norm,
    'origin_name', v_origin_name,
    'origin_city', v_origin_city,
    'case_id', v_case_id);
END;
$$;

-- ============================================================================================================
-- 7. Reintento de los not_found pendientes
-- ============================================================================================================
-- Para cada caso not_found/pending: repite la busqueda (exacta + tecleo) con la fecha del primer intento, sin crear
-- casos nuevos. Si resuelve (fixed / compensated) actualiza el caso y encola el recordatorio; si el reintento da
-- ambiguous_typo, pasa a decision con ese motivo; si el envio ya estaba recibido (already_received) el caso se cierra
-- como informativo (no hay nada que esperar); si no y han pasado >= 5 dias laborables desde el primer intento
-- (contados desde el dia local siguiente hasta hoy, ambos incluidos), pasa a needs_decision.
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
      ELSIF v_outcome = 'ambiguous_typo' THEN
        UPDATE public.receipt_case SET reason = v_outcome, status = 'needs_decision' WHERE id = c.id;
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
-- 8. Permisos: solo service_role (y pg_cron como postgres) y llamadas internas.
-- ============================================================================================================
REVOKE EXECUTE ON FUNCTION public.receipt_outcome_status(text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.receipt_outcome_culprit(text, uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.receipt_match_tag(uuid, uuid, text, uuid, text, text, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.receipt_send_after(uuid, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.enqueue_receipt_reminder(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.receipt_retry_pending() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bot_receive_parcel(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.receipt_outcome_status(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.receipt_outcome_culprit(text, uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.receipt_match_tag(uuid, uuid, text, uuid, text, text, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.receipt_send_after(uuid, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.enqueue_receipt_reminder(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.receipt_retry_pending() TO service_role;
GRANT EXECUTE ON FUNCTION public.bot_receive_parcel(text, text) TO service_role;

-- ============================================================================================================
-- 9. pg_cron: reintento cada 30 minutos (idempotente: se quita el job previo si existe)
-- ============================================================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'receipt-retry') THEN
    PERFORM cron.unschedule('receipt-retry');
  END IF;
  PERFORM cron.schedule('receipt-retry', '*/30 * * * *', 'SELECT public.receipt_retry_pending()');
END $$;
