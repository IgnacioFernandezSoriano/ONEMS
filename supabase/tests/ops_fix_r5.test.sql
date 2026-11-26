-- Arreglo R5 del agente de operaciones: etiqueta mal escrita, el gestor elige el candidato (deshacer 24 h).
-- Caso de referencia (00011418, Kenya 26/11): el receptor P4 (N4/City2) declara 00011418, que no esta en el plan;
-- el remitente P1 (N1/City1) declaro 00014118 (cifras contiguas intercambiadas, anulado por plazo) y 00011415
-- (una cifra, en camino), ambos hacia P4. Aplicar con 00014118 da ok_typo_fixed.
\set ON_ERROR_STOP on
SET client_min_messages = error;
CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

-- Huella de las lineas, el caso, ONE DB, avisos y registro (para comprobar "sin cambios").
CREATE OR REPLACE FUNCTION pg_temp.state() RETURNS text LANGUAGE sql AS $$
  SELECT md5(concat_ws('#',
    (SELECT string_agg(to_jsonb(d)::text, '|' ORDER BY d.id) FROM public.allocation_plan_details d
      WHERE d.id IN ('d5000000-0000-0000-0000-000000000001', 'd5000000-0000-0000-0000-000000000002')),
    (SELECT to_jsonb(c)::text FROM public.receipt_case c WHERE c.id = 'f5000000-0000-0000-0000-000000000001'),
    (SELECT count(*)::text FROM public.one_db o WHERE o.allocation_detail_id = 'd5000000-0000-0000-0000-000000000001'),
    (SELECT string_agg(to_jsonb(n)::text, '|' ORDER BY n.id) FROM public.panelist_notification n),
    (SELECT string_agg(to_jsonb(l)::text, '|' ORDER BY l.id) FROM ops_fix.log l)));
$$;

-- Fixture comun (se llama dentro de cada BEGIN, tras los \ir).
CREATE OR REPLACE FUNCTION pg_temp.fixture() RETURNS void LANGUAGE sql AS $$
  INSERT INTO ops_test.secret(token_sha256) VALUES (encode(extensions.digest('t0ken-de-prueba','sha256'),'hex'));
  UPDATE public.accounts SET name = 'DEMO2' WHERE id = 'a0000000-0000-0000-0000-000000000001';
  INSERT INTO public.delivery_standards (account_id, carrier_id, product_id, origin_city_id, destination_city_id, standard_time, time_unit, success_percentage) VALUES
    ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',6,'hours',90);
  INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, tag_id, sent_at,
                                              cancellation_reason, cancelled_at,
                                              origin_panelist_id, origin_panelist_name, destination_panelist_id, destination_panelist_name) VALUES
    ('d5000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004',
     current_date - 22,'cancelled','00014118', now() - interval '22 days','not_received_timeout', now() - interval '7 days',
     'e1000000-0000-0000-0000-000000000001','Pan1','e4000000-0000-0000-0000-000000000004','Pan4'),
    ('d5000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004',
     current_date - 7,'sent','00011415', now() - interval '7 days', NULL, NULL,
     'e1000000-0000-0000-0000-000000000001','Pan1','e4000000-0000-0000-0000-000000000004','Pan4');
  INSERT INTO public.receipt_case (id, account_id, panelist_id, telegram_id, tag_raw, tag_norm, detail_id, reason, status, attempts, first_attempt_at, last_attempt_at)
  VALUES ('f5000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000004','4004',
          '00011418','00011418',NULL,'ambiguous_typo','needs_decision',3, now(), now());
$$;

-- ============================================================================================================
-- 1. Flujo completo y casos que no aplican (sin disparadores de incidencias)
-- ============================================================================================================
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.fixture();

DO $$
DECLARE r jsonb; e jsonb; v_pv jsonb; v_err text; t text := 't0ken-de-prueba'; v_log bigint; v_log2 bigint; v_s text;
  v_case uuid := 'f5000000-0000-0000-0000-000000000001';
  v_a uuid := 'd5000000-0000-0000-0000-000000000001';
  v_b uuid := 'd5000000-0000-0000-0000-000000000002';
  v_first timestamptz;
  d public.allocation_plan_details; c public.receipt_case;
BEGIN
  SELECT x.first_attempt_at INTO v_first FROM public.receipt_case x WHERE x.id = v_case;

  -- ---------- vista previa ----------
  r := public.ops_fix_r5_preview(t, v_case);
  PERFORM pg_temp.fail_if(NOT (r->>'applicable')::bool OR r->'reason' <> 'null'::jsonb, 'preview applicable: ' || r::text);
  PERFORM pg_temp.fail_if(r->>'case_status' <> 'needs_decision' OR r->>'tag' <> '00011418', 'preview caso: ' || r::text);
  PERFORM pg_temp.fail_if(r ? 'account_id', 'preview sin ids internos: ' || r::text);
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'candidates') <> 2, 'preview 2 candidatos: ' || r::text);
  e := r->'candidates'->0;
  PERFORM pg_temp.fail_if((e->>'detail_id')::uuid <> v_a OR e->>'current_tag' <> '00014118' OR e->>'new_tag' <> '00011418'
                          OR e->>'kind' <> 'swap' OR NOT (e->>'revive')::bool OR (e->>'moves_node')::bool
                          OR e->>'status' <> 'cancelled', 'candidato 1: ' || e::text);
  PERFORM pg_temp.fail_if(e->>'origin_code' <> 'P1' OR e->>'origin_name' <> 'Pan1' OR e->>'destination_code' <> 'P4'
                          OR e->>'destination_name' <> 'Pan4', 'candidato 1 lados: ' || e::text);
  PERFORM pg_temp.fail_if((e->>'sent_at')::timestamptz <> now() - interval '22 days', 'candidato 1 sent_at: ' || e::text);
  PERFORM pg_temp.fail_if((r->'candidates'->1->>'detail_id')::uuid <> v_b OR r->'candidates'->1->>'kind' <> 'one_digit'
                          OR (r->'candidates'->1->>'revive')::bool OR r->'candidates'->1->>'status' <> 'sent',
                          'candidato 2: ' || (r->'candidates'->1)::text);
  -- con la cuenta correcta tambien aplica
  PERFORM pg_temp.fail_if(NOT (public.ops_fix_r5_preview(t, v_case, 'DEMO2')->>'applicable')::bool, 'preview con cuenta');

  -- ---------- apply: no es un candidato / expected distinto -> error y nada cambia ----------
  v_s := pg_temp.state();
  BEGIN
    PERFORM public.ops_fix_r5_apply(t, v_case, '00000000-0000-0000-0000-00000000dead', e);
    RAISE EXCEPTION 'FAIL: apply no candidato';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err <> 'ops_fix: no es un candidato', 'mensaje no candidato: ' || v_err);
  END;
  BEGIN
    PERFORM public.ops_fix_r5_apply(t, v_case, v_a, jsonb_set(e, '{sent_at}', to_jsonb(now() - interval '21 days')));
    RAISE EXCEPTION 'FAIL: apply con sent_at distinto';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err <> 'ops_fix: ha cambiado desde la propuesta', 'mensaje expected: ' || v_err);
  END;
  BEGIN
    PERFORM public.ops_fix_r5_apply(t, v_case, v_a, r->'candidates'->1);
    RAISE EXCEPTION 'FAIL: apply con la ficha de otro candidato';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err <> 'ops_fix: ha cambiado desde la propuesta', 'mensaje ficha otra: ' || v_err);
  END;
  PERFORM pg_temp.fail_if(pg_temp.state() <> v_s, 'apply rechazado toco algo');

  -- ---------- apply con 00014118 ----------
  r := public.ops_fix_r5_apply(t, v_case, v_a, e);
  v_log := (r->>'log_id')::bigint;
  PERFORM pg_temp.fail_if(v_log IS NULL OR r->>'outcome' <> 'ok_typo_fixed', 'apply: ' || r::text);
  SELECT * INTO d FROM public.allocation_plan_details x WHERE x.id = v_a;
  PERFORM pg_temp.fail_if(d.status <> 'received' OR d.tag_id <> '00011418' OR d.received_at <> v_first
                          OR d.cancellation_reason IS NOT NULL, 'linea recibida: ' || to_jsonb(d)::text);
  PERFORM pg_temp.fail_if(d.transferred_to_one_db_at IS NULL, 'transferida');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.one_db o WHERE o.allocation_detail_id = v_a) <> 1, 'copia en one_db');
  SELECT * INTO d FROM public.allocation_plan_details x WHERE x.id = v_b;
  PERFORM pg_temp.fail_if(d.status <> 'sent' OR d.tag_id <> '00011415' OR d.received_at IS NOT NULL, '00011415 intacta');
  SELECT * INTO c FROM public.receipt_case x WHERE x.id = v_case;
  PERFORM pg_temp.fail_if(c.status <> 'fixed' OR c.reason <> 'ok_typo_fixed' OR c.original_tag <> '00014118'
                          OR c.detail_id <> v_a OR c.culprit_panelist_id IS NULL, 'caso fixed: ' || to_jsonb(c)::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_notification n
                            WHERE n.case_id = v_case AND n.kind = 'receipt_reminder') <> 1, 'recordatorio encolado');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM ops_fix.log l WHERE l.id = v_log AND l.kind = 'r5'
                             AND l.account_id = 'a0000000-0000-0000-0000-000000000001'
                             AND (l.target::jsonb->>'case_id')::uuid = v_case AND (l.target::jsonb->>'detail_id')::uuid = v_a) <> 1, 'log r5');
  -- vista previa tras aplicar: no aplica, case_status fixed
  v_pv := public.ops_fix_r5_preview(t, v_case);
  PERFORM pg_temp.fail_if((v_pv->>'applicable')::bool OR v_pv->>'case_status' IS DISTINCT FROM 'fixed'
                          OR v_pv->>'reason' <> 'el caso no está abierto', 'preview tras apply: ' || v_pv::text);
  BEGIN
    PERFORM public.ops_fix_r5_apply(t, v_case, v_a, e);
    RAISE EXCEPTION 'FAIL: segundo apply';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err <> 'ops_fix: R5 no aplica: el caso no está abierto', 'mensaje segundo apply: ' || v_err);
  END;

  -- ---------- undo ----------
  r := public.ops_fix_r5_undo(t, v_log);
  PERFORM pg_temp.fail_if(NOT (r->>'undone')::bool OR (r->>'reminder_already_sent')::bool, 'undo: ' || r::text);
  SELECT * INTO d FROM public.allocation_plan_details x WHERE x.id = v_a;
  PERFORM pg_temp.fail_if(d.status <> 'cancelled' OR d.cancellation_reason <> 'not_received_timeout' OR d.tag_id <> '00014118'
                          OR d.received_at IS NOT NULL OR d.cancelled_at IS NULL OR d.transferred_to_one_db_at IS NOT NULL
                          OR d.destination_node_id <> 'b4000000-0000-0000-0000-000000000004',
                          'linea restaurada: ' || to_jsonb(d)::text);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.one_db o WHERE o.allocation_detail_id = v_a), 'copia one_db borrada');
  SELECT * INTO c FROM public.receipt_case x WHERE x.id = v_case;
  PERFORM pg_temp.fail_if(c.status <> 'needs_decision' OR c.reason <> 'ambiguous_typo' OR c.detail_id IS NOT NULL
                          OR c.culprit_role IS NOT NULL OR c.culprit_panelist_id IS NOT NULL OR c.original_tag IS NOT NULL
                          OR c.resolved_at IS NOT NULL, 'caso restaurado: ' || to_jsonb(c)::text);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_notification n WHERE n.case_id = v_case), 'recordatorio borrado');
  PERFORM pg_temp.fail_if((SELECT l.undone_at FROM ops_fix.log l WHERE l.id = v_log) IS NULL, 'undone_at');
  BEGIN
    PERFORM public.ops_fix_r5_undo(t, v_log);
    RAISE EXCEPTION 'FAIL: segundo undo';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err <> format('ops_fix: el arreglo %s ya se deshizo', v_log), 'mensaje segundo undo: ' || v_err);
  END;
  -- undo de un registro que no es r5
  INSERT INTO ops_fix.log (kind, account_id, target, before, after)
  VALUES ('r4', 'a0000000-0000-0000-0000-000000000001', v_case::text, '{}', '{}') RETURNING id INTO v_log2;
  BEGIN
    PERFORM public.ops_fix_r5_undo(t, v_log2);
    RAISE EXCEPTION 'FAIL: undo de r4';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_fix:%no es un arreglo R5%', 'mensaje undo r4: ' || v_err);
  END;

  -- ---------- segunda vuelta: el recordatorio ya habia salido ----------
  r := public.ops_fix_r5_preview(t, v_case);
  PERFORM pg_temp.fail_if(NOT (r->>'applicable')::bool, 'aplicable otra vez tras deshacer: ' || r::text);
  e := r->'candidates'->0;
  v_log := (public.ops_fix_r5_apply(t, v_case, v_a, e)->>'log_id')::bigint;
  UPDATE public.panelist_notification SET status = 'sent', sent_at = now() WHERE case_id = v_case;
  r := public.ops_fix_r5_undo(t, v_log);
  PERFORM pg_temp.fail_if(NOT (r->>'undone')::bool OR NOT (r->>'reminder_already_sent')::bool, 'undo enviado: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_notification n WHERE n.case_id = v_case AND n.status = 'sent') <> 1,
                          'recordatorio enviado se conserva');
  PERFORM pg_temp.fail_if((SELECT x.status FROM public.receipt_case x WHERE x.id = v_case) <> 'needs_decision', 'caso restaurado 2');
  DELETE FROM public.panelist_notification WHERE case_id = v_case;

  -- ---------- undo pasadas 24 h ----------
  e := public.ops_fix_r5_preview(t, v_case)->'candidates'->0;
  v_log := (public.ops_fix_r5_apply(t, v_case, v_a, e)->>'log_id')::bigint;
  UPDATE ops_fix.log SET applied_at = now() - interval '25 hours' WHERE id = v_log;
  v_s := pg_temp.state();
  BEGIN
    PERFORM public.ops_fix_r5_undo(t, v_log);
    RAISE EXCEPTION 'FAIL: undo pasadas 24 h';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err <> format('ops_fix: han pasado más de 24 h desde el arreglo %s; no lo deshago', v_log), 'mensaje 24 h: ' || v_err);
  END;
  PERFORM pg_temp.fail_if(pg_temp.state() <> v_s, 'undo 24 h toco algo');

  -- ---------- undo tras cambiar a mano el caso ----------
  UPDATE ops_fix.log SET applied_at = now() WHERE id = v_log;
  UPDATE public.receipt_case SET resolution_note = 'tocado a mano' WHERE id = v_case;
  v_s := pg_temp.state();
  BEGIN
    PERFORM public.ops_fix_r5_undo(t, v_log);
    RAISE EXCEPTION 'FAIL: undo tras cambio a mano';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err <> 'ops_fix: cambió después del arreglo; no lo deshago', 'mensaje cambio: ' || v_err);
  END;
  PERFORM pg_temp.fail_if(pg_temp.state() <> v_s, 'undo tras cambio toco algo');
  UPDATE public.receipt_case SET resolution_note = NULL WHERE id = v_case;
  r := public.ops_fix_r5_undo(t, v_log);
  PERFORM pg_temp.fail_if(NOT (r->>'undone')::bool, 'undo final');
  PERFORM pg_temp.fail_if(NOT (public.ops_fix_r5_preview(t, v_case)->>'applicable')::bool, 'fixture restaurado');
END $$;

-- ---------- casos que no aplican (cada uno en una subtransaccion que se deshace) ----------
DO $$
DECLARE r jsonb; v_err text; t text := 't0ken-de-prueba'; v_s text;
  v_case uuid := 'f5000000-0000-0000-0000-000000000001';
  v_a uuid := 'd5000000-0000-0000-0000-000000000001';
  v_b uuid := 'd5000000-0000-0000-0000-000000000002';
BEGIN
  -- motivo other_city_tag
  BEGIN
    UPDATE public.receipt_case SET reason = 'other_city_tag' WHERE id = v_case;
    r := public.ops_fix_r5_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if((r->>'applicable')::bool OR r->>'reason' <> 'motivo del caso no admitido', 'other_city_tag: ' || r::text);

  -- motivo not_found: aplica
  BEGIN
    UPDATE public.receipt_case SET reason = 'not_found', status = 'pending' WHERE id = v_case;
    r := public.ops_fix_r5_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if(NOT (r->>'applicable')::bool, 'not_found aplica: ' || r::text);

  -- caso fixed
  BEGIN
    UPDATE public.receipt_case SET status = 'fixed' WHERE id = v_case;
    r := public.ops_fix_r5_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if((r->>'applicable')::bool OR r->>'reason' <> 'el caso no está abierto' OR r->>'case_status' <> 'fixed', 'fixed: ' || r::text);

  -- ya hay una linea con la etiqueta exacta
  BEGIN
    INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, tag_id, sent_at,
                                                origin_panelist_id, destination_panelist_id) VALUES
      ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000002',
       current_date - 3,'sent','00011418', now() - interval '3 days','e1000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000002');
    r := public.ops_fix_r5_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if((r->>'applicable')::bool OR r->>'reason' <> 'la etiqueta ya existe en el plan', 'etiqueta exacta: ' || r::text);

  -- ningun parecido
  BEGIN
    UPDATE public.allocation_plan_details SET tag_id = '00099991' WHERE id = v_a;
    UPDATE public.allocation_plan_details SET tag_id = '00099992' WHERE id = v_b;
    r := public.ops_fix_r5_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if((r->>'applicable')::bool OR r->>'reason' <> 'ningún envío parecido'
                          OR jsonb_array_length(r->'candidates') <> 0, 'cero: ' || r::text);

  -- parecido hacia otra ciudad: no es candidato
  BEGIN
    UPDATE public.allocation_plan_details SET tag_id = '00099991' WHERE id = v_a;
    UPDATE public.allocation_plan_details SET destination_node_id = 'b2000000-0000-0000-0000-000000000002' WHERE id = v_b;
    r := public.ops_fix_r5_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if((r->>'applicable')::bool OR r->>'reason' <> 'ningún envío parecido', 'otra ciudad: ' || r::text);

  -- seis parecidos: no aplica, se devuelven los 5 primeros
  BEGIN
    INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, tag_id, sent_at,
                                                origin_panelist_id, destination_panelist_id)
    SELECT 'a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004',
           current_date - 5,'sent', v.tag, now() - interval '5 days','e1000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000004'
      FROM (VALUES ('00011410'), ('00011411'), ('00011412'), ('00011413')) v(tag);
    r := public.ops_fix_r5_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if((r->>'applicable')::bool OR r->>'reason' <> 'demasiados parecidos'
                          OR jsonb_array_length(r->'candidates') <> 5, 'seis: ' || r::text);
  PERFORM pg_temp.fail_if(r->'candidates'->0->>'current_tag' <> '00014118', 'seis orden: ' || r::text);

  -- candidato declarado despues del primer intento: fuera
  BEGIN
    UPDATE public.allocation_plan_details SET sent_at = now() + interval '1 hour' WHERE id = v_b;
    r := public.ops_fix_r5_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if(NOT (r->>'applicable')::bool OR jsonb_array_length(r->'candidates') <> 1
                          OR (r->'candidates'->0->>'detail_id')::uuid <> v_a, 'sent_at posterior: ' || r::text);

  -- candidato en deferred_samples: fuera
  BEGIN
    INSERT INTO public.deferred_samples (account_id, plan_id, origin_city_id, dest_city_id, origin_node_id, destination_node_id,
                                         fecha_programada, reason, row_snapshot)
    SELECT d.account_id, d.plan_id, 'c1000000-0000-0000-0000-000000000001', 'c2000000-0000-0000-0000-000000000002',
           d.origin_node_id, d.destination_node_id, d.fecha_programada, 'pobox_absent_no_visit', to_jsonb(d)
      FROM public.allocation_plan_details d WHERE d.id = v_a;
    r := public.ops_fix_r5_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if(NOT (r->>'applicable')::bool OR jsonb_array_length(r->'candidates') <> 1
                          OR (r->'candidates'->0->>'detail_id')::uuid <> v_b, 'deferred: ' || r::text);

  -- otro nodo de la misma ciudad: candidato con moves_node, va despues de los del mismo nodo
  BEGIN
    INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
      ('b6000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002','N6');
    UPDATE public.allocation_plan_details SET destination_node_id = 'b6000000-0000-0000-0000-000000000006',
                                              destination_panelist_id = NULL, destination_panelist_name = NULL WHERE id = v_a;
    r := public.ops_fix_r5_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if(NOT (r->>'applicable')::bool OR (r->'candidates'->0->>'detail_id')::uuid <> v_b
                          OR (r->'candidates'->0->>'moves_node')::bool OR NOT (r->'candidates'->1->>'moves_node')::bool,
                          'otro nodo: ' || r::text);

  -- panelista sin nodo: no aplica, sin excepcion
  BEGIN
    UPDATE public.panelists SET node_id = NULL WHERE id = 'e4000000-0000-0000-0000-000000000004';
    r := public.ops_fix_r5_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if((r->>'applicable')::bool OR r->>'reason' <> 'el panelista no tiene nodo con ciudad', 'sin nodo: ' || r::text);

  -- apply cuando no aplica: error con el motivo
  BEGIN
    UPDATE public.receipt_case SET reason = 'other_city_tag' WHERE id = v_case;
    PERFORM public.ops_fix_r5_apply(t, v_case, v_a, '{}'::jsonb);
    RAISE EXCEPTION 'FAIL: apply no aplicable';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err <> 'ops_fix: R5 no aplica: motivo del caso no admitido', 'mensaje apply no aplica: ' || v_err);
  END;

  -- linea que no es candidato (parecida pero hacia otra ciudad)
  BEGIN
    INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, tag_id, sent_at,
                                                origin_panelist_id, destination_panelist_id) VALUES
      ('d5000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000002',
       current_date - 3,'sent','00011417', now() - interval '3 days','e1000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000002');
    v_s := pg_temp.state();
    BEGIN
      PERFORM public.ops_fix_r5_apply(t, v_case, 'd5000000-0000-0000-0000-000000000009', '{}'::jsonb);
      RAISE EXCEPTION 'FAIL: apply otra ciudad';
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      PERFORM pg_temp.fail_if(v_err <> 'ops_fix: no es un candidato', 'mensaje otra ciudad: ' || v_err);
    END;
    PERFORM pg_temp.fail_if(pg_temp.state() <> v_s, 'apply no candidato toco algo');
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;

  -- caso de la cuenta 2 con p_account de la cuenta 1
  BEGIN
    INSERT INTO public.receipt_case (id, account_id, panelist_id, telegram_id, tag_raw, tag_norm, reason, status, first_attempt_at, last_attempt_at)
    VALUES ('f5000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002',NULL,'9009','00011418','00011418',
            'ambiguous_typo','needs_decision',now(),now());
    BEGIN
      PERFORM public.ops_fix_r5_preview(t, 'f5000000-0000-0000-0000-000000000002', 'DEMO2');
      RAISE EXCEPTION 'FAIL: preview otra cuenta';
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      PERFORM pg_temp.fail_if(v_err <> 'ops_fix: otra cuenta', 'mensaje preview otra cuenta: ' || v_err);
    END;
    BEGIN
      PERFORM public.ops_fix_r5_apply(t, 'f5000000-0000-0000-0000-000000000002', v_a, '{}'::jsonb, 'DEMO2');
      RAISE EXCEPTION 'FAIL: apply otra cuenta';
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      PERFORM pg_temp.fail_if(v_err <> 'ops_fix: otra cuenta', 'mensaje apply otra cuenta: ' || v_err);
    END;
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;

  -- caso inexistente y token malo
  BEGIN
    PERFORM public.ops_fix_r5_preview(t, '00000000-0000-0000-0000-000000000000');
    RAISE EXCEPTION 'FAIL: caso inexistente';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_fix:%no existe%', 'mensaje inexistente: ' || v_err);
  END;
  BEGIN
    PERFORM public.ops_fix_r5_preview('malo', v_case);
    RAISE EXCEPTION 'FAIL: token malo preview';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_test: token no valido%', 'token preview: ' || v_err);
  END;
  BEGIN
    PERFORM public.ops_fix_r5_apply('malo', v_case, v_a, '{}'::jsonb);
    RAISE EXCEPTION 'FAIL: token malo apply';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_test: token no valido%', 'token apply: ' || v_err);
  END;
  BEGIN
    PERFORM public.ops_fix_r5_undo('malo', 1);
    RAISE EXCEPTION 'FAIL: token malo undo';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_test: token no valido%', 'token undo: ' || v_err);
  END;

  -- permisos: como R4 (el agente llama con la clave anon + su token; authenticated nunca; internas nadie)
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.ops_fix_r5_preview(text,uuid,text,text)', 'EXECUTE'), 'authenticated preview');
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.ops_fix_r5_apply(text,uuid,uuid,jsonb,text,text)', 'EXECUTE'), 'authenticated apply');
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.ops_fix_r5_undo(text,bigint,text,text)', 'EXECUTE'), 'authenticated undo');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('anon', 'public.ops_fix_r5_preview(text,uuid,text,text)', 'EXECUTE'), 'anon preview');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('anon', 'public.ops_fix_r5_apply(text,uuid,uuid,jsonb,text,text)', 'EXECUTE'), 'anon apply');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('anon', 'public.ops_fix_r5_undo(text,bigint,text,text)', 'EXECUTE'), 'anon undo');
  PERFORM pg_temp.fail_if(has_function_privilege('anon', 'ops_fix._r5_check(uuid)', 'EXECUTE'), 'anon _r5_check');
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'ops_fix._r5_check(uuid)', 'EXECUTE'), 'authenticated _r5_check');
END $$;

ROLLBACK;

-- ============================================================================================================
-- 2. Variante con los disparadores de incidencias activos (como en produccion): apply + undo
-- ============================================================================================================
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.fixture();

DO $$
DECLARE r jsonb; t text := 't0ken-de-prueba'; v_log bigint;
  v_case uuid := 'f5000000-0000-0000-0000-000000000001';
  v_a uuid := 'd5000000-0000-0000-0000-000000000001';
  d public.allocation_plan_details; c public.receipt_case;
BEGIN
  r := public.ops_fix_r5_preview(t, v_case);
  PERFORM pg_temp.fail_if(NOT (r->>'applicable')::bool OR jsonb_array_length(r->'candidates') <> 2, 'trg preview: ' || r::text);
  r := public.ops_fix_r5_apply(t, v_case, v_a, r->'candidates'->0);
  v_log := (r->>'log_id')::bigint;
  PERFORM pg_temp.fail_if(r->>'outcome' <> 'ok_typo_fixed', 'trg apply: ' || r::text);
  SELECT * INTO d FROM public.allocation_plan_details x WHERE x.id = v_a;
  PERFORM pg_temp.fail_if(d.status <> 'received' OR d.tag_id <> '00011418' OR d.transferred_to_one_db_at IS NULL, 'trg linea');
  r := public.ops_fix_r5_undo(t, v_log);
  PERFORM pg_temp.fail_if(NOT (r->>'undone')::bool OR (r->>'reminder_already_sent')::bool, 'trg undo: ' || r::text);
  SELECT * INTO d FROM public.allocation_plan_details x WHERE x.id = v_a;
  PERFORM pg_temp.fail_if(d.status <> 'cancelled' OR d.tag_id <> '00014118' OR d.received_at IS NOT NULL, 'trg linea restaurada');
  SELECT * INTO c FROM public.receipt_case x WHERE x.id = v_case;
  PERFORM pg_temp.fail_if(c.status <> 'needs_decision' OR c.reason <> 'ambiguous_typo' OR c.detail_id IS NOT NULL, 'trg caso restaurado');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.one_db o WHERE o.allocation_detail_id = v_a), 'trg one_db');
END $$;

ROLLBACK;
