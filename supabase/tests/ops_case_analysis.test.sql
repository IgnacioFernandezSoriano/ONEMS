-- Agente de analisis de casos, Tarea 2: lectura del caso (ops_case_find_panelists / ops_case_data).
-- Caso de referencia: Arbe (N1/City1) -> James (N4/City2), etiqueta 00011844 programada 27/10 y enviada 30/10.
-- Samwel (N3/City1) declara esa etiqueta como recibida (receipt_case needs_decision) y tiene una baja activa.
\set ON_ERROR_STOP on
SET client_min_messages = error;
CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
INSERT INTO ops_test.secret(token_sha256) VALUES (encode(extensions.digest('t0ken-de-prueba','sha256'),'hex'));
UPDATE public.panelists SET name = 'Arbe Tester', telegram_id = '1001' WHERE panelist_code = 'P1';
UPDATE public.panelists SET name = 'James Tester', language = 'fr' WHERE panelist_code = 'P4';
UPDATE public.panelists SET name = 'Samwel Mettet', telegram_id = '3003' WHERE panelist_code = 'P3';
-- segundo Samwel en la cuenta 2
INSERT INTO public.regions (id, account_id, name, code) VALUES ('e0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','Reg2','R2');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES ('c3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','City9','C9');
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES ('b9000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000002','c3000000-0000-0000-0000-000000000003','N9');
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language) VALUES
  ('e9000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000002','P9','Samwel Otro','p9@t.l','9','b9000000-0000-0000-0000-000000000009','active','en');
-- norma 6 h para el producto del plan; 48 h para otro producto en el mismo par (no debe salir)
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','PR2','Prod2',48);
INSERT INTO public.delivery_standards (account_id, carrier_id, product_id, origin_city_id, destination_city_id, standard_time, time_unit, success_percentage) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',6,'hours',90),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000002','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',48,'hours',90);
-- la linea del caso + 3 hermanas (mismo origen, mismo mes, destino Samwel)
INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, tag_id, sent_at,
                                            origin_panelist_id, destination_panelist_id) VALUES
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004',
   '2026-10-27','sent','00011844','2026-10-30 09:00+00','e1000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000004');
INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, tag_id, sent_at,
                                            origin_panelist_id, destination_panelist_id)
SELECT 'a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000003',
       ('2026-10-2' || i)::date,'sent','0001184' || i,('2026-10-2' || i || ' 09:00+00')::timestamptz,
       'e1000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000003' FROM generate_series(1,3) i;
-- caso de recepcion abierto de Samwel y baja activa
INSERT INTO public.receipt_case (id, account_id, panelist_id, telegram_id, tag_raw, tag_norm, detail_id, reason, status, attempts, first_attempt_at, last_attempt_at)
VALUES ('f1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000003','3003',
        '00011844','00011844','d1000000-0000-0000-0000-000000000001','other_city_tag','needs_decision',2,now(),now());
INSERT INTO public.panelist_unavailability (id, panelist_id, account_id, start_date, end_date, reason, status)
VALUES ('f2000000-0000-0000-0000-000000000001','e3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001',
        current_date - 1, current_date + 6, 'vacation', 'active');
-- incidencia de la cuenta 2
INSERT INTO public.panelist_incident (id, account_id, panelist_id, category) VALUES
  ('f3000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000002','e9000000-0000-0000-0000-000000000009','other');
-- incidencia abierta ligada a la linea (James) y mensajes: uno de un implicado (Arbe), uno de la cuenta 2 (no debe salir)
INSERT INTO public.panelist_incident (id, account_id, panelist_id, category, status, description, allocation_plan_detail_id) VALUES
  ('f3000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','e4000000-0000-0000-0000-000000000004','other','open','No llego la carta','d1000000-0000-0000-0000-000000000001');
INSERT INTO public.incident_message (account_id, panelist_id, incident_kind, incident_id, direction, author, body, status) VALUES
  ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','reported','f3000000-0000-0000-0000-000000000004','inbound','panelist','Mensaje de Arbe','received'),
  ('a0000000-0000-0000-0000-000000000002','e9000000-0000-0000-0000-000000000009','reported','f3000000-0000-0000-0000-000000000009','inbound','panelist','Mensaje de otra cuenta','received');

DO $$
DECLARE r jsonb; v_err text; t text := 't0ken-de-prueba';
  p_samwel uuid := 'e3000000-0000-0000-0000-000000000003';
BEGIN
  -- find_panelists
  r := public.ops_case_find_panelists(t, 'Samwel Mettet', '00011844');
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 1, 'find 1 fila: ' || r::text);
  PERFORM pg_temp.fail_if(NOT (r->0->>'by_name')::bool OR NOT (r->0->>'by_tag')::bool, 'by_name/by_tag: ' || r::text);
  PERFORM pg_temp.fail_if(r->0->>'code' <> 'P3' OR r->0->>'account' <> 'Acc' OR r->0->>'city' <> 'City1', 'campos find: ' || r::text);
  r := public.ops_case_find_panelists(t, 'Samwel', NULL);
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 2, 'find Samwel 2 filas: ' || r::text);
  r := public.ops_case_find_panelists(t, NULL, '00011844');   -- solo etiqueta: origen, destino y receptor
  PERFORM pg_temp.fail_if(jsonb_array_length(r) <> 3, 'find por etiqueta 3: ' || r::text);

  -- data
  r := public.ops_case_data(t, p_samwel, '00011844');
  PERFORM pg_temp.fail_if(r->'account'->>'name' <> 'Acc', 'account: ' || (r->'account')::text);
  PERFORM pg_temp.fail_if(r->'panelist'->>'code' <> 'P3' OR r->'panelist'->>'node' <> 'N3'
                          OR r->'panelist'->>'city' <> 'City1' OR NOT (r->'panelist'->>'has_telegram')::bool, 'panelist: ' || (r->'panelist')::text);
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'details') <> 1, 'details 1');
  PERFORM pg_temp.fail_if(r->'details'->0->>'carrier' <> 'Carrier' OR r->'details'->0->>'product_code' <> 'PR'
                          OR r->'details'->0->>'product' <> 'Prod', 'carrier/product: ' || (r->'details'->0)::text);
  PERFORM pg_temp.fail_if(r->'details'->0->'origin'->>'code' <> 'P1' OR r->'details'->0->'destination'->>'code' <> 'P4'
                          OR r->'details'->0->'destination'->>'language' <> 'fr' OR r->'details'->0->'origin'->>'node' <> 'N1', 'origen/destino');
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'details'->0->'standards') <> 1
                          OR (r->'details'->0->'standards'->0->>'standard_time')::numeric <> 6
                          OR r->'details'->0->'standards'->0->>'time_unit' <> 'hours', 'standards: ' || (r->'details'->0->'standards')::text);
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'siblings') <> 3, 'siblings 3: ' || (r->'siblings')::text);
  PERFORM pg_temp.fail_if(r->'anchor'->>'kind' <> 'receipt' OR r->'anchor'->>'id' <> 'f1000000-0000-0000-0000-000000000001', 'anchor: ' || (r->'anchor')::text);
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'receipt_cases') <> 1, 'receipt_cases 1');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'unavailability') u
                          WHERE u->>'id' = 'f2000000-0000-0000-0000-000000000001' AND u->>'panelist_code' = 'P3'), 'unavailability: ' || (r->'unavailability')::text);
  PERFORM pg_temp.fail_if(jsonb_typeof(r->'messages') <> 'array' OR jsonb_typeof(r->'incidents') <> 'array', 'arrays');

  -- incidencias y mensajes de los implicados; nada de la cuenta 2
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(r->'incidents') i
            WHERE i->>'id' = 'f3000000-0000-0000-0000-000000000004' AND i->>'panelist_code' = 'P4' AND i->>'category' = 'other'
              AND i->>'status' = 'open' AND i->>'description' = 'No llego la carta' AND i ? 'reported_at'), 'incidents: ' || (r->'incidents')::text);
  PERFORM pg_temp.fail_if(jsonb_array_length(r->'messages') <> 1, 'messages 1: ' || (r->'messages')::text);
  PERFORM pg_temp.fail_if(r->'messages'->0->>'body' <> 'Mensaje de Arbe' OR r->'messages'->0->>'panelist_code' <> 'P1'
            OR r->'messages'->0->>'incident_kind' <> 'reported' OR r->'messages'->0->>'direction' <> 'inbound'
            OR r->'messages'->0->>'author' <> 'panelist' OR NOT (r->'messages'->0 ? 'created_at')
            OR r->'messages'->0->>'incident_id' <> 'f3000000-0000-0000-0000-000000000004', 'message keys: ' || (r->'messages'->0)::text);
  PERFORM pg_temp.fail_if(r::text LIKE '%otra cuenta%' OR r::text LIKE '%P9%', 'fuga de cuenta 2');

  -- anchor por defecto sin caso de recepcion abierto: incidencia abierta ligada a la linea
  r := public.ops_case_data(t, 'e1000000-0000-0000-0000-000000000001', '00011844');
  PERFORM pg_temp.fail_if(r->'anchor'->>'kind' <> 'reported' OR r->'anchor'->>'id' <> 'f3000000-0000-0000-0000-000000000004', 'anchor reported: ' || (r->'anchor')::text);
  r := public.ops_case_data(t, 'e1000000-0000-0000-0000-000000000001', '99999999');
  PERFORM pg_temp.fail_if(r->'anchor' <> 'null'::jsonb OR jsonb_array_length(r->'details') <> 0, 'sin etiqueta: sin anchor');

  -- anchor explicito y de otra cuenta
  r := public.ops_case_data(t, p_samwel, '00011844', 'unavailability', 'f2000000-0000-0000-0000-000000000001');
  PERFORM pg_temp.fail_if(r->'anchor'->>'kind' <> 'unavailability', 'anchor explicito');
  BEGIN
    PERFORM public.ops_case_data(t, p_samwel, '00011844', 'reported', 'f3000000-0000-0000-0000-000000000009');
    RAISE EXCEPTION 'FAIL: no rechazo otra cuenta';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err <> 'ops_case: otra cuenta', 'mensaje otra cuenta: ' || v_err);
  END;
  -- token erroneo
  BEGIN
    PERFORM public.ops_case_data('malo', p_samwel, '00011844');
    RAISE EXCEPTION 'FAIL: token malo aceptado';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_test: token no valido%', 'mensaje token: ' || v_err);
  END;
  BEGIN
    PERFORM public.ops_case_find_panelists('malo', 'x', NULL);
    RAISE EXCEPTION 'FAIL: token malo aceptado (find)';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_test: token no valido%', 'mensaje token find: ' || v_err);
  END;
  -- privilegios
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.ops_case_data(text,uuid,text,text,uuid)', 'EXECUTE'), 'authenticated data');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('anon', 'public.ops_case_data(text,uuid,text,text,uuid)', 'EXECUTE'), 'anon data');
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.ops_case_find_panelists(text,text,text)', 'EXECUTE'), 'authenticated find');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('anon', 'public.ops_case_find_panelists(text,text,text)', 'EXECUTE'), 'anon find');
END $$;

-- ===== Tarea 3: cola desde ONEMS, envio y notas del agente =====
CREATE OR REPLACE FUNCTION pg_temp.act(p text) RETURNS void LANGUAGE sql AS $$
  SELECT set_config('request.jwt.claim.sub', p, true) $$;
UPDATE public.profiles SET role = 'admin' WHERE id IN ('99000000-0000-0000-0000-000000000099','98000000-0000-0000-0000-000000000098');
INSERT INTO auth.users (id, email) VALUES ('96000000-0000-0000-0000-000000000096', 'user@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('96000000-0000-0000-0000-000000000096', 'user@t.l', 'Normal', 'user', 'a0000000-0000-0000-0000-000000000001');
UPDATE public.panelists SET telegram_id = '9009' WHERE panelist_code = 'P9';

DO $$
DECLARE t text := 't0ken-de-prueba'; v_err text; r jsonb; v_req uuid; v_req2 uuid; v_old uuid; v_m1 uuid; v_m2 uuid; n int;
  v_case uuid := 'f1000000-0000-0000-0000-000000000001';
  v_arbe uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  -- request: dos veces seguidas = mismo id
  PERFORM pg_temp.act('99000000-0000-0000-0000-000000000099');
  v_req := public.request_case_analysis('receipt', v_case);
  v_req2 := public.request_case_analysis('receipt', v_case);
  PERFORM pg_temp.fail_if(v_req IS NULL OR v_req <> v_req2, 'request idempotente');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.case_analysis_request) <> 1, 'una sola fila');
  PERFORM pg_temp.fail_if((SELECT requested_by FROM public.case_analysis_request WHERE id = v_req) <> '99000000-0000-0000-0000-000000000099', 'requested_by');
  -- otra cuenta
  PERFORM pg_temp.act('98000000-0000-0000-0000-000000000098');
  BEGIN
    PERFORM public.request_case_analysis('receipt', v_case);
    RAISE EXCEPTION 'FAIL: no rechazo cross-tenant';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'Cross-tenant%', 'cross-tenant: ' || v_err);
  END;
  PERFORM pg_temp.act('99000000-0000-0000-0000-000000000099');

  -- claim
  r := public.ops_case_claim(t);
  PERFORM pg_temp.fail_if((r->>'request_id')::uuid <> v_req OR r->>'account' <> 'Acc' OR r->>'incident_kind' <> 'receipt'
     OR (r->>'incident_id')::uuid <> v_case OR r->>'tag' <> '00011844'
     OR (r->>'panelist_id')::uuid <> 'e3000000-0000-0000-0000-000000000003', 'claim: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT status FROM public.case_analysis_request WHERE id = v_req) <> 'running'
     OR (SELECT started_at FROM public.case_analysis_request WHERE id = v_req) IS NULL, 'running');
  PERFORM pg_temp.fail_if(public.ops_case_claim(t) <> '{}'::jsonb, 'segundo claim vacio');
  -- claim de una incidencia reportada: tag del plan
  INSERT INTO public.case_analysis_request (account_id, incident_kind, incident_id)
    VALUES ('a0000000-0000-0000-0000-000000000001','reported','f3000000-0000-0000-0000-000000000004');
  r := public.ops_case_claim(t);
  PERFORM pg_temp.fail_if(r->>'tag' <> '00011844' OR r->>'incident_kind' <> 'reported', 'claim reported: ' || r::text);
  INSERT INTO public.case_analysis_request (account_id, incident_kind, incident_id)
    VALUES ('a0000000-0000-0000-0000-000000000001','unavailability','f2000000-0000-0000-0000-000000000001');
  r := public.ops_case_claim(t);
  PERFORM pg_temp.fail_if(r->'tag' <> 'null'::jsonb, 'claim baja tag null: ' || r::text);

  -- finish
  PERFORM public.ops_case_finish(t, v_req, '{"x":1}', 'nota', NULL);
  PERFORM pg_temp.fail_if((SELECT status FROM public.case_analysis_request WHERE id = v_req) <> 'done'
     OR (SELECT result->>'x' FROM public.case_analysis_request WHERE id = v_req) <> '1'
     OR (SELECT finished_at FROM public.case_analysis_request WHERE id = v_req) IS NULL, 'done');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.incident_message WHERE incident_kind = 'receipt' AND incident_id = v_case
     AND direction = 'internal' AND author = 'system' AND status = 'sent' AND body = 'nota') <> 1, 'nota interna');
  PERFORM pg_temp.fail_if(public.case_analysis_status(v_req)->>'status' <> 'done', 'status done');
  -- finish con error
  INSERT INTO public.case_analysis_request (account_id, incident_kind, incident_id, status)
    VALUES ('a0000000-0000-0000-0000-000000000001','receipt',v_case,'running') RETURNING id INTO v_req2;
  PERFORM public.ops_case_finish(t, v_req2, NULL, '', 'boom');
  PERFORM pg_temp.fail_if((SELECT status || error FROM public.case_analysis_request WHERE id = v_req2) <> 'failedboom', 'failed');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.incident_message WHERE incident_kind = 'receipt' AND incident_id = v_case AND direction = 'internal') <> 1, 'sin nota vacia');

  -- timeout
  INSERT INTO public.case_analysis_request (account_id, incident_kind, incident_id, status, created_at)
    VALUES ('a0000000-0000-0000-0000-000000000001','reported','f3000000-0000-0000-0000-000000000004','queued', now() - interval '11 minutes')
    RETURNING id INTO v_old;
  r := public.case_analysis_status(v_old);
  PERFORM pg_temp.fail_if(r->>'status' <> 'failed' OR r->>'error' <> 'agent_timeout', 'timeout: ' || r::text);
  -- status de otra cuenta
  PERFORM pg_temp.act('98000000-0000-0000-0000-000000000098');
  BEGIN
    PERFORM public.case_analysis_status(v_req);
    RAISE EXCEPTION 'FAIL: status cross-tenant';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'Cross-tenant%', 'status cross: ' || v_err);
  END;
  PERFORM pg_temp.act('99000000-0000-0000-0000-000000000099');

  -- send con incidencia: dedupe
  v_m1 := public.ops_case_send(t, 'receipt', v_case, v_arbe, 'hi', 'r1:0');
  v_m2 := public.ops_case_send(t, 'receipt', v_case, v_arbe, 'hi', 'r1:0');
  PERFORM pg_temp.fail_if(v_m1 IS NULL OR v_m1 <> v_m2, 'send dedupe id');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.incident_message WHERE meta->>'case_draft_key' = 'r1:0') <> 1, 'una fila');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.incident_message WHERE id = v_m1 AND direction = 'outbound' AND author = 'manager'
     AND status = 'pending_send' AND panelist_id = v_arbe AND meta ? 'manager_user_id' AND meta->'manager_user_id' = 'null'::jsonb
     AND meta->>'via' = 'ops_agent'), 'send campos');
  -- send sin incidencia
  v_m1 := public.ops_case_send(t, NULL, NULL, v_arbe, 'hi', 'r1:1');
  v_m2 := public.ops_case_send(t, NULL, NULL, v_arbe, 'hi', 'r1:1');
  PERFORM pg_temp.fail_if(v_m1 <> v_m2, 'notice dedupe');
  SELECT count(*) INTO n FROM public.panelist_notification WHERE kind = 'manager_notice' AND payload->>'case_draft_key' = 'r1:1'
     AND payload->>'body' = 'hi' AND payload->>'via' = 'ops_agent' AND panelist_id = v_arbe;
  PERFORM pg_temp.fail_if(n <> 1, 'notice 1 fila: ' || n);
  -- panelista de otra cuenta
  BEGIN
    PERFORM public.ops_case_send(t, 'receipt', v_case, 'e9000000-0000-0000-0000-000000000009', 'hi', 'r1:2');
    RAISE EXCEPTION 'FAIL: envio a otra cuenta';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err <> 'ops_case: otra cuenta', 'otra cuenta: ' || v_err);
  END;
  -- 901 caracteres, vacio, sin telegram
  BEGIN
    PERFORM public.ops_case_send(t, 'receipt', v_case, v_arbe, repeat('x', 901), 'r1:3');
    RAISE EXCEPTION 'FAIL: 901 aceptado';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_case:%', '901: ' || v_err);
  END;
  PERFORM public.ops_case_send(t, 'receipt', v_case, v_arbe, repeat('x', 900), 'r1:4');
  BEGIN
    PERFORM public.ops_case_send(t, 'receipt', v_case, v_arbe, '  ', 'r1:5');
    RAISE EXCEPTION 'FAIL: vacio aceptado';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_case:%', 'vacio: ' || v_err);
  END;
  BEGIN
    PERFORM public.ops_case_send(t, 'receipt', v_case, 'e4000000-0000-0000-0000-000000000004', 'hi', 'r1:6');
    RAISE EXCEPTION 'FAIL: sin telegram aceptado';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_case:%', 'sin telegram: ' || v_err);
  END;

  -- nota
  v_m1 := public.ops_case_note(t, 'reported', 'f3000000-0000-0000-0000-000000000004', 'una nota');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.incident_message WHERE id = v_m1 AND direction = 'internal' AND author = 'system'
     AND incident_kind = 'reported' AND body = 'una nota'), 'nota');

  -- token malo
  BEGIN
    PERFORM public.ops_case_claim('malo');
    RAISE EXCEPTION 'FAIL: token malo';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_test: token no valido%', 'token claim: ' || v_err);
  END;

  -- privilegios
  PERFORM pg_temp.fail_if(NOT has_function_privilege('authenticated', 'public.request_case_analysis(text,uuid)', 'EXECUTE'), 'auth request');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('authenticated', 'public.case_analysis_status(uuid)', 'EXECUTE'), 'auth status');
  PERFORM pg_temp.fail_if(has_function_privilege('anon', 'public.request_case_analysis(text,uuid)', 'EXECUTE'), 'anon request');
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.ops_case_claim(text)', 'EXECUTE'), 'auth claim');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('anon', 'public.ops_case_claim(text)', 'EXECUTE'), 'anon claim');
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.ops_case_send(text,text,uuid,uuid,text,text)', 'EXECUTE'), 'auth send');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('anon', 'public.ops_case_send(text,text,uuid,uuid,text,text)', 'EXECUTE'), 'anon send');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('anon', 'public.ops_case_note(text,text,uuid,text)', 'EXECUTE'), 'anon note');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('anon', 'public.ops_case_finish(text,uuid,jsonb,text,text)', 'EXECUTE'), 'anon finish');
END $$;

-- RLS: el 96 (cuenta 1) ve la peticion; el 98 no. Sin escritura directa.
SET LOCAL ROLE authenticated;
SELECT pg_temp.act('96000000-0000-0000-0000-000000000096');
DO $$ BEGIN
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.case_analysis_request) < 1, '96 no ve su peticion');
END $$;
SELECT pg_temp.act('98000000-0000-0000-0000-000000000098');
DO $$ BEGIN
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.case_analysis_request) <> 0, '98 ve peticiones ajenas');
  BEGIN
    INSERT INTO public.case_analysis_request (account_id, incident_kind, incident_id)
      VALUES ('a0000000-0000-0000-0000-000000000002','reported','f3000000-0000-0000-0000-000000000009');
    RAISE EXCEPTION 'FAIL: INSERT directo permitido';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
ROLLBACK;
