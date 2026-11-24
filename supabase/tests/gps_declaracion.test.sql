-- Posicion GPS al declarar envios y recepciones (spec 2026-11-17-gps-declaracion-design).
-- Cada escenario en su propia transaccion (BEGIN ... ROLLBACK) con la fixture comun.
-- Fixture: P1 (telegram 1001) en N1 / City1, con 2 centros con coordenadas; P4 (telegram 1004) en N4 / City2,
-- sin centros con coordenadas. Centro A en (-1.28000, 36.82000); 0.0009 grados de latitud ~ 100 m.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT FALSE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

-- Fixture GPS (se incluye dentro de cada BEGIN, despues de incident_city.sql)
CREATE OR REPLACE FUNCTION pg_temp.gps_fixture() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.panelists SET telegram_id = '1001' WHERE id = 'e1000000-0000-0000-0000-000000000001';
  UPDATE public.panelists SET telegram_id = '1004' WHERE id = 'e4000000-0000-0000-0000-000000000004';
  -- 20261123190000 (fase 2): estas pruebas comparan con la oficina = caso POBOX (sin POBOX no hay referencia sin casa)
  INSERT INTO public.account_config (account_id, pobox_enabled) VALUES ('a0000000-0000-0000-0000-000000000001', true)
  ON CONFLICT (account_id) DO UPDATE SET pobox_enabled = true;
  INSERT INTO public.postal_centers (id, account_id, code, name, city_id, latitude, longitude) VALUES
    ('dd000000-0000-0000-0000-00000000000a','a0000000-0000-0000-0000-000000000001','PCA','Centro A',
     'c1000000-0000-0000-0000-000000000001', -1.28000, 36.82000),
    ('dd000000-0000-0000-0000-00000000000b','a0000000-0000-0000-0000-000000000001','PCB','Centro B',
     'c1000000-0000-0000-0000-000000000001', -1.33000, 36.87000),
    -- City2: centro SIN coordenadas
    ('dd000000-0000-0000-0000-00000000000c','a0000000-0000-0000-0000-000000000001','PCC','Centro C',
     'c2000000-0000-0000-0000-000000000002', NULL, NULL);
  INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id,
      fecha_programada, status, tag_id, origin_panelist_id, destination_panelist_id, sent_at, received_at,
      transferred_to_one_db_at) VALUES
    -- D1: enviado por P1
    ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
     'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-10','sent','11111111',
     'e1000000-0000-0000-0000-000000000001', NULL, now(), NULL, NULL),
    -- D2: recibido por P1
    ('d2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
     'b4000000-0000-0000-0000-000000000004','b1000000-0000-0000-0000-000000000001','2027-03-10','received','22222222',
     NULL, 'e1000000-0000-0000-0000-000000000001', now(), now(), now()),
    -- D3: otro enviado por P1
    ('d3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
     'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-11','sent','33333333',
     'e1000000-0000-0000-0000-000000000001', NULL, now(), NULL, NULL);
END $$;

-- ===== 1) Permiso =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; n int; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  r := public.gps_visit_start(P, '1001');
  PERFORM pg_temp.fail_if((r->>'need_consent')::boolean IS NOT TRUE, 'sin filas: need_consent ' || r::text);
  PERFORM pg_temp.fail_if((r->>'need_location')::boolean IS NOT FALSE, 'sin filas: need_location ' || r::text);
  PERFORM pg_temp.fail_if(r->>'consent' IS NOT NULL, 'sin filas: consent ' || r::text);
  -- misma visita: el permiso ya se pregunto en esta visita, no se repite
  r := public.gps_visit_start(P, '1001');
  PERFORM pg_temp.fail_if((r->>'need_consent')::boolean IS NOT FALSE, 'misma visita: no repetir permiso ' || r::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_context
                            WHERE context_data->>'panelist_id' = P::text AND context_type = 'gps_visit') <> 1, 'una sola visita');

  r := public.gps_record_consent(P, 'granted', 'es', 'v1', 'Texto del permiso', '555');
  PERFORM pg_temp.fail_if(r->>'decision' <> 'granted' OR (r->>'need_location')::boolean IS NOT TRUE, 'record granted ' || r::text);
  -- 20261117151000 (ask once): el teclado se manda tras "Acepto"; el siguiente "Confirmar..." de la misma visita no lo repite
  r := public.gps_visit_start(P, '1001');
  PERFORM pg_temp.fail_if((r->>'need_consent')::boolean IS NOT FALSE OR (r->>'need_location')::boolean IS NOT FALSE
                          OR r->>'consent' <> 'granted', 'granted: ' || r::text);
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.panelist_location_consent
      WHERE panelist_id = P AND decision = 'granted' AND language = 'es' AND consent_text_version = 'v1'
        AND consent_text = 'Texto del permiso' AND telegram_message_id = '555' AND telegram_id = '1001'
        AND source = 'bot' AND account_id = 'a0000000-0000-0000-0000-000000000001'), 'fila de permiso incompleta');

  r := public.gps_record_consent(P, 'denied', 'es', 'v1', 'Texto del permiso', '556');
  r := public.gps_visit_start(P, '1001');
  PERFORM pg_temp.fail_if((r->>'need_location')::boolean IS NOT FALSE OR r->>'consent' <> 'denied', 'denied: ' || r::text);
  SELECT count(*) INTO n FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location';
  PERFORM pg_temp.fail_if(n <> 1, 'denied debe abrir 1 incidencia, hay ' || n);
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.panelist_incident WHERE panelist_id = P
      AND category = 'gps_location' AND status = 'open' AND payload = '{"reason":"consent_denied"}'::jsonb),
      'incidencia de permiso con payload/estado incorrecto');
  -- repetir "No acepto" sin cambio no duplica la incidencia
  r := public.gps_record_consent(P, 'denied', 'es', 'v1', 'Texto del permiso', '557');
  SELECT count(*) INTO n FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location';
  PERFORM pg_temp.fail_if(n <> 1, 'denied repetido no debe duplicar, hay ' || n);
  -- decision invalida
  BEGIN
    PERFORM public.gps_record_consent(P, 'maybe', 'es', 'v1', 'x', NULL);
    RAISE EXCEPTION 'FAIL: decision invalida aceptada';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
  END;
END $$;
ROLLBACK;

BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; n int; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM public.gps_record_consent(P, 'denied', 'en', 'v1', 't', NULL);
  PERFORM public.gps_record_consent(P, 'granted', 'en', 'v1', 't', NULL);
  PERFORM public.gps_record_consent(P, 'denied', 'en', 'v1', 't', NULL);
  SELECT count(*) INTO n FROM public.panelist_location_consent WHERE panelist_id = P;
  PERFORM pg_temp.fail_if(n <> 3, 'denied->granted->denied: 3 filas, hay ' || n);
  r := public.gps_visit_start(P, '1001');
  PERFORM pg_temp.fail_if(r->>'consent' <> 'denied', 'vigente debe ser denied: ' || r::text);
  SELECT count(*) INTO n FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location';
  PERFORM pg_temp.fail_if(n <> 2, 'una incidencia por cada paso a denied, hay ' || n);
END $$;
ROLLBACK;

-- ===== 2) Posiciones =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; n int; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
        P4 constant uuid := 'e4000000-0000-0000-0000-000000000004';
BEGIN
  PERFORM public.gps_record_consent(P, 'granted', 'es', 'v1', 't', NULL);
  PERFORM public.gps_visit_start(P, '1001');

  -- 100 m del centro A, precision 20
  r := public.gps_save_location(P, '1001', -1.27910, 36.82000, 20, now(), 'm1');
  PERFORM pg_temp.fail_if(r->>'action' <> 'saved' OR r->>'status' <> 'ok', '100 m: ' || r::text);
  PERFORM pg_temp.fail_if((r->>'distance_m')::numeric NOT BETWEEN 90 AND 110, '100 m: distancia ' || r::text);
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.declaration_location
      WHERE id = (r->>'location_id')::uuid AND status = 'ok' AND accuracy_m = 20
        AND nearest_postal_center_id = 'dd000000-0000-0000-0000-00000000000a'
        AND telegram_message_id = 'm1' AND account_id = 'a0000000-0000-0000-0000-000000000001'), 'fila 100 m');
  -- con posicion valida en la visita ya no hay que pedirla
  r := public.gps_visit_start(P, '1001');
  PERFORM pg_temp.fail_if((r->>'need_location')::boolean IS NOT FALSE, 'con posicion no pedir otra: ' || r::text);

  -- 900 m, precision 50 -> far (900 - 50 > 500)
  r := public.gps_save_location(P, '1001', -1.27190, 36.82000, 50, now(), 'm2');
  PERFORM pg_temp.fail_if(r->>'action' <> 'saved' OR r->>'status' <> 'far', '900 m: ' || r::text);

  -- 20261123180000 (solo distancia): la precision ya no cuenta ni provoca reintento; se guarda como dato
  r := public.gps_save_location(P, '1001', -1.27910, 36.82000, 350, now(), 'm3');
  PERFORM pg_temp.fail_if(r->>'action' <> 'saved' OR r->>'status' <> 'ok', '350 a 100 m: ' || r::text);
  r := public.gps_save_location(P, '1001', -1.27910, 36.82000, NULL, now(), 'm4b');
  PERFORM pg_temp.fail_if(r->>'action' <> 'saved' OR r->>'status' <> 'ok', 'sin precision a 100 m: ' || r::text);

  -- mensaje de hace 10 min -> stale, no se guarda
  SELECT count(*) INTO n FROM public.declaration_location WHERE panelist_id = P;
  r := public.gps_save_location(P, '1001', -1.27910, 36.82000, 20, now() - interval '10 minutes', 'm5');
  PERFORM pg_temp.fail_if(r->>'action' <> 'stale', 'stale: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.declaration_location WHERE panelist_id = P) <> n,
                          'stale no debe guardar fila');

  -- ciudad sin centros con coordenadas -> no_reference
  PERFORM public.gps_record_consent(P4, 'granted', 'es', 'v1', 't', NULL);
  r := public.gps_save_location(P4, '1004', -1.27910, 36.82000, 20, now(), 'm6');
  PERFORM pg_temp.fail_if(r->>'action' <> 'saved' OR r->>'status' <> 'no_reference' OR r->>'distance_m' IS NOT NULL,
                          'no_reference: ' || r::text);
END $$;
ROLLBACK;

-- ===== 3) Declaraciones sin posicion -> incidencia por visita, resuelta por enlace retroactivo =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; n int; inc uuid; pl jsonb; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM public.gps_record_consent(P, 'granted', 'es', 'v1', 't', NULL);
  PERFORM public.gps_visit_start(P, '1001');

  r := public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'sent', P);
  PERFORM pg_temp.fail_if(r->>'status' <> 'no_location' OR (r->>'warn')::boolean IS NOT TRUE, 'D1: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT sent_gps_status FROM public.allocation_plan_details
                            WHERE id = 'd1000000-0000-0000-0000-000000000001') <> 'no_location', 'D1 marca');
  SELECT count(*), max(id::text)::uuid INTO n, inc FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location';
  PERFORM pg_temp.fail_if(n <> 1, 'D1 debe abrir 1 incidencia, hay ' || n);
  PERFORM pg_temp.fail_if((SELECT status FROM public.panelist_incident WHERE id = inc) <> 'open', 'incidencia abierta');
  PERFORM pg_temp.fail_if((SELECT allocation_plan_detail_id FROM public.panelist_incident WHERE id = inc)
                          <> 'd1000000-0000-0000-0000-000000000001', 'detail de la incidencia = primera declaracion');

  r := public.gps_mark_declaration('d2000000-0000-0000-0000-000000000002', 'received', P);
  PERFORM pg_temp.fail_if(r->>'status' <> 'no_location' OR (r->>'warn')::boolean IS NOT FALSE, 'D2: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT received_gps_status FROM public.allocation_plan_details
                            WHERE id = 'd2000000-0000-0000-0000-000000000002') <> 'no_location', 'D2 marca');
  SELECT count(*) INTO n FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location';
  PERFORM pg_temp.fail_if(n <> 1, 'D2 misma visita: misma incidencia, hay ' || n);
  SELECT payload INTO pl FROM public.panelist_incident WHERE id = inc;
  PERFORM pg_temp.fail_if(jsonb_array_length(pl->'details') <> 2, 'payload con 2 detalles: ' || pl::text);
  PERFORM pg_temp.fail_if(pl->'visit_started_at' IS NULL OR NOT (pl ? 'distance_m'), 'forma del payload: ' || pl::text);
  PERFORM pg_temp.fail_if(NOT pl->'details' @> '[{"detail_id":"d2000000-0000-0000-0000-000000000002","kind":"received","status":"no_location","tag":"22222222"}]'::jsonb,
                          'detalle D2 en payload: ' || pl::text);

  -- llega una posicion valida dentro de la ventana -> ambas ok e incidencia auto_resolved
  r := public.gps_save_location(P, '1001', -1.27910, 36.82000, 20, now(), 'm1');
  PERFORM pg_temp.fail_if(r->>'status' <> 'ok', 'posicion: ' || r::text);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.allocation_plan_details
      WHERE (id = 'd1000000-0000-0000-0000-000000000001' AND (sent_gps_status IS DISTINCT FROM 'ok' OR sent_location_id IS DISTINCT FROM (r->>'location_id')::uuid))
         OR (id = 'd2000000-0000-0000-0000-000000000002' AND (received_gps_status IS DISTINCT FROM 'ok' OR received_location_id IS DISTINCT FROM (r->>'location_id')::uuid))),
      'enlace retroactivo');
  SELECT payload INTO pl FROM public.panelist_incident WHERE id = inc;
  PERFORM pg_temp.fail_if((SELECT status FROM public.panelist_incident WHERE id = inc) <> 'auto_resolved',
                          'incidencia debe quedar auto_resolved');
  PERFORM pg_temp.fail_if((SELECT resolved_at FROM public.panelist_incident WHERE id = inc) IS NULL, 'resolved_at');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM jsonb_array_elements(pl->'details') e WHERE e->>'status' <> 'ok')
                          OR pl->'distance_m' = 'null'::jsonb, 'payload tras resolver: ' || pl::text);

  -- tras la posicion valida, otra declaracion de la visita queda ok sin incidencia nueva
  r := public.gps_mark_declaration('d3000000-0000-0000-0000-000000000003', 'sent', P);
  PERFORM pg_temp.fail_if(r->>'status' <> 'ok' OR (r->>'warn')::boolean IS NOT FALSE, 'D3 con posicion: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location') <> 1,
                          'sin incidencia nueva con posicion ok');
END $$;
ROLLBACK;

-- ===== 4) Visita caducada -> incidencia distinta =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; n int; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM public.gps_record_consent(P, 'granted', 'es', 'v1', 't', NULL);
  PERFORM public.gps_visit_start(P, '1001');
  r := public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'sent', P);
  UPDATE public.panelist_context SET created_at = created_at - interval '31 minutes'
   WHERE context_data->>'panelist_id' = P::text AND context_type = 'gps_visit';
  r := public.gps_mark_declaration('d3000000-0000-0000-0000-000000000003', 'sent', P);
  PERFORM pg_temp.fail_if(r->>'status' <> 'no_location' OR (r->>'warn')::boolean IS NOT TRUE,
                          'visita nueva: vuelve a avisar ' || r::text);
  SELECT count(*) INTO n FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location';
  PERFORM pg_temp.fail_if(n <> 2, 'visita caducada: 2 incidencias distintas, hay ' || n);
  PERFORM pg_temp.fail_if((SELECT count(DISTINCT allocation_plan_detail_id) FROM public.panelist_incident
                            WHERE panelist_id = P AND category = 'gps_location') <> 2, 'cada incidencia con su detalle');
END $$;
ROLLBACK;

-- ===== 5) "Mi GPS no funciona" =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; pl jsonb; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM public.gps_record_consent(P, 'granted', 'es', 'v1', 't', NULL);
  PERFORM public.gps_visit_start(P, '1001');
  r := public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'sent', P);
  r := public.gps_set_unavailable(P, '1001');
  PERFORM pg_temp.fail_if(r->>'status' <> 'gps_unavailable', 'set_unavailable: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT sent_gps_status FROM public.allocation_plan_details
                            WHERE id = 'd1000000-0000-0000-0000-000000000001') <> 'gps_unavailable', 'D1 a gps_unavailable');
  r := public.gps_visit_start(P, '1001');
  PERFORM pg_temp.fail_if((r->>'need_location')::boolean IS NOT FALSE, 'con GPS no funciona no se vuelve a pedir: ' || r::text);
  r := public.gps_mark_declaration('d2000000-0000-0000-0000-000000000002', 'received', P);
  PERFORM pg_temp.fail_if(r->>'status' <> 'gps_unavailable' OR (r->>'warn')::boolean IS NOT FALSE, 'D2: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location') <> 1,
                          'una sola incidencia en la visita');
  SELECT payload INTO pl FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location';
  PERFORM pg_temp.fail_if(jsonb_array_length(pl->'details') <> 2
                          OR EXISTS (SELECT 1 FROM jsonb_array_elements(pl->'details') e WHERE e->>'status' <> 'gps_unavailable'),
                          'payload gps_unavailable: ' || pl::text);
  PERFORM pg_temp.fail_if((SELECT status FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location') <> 'open',
                          'sigue abierta para el gestor');
END $$;
ROLLBACK;

-- ===== 6) Sin permiso / sin responder / detalle inexistente =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  -- sin responder
  PERFORM public.gps_visit_start(P, '1001');
  r := public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'sent', P);
  PERFORM pg_temp.fail_if(r->>'status' <> 'no_answer' OR (r->>'warn')::boolean IS NOT FALSE, 'no_answer: ' || r::text);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_incident WHERE panelist_id = P), 'no_answer sin incidencia');
  -- sin permiso: solo la incidencia de la denegacion
  PERFORM public.gps_record_consent(P, 'denied', 'es', 'v1', 't', NULL);
  r := public.gps_mark_declaration('d3000000-0000-0000-0000-000000000003', 'sent', P);
  PERFORM pg_temp.fail_if(r->>'status' <> 'no_consent' OR (r->>'warn')::boolean IS NOT FALSE, 'no_consent: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_incident WHERE panelist_id = P) <> 1,
                          'no_consent no abre incidencia nueva');
  PERFORM pg_temp.fail_if((SELECT sent_gps_status FROM public.allocation_plan_details
                            WHERE id = 'd3000000-0000-0000-0000-000000000003') <> 'no_consent', 'D3 marca no_consent');
  -- detalle inexistente / tipo invalido / panelista inexistente: no lanza
  r := public.gps_mark_declaration('00000000-0000-0000-0000-0000000000ff', 'sent', P);
  PERFORM pg_temp.fail_if(r->'status' <> 'null'::jsonb OR (r->>'warn')::boolean IS NOT FALSE, 'inexistente: ' || r::text);
  r := public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'bogus', P);
  PERFORM pg_temp.fail_if(r->'status' <> 'null'::jsonb, 'kind invalido: ' || r::text);
  r := public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'sent', '00000000-0000-0000-0000-0000000000ee');
  PERFORM pg_temp.fail_if(r->'status' <> 'null'::jsonb, 'panelista inexistente: ' || r::text);
  -- las llamadas fallidas no han cambiado la marca previa de D1
  PERFORM pg_temp.fail_if((SELECT sent_gps_status FROM public.allocation_plan_details
                            WHERE id = 'd1000000-0000-0000-0000-000000000001') <> 'no_answer', 'D1 conserva no_answer');
  -- detalle existente de OTRA cuenta: no marca y no lanza
  INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id,
      fecha_programada, status, tag_id)
  VALUES ('d9000000-0000-0000-0000-000000000009','a0000000-0000-0000-0000-000000000002','cc000000-0000-0000-0000-000000000001',
          'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-10','sent','99999999');
  r := public.gps_mark_declaration('d9000000-0000-0000-0000-000000000009', 'sent', P);
  PERFORM pg_temp.fail_if(r->'status' <> 'null'::jsonb OR (r->>'warn')::boolean IS NOT FALSE, 'otra cuenta: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT sent_gps_status FROM public.allocation_plan_details
                            WHERE id = 'd9000000-0000-0000-0000-000000000009') IS NOT NULL, 'otra cuenta: sin marca');
END $$;
ROLLBACK;

-- ===== 6b) Fix round 1 =====
-- (1) gps_save_location sin permiso concedido: no guarda nada
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  r := public.gps_save_location(P, '1001', -1.27910, 36.82000, 20, now(), 'x1');   -- nunca respondio
  PERFORM pg_temp.fail_if(r->>'action' <> 'no_consent' OR r->>'location_id' IS NOT NULL, 'sin responder: ' || r::text);
  PERFORM public.gps_record_consent(P, 'denied', 'es', 'v1', 't', NULL);
  r := public.gps_save_location(P, '1001', -1.27910, 36.82000, 20, now(), 'x2');   -- denegado
  PERFORM pg_temp.fail_if(r->>'action' <> 'no_consent', 'denegado: ' || r::text);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.declaration_location WHERE panelist_id = P), 'no debe guardar coordenadas');
END $$;
ROLLBACK;

-- (2) una posicion solo refresca las incidencias cuyas declaraciones enlaza
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; inc_a uuid; inc_b uuid; pl_a jsonb; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM public.gps_record_consent(P, 'granted', 'es', 'v1', 't', NULL);
  -- visita A: D1 sin posicion, marcada hace 40 min (fuera de la ventana del enlace)
  PERFORM public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'sent', P);
  SELECT id INTO inc_a FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location';
  UPDATE public.panelist_context
     SET created_at = created_at - interval '40 minutes',
         context_data = jsonb_set(context_data, '{details,0,at}', to_jsonb(now() - interval '40 minutes'))
   WHERE context_data->>'panelist_id' = P::text AND context_type = 'gps_visit';
  SELECT payload INTO pl_a FROM public.panelist_incident WHERE id = inc_a;
  -- visita B: D3 sin posicion, luego llega posicion -> solo B se refresca
  PERFORM public.gps_mark_declaration('d3000000-0000-0000-0000-000000000003', 'sent', P);
  SELECT id INTO inc_b FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location' AND id <> inc_a;
  r := public.gps_save_location(P, '1001', -1.27910, 36.82000, 20, now(), 'm1');
  PERFORM pg_temp.fail_if((SELECT status FROM public.panelist_incident WHERE id = inc_b) <> 'auto_resolved', 'B auto_resolved');
  PERFORM pg_temp.fail_if((SELECT payload FROM public.panelist_incident WHERE id = inc_a) IS DISTINCT FROM pl_a,
                          'A no debe tocarse (payload cambiado)');
  PERFORM pg_temp.fail_if((SELECT status FROM public.panelist_incident WHERE id = inc_a) <> 'open', 'A sigue abierta');
  PERFORM pg_temp.fail_if((SELECT sent_gps_status FROM public.allocation_plan_details
                            WHERE id = 'd1000000-0000-0000-0000-000000000001') <> 'no_location', 'D1 fuera de ventana');
END $$;
ROLLBACK;

-- (3) herencia de posicion: solo ok/far y nunca mas de 30 min desde received_at
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM public.gps_record_consent(P, 'granted', 'es', 'v1', 't', NULL);
  r := public.gps_save_location(P, '1001', -1.27910, 36.82000, 20, now(), 'm1');
  -- la posicion se recibio hace 25 min y la visita ha caducado -> la nueva visita la hereda
  UPDATE public.declaration_location SET received_at = received_at - interval '25 minutes',
                                         captured_at = captured_at - interval '25 minutes'
   WHERE panelist_id = P;
  UPDATE public.panelist_context SET created_at = created_at - interval '31 minutes'
   WHERE context_data->>'panelist_id' = P::text AND context_type = 'gps_visit';
  r := public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'sent', P);
  PERFORM pg_temp.fail_if(r->>'status' <> 'ok', 'hereda posicion de hace 25 min: ' || r::text);
  -- pasan otros 6 min (31 desde la posicion): la visita sigue viva pero la posicion ya no cubre
  UPDATE public.declaration_location SET received_at = received_at - interval '6 minutes' WHERE panelist_id = P;
  r := public.gps_mark_declaration('d3000000-0000-0000-0000-000000000003', 'sent', P);
  PERFORM pg_temp.fail_if(r->>'status' <> 'no_location', 'posicion de hace 31 min no cubre: ' || r::text);
  r := public.gps_visit_start(P, '1001');
  PERFORM pg_temp.fail_if((r->>'need_location')::boolean IS NOT TRUE, 'hay que volver a pedirla: ' || r::text);
END $$;
ROLLBACK;

BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM public.gps_record_consent(P, 'granted', 'es', 'v1', 't', NULL);
  -- 20261123180000: 'low_accuracy' ya no se genera; fila antigua insertada a mano (anterior al 23/11)
  PERFORM public.gps_visit_start(P, '1001');
  INSERT INTO public.declaration_location (account_id, panelist_id, telegram_id, captured_at, latitude, longitude,
                                           accuracy_m, nearest_postal_center_id, distance_m, status)
  VALUES ('a0000000-0000-0000-0000-000000000001', P, '1001', now(), -1.27910, 36.82000, 350,
          'dd000000-0000-0000-0000-00000000000a', 100, 'low_accuracy');
  UPDATE public.panelist_context SET created_at = created_at - interval '31 minutes'
   WHERE context_data->>'panelist_id' = P::text AND context_type = 'gps_visit';
  r := public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'sent', P);
  PERFORM pg_temp.fail_if(r->>'status' <> 'no_location', 'low_accuracy no se hereda: ' || r::text);
END $$;
ROLLBACK;

-- (4) incidencia de la visita cerrada por el gestor -> la siguiente declaracion abre una NUEVA
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; inc_a uuid; n int; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM public.gps_record_consent(P, 'granted', 'es', 'v1', 't', NULL);
  PERFORM public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'sent', P);
  SELECT id INTO inc_a FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location';
  UPDATE public.panelist_incident SET status = 'resolved', resolved_at = now() WHERE id = inc_a;
  r := public.gps_mark_declaration('d2000000-0000-0000-0000-000000000002', 'received', P);
  SELECT count(*) INTO n FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location';
  PERFORM pg_temp.fail_if(n <> 2, 'debe abrirse una incidencia nueva, hay ' || n);
  PERFORM pg_temp.fail_if(jsonb_array_length((SELECT payload->'details' FROM public.panelist_incident WHERE id = inc_a)) <> 1,
                          'la cerrada no se amplia');
  PERFORM pg_temp.fail_if((SELECT status FROM public.panelist_incident WHERE id = inc_a) <> 'resolved', 'la cerrada sigue cerrada');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location'
      AND id <> inc_a AND status = 'open' AND allocation_plan_detail_id = 'd2000000-0000-0000-0000-000000000002'), 'nueva abierta con D2');
  -- dismissed igual
  UPDATE public.panelist_incident SET status = 'dismissed' WHERE panelist_id = P AND category = 'gps_location' AND id <> inc_a;
  PERFORM public.gps_mark_declaration('d3000000-0000-0000-0000-000000000003', 'sent', P);
  SELECT count(*) INTO n FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location';
  PERFORM pg_temp.fail_if(n <> 3, 'tras dismissed otra nueva, hay ' || n);
END $$;
ROLLBACK;

-- (5) panelista SIN telegram_id: visit_start (con telegram) y mark_declaration usan la misma visita
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; n int; P2 constant uuid := 'e2000000-0000-0000-0000-000000000002';
BEGIN
  INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id,
      fecha_programada, status, tag_id)
  VALUES ('d5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
          'b2000000-0000-0000-0000-000000000002','b4000000-0000-0000-0000-000000000004','2027-03-10','sent','55555555'),
         ('d6000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
          'b2000000-0000-0000-0000-000000000002','b4000000-0000-0000-0000-000000000004','2027-03-11','sent','66666666');
  PERFORM public.gps_record_consent(P2, 'granted', 'es', 'v1', 't', NULL);
  r := public.gps_visit_start(P2, '2002');
  r := public.gps_mark_declaration('d5000000-0000-0000-0000-000000000005', 'sent', P2);
  PERFORM pg_temp.fail_if((r->>'warn')::boolean IS NOT TRUE, 'primer aviso: ' || r::text);
  r := public.gps_mark_declaration('d6000000-0000-0000-0000-000000000006', 'sent', P2);
  PERFORM pg_temp.fail_if((r->>'warn')::boolean IS NOT FALSE, 'segundo sin aviso (misma visita): ' || r::text);
  SELECT count(*) INTO n FROM public.panelist_context WHERE context_type = 'gps_visit' AND context_data->>'panelist_id' = P2::text;
  PERFORM pg_temp.fail_if(n <> 1, 'una sola visita, hay ' || n);
  SELECT count(*) INTO n FROM public.panelist_incident WHERE panelist_id = P2 AND category = 'gps_location';
  PERFORM pg_temp.fail_if(n <> 1, 'una sola incidencia, hay ' || n);
  r := public.gps_save_location(P2, '2002', -1.27910, 36.82000, 20, now(), 'm1');
  PERFORM pg_temp.fail_if((SELECT status FROM public.panelist_incident WHERE panelist_id = P2 AND category = 'gps_location') <> 'auto_resolved',
                          'resuelta tras la posicion');
END $$;
ROLLBACK;

-- ===== 7) Borrado de coordenadas a 12 meses =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE n int; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO public.declaration_location (id, account_id, panelist_id, telegram_id, captured_at, received_at,
      latitude, longitude, accuracy_m, distance_m, status) VALUES
    ('dc000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001', P, '1001',
     now() - interval '13 months', now() - interval '13 months', -1.27910, 36.82000, 20, 123, 'ok'),
    ('dc000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001', P, '1001',
     now() - interval '11 months', now() - interval '11 months', -1.27910, 36.82000, 20, 99, 'ok');
  n := public.gps_purge_coordinates();
  PERFORM pg_temp.fail_if(n <> 1, 'purga: 1 fila, devuelve ' || n);
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.declaration_location
      WHERE id = 'dc000000-0000-0000-0000-000000000001' AND latitude IS NULL AND longitude IS NULL AND distance_m = 123 AND status = 'ok'),
      'fila vieja: coordenadas a NULL y distancia conservada');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.declaration_location
      WHERE id = 'dc000000-0000-0000-0000-000000000002' AND latitude IS NOT NULL), 'fila reciente intacta');
  PERFORM pg_temp.fail_if(public.gps_purge_coordinates() <> 0, 'purga idempotente');
END $$;
ROLLBACK;

-- ===== 8) Esquema, permisos, RLS y cron =====
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.gps_visit_start(uuid,text)',
    'public.gps_record_consent(uuid,text,text,text,text,text)',
    'public.gps_save_location(uuid,text,numeric,numeric,numeric,timestamptz,text)',
    'public.gps_set_unavailable(uuid,text)',
    'public.gps_mark_declaration(uuid,text,uuid)',
    'public.gps_purge_coordinates()'] LOOP
    PERFORM pg_temp.fail_if(has_function_privilege('authenticated', f, 'EXECUTE'), 'authenticated no debe ejecutar ' || f);
    PERFORM pg_temp.fail_if(has_function_privilege('anon', f, 'EXECUTE'), 'anon no debe ejecutar ' || f);
    PERFORM pg_temp.fail_if(NOT has_function_privilege('service_role', f, 'EXECUTE'), 'service_role debe ejecutar ' || f);
    PERFORM pg_temp.fail_if(NOT (SELECT prosecdef FROM pg_proc WHERE oid = f::regprocedure), 'SECURITY DEFINER ' || f);
  END LOOP;
  PERFORM pg_temp.fail_if(NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.panelist_location_consent'::regclass), 'RLS consent');
  PERFORM pg_temp.fail_if(NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.declaration_location'::regclass), 'RLS location');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'panelist_location_consent' AND cmd = 'SELECT'), 'policy consent');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'declaration_location' AND cmd = 'SELECT'), 'policy location');
  PERFORM pg_temp.fail_if(has_table_privilege('anon', 'public.declaration_location', 'SELECT'), 'anon no lee posiciones');
  PERFORM pg_temp.fail_if(has_table_privilege('authenticated', 'public.panelist_location_consent', 'DELETE'), 'el permiso no se borra');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM cron.job WHERE schedule = '0 3 * * *' AND command ILIKE '%gps_purge_coordinates%'),
                          'cron diario de purga (20261117170000)');
END $$;

BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
BEGIN
  BEGIN
    UPDATE public.allocation_plan_details SET sent_gps_status = 'bogus' WHERE id = 'd1000000-0000-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL: CHECK sent_gps_status';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  -- la categoria nueva es valida
  PERFORM public.insert_panelist_incident_auto('e1000000-0000-0000-0000-000000000001', 'gps_location', 'x', NULL, NULL, 'open');
END $$;
ROLLBACK;

SELECT 'gps_declaracion OK';
