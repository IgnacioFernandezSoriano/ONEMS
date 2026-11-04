-- Errores de recepcion: registro de casos y recepcion del bot con arreglo automatico.
-- Spec: docs/superpowers/specs/2026-11-04-errores-recepcion-design.md (secciones 3, 4 y 7 bis). Tarea 1 del plan.
--
-- Todo es ADITIVO: el SQL actual del nodo n8n «Find and mark received» sigue funcionando igual (no se toca el
-- trigger pobox_receipt_rule ni ninguna columna existente). El bot pasara a llamar a bot_receive_parcel en la tarea 6.
--
--   * receipt_case: un caso por intento fallido (o arreglado) de declarar una recepcion; los reintentos de la misma
--     etiqueta se agrupan en el mismo caso (attempts).
--   * receipt_typo_candidates: envios 'sent' hacia la ciudad del receptor cuya etiqueta difiere en 1 cifra o en
--     2 cifras adyacentes intercambiadas.
--   * register_receipt_with_rules: marca recibido con la fecha dada y evalua la regla POBOX aqui mismo (tambien con
--     usuario web), sin pasar nunca por 'received' si la regla la anula (no llega a one_db).
--   * cancel_detail_for_compensation: anula un envio y lo anota en deferred_samples para el siguiente balanceo.
--   * bot_receive_parcel: clasificacion + arreglo automatico + registro del caso + respuesta, en una transaccion.

-- Si una tabla esta ocupada, mejor fallar a los 5 s que dejar en cola a todas las consultas detras del cerrojo.
SET lock_timeout = '5s';

-- ============================================================================================================
-- 1. Motivos nuevos de anulacion / compensacion
-- ============================================================================================================
ALTER TABLE public.allocation_plan_details
  DROP CONSTRAINT IF EXISTS allocation_plan_details_cancellation_reason_check;
-- El DROP/ADD toma ACCESS EXCLUSIVE sobre la tabla hasta el final de la transaccion (la migracion entera); NOT VALID +
-- VALIDATE solo acorta el tramo de comprobacion de las filas existentes (VALIDATE usa un cerrojo mas ligero), no
-- evita el bloqueo. Por eso el lock_timeout de arriba.
ALTER TABLE public.allocation_plan_details
  ADD CONSTRAINT allocation_plan_details_cancellation_reason_check
  CHECK (cancellation_reason IS NULL
         OR cancellation_reason IN ('pobox_absent_unavailable', 'pobox_absent_no_visit',
                                    'receipt_before_sent', 'received_wrong_city')) NOT VALID;
ALTER TABLE public.allocation_plan_details VALIDATE CONSTRAINT allocation_plan_details_cancellation_reason_check;

ALTER TABLE public.deferred_samples DROP CONSTRAINT IF EXISTS deferred_samples_reason_check;
ALTER TABLE public.deferred_samples
  ADD CONSTRAINT deferred_samples_reason_check
  CHECK (reason IN ('origin_no_panelist', 'dest_no_panelist', 'no_valid_day',
                    'pobox_absent_unavailable', 'pobox_absent_no_visit',
                    'receipt_before_sent', 'received_wrong_city')) NOT VALID;
ALTER TABLE public.deferred_samples VALIDATE CONSTRAINT deferred_samples_reason_check;

-- ============================================================================================================
-- 2. Registro de casos
-- ============================================================================================================
CREATE TABLE IF NOT EXISTS public.receipt_case (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  panelist_id uuid NULL REFERENCES public.panelists(id) ON DELETE SET NULL,
  telegram_id text NOT NULL,
  tag_raw text NOT NULL,
  tag_norm text NULL,
  detail_id uuid NULL REFERENCES public.allocation_plan_details(id) ON DELETE SET NULL,
  reason text NOT NULL CHECK (reason IN ('ok', 'ok_typo_fixed', 'ok_same_city',
                                         'pobox_absent_unavailable', 'pobox_absent_no_visit',
                                         'not_sent_cancelled', 'wrong_city_cancelled',
                                         'already_received', 'blocked', 'not_found', 'ambiguous_typo',
                                         'invalid_format', 'no_panelist', 'no_node')),
  status text NOT NULL CHECK (status IN ('fixed', 'compensated', 'informative', 'pending', 'needs_decision', 'discarded')),
  culprit_panelist_id uuid NULL,
  culprit_role text NULL CHECK (culprit_role IN ('sender', 'receiver')),
  attempts int NOT NULL DEFAULT 1,
  first_attempt_at timestamptz NOT NULL,
  last_attempt_at timestamptz NOT NULL,
  resolved_at timestamptz NULL,
  resolved_by uuid NULL,
  resolution_note text NULL,
  -- Etiqueta que tenia el envio (la que declaro el remitente) cuando un arreglo por tecleo la reescribe.
  original_tag text NULL,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS receipt_case_account_first_idx ON public.receipt_case (account_id, first_attempt_at);
CREATE INDEX IF NOT EXISTS receipt_case_account_status_idx ON public.receipt_case (account_id, status);
CREATE INDEX IF NOT EXISTS receipt_case_culprit_first_idx ON public.receipt_case (culprit_panelist_id, first_attempt_at);
-- Un solo caso abierto por panelista (telegram) y etiqueta.
CREATE UNIQUE INDEX IF NOT EXISTS receipt_case_open_uq ON public.receipt_case (account_id, telegram_id, tag_norm)
  WHERE status IN ('pending', 'needs_decision');

ALTER TABLE public.receipt_case ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS receipt_case_select ON public.receipt_case;
CREATE POLICY receipt_case_select ON public.receipt_case
  FOR SELECT TO authenticated
  USING ((public.current_user_role() = 'admin' AND account_id = public.current_user_account_id())
         OR public.is_superadmin());

-- Escrituras solo desde funciones SECURITY DEFINER.
REVOKE ALL ON public.receipt_case FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.receipt_case TO authenticated;
GRANT ALL ON public.receipt_case TO service_role;

-- ============================================================================================================
-- 3. Candidatos por error de tecleo
-- ============================================================================================================
-- Envios 'sent' de la cuenta con destino en un nodo de p_city_id cuya etiqueta (solo cifras, misma longitud) difiere
-- de p_tag en exactamente 1 posicion, o en 2 posiciones adyacentes intercambiadas. Nunca la propia p_tag.
-- Solo envios declarados (sent_at) no despues de p_max_sent_at (la hora de la recepcion): un envio declarado despues
-- de la recepcion no puede ser la carta recibida.
DROP FUNCTION IF EXISTS public.receipt_typo_candidates(uuid, uuid, text);
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
     AND x.status = 'sent'
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
-- 4. Recepcion con la regla POBOX evaluada aqui
-- ============================================================================================================
-- Marca el detalle como recibido en p_received_at (rellena el panelista de destino si falta). La regla POBOX se salta
-- en el trigger y se evalua aqui sobre la fila resultante, haya o no usuario web: si la anula, la muestra va a
-- deferred_samples (snapshot con status 'received') y la fila queda 'cancelled' con el motivo, sin haber pasado
-- por 'received' (no se transfiere a one_db).
-- Devuelve un codigo de outcome: 'ok', el motivo POBOX, 'already_received' / 'blocked' (la fila, ya bloqueada, no
-- esta 'sent': no se toca) o 'not_sent_cancelled' (la recepcion seria anterior a la declaracion del envio: se anula
-- y se compensa como receipt_before_sent).
CREATE OR REPLACE FUNCTION public.register_receipt_with_rules(p_detail_id uuid, p_received_at timestamptz,
                                                              p_receiver_panelist_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r public.allocation_plan_details%ROWTYPE;
  v_reason text;
  v_prev text;
  v_origin_city uuid;
  v_dest_city uuid;
BEGIN
  SELECT * INTO r FROM public.allocation_plan_details WHERE id = p_detail_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'register_receipt_with_rules: el detalle % no existe', p_detail_id;
  END IF;
  IF r.status = 'received' THEN
    RETURN 'already_received';
  ELSIF r.status <> 'sent' THEN
    RETURN 'blocked';
  END IF;
  -- Recepcion anterior a la declaracion del envio (p. ej. reintento con la fecha del primer intento): no vale.
  IF r.sent_at IS NOT NULL AND r.sent_at > p_received_at THEN
    PERFORM public.cancel_detail_for_compensation(p_detail_id, 'receipt_before_sent');
    RETURN 'not_sent_cancelled';
  END IF;

  r.status := 'received';
  r.received_at := p_received_at;
  r.destination_panelist_id := COALESCE(r.destination_panelist_id, p_receiver_panelist_id);
  r.destination_panelist_name := COALESCE(r.destination_panelist_name,
                                          (SELECT p.name FROM public.panelists p WHERE p.id = p_receiver_panelist_id));

  BEGIN
    v_reason := public.pobox_receipt_check(r);
  EXCEPTION WHEN OTHERS THEN
    -- Igual que el trigger: ante cualquier fallo de la regla, la recepcion se acepta.
    RAISE WARNING 'register_receipt_with_rules: regla POBOX: % (detalle %)', SQLERRM, p_detail_id;
    v_reason := NULL;
  END;

  v_prev := current_setting('onems.skip_pobox_receipt_rule', true);
  PERFORM set_config('onems.skip_pobox_receipt_rule', 'on', true);

  IF v_reason IS NOT NULL THEN
    BEGIN
      SELECT n.city_id INTO v_origin_city FROM public.nodes n WHERE n.id = r.origin_node_id;
      SELECT n.city_id INTO v_dest_city FROM public.nodes n WHERE n.id = r.destination_node_id;
      INSERT INTO public.deferred_samples
        (account_id, plan_id, origin_city_id, dest_city_id, origin_node_id, destination_node_id,
         fecha_programada, reason, row_snapshot, created_by)
      VALUES
        (r.account_id, r.plan_id, v_origin_city, v_dest_city, r.origin_node_id, r.destination_node_id,
         r.fecha_programada, v_reason, to_jsonb(r), NULL);
      UPDATE public.allocation_plan_details
         SET status = 'cancelled',
             cancellation_reason = v_reason,
             cancelled_at = now(),
             received_at = p_received_at,
             destination_panelist_id = r.destination_panelist_id,
             destination_panelist_name = r.destination_panelist_name
       WHERE id = p_detail_id;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'register_receipt_with_rules: anulacion POBOX: % (detalle %)', SQLERRM, p_detail_id;
      v_reason := NULL;
    END;
  END IF;

  IF v_reason IS NULL THEN
    UPDATE public.allocation_plan_details
       SET status = 'received',
           received_at = p_received_at,
           destination_panelist_id = r.destination_panelist_id,
           destination_panelist_name = r.destination_panelist_name
     WHERE id = p_detail_id;
  END IF;

  -- Restaura el ajuste para que el resto de la transaccion vuelva a pasar por el trigger.
  PERFORM set_config('onems.skip_pobox_receipt_rule', COALESCE(v_prev, ''), true);
  RETURN COALESCE(v_reason, 'ok');
END;
$$;

-- ============================================================================================================
-- 5. Anulacion para compensar
-- ============================================================================================================
-- Devuelve true si actuo; false (sin cambios) si la fila, ya bloqueada, no esta en sent/pending/notified.
CREATE OR REPLACE FUNCTION public.cancel_detail_for_compensation(p_detail_id uuid, p_reason text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r public.allocation_plan_details%ROWTYPE;
  v_origin_city uuid;
  v_dest_city uuid;
BEGIN
  SELECT * INTO r FROM public.allocation_plan_details WHERE id = p_detail_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'cancel_detail_for_compensation: el detalle % no existe', p_detail_id;
  END IF;
  IF r.status NOT IN ('sent', 'pending', 'notified') THEN
    RETURN false;
  END IF;
  SELECT n.city_id INTO v_origin_city FROM public.nodes n WHERE n.id = r.origin_node_id;
  SELECT n.city_id INTO v_dest_city FROM public.nodes n WHERE n.id = r.destination_node_id;

  INSERT INTO public.deferred_samples
    (account_id, plan_id, origin_city_id, dest_city_id, origin_node_id, destination_node_id,
     fecha_programada, reason, row_snapshot, created_by)
  VALUES
    (r.account_id, r.plan_id, v_origin_city, v_dest_city, r.origin_node_id, r.destination_node_id,
     r.fecha_programada, p_reason, to_jsonb(r), auth.uid());

  UPDATE public.allocation_plan_details
     SET status = 'cancelled', cancellation_reason = p_reason, cancelled_at = now()
   WHERE id = p_detail_id;
  RETURN true;
END;
$$;

-- ============================================================================================================
-- 6. Recepcion del bot
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
  v_city uuid;
  v_recv_at timestamptz;
  v_det_id uuid;
  v_det_status text;
  v_det_dest uuid;
  v_det_city uuid;
  v_det_sent timestamptz;
  v_orig_tag text;
  v_detail uuid;
  v_outcome text;
  v_res text;
  v_cancel_reason text;
  v_n int;
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
    SELECT n.city_id INTO v_city FROM public.nodes n WHERE n.id = v_pnode;
    -- Si ya habia un caso abierto con esta etiqueta, la recepcion cuenta desde el primer intento.
    SELECT rc.first_attempt_at INTO v_recv_at
      FROM public.receipt_case rc
     WHERE rc.account_id = v_account AND rc.telegram_id = v_tg AND rc.tag_norm = v_norm
       AND rc.status IN ('pending', 'needs_decision')
     LIMIT 1;
    v_recv_at := COALESCE(v_recv_at, v_now);

    -- 2. Envio con esa etiqueta hacia su nodo ('sent' primero, el mas antiguo; si no, el no-sent mas reciente).
    SELECT x.id, x.status INTO v_det_id, v_det_status
      FROM public.allocation_plan_details x
     WHERE x.account_id = v_account AND x.destination_node_id = v_pnode AND x.tag_id = v_norm
     ORDER BY (x.status = 'sent') DESC,
              CASE WHEN x.status = 'sent' THEN x.fecha_programada END ASC,
              x.fecha_programada DESC
     LIMIT 1;

    IF FOUND THEN
      v_detail := v_det_id;
      IF v_det_status = 'sent' THEN
        -- 'ok', el motivo POBOX, o already_received / blocked / not_sent_cancelled tras bloquear la fila
        v_outcome := public.register_receipt_with_rules(v_det_id, v_recv_at, v_pid);
      ELSIF v_det_status = 'received' THEN
        v_outcome := 'already_received';
      ELSIF v_det_status IN ('pending', 'notified') THEN
        v_cancel_reason := 'receipt_before_sent';
      ELSE
        v_outcome := 'blocked';
      END IF;
    ELSE
      -- 3. Envio con esa etiqueta hacia otro nodo: misma ciudad antes que otra ciudad; dentro, como en 2.
      SELECT x.id, x.status, x.destination_node_id, n.city_id, x.sent_at
        INTO v_det_id, v_det_status, v_det_dest, v_det_city, v_det_sent
        FROM public.allocation_plan_details x
        JOIN public.nodes n ON n.id = x.destination_node_id
       WHERE x.account_id = v_account AND x.tag_id = v_norm AND x.destination_node_id <> v_pnode
       ORDER BY (v_city IS NOT NULL AND n.city_id = v_city) DESC,
                (x.status = 'sent') DESC,
                CASE WHEN x.status = 'sent' THEN x.fecha_programada END ASC,
                x.fecha_programada DESC
       LIMIT 1;

      IF FOUND THEN
        v_detail := v_det_id;
        IF v_det_status = 'received' THEN
          v_outcome := 'already_received';
        ELSIF v_det_status NOT IN ('sent', 'pending', 'notified') THEN
          v_outcome := 'blocked';
        ELSIF v_city IS NOT NULL AND v_det_city = v_city THEN
          -- Declarado despues de la recepcion: no se mueve el destino; se anula como receipt_before_sent.
          IF v_det_status = 'sent' AND (v_det_sent IS NULL OR v_det_sent <= v_recv_at) THEN
            UPDATE public.allocation_plan_details
               SET original_destination_node_id = COALESCE(original_destination_node_id, destination_node_id),
                   destination_node_id = v_pnode,
                   destination_panelist_id = v_pid,
                   destination_panelist_name = v_pname
             WHERE id = v_det_id AND status = 'sent';
            -- Si ya no estaba 'sent', register no toca la fila y devuelve already_received / blocked.
            v_res := public.register_receipt_with_rules(v_det_id, v_recv_at, v_pid);
            v_outcome := CASE WHEN v_res = 'ok' THEN 'ok_same_city' ELSE v_res END;
          ELSE
            v_cancel_reason := 'receipt_before_sent';
          END IF;
        ELSE
          v_cancel_reason := 'received_wrong_city';
        END IF;
      ELSE
        -- 4. No existe: error de tecleo con un unico candidato en su ciudad.
        SELECT count(*), min(c.id::text)::uuid INTO v_n, v_det_id
          FROM public.receipt_typo_candidates(v_account, v_city, v_norm, v_recv_at) c(id);
        IF v_n = 1 THEN
          SELECT x.tag_id INTO v_orig_tag FROM public.allocation_plan_details x WHERE x.id = v_det_id FOR UPDATE;
          UPDATE public.allocation_plan_details
             SET tag_id = v_norm, idtag = COALESCE(NULLIF(btrim(v_raw), ''), v_norm)
           WHERE id = v_det_id AND status = 'sent'
          RETURNING destination_node_id INTO v_det_dest;
          IF NOT FOUND THEN
            v_orig_tag := NULL;
            v_outcome := 'not_found';   -- el candidato dejo de estar 'sent' entretanto
          ELSE
            v_detail := v_det_id;
            IF v_det_dest <> v_pnode THEN
              UPDATE public.allocation_plan_details
                 SET original_destination_node_id = COALESCE(original_destination_node_id, destination_node_id),
                     destination_node_id = v_pnode,
                     destination_panelist_id = v_pid,
                     destination_panelist_name = v_pname
               WHERE id = v_det_id AND status = 'sent';
            END IF;
            v_res := public.register_receipt_with_rules(v_det_id, v_recv_at, v_pid);
            v_outcome := CASE WHEN v_res = 'ok' THEN 'ok_typo_fixed' ELSE v_res END;
          END IF;
        ELSIF v_n > 1 THEN
          v_outcome := 'ambiguous_typo';
        ELSE
          v_outcome := 'not_found';
        END IF;
      END IF;
    END IF;

    -- Anulacion para compensar; si la fila (ya bloqueada) cambio de estado, no se toca.
    IF v_cancel_reason IS NOT NULL THEN
      IF public.cancel_detail_for_compensation(v_detail, v_cancel_reason) THEN
        v_outcome := CASE v_cancel_reason WHEN 'receipt_before_sent' THEN 'not_sent_cancelled'
                                          ELSE 'wrong_city_cancelled' END;
      ELSE
        v_outcome := CASE WHEN (SELECT x.status FROM public.allocation_plan_details x WHERE x.id = v_detail) = 'received'
                          THEN 'already_received' ELSE 'blocked' END;
      END IF;
    END IF;
  END IF;

  -- 5. Registro del caso (fail-open: un fallo aqui nunca impide contestar ni deshace la recepcion).
  v_status := CASE
    -- 'ok' solo deja huella si cierra un caso abierto (reintento que ahora si encuentra el envio)
    WHEN v_outcome IN ('ok', 'ok_typo_fixed', 'ok_same_city') THEN 'fixed'
    WHEN v_outcome IN ('pobox_absent_no_visit', 'pobox_absent_unavailable', 'not_sent_cancelled',
                       'wrong_city_cancelled') THEN 'compensated'
    WHEN v_outcome IN ('already_received', 'blocked', 'invalid_format') THEN 'informative'
    WHEN v_outcome = 'not_found' THEN 'pending'
    WHEN v_outcome IN ('ambiguous_typo', 'no_panelist', 'no_node') THEN 'needs_decision'
  END;
  IF v_outcome IN ('pobox_absent_no_visit', 'pobox_absent_unavailable') THEN
    v_culprit_role := 'receiver';
    v_culprit := v_pid;
  ELSIF v_outcome IN ('ok_typo_fixed', 'ok_same_city', 'not_sent_cancelled', 'wrong_city_cancelled') THEN
    v_culprit_role := 'sender';
    SELECT COALESCE(x.origin_panelist_id,
                    (SELECT p.id FROM public.panelists p
                      WHERE p.node_id = x.origin_node_id AND p.account_id = x.account_id
                      ORDER BY (p.status = 'active') DESC, p.id LIMIT 1))
      INTO v_culprit
      FROM public.allocation_plan_details x WHERE x.id = v_detail;
  END IF;

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
-- 7. Permisos: solo service_role (el bot conecta con la credencial Postgres = propietario) y llamadas internas.
-- ============================================================================================================
REVOKE EXECUTE ON FUNCTION public.receipt_typo_candidates(uuid, uuid, text, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.register_receipt_with_rules(uuid, timestamptz, uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.cancel_detail_for_compensation(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bot_receive_parcel(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.receipt_typo_candidates(uuid, uuid, text, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.register_receipt_with_rules(uuid, timestamptz, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.cancel_detail_for_compensation(uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.bot_receive_parcel(text, text) TO service_role;
