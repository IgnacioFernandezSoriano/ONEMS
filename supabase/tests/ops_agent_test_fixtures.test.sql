-- Test: funciones de datos de prueba del agente de operaciones (ops_test_prepare/status/reset).
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

BEGIN;
-- otra cuenta con datos (para comprobar que no se toca)
\ir fixtures/incident_city.sql
INSERT INTO public.allocation_plan_details (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, generation_source)
VALUES ('a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
        'b1000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000002','2027-03-01','pending','plan');

-- DEMO2 minima con los ids reales
INSERT INTO public.accounts (id, name, slug, timezone) VALUES ('f4d823d2-93e6-4755-9a89-9da87e7fa86e','DEMO2','demo2','Europe/Madrid');
INSERT INTO public.regions (id, account_id, name, code) VALUES ('e0000000-0000-0000-0000-0000000000d2','f4d823d2-93e6-4755-9a89-9da87e7fa86e','RegD','RD');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c0000000-0000-0000-0000-0000000000d2','f4d823d2-93e6-4755-9a89-9da87e7fa86e','e0000000-0000-0000-0000-0000000000d2','CityD','CD');
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('a827d7a8-78db-4d25-8326-c38b8ff3c00a','f4d823d2-93e6-4755-9a89-9da87e7fa86e','c0000000-0000-0000-0000-0000000000d2','ND4'),
  ('2940e6ff-f666-4cb2-8780-ffb464bce544','f4d823d2-93e6-4755-9a89-9da87e7fa86e','c0000000-0000-0000-0000-0000000000d2','ND3');
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language, telegram_id) VALUES
  ('ed98f175-853d-4a6b-a2fd-0c6d5641fd99','f4d823d2-93e6-4755-9a89-9da87e7fa86e','PAN-DEM-004','Tester','t4@t.l','4','a827d7a8-78db-4d25-8326-c38b8ff3c00a','active','es','7014977036'),
  ('9ba5739f-defd-4f3e-8bcd-f29bbec20eed','f4d823d2-93e6-4755-9a89-9da87e7fa86e','PAN-DEM-003','Peer','t3@t.l','3','2940e6ff-f666-4cb2-8780-ffb464bce544','active','en','8349275418');
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-0000000000d2','f4d823d2-93e6-4755-9a89-9da87e7fa86e','CD','CarrierD');
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-0000000000d1','f4d823d2-93e6-4755-9a89-9da87e7fa86e','ca000000-0000-0000-0000-0000000000d2','A POBOX','POBOX',48),
  ('cb000000-0000-0000-0000-0000000000d2','f4d823d2-93e6-4755-9a89-9da87e7fa86e','ca000000-0000-0000-0000-0000000000d2','A STANDARD','A STANDARD',48);

INSERT INTO ops_test.secret(token_sha256) VALUES (encode(extensions.digest('t0ken-de-prueba','sha256'),'hex'));

CREATE TEMP TABLE _snap AS
  SELECT md5(string_agg(to_jsonb(d)::text, '|' ORDER BY d.id)) AS h
  FROM public.allocation_plan_details d WHERE d.account_id <> 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';

DO $$
DECLARE r jsonb; s jsonb; n int; v_err text; v_send uuid; v_recv uuid;
BEGIN
  -- token malo
  BEGIN
    PERFORM public.ops_test_prepare('malo');
    RAISE EXCEPTION 'FAIL: token malo aceptado';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_test: token no valido%', 'mensaje token malo: ' || v_err);
  END;

  r := public.ops_test_prepare('t0ken-de-prueba');
  PERFORM pg_temp.fail_if(r->>'send_tag' <> '73915086' OR r->>'receive_tag' <> '73915087', 'etiquetas: ' || r::text);
  PERFORM pg_temp.fail_if(r->>'send_date' <> '05/01/2026' OR r->>'receive_date' <> '05/01/2026', 'fechas: ' || r::text);
  v_send := (r->>'send_detail_id')::uuid; v_recv := (r->>'receive_detail_id')::uuid;

  SELECT count(*) INTO n FROM public.allocation_plan_details d JOIN public.allocation_plans p ON p.id = d.plan_id
   WHERE p.plan_name = 'OPS-AGENT pruebas automáticas (no tocar)';
  PERFORM pg_temp.fail_if(n <> 2, 'filas de prueba: ' || n);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.allocation_plans p JOIN public.products pr ON pr.id = p.product_id
                                   WHERE p.plan_name = 'OPS-AGENT pruebas automáticas (no tocar)' AND pr.code ILIKE '%pobox%'),
                          'el plan de prueba no debe usar un producto POBOX');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.allocation_plan_details WHERE id = v_send AND status = 'pending'
                                       AND origin_node_id = 'a827d7a8-78db-4d25-8326-c38b8ff3c00a'), 'fila de envio');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.allocation_plan_details WHERE id = v_recv AND status = 'sent'
                                       AND tag_id = '73915087' AND destination_node_id = 'a827d7a8-78db-4d25-8326-c38b8ff3c00a'
                                       AND origin_panelist_id IS NOT NULL AND destination_panelist_id IS NOT NULL), 'fila de recepcion');

  s := public.ops_test_status('t0ken-de-prueba');
  PERFORM pg_temp.fail_if((s->>'one_db')::boolean OR (s->>'incident')::boolean, 'status inicial: ' || s::text);
  PERFORM pg_temp.fail_if(jsonb_array_length(s->'unexpected') <> 0, 'sin efectos al principio: ' || s::text);

  -- simula lo que haria el bot
  UPDATE public.allocation_plan_details SET status = 'sent', tag_id = '73915086', idtag = '73915086', sent_at = now() WHERE id = v_send;
  UPDATE public.allocation_plan_details SET status = 'received', received_at = now() WHERE id = v_recv;
  INSERT INTO public.panelist_incident (account_id, panelist_id, category, status, description, created_via)
  VALUES ('f4d823d2-93e6-4755-9a89-9da87e7fa86e','ed98f175-853d-4a6b-a2fd-0c6d5641fd99','parcel_damaged','auto_resolved','x','telegram');
  INSERT INTO public.panelist_context (telegram_id, context_type, context_data) VALUES ('7014977036','pending_list','{}');

  s := public.ops_test_status('t0ken-de-prueba');
  PERFORM pg_temp.fail_if(s->>'send_status' <> 'sent' OR s->>'send_tag' <> '73915086', 'status envio: ' || s::text);
  PERFORM pg_temp.fail_if(s->>'receive_status' <> 'received' OR NOT (s->>'one_db')::boolean, 'status recepcion: ' || s::text);
  PERFORM pg_temp.fail_if(NOT (s->>'incident')::boolean, 'status incidencia: ' || s::text);
  PERFORM pg_temp.fail_if(jsonb_array_length(s->'unexpected') <> 0, 'lo esperado no es inesperado: ' || s::text);

  -- un aviso a un panelista SI es inesperado
  INSERT INTO public.panelist_notification (account_id, panelist_id, kind, payload)
  VALUES ('f4d823d2-93e6-4755-9a89-9da87e7fa86e','9ba5739f-defd-4f3e-8bcd-f29bbec20eed','manager_notice','{}');
  s := public.ops_test_status('t0ken-de-prueba');
  PERFORM pg_temp.fail_if(jsonb_array_length(s->'unexpected') <> 1, 'aviso inesperado no detectado: ' || s::text);

  r := public.ops_test_reset('t0ken-de-prueba');
  SELECT count(*) INTO n FROM public.allocation_plan_details d JOIN public.allocation_plans p ON p.id = d.plan_id
   WHERE p.plan_name = 'OPS-AGENT pruebas automáticas (no tocar)';
  PERFORM pg_temp.fail_if(n <> 0, 'tras reset quedan filas: ' || n);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.one_db WHERE tag_id IN ('73915086','73915087')), 'tras reset queda one_db');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_incident WHERE panelist_id = 'ed98f175-853d-4a6b-a2fd-0c6d5641fd99'), 'queda incidencia');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_context WHERE telegram_id = '7014977036'), 'queda contexto');
  -- el aviso inesperado NO se borra: queda para revisarlo
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.panelist_notification WHERE kind = 'manager_notice'), 'el aviso inesperado no debe borrarse');

  -- tope diario: ya hubo 1; 2 mas valen, la 4.a no
  PERFORM public.ops_test_prepare('t0ken-de-prueba');
  PERFORM public.ops_test_prepare('t0ken-de-prueba');
  SELECT count(*) INTO n FROM public.allocation_plan_details d JOIN public.allocation_plans p ON p.id = d.plan_id
   WHERE p.plan_name = 'OPS-AGENT pruebas automáticas (no tocar)';
  PERFORM pg_temp.fail_if(n <> 2, 'preparar dos veces seguidas debe dejar 2 filas: ' || n);
  BEGIN
    PERFORM public.ops_test_prepare('t0ken-de-prueba');
    RAISE EXCEPTION 'FAIL: 4.a preparacion aceptada';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_err = MESSAGE_TEXT;
    PERFORM pg_temp.fail_if(v_err NOT LIKE 'ops_test: tope diario%', 'mensaje tope: ' || v_err);
  END;
  PERFORM public.ops_test_reset('t0ken-de-prueba');
END $$;

DO $$ BEGIN
  PERFORM pg_temp.fail_if((SELECT md5(string_agg(to_jsonb(d)::text, '|' ORDER BY d.id)) FROM public.allocation_plan_details d
                            WHERE d.account_id <> 'f4d823d2-93e6-4755-9a89-9da87e7fa86e') IS DISTINCT FROM (SELECT h FROM _snap),
                          'se ha tocado otra cuenta');
END $$;
ROLLBACK;

-- permisos
DO $$
BEGIN
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.ops_test_prepare(text)', 'EXECUTE'), 'authenticated no debe poder preparar');
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.ops_test_reset(text)', 'EXECUTE'), 'authenticated no debe poder resetear');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('anon', 'public.ops_test_status(text)', 'EXECUTE'), 'anon debe poder llamar a status');
  PERFORM pg_temp.fail_if(has_schema_privilege('anon', 'ops_test', 'USAGE'), 'anon no debe ver el esquema ops_test');
  PERFORM pg_temp.fail_if(has_table_privilege('anon', 'ops_test.secret', 'SELECT'), 'anon no debe leer el secreto');
END $$;

SELECT 'ops_agent_test_fixtures OK';
