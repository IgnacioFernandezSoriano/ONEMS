-- GPS fase 2, arreglos de la revision final (20261123190200):
--  I1: una visita nueva hereda tambien una posicion 'no_reference' (casa sin guardar) de los ultimos 30 min.
--  I2: gps_answer_place solo vale para la visita que hizo la pregunta y para la posicion por la que se pregunto.
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
     'e1000000-0000-0000-0000-000000000001', now());
  PERFORM public.gps_record_consent('e1000000-0000-0000-0000-000000000001', 'granted', 'es', 'v4', 't', NULL);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.end_visit() RETURNS void LANGUAGE sql AS $$
  UPDATE public.panelist_context SET created_at = created_at - interval '31 minutes'
   WHERE context_type = 'gps_visit' AND context_data->>'panelist_id' = 'e1000000-0000-0000-0000-000000000001';
$$;

-- 20261123190300: la pregunta se hace al terminar la declaracion; estas pruebas solo miran la RESPUESTA, asi que
-- dejan la pregunta 'hecha' en la visita vigente (el momento de preguntar se prueba en gps_place_after_decl).
CREATE OR REPLACE FUNCTION pg_temp.asked() RETURNS void LANGUAGE sql AS $$
  UPDATE public.panelist_context SET context_data = context_data || '{"place_asked": true, "place_pending": false}'::jsonb
   WHERE context_type = 'gps_visit' AND context_data->>'panelist_id' = 'e1000000-0000-0000-0000-000000000001'
     AND created_at > now() - interval '30 minutes';
$$;

-- ===== I1: herencia de una posicion no_reference =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.fx(false);
DO $$
DECLARE r jsonb; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  r := public.gps_save_location(P, '1001', -1.25000, 36.82000, NULL, now(), 'm1');
  PERFORM pg_temp.fail_if(r->>'status' <> 'no_reference', 'casa sin guardar: ' || r::text);
  PERFORM pg_temp.end_visit();                                   -- la posicion sigue teniendo < 30 min
  r := public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'sent', P);
  PERFORM pg_temp.fail_if(r->>'status' <> 'no_reference', 'visita nueva hereda la posicion no_reference: ' || r::text);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location'),
                          'sin incidencia falsa de sin posicion');
  r := public.gps_visit_start(P, '1001');
  PERFORM pg_temp.fail_if((r->>'need_location')::boolean IS NOT FALSE, 'no vuelve a pedir la ubicacion: ' || r::text);
END $$;
ROLLBACK;

-- ===== I2: la respuesta pertenece a la pregunta =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.fx(true);
DO $$
DECLARE r jsonb; loc1 uuid; loc2 uuid; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
  T constant jsonb := '{"question":"Q","answer":"A","reminder":"R"}';
BEGIN
  -- visita 1 con pregunta (posicion lejos)
  r := public.gps_save_location(P, '1001', -1.28360, 36.82000, NULL, now(), 'm1');
  loc1 := (r->>'location_id')::uuid;
  PERFORM pg_temp.fail_if(((r->>'ask_place')::boolean OR (r->>'place_pending')::boolean) IS NOT TRUE, 'visita 1 pregunta');
  -- visita 2 sin pregunta (posicion bien)
  PERFORM pg_temp.end_visit();
  UPDATE public.declaration_location SET received_at = received_at - interval '31 minutes' WHERE panelist_id = P;
  r := public.gps_save_location(P, '1001', -1.28090, 36.82000, NULL, now(), 'm2');
  loc2 := (r->>'location_id')::uuid;
  PERFORM pg_temp.fail_if(r->>'status' <> 'ok' OR ((r->>'ask_place')::boolean OR (r->>'place_pending')::boolean) IS NOT FALSE, 'visita 2 sin pregunta: ' || r::text);
  -- boton viejo de la visita 1 pulsado en la visita 2
  r := public.gps_answer_place(P, 'no', T, loc1);
  PERFORM pg_temp.fail_if(r->>'action' <> 'expired', 'boton viejo (con posicion): ' || r::text);
  r := public.gps_answer_place(P, 'yes', T);
  PERFORM pg_temp.fail_if(r->>'action' <> 'expired', 'visita sin pregunta (sin posicion en el boton): ' || r::text);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_incident WHERE panelist_id = P), 'sin incidencia');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_location_reference WHERE panelist_id = P), 'sin referencia');
END $$;
ROLLBACK;

BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.fx(true);
DO $$
DECLARE r jsonb; loc1 uuid; loc2 uuid; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
  T constant jsonb := '{"question":"Q","answer":"A","reminder":"R"}';
BEGIN
  r := public.gps_save_location(P, '1001', -1.28360, 36.82000, NULL, now(), 'm1');
  loc1 := (r->>'location_id')::uuid;
  -- otra posicion en la misma visita: el boton de la primera ya no vale
  r := public.gps_save_location(P, '1001', -1.28400, 36.82000, NULL, now(), 'm2');
  loc2 := (r->>'location_id')::uuid;
  PERFORM pg_temp.asked();
  r := public.gps_answer_place(P, 'yes', T, loc1);
  PERFORM pg_temp.fail_if(r->>'action' <> 'expired', 'posicion distinta: ' || r::text);
  r := public.gps_answer_place(P, 'yes', T, loc2);
  PERFORM pg_temp.fail_if(r->>'action' <> 'reference_saved', 'posicion correcta: ' || r::text);
END $$;
ROLLBACK;

-- v4: 'home_declined' solo tras un "Si" pendiente de v4
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.fx(false);
DO $$
DECLARE r jsonb; loc uuid; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  r := public.gps_save_location(P, '1001', -1.25000, 36.82000, NULL, now(), 'm1');
  loc := (r->>'location_id')::uuid;
  r := public.gps_answer_place(P, 'home_declined', '{}'::jsonb, loc);
  PERFORM pg_temp.fail_if(r->>'action' <> 'expired', 'declined sin v4 pendiente: ' || r::text);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_location_reference WHERE panelist_id = P), 'nada guardado');
END $$;
ROLLBACK;

-- ===== permiso retirado con la pregunta en pantalla: la respuesta no guarda nada (revision de seguridad 24/11) =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.fx(false);                                      -- casa, permiso v4 concedido
DO $$
DECLARE r jsonb; loc uuid; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
  T constant jsonb := '{"question":"Q","answer":"A","reminder":"R"}';
BEGIN
  r := public.gps_save_location(P, '1001', -1.25000, 36.82000, NULL, now(), 'm1');
  loc := (r->>'location_id')::uuid;
  PERFORM pg_temp.fail_if((r->>'ask_place')::boolean IS NOT TRUE, 'pregunta hecha');
  PERFORM public.gps_record_consent(P, 'denied', 'es', 'v4', 't', NULL);   -- retira el permiso
  r := public.gps_answer_place(P, 'yes', T, loc);
  PERFORM pg_temp.fail_if(r->>'action' <> 'no_consent', 'Si sin permiso vigente: ' || r::text);
  r := public.gps_answer_place(P, 'no', T, loc);
  PERFORM pg_temp.fail_if(r->>'action' <> 'no_consent', 'No sin permiso vigente: ' || r::text);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_location_reference WHERE panelist_id = P), 'sin referencia');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_incident WHERE panelist_id = P AND payload->>'reason' = 'wrong_place'),
                          'sin incidencia wrong_place');
END $$;
ROLLBACK;
