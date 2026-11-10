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
ROLLBACK;
