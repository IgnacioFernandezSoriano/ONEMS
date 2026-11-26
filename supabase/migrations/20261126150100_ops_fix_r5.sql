-- ============================================================
-- Agente de operaciones: arreglo R5 «Etiqueta mal escrita» — 2026-11-26
-- ============================================================
-- Spec: docs/superpowers/specs/2026-11-26-agente-analisis-completo-r5-design.md (§2).
-- Mismo patrón que R4 (20261110140000_ops_fix_r4.sql, firma de gestor en 20261111090000_bot_managers.sql):
-- token + cuenta + quien actúa (ops_case._actor, prefijo 'ops_fix'), caso FOR UPDATE, foto «before» en
-- ops_fix.log, comprobación de la copia a ONE DB y deshacer en 24 h.
-- Requiere ops_case._typo_kind (20261126150000) y, sin cambios, public.receipt_typo_candidates,
-- public.revive_timeout_detail (20261104130000) y public.rpc_receipt_case_fix (20261119100200).
--
-- Caso: un receptor declara una etiqueta que no está en el plan (receipt_case.reason 'ambiguous_typo' o
-- 'not_found', abierto). Si el remitente la escribió mal, la línea buena es una con la etiqueta a un error de
-- tecleo (una cifra distinta o dos contiguas intercambiadas) hacia la ciudad del receptor. La BD NO elige:
-- la vista previa devuelve los candidatos (1 a 5) y el gestor escoge uno.
--
--   * Aplicar: revive_timeout_detail si la línea estaba anulada por plazo, luego rpc_receipt_case_fix(caso,
--     línea): etiqueta = la del caso, destino al nodo del receptor si es otro de la misma ciudad, recepción con
--     first_attempt_at (copia a ONE DB por el disparador), caso 'fixed' con culpable y recordatorio al remitente.
--     Exige resultado ok_typo_fixed / ok_same_city y la copia a ONE DB; si no, falla sin dejar nada escrito.
--   * Deshacer (24 h, una vez): borra la copia en ONE DB, restaura la línea y el caso desde la foto y borra el
--     recordatorio de ese arreglo si no ha salido (si salió, deshace igual y lo dice: reminder_already_sent).
-- ============================================================

SET lock_timeout = '5s';

ALTER TABLE ops_fix.log
  DROP CONSTRAINT IF EXISTS log_kind_check,
  ADD CONSTRAINT log_kind_check CHECK (kind IN ('r1', 'r2', 'r3', 'r4', 'r5'));

-- ---------- internas ----------
-- Campos de la línea que toca R5 (o rpc_receipt_case_fix / el disparador de ONE DB al aplicarlo).
CREATE OR REPLACE FUNCTION ops_fix._r5_line(p_detail_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'id', d.id, 'account_id', d.account_id, 'tag_id', d.tag_id, 'idtag', d.idtag, 'status', d.status,
    'received_at', d.received_at, 'cancellation_reason', d.cancellation_reason, 'cancelled_at', d.cancelled_at,
    'destination_node_id', d.destination_node_id, 'destination_panelist_id', d.destination_panelist_id,
    'destination_panelist_name', d.destination_panelist_name,
    'original_destination_node_id', d.original_destination_node_id,
    'origin_panelist_id', d.origin_panelist_id, 'origin_panelist_name', d.origin_panelist_name,
    'transferred_to_one_db_at', d.transferred_to_one_db_at, 'validation_errors', d.validation_errors,
    'transfer_error_message', d.transfer_error_message)
    FROM public.allocation_plan_details d WHERE d.id = p_detail_id;
$$;

-- Campos del caso que toca R5.
CREATE OR REPLACE FUNCTION ops_fix._r5_case(p_case_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object('id', c.id, 'account_id', c.account_id, 'status', c.status, 'reason', c.reason,
                            'detail_id', c.detail_id, 'original_tag', c.original_tag,
                            'culprit_role', c.culprit_role, 'culprit_panelist_id', c.culprit_panelist_id,
                            'resolved_at', c.resolved_at, 'resolved_by', c.resolved_by,
                            'resolution_note', c.resolution_note)
    FROM public.receipt_case c WHERE c.id = p_case_id;
$$;

-- Vista previa de R5 (también la usa apply). Falla solo si el caso no existe. Claves: applicable, reason,
-- case_status, tag, candidates [{detail_id, current_tag, new_tag, kind, origin_code, origin_name,
-- destination_code, destination_name, sent_at, status, revive, moves_node}] y, interna, account_id.
-- candidates va vacío si no aplica, salvo con «demasiados parecidos» (los 5 primeros).
-- Orden: mismo nodo que el receptor, luego cifras intercambiadas, luego sent_at más antiguo (solo presentación).
CREATE OR REPLACE FUNCTION ops_fix._r5_check(p_case_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  c public.receipt_case; v_reason text; v_node uuid; v_city uuid; v_cands jsonb := '[]'::jsonb; v_n int := 0;
BEGIN
  SELECT * INTO c FROM public.receipt_case x WHERE x.id = p_case_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ops_fix: el caso % no existe', p_case_id;
  END IF;

  -- El receptor (panelista del caso, de la misma cuenta) y la ciudad de su nodo.
  IF c.panelist_id IS NOT NULL THEN
    SELECT p.node_id, n.city_id INTO v_node, v_city
      FROM public.panelists p
      JOIN public.nodes n ON n.id = p.node_id AND n.account_id = c.account_id
     WHERE p.id = c.panelist_id AND p.account_id = c.account_id;
  END IF;

  IF c.status NOT IN ('pending', 'needs_decision') THEN
    v_reason := 'el caso no está abierto';
  ELSIF c.reason NOT IN ('ambiguous_typo', 'not_found') THEN
    v_reason := 'motivo del caso no admitido';
  ELSIF v_city IS NULL THEN
    v_reason := 'el panelista no tiene nodo con ciudad';
  ELSIF c.tag_norm IS NOT NULL AND EXISTS (SELECT 1 FROM public.allocation_plan_details x
                                            WHERE x.account_id = c.account_id
                                              AND public.normalize_tag(x.tag_id) = c.tag_norm) THEN
    v_reason := 'la etiqueta ya existe en el plan';
  END IF;

  IF v_reason IS NULL THEN
    -- Candidatos: exactamente receipt_typo_candidates (misma ciudad, sent o anulado por plazo sin recepción,
    -- sent_at <= primer intento, a un error de tecleo) y fuera de deferred_samples.
    SELECT count(*), COALESCE(jsonb_agg(q.obj ORDER BY q.ord1, q.ord2, q.sent_at, q.id) FILTER (WHERE q.rn <= 5), '[]'::jsonb)
      INTO v_n, v_cands
      FROM (SELECT z.*, row_number() OVER (ORDER BY z.ord1, z.ord2, z.sent_at, z.id) AS rn
              FROM (SELECT x.id, x.sent_at,
                           (x.destination_node_id IS DISTINCT FROM v_node) AS ord1,
                           (ops_case._typo_kind(c.tag_norm, x.tag_id) IS DISTINCT FROM 'swap') AS ord2,
                           jsonb_build_object(
                             'detail_id', x.id,
                             'current_tag', x.tag_id,
                             'new_tag', c.tag_norm,
                             'kind', ops_case._typo_kind(c.tag_norm, x.tag_id),
                             'origin_code', op.panelist_code, 'origin_name', op.name,
                             'destination_code', dp.panelist_code, 'destination_name', dp.name,
                             'sent_at', x.sent_at,
                             'status', x.status,
                             'revive', x.status = 'cancelled',
                             'moves_node', x.destination_node_id IS DISTINCT FROM v_node) AS obj
                      FROM public.receipt_typo_candidates(c.account_id, v_city, c.tag_norm, c.first_attempt_at) k(id)
                      JOIN public.allocation_plan_details x ON x.id = k.id AND x.account_id = c.account_id
                      LEFT JOIN public.panelists op
                        ON op.id = ops_case._side(x.origin_panelist_id, x.origin_node_id, c.account_id)
                       AND op.account_id = c.account_id
                      LEFT JOIN public.panelists dp
                        ON dp.id = ops_case._side(x.destination_panelist_id, x.destination_node_id, c.account_id)
                       AND dp.account_id = c.account_id
                     WHERE NOT EXISTS (SELECT 1 FROM public.deferred_samples ds
                                        WHERE ds.row_snapshot->>'id' = x.id::text)) z) q;
    IF v_n = 0 THEN
      v_reason := 'ningún envío parecido';
    ELSIF v_n > 5 THEN
      v_reason := 'demasiados parecidos';
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'applicable', v_reason IS NULL,
    'reason', v_reason,
    'account_id', c.account_id,
    'case_status', c.status,
    'tag', c.tag_norm,
    'candidates', CASE WHEN v_reason IS NULL OR v_reason = 'demasiados parecidos' THEN v_cands ELSE '[]'::jsonb END);
END $$;

-- ---------- R5: vista previa ----------
CREATE OR REPLACE FUNCTION public.ops_fix_r5_preview(p_token text, p_case_id uuid, p_account text DEFAULT NULL,
                                                     p_actor_email text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v jsonb; v_acc uuid; v_case_acc uuid;
BEGIN
  v_acc := ops_case._actor(p_token, p_account, p_actor_email, 'ops_fix');
  -- la cuenta del caso se mira ANTES de _r5_check: con otra cuenta no se evalúa nada de sus datos
  IF v_acc IS NOT NULL THEN
    SELECT c.account_id INTO v_case_acc FROM public.receipt_case c WHERE c.id = p_case_id;
    IF v_case_acc IS NOT NULL AND v_case_acc <> v_acc THEN
      RAISE EXCEPTION 'ops_fix: otra cuenta';
    END IF;
  END IF;
  v := ops_fix._r5_check(p_case_id);
  IF v_acc IS NOT NULL AND (v->>'account_id')::uuid IS DISTINCT FROM v_acc THEN
    RAISE EXCEPTION 'ops_fix: otra cuenta';
  END IF;
  RETURN v - 'account_id';
END $$;

-- ---------- R5: aplicar ----------
-- p_expected = el objeto candidato tal como se enseñó (detail_id, etiquetas, lados, sent_at, estado...).
CREATE OR REPLACE FUNCTION public.ops_fix_r5_apply(p_token text, p_case_id uuid, p_detail_id uuid, p_expected jsonb,
                                                   p_account text DEFAULT NULL, p_actor_email text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE c public.receipt_case; v jsonb; v_cand jsonb; v_exp_at timestamptz; v_acc uuid; v_before jsonb; v_after jsonb;
        v_prev_notif uuid[]; v_new_notif uuid[]; v_outcome text; v_line jsonb; v_onedb uuid[]; v_log bigint;
BEGIN
  v_acc := ops_case._actor(p_token, p_account, p_actor_email, 'ops_fix');
  SELECT * INTO c FROM public.receipt_case x WHERE x.id = p_case_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ops_fix: el caso % no existe', p_case_id;
  END IF;
  IF v_acc IS NOT NULL AND c.account_id IS DISTINCT FROM v_acc THEN
    RAISE EXCEPTION 'ops_fix: otra cuenta';
  END IF;
  -- la línea elegida (si es de la cuenta) y las que ya tuvieran la etiqueta del caso
  PERFORM 1 FROM public.allocation_plan_details x
   WHERE x.account_id = c.account_id
     AND (x.id = p_detail_id OR (c.tag_norm IS NOT NULL AND public.normalize_tag(x.tag_id) = c.tag_norm))
   FOR UPDATE;

  v := ops_fix._r5_check(p_case_id);
  IF NOT (v->>'applicable')::boolean THEN
    RAISE EXCEPTION 'ops_fix: R5 no aplica: %', v->>'reason';
  END IF;
  SELECT x INTO v_cand FROM jsonb_array_elements(v->'candidates') x WHERE x->>'detail_id' = p_detail_id::text;
  IF v_cand IS NULL THEN
    RAISE EXCEPTION 'ops_fix: no es un candidato';
  END IF;
  BEGIN
    v_exp_at := (p_expected->>'sent_at')::timestamptz;
  EXCEPTION WHEN OTHERS THEN
    v_exp_at := NULL;
  END;
  -- la ficha mostrada debe contener todos los campos actuales del candidato (sent_at se compara como fecha)
  IF p_expected IS NULL OR jsonb_typeof(p_expected) <> 'object'
     OR NOT (p_expected @> (v_cand - 'sent_at'))
     OR (v_cand->>'sent_at')::timestamptz IS DISTINCT FROM v_exp_at THEN
    RAISE EXCEPTION 'ops_fix: ha cambiado desde la propuesta';
  END IF;

  v_before := jsonb_build_object('line', ops_fix._r5_line(p_detail_id), 'case', ops_fix._r5_case(p_case_id));
  v_prev_notif := ARRAY(SELECT n.id FROM public.panelist_notification n
                         WHERE n.case_id = p_case_id AND n.kind = 'receipt_reminder');

  IF (v_cand->>'revive')::boolean THEN
    IF NOT public.revive_timeout_detail(p_detail_id) THEN
      RAISE EXCEPTION 'ops_fix: la línea cambió mientras se aplicaba; no toco nada';
    END IF;
  END IF;
  v_outcome := public.rpc_receipt_case_fix(p_case_id, p_detail_id);
  IF v_outcome IS NULL OR v_outcome NOT IN ('ok_typo_fixed', 'ok_same_city') THEN
    RAISE EXCEPTION 'ops_fix: el arreglo dio «%»; no toco nada', v_outcome;
  END IF;

  -- Relectura: la línea recibida y su copia en ONE DB (la hace el disparador transfer_to_one_db).
  v_line := ops_fix._r5_line(p_detail_id);
  v_onedb := ARRAY(SELECT o.id FROM public.one_db o WHERE o.allocation_detail_id = p_detail_id);
  IF v_line->>'status' IS DISTINCT FROM 'received' OR (v_line->>'transferred_to_one_db_at') IS NULL
     OR cardinality(v_onedb) <> 1 THEN
    RAISE EXCEPTION 'ops_fix: la copia a ONE DB no se hizo; no toco nada';
  END IF;

  -- recordatorios que ha encolado este arreglo (los anteriores del caso, si los hubiera, no se tocan al deshacer)
  v_new_notif := ARRAY(SELECT n.id FROM public.panelist_notification n
                        WHERE n.case_id = p_case_id AND n.kind = 'receipt_reminder' AND NOT (n.id = ANY (v_prev_notif)));

  v_after := jsonb_build_object('line', v_line, 'case', ops_fix._r5_case(p_case_id), 'one_db_id', v_onedb[1],
                                'notification_ids', to_jsonb(v_new_notif), 'outcome', v_outcome);
  INSERT INTO ops_fix.log (kind, account_id, target, before, after)
  VALUES ('r5', c.account_id, jsonb_build_object('case_id', p_case_id, 'detail_id', p_detail_id)::text, v_before, v_after)
  RETURNING id INTO v_log;
  RETURN jsonb_build_object('log_id', v_log, 'outcome', v_outcome);
END $$;

-- ---------- R5: deshacer (24 h) ----------
CREATE OR REPLACE FUNCTION public.ops_fix_r5_undo(p_token text, p_log_id bigint, p_account text DEFAULT NULL,
                                                  p_actor_email text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE l ops_fix.log; v_acc uuid; v_det uuid; v_case uuid; v_onedb uuid; v_notif uuid[]; v_n int; v_sent boolean;
BEGIN
  v_acc := ops_case._actor(p_token, p_account, p_actor_email, 'ops_fix');
  SELECT * INTO l FROM ops_fix.log x WHERE x.id = p_log_id FOR UPDATE;
  IF NOT FOUND OR l.kind <> 'r5' THEN
    RAISE EXCEPTION 'ops_fix: el registro % no es un arreglo R5', p_log_id;
  END IF;
  IF v_acc IS NOT NULL AND l.account_id IS DISTINCT FROM v_acc THEN
    RAISE EXCEPTION 'ops_fix: otra cuenta';
  END IF;
  IF l.undone_at IS NOT NULL THEN
    RAISE EXCEPTION 'ops_fix: el arreglo % ya se deshizo', p_log_id;
  END IF;
  IF l.applied_at <= now() - interval '24 hours' THEN
    RAISE EXCEPTION 'ops_fix: han pasado más de 24 h desde el arreglo %; no lo deshago', p_log_id;
  END IF;

  v_det := (l.after->'line'->>'id')::uuid;
  v_case := (l.after->'case'->>'id')::uuid;
  v_onedb := (l.after->>'one_db_id')::uuid;
  v_notif := ARRAY(SELECT jsonb_array_elements_text(COALESCE(l.after->'notification_ids', '[]'::jsonb))::uuid);
  PERFORM 1 FROM public.allocation_plan_details x WHERE x.id = v_det AND x.account_id = l.account_id FOR UPDATE;
  PERFORM 1 FROM public.receipt_case x WHERE x.id = v_case AND x.account_id = l.account_id FOR UPDATE;
  PERFORM 1 FROM public.one_db o WHERE o.id = v_onedb FOR UPDATE;
  PERFORM 1 FROM public.panelist_notification n WHERE n.id = ANY (v_notif) FOR UPDATE;

  IF ops_fix._r5_line(v_det) IS DISTINCT FROM l.after->'line'
     OR ops_fix._r5_case(v_case) IS DISTINCT FROM l.after->'case'
     OR (l.after->'line'->>'account_id')::uuid IS DISTINCT FROM l.account_id
     OR (l.after->'case'->>'account_id')::uuid IS DISTINCT FROM l.account_id
     OR NOT EXISTS (SELECT 1 FROM public.one_db o
                     WHERE o.id = v_onedb AND o.allocation_detail_id = v_det AND o.account_id = l.account_id)
     OR (SELECT count(*) FROM public.one_db o WHERE o.allocation_detail_id = v_det) <> 1 THEN
    RAISE EXCEPTION 'ops_fix: cambió después del arreglo; no lo deshago';
  END IF;

  -- Recordatorio al remitente: si ya salió (o lo está enviando n8n: reserva de menos de 10 min) se avisa.
  v_sent := EXISTS (SELECT 1 FROM public.panelist_notification n
                     WHERE n.id = ANY (v_notif)
                       AND (n.status = 'sent' OR (n.claimed_at IS NOT NULL AND n.claimed_at > now() - interval '10 minutes')));
  DELETE FROM public.panelist_notification n WHERE n.id = ANY (v_notif) AND n.status <> 'sent';

  -- Como en R4: los disparadores de allocation_plan_details sin search_path propio ven 'public'.
  PERFORM set_config('search_path', 'public, extensions, pg_temp', true);
  DELETE FROM public.one_db o WHERE o.id = v_onedb AND o.allocation_detail_id = v_det;

  UPDATE public.allocation_plan_details x
     SET (tag_id, idtag, status, received_at, cancellation_reason, cancelled_at, destination_node_id,
          destination_panelist_id, destination_panelist_name, original_destination_node_id,
          origin_panelist_id, origin_panelist_name, transferred_to_one_db_at, validation_errors,
          transfer_error_message) =
         (SELECT r.tag_id, r.idtag, r.status, r.received_at, r.cancellation_reason, r.cancelled_at, r.destination_node_id,
                 r.destination_panelist_id, r.destination_panelist_name, r.original_destination_node_id,
                 r.origin_panelist_id, r.origin_panelist_name, r.transferred_to_one_db_at, r.validation_errors,
                 r.transfer_error_message
            FROM pg_catalog.jsonb_populate_record(NULL::public.allocation_plan_details, l.before->'line') r)
   WHERE x.id = v_det AND x.account_id = l.account_id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  PERFORM set_config('search_path', '', true);
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'ops_fix: cambió después del arreglo; no lo deshago';
  END IF;

  UPDATE public.receipt_case x
     SET (status, reason, detail_id, original_tag, culprit_role, culprit_panelist_id, resolved_at, resolved_by,
          resolution_note) =
         (SELECT r.status, r.reason, r.detail_id, r.original_tag, r.culprit_role, r.culprit_panelist_id,
                 r.resolved_at, r.resolved_by, r.resolution_note
            FROM pg_catalog.jsonb_populate_record(NULL::public.receipt_case, l.before->'case') r)
   WHERE x.id = v_case AND x.account_id = l.account_id;

  UPDATE ops_fix.log x SET undone_at = now() WHERE x.id = l.id;
  RETURN jsonb_build_object('undone', true, 'reminder_already_sent', v_sent);
END $$;

-- ---------- permisos: como R4 (solo anon: el agente con su token; authenticated nunca) ----------
REVOKE ALL ON FUNCTION ops_fix._r5_line(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION ops_fix._r5_case(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION ops_fix._r5_check(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_fix_r5_preview(text, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_fix_r5_apply(text, uuid, uuid, jsonb, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_fix_r5_undo(text, bigint, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_fix_r5_preview(text, uuid, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.ops_fix_r5_apply(text, uuid, uuid, jsonb, text, text) TO anon;
GRANT EXECUTE ON FUNCTION public.ops_fix_r5_undo(text, bigint, text, text) TO anon;
