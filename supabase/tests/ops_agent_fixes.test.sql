-- Reparaciones de datos del agente de operaciones (fase 3): R1 desatascar conversacion, R2 asignar nodo,
-- R3 rellenar dias sin envio de una ciudad POBOX con el balanceo existente; y dos avisos nuevos en
-- ops_test_checks (panelist_no_node, stuck_context). Todas protegidas con el token del agente.
--
-- Lo que escribe public.rpc_balance_city_v2 con p_apply_changes = true (ultima definicion:
-- 20261102072347_pobox_receipt_after_absence.sql, seccion 7), y por tanto lo que R3 copia y deshace:
--   * public.allocation_plan_details
--       - UPDATE (reparto y POBOX): origin_node_id, origin_panelist_name, origin_panelist_id, fecha_programada,
--         week_number, month, year, original_fecha_programada, original_origin_node_id, reassignment_reason,
--         reassigned_at, reassigned_by, updated_at
--       - UPDATE (destino reasignado, fase 0): destination_node_id, original_destination_node_id,
--         destination_panelist_id, destination_panelist_name, reassignment_reason, reassigned_at, reassigned_by,
--         updated_at
--       - UPDATE (sustitucion POBOX -> compensation): plan_id, destination_node_id, destination_panelist_id,
--         destination_panelist_name, original_origin_node_id, original_destination_node_id, generation_source,
--         updated_at
--       - INSERT filas nuevas generation_source 'pobox' y 'compensation'
--       - DELETE de las filas apartadas al registro
--   * public.deferred_samples
--       - INSERT (muestra apartada: copia completa en row_snapshot)
--       - UPDATE status, reintroduced_at, reintroduced_detail_id, waiting_reason
--   * public.cities: balance_rotation_offset (+1)
--   (Ademas los triggers de allocation_plan_details: updated_at, campos de semana, incidencias de bajas.)
-- auth.uid() es NULL en una llamada interna: la guarda de cuenta la deja pasar.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

-- Huella de todo lo de la cuenta 2 (nada de lo que hace el agente en la cuenta 1 debe cambiarla).
CREATE OR REPLACE FUNCTION pg_temp.acc2_md5() RETURNS text LANGUAGE sql AS $$
  SELECT md5(concat_ws('#',
    (SELECT string_agg(to_jsonb(x)::text, '|' ORDER BY x.id) FROM public.allocation_plan_details x
      WHERE x.account_id = 'a0000000-0000-0000-0000-000000000002'),
    (SELECT string_agg(to_jsonb(x)::text, '|' ORDER BY x.id) FROM public.panelists x
      WHERE x.account_id = 'a0000000-0000-0000-0000-000000000002'),
    (SELECT string_agg(to_jsonb(x)::text, '|' ORDER BY x.id) FROM public.nodes x
      WHERE x.account_id = 'a0000000-0000-0000-0000-000000000002'),
    (SELECT string_agg(to_jsonb(x)::text, '|' ORDER BY x.id) FROM public.cities x
      WHERE x.account_id = 'a0000000-0000-0000-0000-000000000002'),
    (SELECT string_agg(to_jsonb(x)::text, '|' ORDER BY x.id) FROM public.deferred_samples x
      WHERE x.account_id = 'a0000000-0000-0000-0000-000000000002'),
    (SELECT string_agg(to_jsonb(x)::text, '|' ORDER BY x.id) FROM public.panelist_context x
      WHERE x.telegram_id = 't9')));
$$;

BEGIN;
\ir fixtures/incident_city.sql
INSERT INTO ops_test.secret(token_sha256) VALUES (encode(extensions.digest('t0ken-de-prueba','sha256'),'hex'));
-- City2 (solo N4) es POBOX; City1 (N1-N3) no. N3 inactivo => City1 tiene 2 nodos activos.
UPDATE public.cities SET pobox_enabled = true WHERE id = 'c2000000-0000-0000-0000-000000000002';
UPDATE public.nodes SET status = 'inactive' WHERE id = 'b3000000-0000-0000-0000-000000000003';
UPDATE public.panelists SET telegram_id = 't1' WHERE id = 'e1000000-0000-0000-0000-000000000001';
UPDATE public.panelists SET telegram_id = 't2' WHERE id = 'e2000000-0000-0000-0000-000000000002';
-- City3 con un unico nodo activo N5, libre (sin panelista).
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City3','C3');
INSERT INTO public.nodes (id, account_id, city_id, auto_id, status) VALUES
  ('b5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000003','N5','active'),
  ('b6000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000001','c3000000-0000-0000-0000-000000000003','N6','inactive');
-- P5: activo, con telegram, sin nodo, en City3 (1 nodo activo y libre) -> R2 aplicable.
-- P6: activo, sin nodo, en City1 (2 nodos activos) -> R2 no aplicable.
-- P7: activo, sin nodo, en City2 (1 nodo activo pero ocupado por P4) -> R2 no aplicable.
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language, telegram_id, city_id) VALUES
  ('e5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','P5','Pan5','p5@t.l','5',NULL,'active','en','t5','c3000000-0000-0000-0000-000000000003'),
  ('e7000000-0000-0000-0000-000000000007','a0000000-0000-0000-0000-000000000001','P7','Pan7','p7@t.l','7',NULL,'active','en',NULL,'c2000000-0000-0000-0000-000000000002'),
  ('e6000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000001','P6','Pan6','p6@t.l','6',NULL,'active','en',NULL,'c1000000-0000-0000-0000-000000000001');
-- Conversaciones: P1 atascada (2 filas, una de hace 2 dias), P2 reciente.
INSERT INTO public.panelist_context (telegram_id, context_type, created_at) VALUES
  ('t1', 'awaiting_tag', now() - interval '2 days'), ('t1', 'awaiting_photo', now() - interval '1 hour'),
  ('t2', 'awaiting_tag', now() - interval '1 hour');

-- Cuenta 2: tambien tiene una ciudad "City2" POBOX con un nodo, panelista, conversacion atascada y envios.
INSERT INTO public.regions (id, account_id, name, code) VALUES
  ('e0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','Reg2','R2');
INSERT INTO public.cities (id, account_id, region_id, name, code, pobox_enabled) VALUES
  ('c9000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','City2','C9', true),
  ('c8000000-0000-0000-0000-000000000008','a0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','City8','C8', NULL);
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b9000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000002','c9000000-0000-0000-0000-000000000009','N9'),
  ('b8000000-0000-0000-0000-000000000008','a0000000-0000-0000-0000-000000000002','c8000000-0000-0000-0000-000000000008','N8');
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language, telegram_id) VALUES
  ('e9000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000002','P9','Pan9','p9@t.l','9','b9000000-0000-0000-0000-000000000009','active','en','t9'),
  ('e8000000-0000-0000-0000-000000000008','a0000000-0000-0000-0000-000000000002','P8','Pan8','p8@t.l','8','b8000000-0000-0000-0000-000000000008','active','en',NULL);
INSERT INTO public.panelist_context (telegram_id, context_type, created_at) VALUES ('t9', 'awaiting_tag', now() - interval '3 days');
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000002','CA9','Carrier9');
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000009','PR9','Prod9',48);
INSERT INTO public.allocation_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date) VALUES
  ('cc000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000002','R3acc2','ca000000-0000-0000-0000-000000000009','cb000000-0000-0000-0000-000000000009',50,current_date - 5,current_date + 25);
INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
SELECT 'a0000000-0000-0000-0000-000000000002','cc000000-0000-0000-0000-000000000009','b9000000-0000-0000-0000-000000000009',
       'b8000000-0000-0000-0000-000000000008', current_date + 20, 'pending' FROM generate_series(1, 6);

-- Cuenta 1, R3: plan en curso con 6 envios pendientes de N4 (City2) amontonados en un solo dia del final.
INSERT INTO public.allocation_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date) VALUES
  ('cc000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','R3plan','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',50,current_date - 5,current_date + 25);
CREATE TEMP TABLE _r3day AS
  SELECT (SELECT g::date FROM generate_series(current_date + 25, current_date + 15, interval '-1 day') g
           WHERE public.is_account_working_day('a0000000-0000-0000-0000-000000000001', g::date) ORDER BY g DESC LIMIT 1) AS d;
INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
SELECT 'a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000003','b4000000-0000-0000-0000-000000000004',
       'b1000000-0000-0000-0000-000000000001', (SELECT d FROM _r3day), 'pending' FROM generate_series(1, 6);
-- Envio que el balanceo aparta al registro (to_registry): destino N6 sin panelista y City3 sin alternativa.
INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
VALUES ('d7000000-0000-0000-0000-000000000007','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000003',
        'b4000000-0000-0000-0000-000000000004','b6000000-0000-0000-0000-000000000006', (SELECT d FROM _r3day), 'pending');
-- Anotacion pendiente del registro de City2 que el balanceo reintroduce (compensation).
INSERT INTO public.deferred_samples (id, account_id, plan_id, origin_city_id, dest_city_id, origin_node_id, destination_node_id,
                                     fecha_programada, reason, row_snapshot)
VALUES ('d8000000-0000-0000-0000-000000000008','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000003',
        'c2000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004',
        'b1000000-0000-0000-0000-000000000001', current_date - 3, 'no_valid_day', '{}'::jsonb);

CREATE TEMP TABLE _m AS SELECT pg_temp.acc2_md5() AS h;

DO $$
DECLARE r jsonb; v_err text; v_log bigint; v_moved uuid; v_linked uuid; v_comp uuid; v_n int; f text;
BEGIN
  -- ===== token malo: todas lo rechazan
  FOREACH f IN ARRAY ARRAY['ops_fix_r1_preview(''malo'',''P1'')', 'ops_fix_r1_apply(''malo'',''P1'')',
                           'ops_fix_r2_preview(''malo'',''P5'')', 'ops_fix_r2_apply(''malo'',''P5'')',
                           'ops_fix_r2_undo(''malo'',1)', 'ops_fix_r3_preview(''malo'',''Acc'',''City2'')',
                           'ops_fix_r3_apply(''malo'',''Acc'',''City2'')', 'ops_fix_r3_undo(''malo'',1)'] LOOP
    BEGIN
      EXECUTE 'SELECT public.' || f;
      RAISE EXCEPTION 'FAIL: token malo aceptado en %', f;
    EXCEPTION WHEN raise_exception THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_test: token no valido%', f || ' mensaje token: ' || v_err);
    END;
  END LOOP;

  -- ===== ops_test_checks: las dos listas nuevas
  r := public.ops_test_checks('t0ken-de-prueba');
  PERFORM pg_temp.fail_if(NOT (r ? 'pobox_no_send' AND r ? 'no_receipts'), 'listas antiguas: ' || r::text);
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'panelist_no_node') <> 1
                          OR r->'panelist_no_node'->0->>'panelist' <> 'P5' OR r->'panelist_no_node'->0->>'account' <> 'Acc'
                          OR r->'panelist_no_node'->0->>'city' <> 'City3', 'panelist_no_node: ' || r::text);
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'stuck_context') <> 2
                          OR NOT (r->'stuck_context' @> '[{"account":"Acc","panelist":"P1"}]')
                          OR NOT (r->'stuck_context' @> '[{"account":"Acc2","panelist":"P9"}]')
                          OR (r->'stuck_context' @> '[{"panelist":"P2"}]'), 'stuck_context: ' || r::text);
  PERFORM pg_temp.fail_if(NOT (r->'pobox_no_send' @> '[{"account":"Acc","city":"City2"}]'),
                          'City2 de Acc debe salir en pobox_no_send: ' || r::text);

  -- ===== R1: borra solo las filas del panelista indicado
  r := public.ops_fix_r1_preview('t0ken-de-prueba', 'P1');
  PERFORM pg_temp.fail_if(r->>'panelist' <> 'P1' OR r->>'account' <> 'Acc' OR jsonb_array_length(r->'contexts') <> 2,
                          'r1 preview: ' || r::text);
  r := public.ops_fix_r1_apply('t0ken-de-prueba', 'P1');
  PERFORM pg_temp.fail_if((r->>'deleted')::int <> 2 OR r->>'log_id' IS NULL, 'r1 apply: ' || r::text);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_context WHERE telegram_id = 't1'), 'r1 no borro t1');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_context WHERE telegram_id IN ('t2', 't9')) <> 2,
                          'r1 borro conversaciones de otros');
  PERFORM pg_temp.fail_if((SELECT kind FROM ops_fix.log WHERE id = (r->>'log_id')::bigint) <> 'r1', 'r1 sin registro');

  -- ===== R2
  BEGIN
    PERFORM public.ops_fix_r2_preview('t0ken-de-prueba', 'P1');
    RAISE EXCEPTION 'FAIL: r2 sobre panelista con nodo';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_fix: no aplicable (%', 'r2 con nodo: ' || v_err);
  END;
  BEGIN
    PERFORM public.ops_fix_r2_apply('t0ken-de-prueba', 'P6');
    RAISE EXCEPTION 'FAIL: r2 en ciudad con 2 nodos';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_fix: no aplicable (%', 'r2 dos nodos: ' || v_err);
  END;
  BEGIN
    PERFORM public.ops_fix_r2_preview('t0ken-de-prueba', 'P7');
    RAISE EXCEPTION 'FAIL: r2 con el unico nodo ocupado';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_fix: no aplicable (%', 'r2 nodo ocupado: ' || v_err);
  END;
  PERFORM pg_temp.fail_if((SELECT node_id FROM public.panelists WHERE panelist_code = 'P6') IS NOT NULL, 'r2 toco P6');
  r := public.ops_fix_r2_preview('t0ken-de-prueba', 'P5');
  PERFORM pg_temp.fail_if(r->>'panelist' <> 'P5' OR r->>'account' <> 'Acc' OR r->>'city' <> 'City3' OR r->>'node' <> 'N5',
                          'r2 preview: ' || r::text);
  r := public.ops_fix_r2_apply('t0ken-de-prueba', 'P5');
  v_log := (r->>'log_id')::bigint;
  PERFORM pg_temp.fail_if(r->>'node' <> 'N5'
                          OR (SELECT node_id FROM public.panelists WHERE panelist_code = 'P5') <> 'b5000000-0000-0000-0000-000000000005',
                          'r2 apply: ' || r::text);
  r := public.ops_fix_r2_undo('t0ken-de-prueba', v_log);
  PERFORM pg_temp.fail_if((r->>'restored')::int <> 1
                          OR (SELECT node_id FROM public.panelists WHERE panelist_code = 'P5') IS NOT NULL, 'r2 undo: ' || r::text);
  -- cambio a mano entre apply y undo: el undo no lo toca
  r := public.ops_fix_r2_apply('t0ken-de-prueba', 'P5');
  v_log := (r->>'log_id')::bigint;
  UPDATE public.panelists SET node_id = 'b6000000-0000-0000-0000-000000000006' WHERE panelist_code = 'P5';
  r := public.ops_fix_r2_undo('t0ken-de-prueba', v_log);
  PERFORM pg_temp.fail_if((r->>'restored')::int <> 0 OR jsonb_array_length(r->'skipped') <> 1
                          OR (SELECT node_id FROM public.panelists WHERE panelist_code = 'P5') IS DISTINCT FROM 'b6000000-0000-0000-0000-000000000006',
                          'r2 undo tras cambio a mano: ' || r::text);
  UPDATE public.panelists SET node_id = NULL WHERE panelist_code = 'P5';

  -- ===== R3 sobre City2 (POBOX, 1 nodo, dias sin envio)
  CREATE TEMP TABLE _apd0 AS SELECT * FROM public.allocation_plan_details WHERE account_id = 'a0000000-0000-0000-0000-000000000001';
  CREATE TEMP TABLE _ds0 AS SELECT * FROM public.deferred_samples WHERE account_id = 'a0000000-0000-0000-0000-000000000001';
  r := public.ops_fix_r3_preview('t0ken-de-prueba', 'Acc', 'City2');
  PERFORM pg_temp.fail_if(r->>'city' <> 'City2' OR (r->>'count')::int <= 0 OR jsonb_array_length(r->'moves') <> (r->>'count')::int,
                          'r3 preview: ' || r::text);
  -- la vista previa no escribe
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details WHERE account_id = 'a0000000-0000-0000-0000-000000000001')
                          <> (SELECT count(*) FROM _apd0)
                          OR EXISTS (SELECT 1 FROM public.allocation_plan_details a JOIN _apd0 b ON b.id = a.id
                                      WHERE a.fecha_programada <> b.fecha_programada), 'r3 preview escribio');
  v_n := (r->>'count')::int;
  -- si el balanceo responde success:false, la vista previa dice "no aplicable" (la funcion se sustituye solo
  -- dentro de esta subtransaccion, que se deshace)
  BEGIN
    BEGIN
      EXECUTE $f$CREATE OR REPLACE FUNCTION public.rpc_balance_city_v2(p_city_id uuid, p_start_date date, p_end_date date,
                   p_apply_changes boolean DEFAULT false, p_fence_until date DEFAULT NULL) RETURNS jsonb LANGUAGE sql
                   AS 'SELECT jsonb_build_object(''success'', false, ''error'', ''City not found'')'$f$;
      PERFORM public.ops_fix_r3_preview('t0ken-de-prueba', 'Acc', 'City2');
      RAISE EXCEPTION 'FAIL: preview con success:false aceptada';
    EXCEPTION WHEN raise_exception THEN
      GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
      PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_fix: no aplicable (%', 'r3 preview success:false: ' || v_err);
    END;
    RAISE EXCEPTION 'deshacer stub' USING ERRCODE = 'TSTUB';
  EXCEPTION WHEN SQLSTATE 'TSTUB' THEN NULL;
  END;
  r := public.ops_fix_r3_apply('t0ken-de-prueba', 'Acc', 'City2');
  v_log := (r->>'log_id')::bigint;
  PERFORM pg_temp.fail_if(v_log IS NULL OR jsonb_array_length(r->'moves') <> v_n, 'r3 apply (mismos movimientos que la vista previa): ' || r::text);
  PERFORM pg_temp.fail_if(NOT (r->'moves' @> '[{"id":"d7000000-0000-0000-0000-000000000007","kind":"to_registry"}]')
                          OR EXISTS (SELECT 1 FROM public.allocation_plan_details WHERE id = 'd7000000-0000-0000-0000-000000000007'),
                          'r3 apply: el envio sin destino valido debia ir al registro: ' || r::text);
  SELECT reintroduced_detail_id INTO v_comp FROM public.deferred_samples
   WHERE id = 'd8000000-0000-0000-0000-000000000008' AND status = 'reintroduced';
  PERFORM pg_temp.fail_if(v_comp IS NULL OR NOT EXISTS (SELECT 1 FROM public.allocation_plan_details
                                                          WHERE id = v_comp AND generation_source = 'compensation'),
                          'r3 apply: la anotacion debia reintroducirse como compensation');
  r := public.ops_test_checks('t0ken-de-prueba');
  PERFORM pg_temp.fail_if(r->'pobox_no_send' @> '[{"account":"Acc","city":"City2"}]', 'tras R3 City2 sigue en pobox_no_send: ' || r::text);
  PERFORM pg_temp.fail_if(NOT (r->'pobox_no_send' @> '[{"account":"Acc2","city":"City2"}]'), 'R3 no debe tocar City2 de Acc2: ' || r::text);
  -- no aplicable si la ciudad ya no sale en pobox_no_send
  BEGIN
    PERFORM public.ops_fix_r3_preview('t0ken-de-prueba', 'Acc', 'City2');
    RAISE EXCEPTION 'FAIL: r3 sobre ciudad que no sale en pobox_no_send';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_fix: no aplicable (%', 'r3 no aplicable: ' || v_err);
  END;

  -- un envio movido se marca a mano como enviado: el undo lo salta y restaura el resto
  SELECT a.id INTO v_moved FROM public.allocation_plan_details a JOIN _apd0 b ON b.id = a.id
   WHERE a.fecha_programada <> b.fecha_programada ORDER BY a.fecha_programada LIMIT 1;
  PERFORM pg_temp.fail_if(v_moved IS NULL, 'r3 no movio ningun envio existente');
  UPDATE public.allocation_plan_details SET status = 'sent', sent_at = now(), tag_id = '55555555' WHERE id = v_moved;
  -- un envio creado por R3, sin cambios pero con una fila enlazada (material_hold, ON DELETE CASCADE): el undo no
  -- lo borra y lo devuelve en skipped
  SELECT a.id INTO v_linked FROM public.allocation_plan_details a
   WHERE a.account_id = 'a0000000-0000-0000-0000-000000000001' AND a.generation_source = 'pobox'
     AND NOT EXISTS (SELECT 1 FROM _apd0 b WHERE b.id = a.id) ORDER BY a.fecha_programada LIMIT 1;
  PERFORM pg_temp.fail_if(v_linked IS NULL, 'r3 no creo ningun envio POBOX');
  INSERT INTO public.material_hold (allocation_plan_detail_id, account_id, panelist_id)
  VALUES (v_linked, 'a0000000-0000-0000-0000-000000000001', 'e4000000-0000-0000-0000-000000000004');
  r := public.ops_fix_r3_undo('t0ken-de-prueba', v_log);
  PERFORM pg_temp.fail_if(NOT (r->'skipped' @> to_jsonb(ARRAY[v_moved::text, v_linked::text])) OR jsonb_array_length(r->'skipped') <> 2
                          OR (r->>'restored')::int < 1, 'r3 undo: ' || r::text);
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.allocation_plan_details WHERE id = v_linked)
                          OR NOT EXISTS (SELECT 1 FROM public.material_hold WHERE allocation_plan_detail_id = v_linked),
                          'r3 undo borro un envio con fila enlazada');
  -- to_registry: el envio vuelve y su anotacion desaparece; compensation: la fila se borra y la anotacion vuelve a pending
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.allocation_plan_details
                                       WHERE id = 'd7000000-0000-0000-0000-000000000007' AND status = 'pending')
                          OR EXISTS (SELECT 1 FROM public.deferred_samples
                                      WHERE account_id = 'a0000000-0000-0000-0000-000000000001'
                                        AND row_snapshot->>'id' = 'd7000000-0000-0000-0000-000000000007'),
                          'r3 undo no devolvio el envio apartado al registro');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.allocation_plan_details WHERE id = v_comp)
                          OR NOT EXISTS (SELECT 1 FROM public.deferred_samples WHERE id = 'd8000000-0000-0000-0000-000000000008'
                                           AND status = 'pending' AND reintroduced_detail_id IS NULL),
                          'r3 undo no deshizo la reintroduccion');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.allocation_plan_details a JOIN _apd0 b ON b.id = a.id
                                   WHERE a.id <> v_moved AND (a.fecha_programada <> b.fecha_programada
                                         OR a.origin_node_id <> b.origin_node_id OR a.status <> b.status)),
                          'r3 undo no restauro las fechas');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.allocation_plan_details WHERE account_id = 'a0000000-0000-0000-0000-000000000001')
                          <> (SELECT count(*) + 1 FROM _apd0), 'r3 undo: quedan filas creadas (salvo la enlazada) o faltan filas');
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v_moved) <> 'sent', 'r3 undo toco la fila enviada');
  -- Los dos caminos del deshacer que vuelven a crear filas, comparados fila a fila con la copia de antes:
  --   to_registry: el envio borrado se reinserta (ops_fix._put modo insert) identico, columna a columna;
  --   compensation: la anotacion del registro vuelve (modo update) identica y su fila creada desaparece.
  PERFORM pg_temp.fail_if((SELECT to_jsonb(a.*) FROM public.allocation_plan_details a WHERE a.id = 'd7000000-0000-0000-0000-000000000007')
                          IS DISTINCT FROM (SELECT to_jsonb(b.*) FROM _apd0 b WHERE b.id = 'd7000000-0000-0000-0000-000000000007'),
                          'r3 undo to_registry: el envio reinsertado no es identico al de antes');
  PERFORM pg_temp.fail_if((SELECT to_jsonb(d.*) FROM public.deferred_samples d WHERE d.id = 'd8000000-0000-0000-0000-000000000008')
                          IS DISTINCT FROM (SELECT to_jsonb(b.*) FROM _ds0 b WHERE b.id = 'd8000000-0000-0000-0000-000000000008'),
                          'r3 undo compensation: la anotacion restaurada no es identica a la de antes');
  -- huella de las dos tablas: todo como antes, salvo el envio marcado a mano como enviado y el creado con fila enlazada
  PERFORM pg_temp.fail_if(
    (SELECT md5(string_agg(to_jsonb(a.*)::text, '|' ORDER BY a.id)) FROM public.allocation_plan_details a
      WHERE a.account_id = 'a0000000-0000-0000-0000-000000000001' AND a.id NOT IN (v_moved, v_linked))
    IS DISTINCT FROM (SELECT md5(string_agg(to_jsonb(b.*)::text, '|' ORDER BY b.id)) FROM _apd0 b WHERE b.id <> v_moved),
    'r3 undo: allocation_plan_details no ha quedado como antes');
  PERFORM pg_temp.fail_if(
    (SELECT md5(string_agg(to_jsonb(d.*)::text, '|' ORDER BY d.id)) FROM public.deferred_samples d
      WHERE d.account_id = 'a0000000-0000-0000-0000-000000000001')
    IS DISTINCT FROM (SELECT md5(string_agg(to_jsonb(b.*)::text, '|' ORDER BY b.id)) FROM _ds0 b),
    'r3 undo: deferred_samples no ha quedado como antes');
  PERFORM pg_temp.fail_if((SELECT undone_at FROM ops_fix.log WHERE id = v_log) IS NULL, 'r3 undo sin marcar');
  BEGIN
    PERFORM public.ops_fix_r3_undo('t0ken-de-prueba', v_log);
    RAISE EXCEPTION 'FAIL: doble undo';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_fix:%', 'doble undo: ' || v_err);
  END;

  -- ===== ninguna fila de otra cuenta cambia
  PERFORM pg_temp.fail_if(pg_temp.acc2_md5() IS DISTINCT FROM (SELECT h FROM _m), 'cambiaron datos de la cuenta 2');
END $$;
ROLLBACK;

DO $$
DECLARE f regprocedure;
BEGIN
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname LIKE 'ops\_fix\_r%' AND pronamespace = 'public'::regnamespace),
                          'no hay funciones ops_fix_*');
  FOR f IN SELECT p.oid::regprocedure FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname LIKE 'ops\_fix\_%' LOOP
    PERFORM pg_temp.fail_if(has_function_privilege('authenticated', f, 'EXECUTE'), 'authenticated puede ejecutar ' || f::text);
    PERFORM pg_temp.fail_if(NOT has_function_privilege('anon', f, 'EXECUTE'), 'anon debe poder ejecutar ' || f::text);
  END LOOP;
  PERFORM pg_temp.fail_if(has_table_privilege('anon', 'ops_fix.log', 'SELECT') OR has_table_privilege('authenticated', 'ops_fix.log', 'SELECT'),
                          'ops_fix.log legible por anon/authenticated');
  PERFORM pg_temp.fail_if(has_schema_privilege('anon', 'ops_fix', 'USAGE') OR has_schema_privilege('authenticated', 'ops_fix', 'USAGE'),
                          'esquema ops_fix usable por anon/authenticated');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('anon', 'public.ops_test_checks(text)', 'EXECUTE')
                          OR has_function_privilege('authenticated', 'public.ops_test_checks(text)', 'EXECUTE'), 'permisos ops_test_checks');
END $$;
SELECT 'ops_agent_fixes OK';
