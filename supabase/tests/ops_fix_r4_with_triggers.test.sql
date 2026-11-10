-- Arreglo R4 del agente de operaciones: redirigir y registrar la recepcion (con deshacer 24 h).
-- Copia de ops_fix_r4.test.sql CON los disparadores de incidencias activos (sin fixtures/no_incident_triggers.sql),
-- como en produccion. Mantener las dos en sincronia.
-- Caso de referencia (como 00011844): remitente P1 en N1/City1, destino previsto P2 en N2/City1; quien lo
-- recibio es P4 en N4/City2, con un caso other_city_tag needs_decision (detail_id NULL). Norma City1 -> City2 6 h.
\set ON_ERROR_STOP on
SET client_min_messages = error;
CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

-- Huella de la linea y del caso (para comprobar "sin cambios").
CREATE OR REPLACE FUNCTION pg_temp.state() RETURNS text LANGUAGE sql AS $$
  SELECT md5(concat_ws('#',
    (SELECT to_jsonb(d)::text FROM public.allocation_plan_details d WHERE d.id = 'd1000000-0000-0000-0000-000000000001'),
    (SELECT to_jsonb(c)::text FROM public.receipt_case c WHERE c.id = 'f1000000-0000-0000-0000-000000000001'),
    (SELECT count(*)::text FROM public.one_db o WHERE o.allocation_detail_id = 'd1000000-0000-0000-0000-000000000001'),
    (SELECT string_agg(to_jsonb(l)::text, '|' ORDER BY l.id) FROM ops_fix.log l)));
$$;

BEGIN;
\ir fixtures/incident_city.sql
INSERT INTO ops_test.secret(token_sha256) VALUES (encode(extensions.digest('t0ken-de-prueba','sha256'),'hex'));
UPDATE public.accounts SET name = 'DEMO2' WHERE id = 'a0000000-0000-0000-0000-000000000001';
INSERT INTO public.delivery_standards (account_id, carrier_id, product_id, origin_city_id, destination_city_id, standard_time, time_unit, success_percentage) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',6,'hours',90);
INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, tag_id, sent_at,
                                            origin_panelist_id, origin_panelist_name, destination_panelist_id, destination_panelist_name) VALUES
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000002',
   '2026-10-27','sent','00011844','2026-10-30 09:00+00','e1000000-0000-0000-0000-000000000001','Pan1','e2000000-0000-0000-0000-000000000002','Pan2');
INSERT INTO public.receipt_case (id, account_id, panelist_id, telegram_id, tag_raw, tag_norm, detail_id, reason, status, attempts, first_attempt_at, last_attempt_at)
VALUES ('f1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000004','4004',
        '11844','00011844',NULL,'other_city_tag','needs_decision',2,'2026-11-02 10:00+00','2026-11-03 10:00+00');

DO $$
DECLARE r jsonb; e jsonb; v_pv jsonb; v_err text; t text := 't0ken-de-prueba'; v_log bigint; v_log2 bigint; v_s text; v_onedb uuid;
  v_case uuid := 'f1000000-0000-0000-0000-000000000001';
  v_det uuid := 'd1000000-0000-0000-0000-000000000001';
  d public.allocation_plan_details; c public.receipt_case;
BEGIN
  -- ---------- vista previa ----------
  r := public.ops_fix_r4_preview(t, v_case);
  PERFORM pg_temp.fail_if(NOT (r->>'applicable')::bool, 'preview applicable: ' || r::text);
  PERFORM pg_temp.fail_if(r->>'new_dest_code' <> 'P4' OR r->>'new_node' <> 'N4' OR r->>'origin_code' <> 'P1'
                          OR r->>'current_dest_code' <> 'P2' OR r->>'tag' <> '00011844' OR r->>'account' <> 'DEMO2',
                          'preview campos: ' || r::text);
  PERFORM pg_temp.fail_if((r->>'received_at')::timestamptz <> '2026-11-02 10:00+00', 'preview received_at: ' || r::text);
  PERFORM pg_temp.fail_if((r->>'detail_id')::uuid <> v_det OR (r->>'case_id')::uuid <> v_case, 'preview ids: ' || r::text);
  PERFORM pg_temp.fail_if((r->>'sla_hours')::numeric <> 6, 'preview sla: ' || r::text);
  PERFORM pg_temp.fail_if(r ? 'account_id', 'preview sin ids internos: ' || r::text);

  -- ---------- apply con expected que no coincide: error y nada cambia ----------
  v_s := pg_temp.state();
  BEGIN
    PERFORM public.ops_fix_r4_apply(t, v_case, jsonb_set(r, '{new_dest_code}', '"P3"'));
    RAISE EXCEPTION 'FAIL: apply con expected distinto';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err <> 'ops_fix: ha cambiado desde la propuesta', 'mensaje expected: ' || v_err);
  END;
  BEGIN
    PERFORM public.ops_fix_r4_apply(t, v_case, jsonb_set(r, '{received_at}', '"2026-11-01T10:00:00+00:00"'));
    RAISE EXCEPTION 'FAIL: apply con received_at distinto';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err <> 'ops_fix: ha cambiado desde la propuesta', 'mensaje expected 2: ' || v_err);
  END;
  PERFORM pg_temp.fail_if(pg_temp.state() <> v_s, 'expected distinto toco algo');

  -- ---------- apply ----------
  e := r;
  r := public.ops_fix_r4_apply(t, v_case, e);
  v_log := (r->>'log_id')::bigint;
  PERFORM pg_temp.fail_if(v_log IS NULL OR (r->>'detail_id')::uuid <> v_det OR r->>'new_dest_code' <> 'P4', 'apply: ' || r::text);
  SELECT * INTO d FROM public.allocation_plan_details x WHERE x.id = v_det;
  PERFORM pg_temp.fail_if(d.status <> 'received' OR d.received_at <> '2026-11-02 10:00+00', 'linea recibida');
  PERFORM pg_temp.fail_if(d.destination_node_id <> 'b4000000-0000-0000-0000-000000000004'
                          OR d.destination_panelist_id <> 'e4000000-0000-0000-0000-000000000004'
                          OR d.destination_panelist_name <> 'Pan4', 'destino nuevo');
  PERFORM pg_temp.fail_if(d.original_destination_node_id IS DISTINCT FROM 'b2000000-0000-0000-0000-000000000002', 'destino original');
  PERFORM pg_temp.fail_if(d.reassignment_reason IS DISTINCT FROM 'sender_wrong_address' OR d.reassigned_at IS NULL, 'motivo');
  PERFORM pg_temp.fail_if(d.transferred_to_one_db_at IS NULL, 'transferida');
  SELECT * INTO c FROM public.receipt_case x WHERE x.id = v_case;
  PERFORM pg_temp.fail_if(c.status <> 'fixed' OR c.resolved_by IS NOT NULL OR c.resolved_at IS NULL
                          OR c.resolution_note <> 'Redirigida al receptor real (error de dirección del remitente) — agente de operaciones',
                          'caso fixed: ' || to_jsonb(c)::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM ops_fix.log l WHERE l.id = v_log AND l.kind = 'r4'
                             AND l.account_id = 'a0000000-0000-0000-0000-000000000001') <> 1, 'log r4');
  SELECT o.id INTO v_onedb FROM public.one_db o WHERE o.allocation_detail_id = v_det;
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.one_db o WHERE o.allocation_detail_id = v_det) <> 1, 'copia en one_db');
  PERFORM pg_temp.fail_if((SELECT o.destination_city_name FROM public.one_db o WHERE o.id = v_onedb) <> 'City2', 'one_db ciudad nueva');
  PERFORM pg_temp.fail_if((SELECT (l.after->>'one_db_id')::uuid FROM ops_fix.log l WHERE l.id = v_log) IS DISTINCT FROM v_onedb, 'log after one_db_id');
  -- la vista previa tras aplicar devuelve el estado del caso (fixed) para que el agente sepa que se aplico
  v_pv := public.ops_fix_r4_preview(t, v_case);
  PERFORM pg_temp.fail_if((v_pv->>'applicable')::bool OR v_pv->>'case_status' IS DISTINCT FROM 'fixed', 'preview tras apply case_status: ' || v_pv::text);

  -- segundo apply: error
  BEGIN
    PERFORM public.ops_fix_r4_apply(t, v_case, e);
    RAISE EXCEPTION 'FAIL: segundo apply';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_fix: R4 no aplica: %', 'mensaje segundo apply: ' || v_err);
  END;

  -- ---------- undo ----------
  r := public.ops_fix_r4_undo(t, v_log);
  PERFORM pg_temp.fail_if(NOT (r->>'restored')::bool, 'undo: ' || r::text);
  SELECT * INTO d FROM public.allocation_plan_details x WHERE x.id = v_det;
  PERFORM pg_temp.fail_if(d.status <> 'sent' OR d.received_at IS NOT NULL OR d.transferred_to_one_db_at IS NOT NULL
                          OR d.destination_node_id <> 'b2000000-0000-0000-0000-000000000002'
                          OR d.destination_panelist_id <> 'e2000000-0000-0000-0000-000000000002'
                          OR d.destination_panelist_name <> 'Pan2'
                          OR d.original_destination_node_id IS NOT NULL OR d.reassignment_reason IS NOT NULL
                          OR d.reassigned_at IS NOT NULL, 'linea restaurada: ' || to_jsonb(d)::text);
  SELECT * INTO c FROM public.receipt_case x WHERE x.id = v_case;
  PERFORM pg_temp.fail_if(c.status <> 'needs_decision' OR c.resolved_at IS NOT NULL OR c.resolution_note IS NOT NULL, 'caso restaurado');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.one_db o WHERE o.allocation_detail_id = v_det), 'copia one_db borrada');
  PERFORM pg_temp.fail_if((SELECT l.undone_at FROM ops_fix.log l WHERE l.id = v_log) IS NULL, 'undone_at');
  BEGIN
    PERFORM public.ops_fix_r4_undo(t, v_log);
    RAISE EXCEPTION 'FAIL: segundo undo';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_fix:%ya se deshizo%', 'mensaje segundo undo: ' || v_err);
  END;
  -- undo de un registro que no es r4
  INSERT INTO ops_fix.log (kind, account_id, target, before, after)
  VALUES ('r2', 'a0000000-0000-0000-0000-000000000001', 'P9', '{}', '{}') RETURNING id INTO v_log2;
  BEGIN
    PERFORM public.ops_fix_r4_undo(t, v_log2);
    RAISE EXCEPTION 'FAIL: undo de r2';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_fix:%no es un arreglo R4%', 'mensaje undo r2: ' || v_err);
  END;

  -- ---------- undo pasadas 24 h ----------
  e := public.ops_fix_r4_preview(t, v_case);
  PERFORM pg_temp.fail_if(NOT (e->>'applicable')::bool, 'aplicable otra vez tras deshacer: ' || e::text);
  v_log := (public.ops_fix_r4_apply(t, v_case, e)->>'log_id')::bigint;
  UPDATE ops_fix.log SET applied_at = now() - interval '25 hours' WHERE id = v_log;
  v_s := pg_temp.state();
  BEGIN
    PERFORM public.ops_fix_r4_undo(t, v_log);
    RAISE EXCEPTION 'FAIL: undo pasadas 24 h';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_fix:%24 h%', 'mensaje 24 h: ' || v_err);
  END;
  PERFORM pg_temp.fail_if(pg_temp.state() <> v_s, 'undo 24 h toco algo');

  -- ---------- undo tras cambiar a mano el caso (subtransaccion que se deshace) ----------
  UPDATE ops_fix.log SET applied_at = now() WHERE id = v_log;
  BEGIN
    UPDATE public.receipt_case SET status = 'discarded', resolution_note = 'cerrado a mano' WHERE id = v_case;
    v_s := pg_temp.state();
    BEGIN
      PERFORM public.ops_fix_r4_undo(t, v_log);
      RAISE EXCEPTION 'FAIL: undo tras cambiar el caso a mano';
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      PERFORM pg_temp.fail_if(v_err <> 'ops_fix: cambió después del arreglo; no lo deshago', 'mensaje caso a mano: ' || v_err);
    END;
    PERFORM pg_temp.fail_if(pg_temp.state() <> v_s, 'undo tras cambiar el caso toco algo');
    -- el caso cerrado por otra persona: la vista previa lo dice con case_status
    v_pv := public.ops_fix_r4_preview(t, v_case);
    PERFORM pg_temp.fail_if((v_pv->>'applicable')::bool OR v_pv->>'case_status' IS DISTINCT FROM 'discarded', 'preview cerrado a mano: ' || v_pv::text);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;

  -- ---------- undo tras cambiar a mano la linea ----------
  UPDATE public.allocation_plan_details SET status = 'cancelled' WHERE id = v_det;
  v_s := pg_temp.state();
  BEGIN
    PERFORM public.ops_fix_r4_undo(t, v_log);
    RAISE EXCEPTION 'FAIL: undo tras cambio a mano';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err <> 'ops_fix: cambió después del arreglo; no lo deshago', 'mensaje cambio: ' || v_err);
  END;
  PERFORM pg_temp.fail_if(pg_temp.state() <> v_s, 'undo tras cambio toco algo');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.one_db o WHERE o.allocation_detail_id = v_det), 'one_db sigue');
  -- deja el fixture como al principio para los casos que no aplican
  DELETE FROM public.one_db WHERE allocation_detail_id = v_det;
  UPDATE public.allocation_plan_details
     SET status = 'sent', received_at = NULL, transferred_to_one_db_at = NULL,
         destination_node_id = 'b2000000-0000-0000-0000-000000000002',
         destination_panelist_id = 'e2000000-0000-0000-0000-000000000002', destination_panelist_name = 'Pan2',
         original_destination_node_id = NULL, reassignment_reason = NULL, reassigned_at = NULL
   WHERE id = v_det;
  UPDATE public.receipt_case SET status = 'needs_decision', resolved_at = NULL, resolution_note = NULL WHERE id = v_case;
  PERFORM pg_temp.fail_if(NOT (public.ops_fix_r4_preview(t, v_case)->>'applicable')::bool, 'fixture restaurado');
END $$;

-- ---------- casos que no aplican (cada uno en una subtransaccion que se deshace) ----------
DO $$
DECLARE r jsonb; v_err text; t text := 't0ken-de-prueba';
  v_case uuid := 'f1000000-0000-0000-0000-000000000001';
  v_det uuid := 'd1000000-0000-0000-0000-000000000001';
BEGIN
  -- motivo not_found
  BEGIN
    UPDATE public.receipt_case SET reason = 'not_found', status = 'pending' WHERE id = v_case;
    r := public.ops_fix_r4_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if((r->>'applicable')::bool OR r->>'reason' NOT LIKE '%otra ciudad%', 'not_found: ' || r::text);

  -- caso cerrado
  BEGIN
    UPDATE public.receipt_case SET status = 'discarded' WHERE id = v_case;
    r := public.ops_fix_r4_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if((r->>'applicable')::bool OR r->>'reason' NOT LIKE '%no está abierto%', 'cerrado: ' || r::text);

  -- dos lineas con la misma etiqueta
  BEGIN
    INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, tag_id, sent_at,
                                                origin_panelist_id, destination_panelist_id) VALUES
      ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000002','b2000000-0000-0000-0000-000000000002','b3000000-0000-0000-0000-000000000003',
       '2026-10-28','sent','00011844','2026-10-29 09:00+00','e2000000-0000-0000-0000-000000000002','e3000000-0000-0000-0000-000000000003');
    r := public.ops_fix_r4_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if((r->>'applicable')::bool OR r->>'reason' NOT LIKE '%2 líneas%', 'dos lineas: ' || r::text);

  -- otro caso abierto con la etiqueta
  BEGIN
    INSERT INTO public.receipt_case (account_id, panelist_id, telegram_id, tag_raw, tag_norm, reason, status, first_attempt_at, last_attempt_at)
    VALUES ('a0000000-0000-0000-0000-000000000001','e2000000-0000-0000-0000-000000000002','2002','00011844','00011844','not_found','pending',now(),now());
    r := public.ops_fix_r4_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if((r->>'applicable')::bool OR r->>'reason' NOT LIKE '%otro caso abierto%', 'otro caso: ' || r::text);

  -- linea ya recibida
  BEGIN
    UPDATE public.allocation_plan_details SET status = 'received', received_at = '2026-11-01 10:00+00' WHERE id = v_det;
    r := public.ops_fix_r4_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if((r->>'applicable')::bool OR r->>'reason' NOT LIKE '%no está en estado enviada%', 'recibida: ' || r::text);

  -- sent_at posterior al primer intento
  BEGIN
    UPDATE public.receipt_case SET first_attempt_at = '2026-10-29 10:00+00' WHERE id = v_case;
    r := public.ops_fix_r4_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if((r->>'applicable')::bool OR r->>'reason' NOT LIKE '%después%', 'sent_at posterior: ' || r::text);

  -- panelista del caso sin nodo
  BEGIN
    UPDATE public.panelists SET node_id = NULL WHERE id = 'e4000000-0000-0000-0000-000000000004';
    r := public.ops_fix_r4_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if((r->>'applicable')::bool OR r->>'reason' NOT LIKE '%no tiene nodo%', 'sin nodo: ' || r::text);

  -- panelista del caso inactivo
  BEGIN
    UPDATE public.panelists SET status = 'inactive' WHERE id = 'e4000000-0000-0000-0000-000000000004';
    r := public.ops_fix_r4_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if((r->>'applicable')::bool OR r->>'reason' NOT LIKE '%no está activo%', 'inactivo: ' || r::text);

  -- origen sin panelista (la copia a ONE DB fallaria)
  BEGIN
    UPDATE public.allocation_plan_details SET origin_panelist_id = NULL, origin_panelist_name = NULL WHERE id = v_det;
    UPDATE public.panelists SET node_id = NULL WHERE id = 'e1000000-0000-0000-0000-000000000001';
    r := public.ops_fix_r4_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if((r->>'applicable')::bool OR r->>'reason' NOT LIKE '%origen%', 'sin origen: ' || r::text);

  -- regla POBOX: el receptor (N4, unico nodo de City2) no fue al apartado el dia laborable anterior
  -- (viernes 30/10) y tenia un envio programado ese dia -> la recepcion se anularia (pobox_absent_no_visit)
  BEGIN
    UPDATE public.cities SET pobox_enabled = true WHERE id = 'c2000000-0000-0000-0000-000000000002';
    INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status,
                                                origin_panelist_id, destination_panelist_id) VALUES
      ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','b1000000-0000-0000-0000-000000000001',
       '2026-10-30','pending','e4000000-0000-0000-0000-000000000004','e1000000-0000-0000-0000-000000000001');
    r := public.ops_fix_r4_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if((r->>'applicable')::bool OR r->>'reason' NOT LIKE '%POBOX anularía%pobox_absent_no_visit%', 'pobox anula: ' || r::text);

  -- regla POBOX que no se puede comprobar (la funcion falla): no aplica (fail-closed)
  BEGIN
    CREATE OR REPLACE FUNCTION public.pobox_receipt_check(p_detail public.allocation_plan_details)
    RETURNS text LANGUAGE plpgsql STABLE SET search_path = public AS $f$
    BEGIN RAISE EXCEPTION 'pobox roto'; END $f$;
    r := public.ops_fix_r4_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if((r->>'applicable')::bool OR r->>'reason' IS DISTINCT FROM 'no pude comprobar la regla POBOX', 'pobox falla: ' || r::text);

  -- sin norma de entrega para el par nuevo: aplica igual, con sla_hours null
  BEGIN
    DELETE FROM public.delivery_standards WHERE account_id = 'a0000000-0000-0000-0000-000000000001';
    r := public.ops_fix_r4_preview(t, v_case);
    RAISE EXCEPTION USING ERRCODE = 'RBACK';
  EXCEPTION WHEN SQLSTATE 'RBACK' THEN NULL; END;
  PERFORM pg_temp.fail_if(NOT (r->>'applicable')::bool OR NOT (r ? 'sla_hours') OR r->'sla_hours' <> 'null'::jsonb, 'sin sla: ' || r::text);

  -- apply cuando no aplica
  BEGIN
    UPDATE public.panelists SET node_id = NULL WHERE id = 'e4000000-0000-0000-0000-000000000004';
    PERFORM public.ops_fix_r4_apply(t, v_case, '{}'::jsonb);
    RAISE EXCEPTION 'FAIL: apply no aplicable';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_fix: R4 no aplica: %no tiene nodo%', 'mensaje apply no aplica: ' || v_err);
  END;

  -- caso inexistente y token malo
  BEGIN
    PERFORM public.ops_fix_r4_preview(t, '00000000-0000-0000-0000-000000000000');
    RAISE EXCEPTION 'FAIL: caso inexistente';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_fix:%no existe%', 'mensaje inexistente: ' || v_err);
  END;
  BEGIN
    PERFORM public.ops_fix_r4_preview('malo', v_case);
    RAISE EXCEPTION 'FAIL: token malo preview';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_test: token no valido%', 'token preview: ' || v_err);
  END;
  BEGIN
    PERFORM public.ops_fix_r4_apply('malo', v_case, '{}'::jsonb);
    RAISE EXCEPTION 'FAIL: token malo apply';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_test: token no valido%', 'token apply: ' || v_err);
  END;
  BEGIN
    PERFORM public.ops_fix_r4_undo('malo', 1);
    RAISE EXCEPTION 'FAIL: token malo undo';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_test: token no valido%', 'token undo: ' || v_err);
  END;

  -- permisos
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.ops_fix_r4_preview(text,uuid)', 'EXECUTE'), 'authenticated preview');
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.ops_fix_r4_apply(text,uuid,jsonb)', 'EXECUTE'), 'authenticated apply');
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.ops_fix_r4_undo(text,bigint)', 'EXECUTE'), 'authenticated undo');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('anon', 'public.ops_fix_r4_preview(text,uuid)', 'EXECUTE'), 'anon preview');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('anon', 'public.ops_fix_r4_apply(text,uuid,jsonb)', 'EXECUTE'), 'anon apply');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('anon', 'public.ops_fix_r4_undo(text,bigint)', 'EXECUTE'), 'anon undo');
  PERFORM pg_temp.fail_if(has_function_privilege('anon', 'ops_fix._r4_check(uuid)', 'EXECUTE'), 'anon _r4_check');
END $$;

ROLLBACK;
