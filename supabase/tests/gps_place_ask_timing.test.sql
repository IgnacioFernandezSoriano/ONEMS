-- GPS fase 2 (24/11, Ignacio, tras probar en real): la pregunta de lugar se hace AL PRINCIPIO, al guardar la ubicacion
-- y antes de la lista de envios (el bot espera la respuesta para ensenar la lista). gps_mark_declaration ya no pregunta.
-- Una vez por visita y nunca dos veces por la misma posicion (una visita que hereda la posicion no vuelve a preguntar).
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT FALSE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.fx(p_pobox boolean) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.panelists SET telegram_id = '1001' WHERE id = 'e1000000-0000-0000-0000-000000000001';
  UPDATE public.cities SET pobox_enabled = p_pobox WHERE id = 'c1000000-0000-0000-0000-000000000001';
  INSERT INTO public.postal_centers (id, account_id, code, name, city_id, latitude, longitude) VALUES
    ('dd000000-0000-0000-0000-00000000000a','a0000000-0000-0000-0000-000000000001','PCA','Centro A',
     'c1000000-0000-0000-0000-000000000001', -1.28000, 36.82000);
  INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id,
      fecha_programada, status, tag_id, origin_panelist_id, sent_at) VALUES
    ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
     'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-10','sent','11111111',
     'e1000000-0000-0000-0000-000000000001', now()),
    ('d3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
     'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-11','sent','33333333',
     'e1000000-0000-0000-0000-000000000001', now());
  PERFORM public.gps_record_consent('e1000000-0000-0000-0000-000000000001', 'granted', 'es', 'v4', 't', NULL);
END $$;

-- ===== se pregunta al guardar la ubicacion; declarar despues no vuelve a preguntar =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.fx(true);
DO $$
DECLARE r jsonb; loc uuid; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  r := public.gps_save_location(P, '1001', -1.28360, 36.82000, NULL, now(), 'm1');   -- lejos
  loc := (r->>'location_id')::uuid;
  PERFORM pg_temp.fail_if(r->>'status' <> 'far' OR (r->>'ask_place')::boolean IS NOT TRUE
                          OR COALESCE((r->>'place_pending')::boolean, false), 'al guardar se pregunta ya: ' || r::text);
  r := public.gps_save_location(P, '1001', -1.28360, 36.82000, NULL, now(), 'm2');
  PERFORM pg_temp.fail_if((r->>'ask_place')::boolean IS NOT FALSE, 'una vez por visita: ' || r::text);
  loc := (r->>'location_id')::uuid;                                       -- posicion vigente de la visita
  r := public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'sent', P);
  PERFORM pg_temp.fail_if(r->>'status' <> 'far' OR COALESCE((r->>'ask_place')::boolean, false), 'declarar no pregunta: ' || r::text);
  r := public.gps_answer_place(P, 'no', '{"question":"Q","answer":"A","reminder":"R"}'::jsonb, loc);
  PERFORM pg_temp.fail_if(r->>'action' <> 'reminder', 'la respuesta vale: ' || r::text);
END $$;
ROLLBACK;

-- ===== posicion buena: no se pregunta =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.fx(true);
DO $$
DECLARE r jsonb; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  r := public.gps_save_location(P, '1001', -1.28090, 36.82000, NULL, now(), 'm1');
  PERFORM pg_temp.fail_if(r->>'status' <> 'ok' OR (r->>'ask_place')::boolean IS NOT FALSE, 'bien: sin pregunta: ' || r::text);
END $$;
ROLLBACK;

-- ===== visita que hereda una posicion ya preguntada: no se repite =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.fx(true);
DO $$
DECLARE r jsonb; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  r := public.gps_save_location(P, '1001', -1.28360, 36.82000, NULL, now(), 'm1');
  PERFORM pg_temp.fail_if((r->>'ask_place')::boolean IS NOT TRUE, 'visita 1 pregunta');
  UPDATE public.panelist_context SET created_at = created_at - interval '31 minutes'
   WHERE context_type = 'gps_visit' AND context_data->>'panelist_id' = P::text;
  r := public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'sent', P);   -- visita 2 hereda la posicion
  PERFORM pg_temp.fail_if(r->>'status' <> 'far' OR COALESCE((r->>'ask_place')::boolean, false), 'no repite: ' || r::text);
END $$;
ROLLBACK;

-- ===== casa sin guardar: se pregunta al guardar; sin permiso nunca =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.fx(false);
DO $$
DECLARE r jsonb; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  r := public.gps_save_location(P, '1001', -1.25000, 36.82000, NULL, now(), 'm1');
  PERFORM pg_temp.fail_if(r->>'status' <> 'no_reference' OR (r->>'ask_place')::boolean IS NOT TRUE OR r->>'place_kind' <> 'home',
                          'casa: pregunta al guardar: ' || r::text);
  PERFORM public.gps_record_consent(P, 'denied', 'es', 'v4', 't', NULL);
  r := public.gps_save_location(P, '1001', -1.25000, 36.82000, NULL, now(), 'm2');
  PERFORM pg_temp.fail_if(r->>'action' <> 'no_consent' OR COALESCE((r->>'ask_place')::boolean, false), 'sin permiso: ' || r::text);
END $$;
ROLLBACK;
