-- ============================================================
-- Agente de operaciones: arreglo R4 «Redirigir y registrar la recepción» — 2026-11-10
-- ============================================================
-- Spec: docs/superpowers/specs/2026-11-10-agente-casos-tarjeta-y-aplicar-design.md (§4 y §8b).
-- Requiere 20261106090000_ops_agent_fixes.sql (esquema ops_fix, ops_fix.log, patrón R1-R3) y
-- 20261105160000_ops_agent_test_fixtures.sql (ops_test._check, token del agente).
--
-- Caso: un panelista declara como recibida una etiqueta que corresponde a un envío hacia OTRA ciudad
-- (receipt_case.reason = 'other_city_tag', detail_id NULL, needs_decision). Si el remitente escribió mal la
-- dirección, la muestra es válida: R4 redirige la línea al receptor real y registra la recepción.
--
--   * Línea (allocation_plan_details): destino = nodo, panelista y nombre del panelista del caso;
--     original_destination_node_id = destino anterior (si estaba vacío); reassignment_reason =
--     'sender_wrong_address'; reassigned_at = now(); reassigned_by = NULL; status = 'received';
--     received_at = receipt_case.first_attempt_at.
--   * Al pasar a 'received', el disparador transfer_to_one_db copia la línea a public.one_db
--     (one_db.allocation_detail_id = id de la línea) y marca transferred_to_one_db_at. R4 lo comprueba
--     releyendo: si la copia no se hizo, falla y no queda nada escrito. El id de la copia se guarda en el
--     'after' del registro (one_db_id).
--   * Caso: status = 'fixed', resolved_at = now(), resolved_by = NULL, nota del agente.
--   * Deshacer (24 h): solo si la línea, el caso y la copia siguen como los dejó R4; borra la copia en
--     one_db y devuelve la línea y el caso a su estado anterior, en la misma transacción.
--
-- Condiciones (si falla cualquiera, applicable = false con el motivo en castellano):
--   caso abierto (pending / needs_decision) de motivo other_city_tag; exactamente una línea de la cuenta con
--   normalize_tag(tag_id) = tag_norm, en 'sent', sin received_at, con sent_at <= first_attempt_at; ningún otro
--   caso abierto con la misma etiqueta; panelista del caso activo, con nodo, de la misma cuenta; y nada que
--   impida la copia a ONE DB (panelista de origen, plan con transportista y producto, ciudades, sin copia
--   previa) ni que la regla POBOX anule la recepción.
-- ============================================================

-- ---------- permisos previos: valores nuevos en los CHECK ----------
ALTER TABLE public.allocation_plan_details
  DROP CONSTRAINT IF EXISTS allocation_plan_details_reassignment_reason_check,
  ADD CONSTRAINT allocation_plan_details_reassignment_reason_check
    CHECK (reassignment_reason IN ('panelist_unavailable','manual','rebalancing','pobox_move','sender_wrong_address'));

ALTER TABLE ops_fix.log
  DROP CONSTRAINT IF EXISTS log_kind_check,
  ADD CONSTRAINT log_kind_check CHECK (kind IN ('r1', 'r2', 'r3', 'r4'));

-- ---------- internas ----------
-- Campos de la línea que toca R4 (o el disparador de ONE DB al aplicarlo).
CREATE OR REPLACE FUNCTION ops_fix._r4_line(p_detail_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'id', d.id, 'account_id', d.account_id, 'status', d.status, 'received_at', d.received_at,
    'destination_node_id', d.destination_node_id, 'destination_panelist_id', d.destination_panelist_id,
    'destination_panelist_name', d.destination_panelist_name,
    'original_destination_node_id', d.original_destination_node_id,
    'reassignment_reason', d.reassignment_reason, 'reassigned_at', d.reassigned_at, 'reassigned_by', d.reassigned_by,
    'origin_panelist_id', d.origin_panelist_id, 'origin_panelist_name', d.origin_panelist_name,
    'transferred_to_one_db_at', d.transferred_to_one_db_at, 'validation_errors', d.validation_errors,
    'transfer_error_message', d.transfer_error_message)
    FROM public.allocation_plan_details d WHERE d.id = p_detail_id;
$$;

-- Campos del caso que toca R4.
CREATE OR REPLACE FUNCTION ops_fix._r4_case(p_case_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object('id', c.id, 'account_id', c.account_id, 'status', c.status,
                            'resolved_at', c.resolved_at, 'resolved_by', c.resolved_by,
                            'resolution_note', c.resolution_note)
    FROM public.receipt_case c WHERE c.id = p_case_id;
$$;

-- Comprueba las condiciones de R4 para un caso de recepción. Falla solo si el caso no existe; si no aplica
-- devuelve applicable = false y el motivo. Claves: applicable, reason, account_id, account, case_id,
-- case_status, tag, detail_id, origin_code, current_dest_code, new_dest_code, new_node, received_at,
-- sla_hours (NULL si no hay norma de entrega para el par nuevo) y, internas, panelist_id y new_node_id.
CREATE OR REPLACE FUNCTION ops_fix._r4_check(p_case_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  c public.receipt_case; d public.allocation_plan_details; p public.panelists; v_sim public.allocation_plan_details;
  v_ids uuid[]; v_reason text; v_origin_pid uuid; v_cur_pid uuid; v_carrier uuid; v_product uuid;
  v_ocity uuid; v_ncity uuid; v_node_acc uuid; v_sla numeric; v_unit text; v_pobox text;
BEGIN
  SELECT * INTO c FROM public.receipt_case x WHERE x.id = p_case_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ops_fix: el caso % no existe', p_case_id;
  END IF;

  IF c.reason IS DISTINCT FROM 'other_city_tag' THEN
    v_reason := format('el motivo del caso es «%s», no «etiqueta de un envío a otra ciudad»', c.reason);
  ELSIF c.status NOT IN ('pending', 'needs_decision') THEN
    v_reason := format('el caso no está abierto (estado «%s»)', c.status);
  ELSIF c.tag_norm IS NULL THEN
    v_reason := 'el caso no tiene etiqueta';
  END IF;

  -- La línea: por etiqueta normalizada dentro de la cuenta del caso.
  IF c.tag_norm IS NOT NULL THEN
    v_ids := ARRAY(SELECT x.id FROM public.allocation_plan_details x
                    WHERE x.account_id = c.account_id AND public.normalize_tag(x.tag_id) = c.tag_norm);
    IF cardinality(v_ids) = 1 THEN
      SELECT * INTO d FROM public.allocation_plan_details x WHERE x.id = v_ids[1];
    ELSIF v_reason IS NULL THEN
      v_reason := CASE WHEN cardinality(v_ids) = 0 THEN 'no hay ninguna línea con esa etiqueta en la cuenta'
                       ELSE format('hay %s líneas con esa etiqueta en la cuenta', cardinality(v_ids)) END;
    END IF;
  END IF;

  IF v_reason IS NULL THEN
    IF d.status IS DISTINCT FROM 'sent' THEN
      v_reason := format('la línea no está en estado enviada (estado «%s»)', d.status);
    ELSIF d.received_at IS NOT NULL THEN
      v_reason := 'la línea ya tiene fecha de recepción';
    ELSIF d.sent_at IS NULL THEN
      v_reason := 'la línea no tiene fecha de envío';
    ELSIF d.sent_at > c.first_attempt_at THEN
      v_reason := 'el envío se declaró después del primer intento de recepción';
    ELSIF EXISTS (SELECT 1 FROM public.receipt_case o
                   WHERE o.account_id = c.account_id AND o.tag_norm = c.tag_norm AND o.id <> c.id
                     AND o.status IN ('pending', 'needs_decision')) THEN
      v_reason := 'hay otro caso abierto con la misma etiqueta';
    END IF;
  END IF;

  -- El receptor real (panelista del caso).
  IF c.panelist_id IS NOT NULL THEN
    SELECT * INTO p FROM public.panelists x WHERE x.id = c.panelist_id AND x.account_id = c.account_id;
  END IF;
  IF p.node_id IS NOT NULL THEN
    SELECT n.account_id, n.city_id INTO v_node_acc, v_ncity FROM public.nodes n WHERE n.id = p.node_id;
  END IF;
  IF v_reason IS NULL THEN
    IF c.panelist_id IS NULL THEN
      v_reason := 'el caso no tiene panelista';
    ELSIF p.id IS NULL THEN
      v_reason := 'el panelista del caso no es de la misma cuenta';
    ELSIF p.status IS DISTINCT FROM 'active' THEN
      v_reason := 'el panelista del caso no está activo';
    ELSIF p.node_id IS NULL THEN
      v_reason := 'el panelista del caso no tiene nodo';
    ELSIF v_node_acc IS DISTINCT FROM c.account_id THEN
      v_reason := 'el nodo del panelista del caso no es de la misma cuenta';
    ELSIF p.node_id = d.destination_node_id THEN
      v_reason := 'el panelista del caso ya es el destino de la línea';
    ELSIF p.node_id = d.origin_node_id THEN
      v_reason := 'el panelista del caso es el propio remitente';
    END IF;
  END IF;

  -- Lo que necesita la copia a ONE DB (transfer_to_one_db) y el SLA del par nuevo.
  IF d.id IS NOT NULL THEN
    v_origin_pid := d.origin_panelist_id;
    IF v_origin_pid IS NULL AND d.origin_node_id IS NOT NULL THEN
      SELECT x.id INTO v_origin_pid FROM public.panelists x
       WHERE x.node_id = d.origin_node_id AND x.account_id = d.account_id
       ORDER BY (x.status = 'active') DESC, x.id LIMIT 1;
    END IF;
    v_cur_pid := d.destination_panelist_id;
    IF v_cur_pid IS NULL AND d.destination_node_id IS NOT NULL THEN
      SELECT x.id INTO v_cur_pid FROM public.panelists x
       WHERE x.node_id = d.destination_node_id AND x.account_id = d.account_id
       ORDER BY (x.status = 'active') DESC, x.id LIMIT 1;
    END IF;
    SELECT ap.carrier_id, ap.product_id INTO v_carrier, v_product
      FROM public.allocation_plans ap WHERE ap.id = d.plan_id AND ap.account_id = d.account_id;
    SELECT n.city_id INTO v_ocity FROM public.nodes n WHERE n.id = d.origin_node_id;
    IF v_ocity IS NOT NULL AND v_ncity IS NOT NULL THEN
      SELECT s.standard_time, s.time_unit INTO v_sla, v_unit
        FROM public.delivery_standards s
       WHERE s.account_id = c.account_id AND s.carrier_id = v_carrier AND s.product_id = v_product
         AND s.origin_city_id = v_ocity AND s.destination_city_id = v_ncity
       ORDER BY s.created_at, s.id LIMIT 1;
    END IF;

    IF v_reason IS NULL THEN
      IF v_origin_pid IS NULL THEN
        v_reason := 'la línea no tiene panelista de origen (la copia a ONE DB fallaría)';
      ELSIF v_carrier IS NULL OR v_product IS NULL THEN
        v_reason := 'el plan de la línea no tiene transportista o producto (la copia a ONE DB fallaría)';
      ELSIF v_ocity IS NULL OR v_ncity IS NULL THEN
        v_reason := 'falta la ciudad de origen o la del receptor (la copia a ONE DB fallaría)';
      ELSIF d.transferred_to_one_db_at IS NOT NULL
         OR EXISTS (SELECT 1 FROM public.one_db o WHERE o.allocation_detail_id = d.id) THEN
        v_reason := 'la línea ya tiene una copia en ONE DB';
      END IF;
    END IF;

    -- La regla POBOX (como register_receipt_with_rules): si anularía la recepción, R4 no aplica.
    IF v_reason IS NULL THEN
      v_sim := d;
      v_sim.destination_node_id := p.node_id;
      v_sim.destination_panelist_id := p.id;
      v_sim.status := 'received';
      v_sim.received_at := c.first_attempt_at;
      BEGIN
        v_pobox := public.pobox_receipt_check(v_sim);
      EXCEPTION WHEN OTHERS THEN
        v_pobox := NULL;
      END;
      IF v_pobox IS NOT NULL THEN
        v_reason := format('la regla POBOX anularía la recepción (%s)', v_pobox);
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'applicable', v_reason IS NULL,
    'reason', v_reason,
    'account_id', c.account_id,
    'account', (SELECT a.name FROM public.accounts a WHERE a.id = c.account_id),
    'case_id', c.id,
    'case_status', c.status,
    'tag', c.tag_norm,
    'detail_id', d.id,
    'origin_code', (SELECT x.panelist_code FROM public.panelists x WHERE x.id = v_origin_pid),
    'current_dest_code', (SELECT x.panelist_code FROM public.panelists x WHERE x.id = v_cur_pid),
    'new_dest_code', p.panelist_code,
    'new_node', (SELECT n.auto_id FROM public.nodes n WHERE n.id = p.node_id),
    'received_at', c.first_attempt_at,
    'sla_hours', CASE WHEN v_sla IS NULL THEN NULL WHEN v_unit = 'days' THEN v_sla * 24 ELSE v_sla END,
    'panelist_id', p.id,
    'new_node_id', p.node_id);
END $$;

-- ---------- R4: vista previa ----------
CREATE OR REPLACE FUNCTION public.ops_fix_r4_preview(p_token text, p_case_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v jsonb;
BEGIN
  PERFORM ops_test._check(p_token);
  v := ops_fix._r4_check(p_case_id);
  RETURN v - 'account_id' - 'panelist_id' - 'new_node_id';
END $$;

-- ---------- R4: aplicar ----------
CREATE OR REPLACE FUNCTION public.ops_fix_r4_apply(p_token text, p_case_id uuid, p_expected jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE c public.receipt_case; v jsonb; v_det uuid; v_exp_at timestamptz; v_before jsonb; v_after jsonb;
        v_n int; v_prev text; v_line jsonb; v_onedb uuid[]; v_log bigint;
BEGIN
  PERFORM ops_test._check(p_token);
  SELECT * INTO c FROM public.receipt_case x WHERE x.id = p_case_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'ops_fix: el caso % no existe', p_case_id;
  END IF;
  IF c.tag_norm IS NOT NULL THEN
    PERFORM 1 FROM public.allocation_plan_details x
     WHERE x.account_id = c.account_id AND public.normalize_tag(x.tag_id) = c.tag_norm FOR UPDATE;
  END IF;

  v := ops_fix._r4_check(p_case_id);
  IF NOT (v->>'applicable')::boolean THEN
    RAISE EXCEPTION 'ops_fix: R4 no aplica: %', v->>'reason';
  END IF;
  BEGIN
    v_exp_at := (p_expected->>'received_at')::timestamptz;
  EXCEPTION WHEN OTHERS THEN
    v_exp_at := NULL;
  END;
  IF (v->>'detail_id') IS DISTINCT FROM (p_expected->>'detail_id')
     OR (v->>'new_dest_code') IS DISTINCT FROM (p_expected->>'new_dest_code')
     OR (v->>'received_at')::timestamptz IS DISTINCT FROM v_exp_at THEN
    RAISE EXCEPTION 'ops_fix: ha cambiado desde la propuesta';
  END IF;

  v_det := (v->>'detail_id')::uuid;
  v_before := jsonb_build_object('line', ops_fix._r4_line(v_det), 'case', ops_fix._r4_case(p_case_id));

  -- La regla POBOX ya se evaluó en _r4_check; el disparador no debe volver a aplicarla.
  v_prev := current_setting('onems.skip_pobox_receipt_rule', true);
  PERFORM set_config('onems.skip_pobox_receipt_rule', 'on', true);
  -- transfer_to_one_db no fija search_path (usa nombres sin esquema): se le da 'public' solo durante la
  -- escritura; al salir de la función vuelve el search_path vacío de la cláusula SET.
  PERFORM set_config('search_path', 'public, extensions, pg_temp', true);
  UPDATE public.allocation_plan_details x
     SET original_destination_node_id = COALESCE(x.original_destination_node_id, x.destination_node_id),
         destination_node_id = (v->>'new_node_id')::uuid,
         destination_panelist_id = (v->>'panelist_id')::uuid,
         destination_panelist_name = (SELECT p.name FROM public.panelists p WHERE p.id = (v->>'panelist_id')::uuid),
         reassignment_reason = 'sender_wrong_address',
         reassigned_at = now(),
         reassigned_by = NULL,
         status = 'received',
         received_at = (v->>'received_at')::timestamptz
   WHERE x.id = v_det AND x.account_id = (v->>'account_id')::uuid AND x.status = 'sent' AND x.received_at IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  PERFORM set_config('search_path', '', true);
  PERFORM set_config('onems.skip_pobox_receipt_rule', COALESCE(v_prev, ''), true);
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'ops_fix: la línea cambió mientras se aplicaba; no toco nada';
  END IF;

  -- Relectura: la línea recibida y su copia en ONE DB (la hace el disparador transfer_to_one_db).
  v_line := ops_fix._r4_line(v_det);
  v_onedb := ARRAY(SELECT o.id FROM public.one_db o WHERE o.allocation_detail_id = v_det);
  IF v_line->>'status' IS DISTINCT FROM 'received' OR (v_line->>'transferred_to_one_db_at') IS NULL
     OR cardinality(v_onedb) <> 1 THEN
    RAISE EXCEPTION 'ops_fix: la copia a ONE DB no se hizo (%); no toco nada',
      COALESCE(v_line->>'transfer_error_message', v_line->>'validation_errors', 'sin detalle');
  END IF;

  UPDATE public.receipt_case x
     SET status = 'fixed', resolved_at = now(), resolved_by = NULL,
         resolution_note = 'Redirigida al receptor real (error de dirección del remitente) — agente de operaciones'
   WHERE x.id = p_case_id;

  v_after := jsonb_build_object('line', v_line, 'case', ops_fix._r4_case(p_case_id), 'one_db_id', v_onedb[1]);
  INSERT INTO ops_fix.log (kind, account_id, target, before, after)
  VALUES ('r4', (v->>'account_id')::uuid, p_case_id::text, v_before, v_after)
  RETURNING id INTO v_log;
  RETURN jsonb_build_object('log_id', v_log, 'detail_id', v_det, 'new_dest_code', v->>'new_dest_code');
END $$;

-- ---------- R4: deshacer (24 h) ----------
CREATE OR REPLACE FUNCTION public.ops_fix_r4_undo(p_token text, p_log_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE l ops_fix.log; v_det uuid; v_case uuid; v_onedb uuid; v_n int;
BEGIN
  PERFORM ops_test._check(p_token);
  SELECT * INTO l FROM ops_fix.log x WHERE x.id = p_log_id FOR UPDATE;
  IF NOT FOUND OR l.kind <> 'r4' THEN
    RAISE EXCEPTION 'ops_fix: el registro % no es un arreglo R4', p_log_id;
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
  PERFORM 1 FROM public.allocation_plan_details x WHERE x.id = v_det AND x.account_id = l.account_id FOR UPDATE;
  PERFORM 1 FROM public.receipt_case x WHERE x.id = v_case AND x.account_id = l.account_id FOR UPDATE;
  PERFORM 1 FROM public.one_db o WHERE o.id = v_onedb FOR UPDATE;

  IF ops_fix._r4_line(v_det) IS DISTINCT FROM l.after->'line'
     OR ops_fix._r4_case(v_case) IS DISTINCT FROM l.after->'case'
     OR (l.after->'line'->>'account_id')::uuid IS DISTINCT FROM l.account_id
     OR (l.after->'case'->>'account_id')::uuid IS DISTINCT FROM l.account_id
     OR NOT EXISTS (SELECT 1 FROM public.one_db o
                     WHERE o.id = v_onedb AND o.allocation_detail_id = v_det AND o.account_id = l.account_id)
     OR (SELECT count(*) FROM public.one_db o WHERE o.allocation_detail_id = v_det) <> 1 THEN
    RAISE EXCEPTION 'ops_fix: cambió después del arreglo; no lo deshago';
  END IF;

  -- Como en apply: los disparadores de allocation_plan_details sin search_path propio ven 'public'.
  PERFORM set_config('search_path', 'public, extensions, pg_temp', true);
  DELETE FROM public.one_db o WHERE o.id = v_onedb AND o.allocation_detail_id = v_det;

  UPDATE public.allocation_plan_details x
     SET (status, received_at, destination_node_id, destination_panelist_id, destination_panelist_name,
          original_destination_node_id, reassignment_reason, reassigned_at, reassigned_by,
          origin_panelist_id, origin_panelist_name, transferred_to_one_db_at, validation_errors,
          transfer_error_message) =
         (SELECT r.status, r.received_at, r.destination_node_id, r.destination_panelist_id, r.destination_panelist_name,
                 r.original_destination_node_id, r.reassignment_reason, r.reassigned_at, r.reassigned_by,
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
     SET (status, resolved_at, resolved_by, resolution_note) =
         (SELECT r.status, r.resolved_at, r.resolved_by, r.resolution_note
            FROM pg_catalog.jsonb_populate_record(NULL::public.receipt_case, l.before->'case') r)
   WHERE x.id = v_case AND x.account_id = l.account_id;

  UPDATE ops_fix.log x SET undone_at = now() WHERE x.id = l.id;
  RETURN jsonb_build_object('restored', true);
END $$;

-- ---------- permisos ----------
REVOKE ALL ON FUNCTION ops_fix._r4_line(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION ops_fix._r4_case(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION ops_fix._r4_check(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_fix_r4_preview(text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_fix_r4_apply(text, uuid, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_fix_r4_undo(text, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_fix_r4_preview(text, uuid) TO anon;
GRANT EXECUTE ON FUNCTION public.ops_fix_r4_apply(text, uuid, jsonb) TO anon;
GRANT EXECUTE ON FUNCTION public.ops_fix_r4_undo(text, bigint) TO anon;
