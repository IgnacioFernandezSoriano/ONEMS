-- GPS fase 2, Task 2: respuesta a "¿estas en tu apartado / domicilio?" (gps_answer_place), recordatorio e incidencia
-- ya resuelta para la estadistica. Centro A (City1) en (-1.28000, 36.82000); 0.0009 grados lat ~ 100 m.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT FALSE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

-- P1 en City1 (centro A con coordenadas); D1 y D3 enviados por P1. p_pobox: City1 con POBOX o sin POBOX.
CREATE OR REPLACE FUNCTION pg_temp.fx(p_pobox boolean, p_version text) RETURNS void LANGUAGE plpgsql AS $$
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
  PERFORM public.gps_record_consent('e1000000-0000-0000-0000-000000000001', 'granted', 'es', p_version, 't', NULL);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.texts() RETURNS jsonb LANGUAGE sql AS $$
  SELECT '{"question":"Q","answer":"A","reminder":"R"}'::jsonb $$;

-- 20261123190300: la pregunta se hace al terminar la declaracion; estas pruebas solo miran la RESPUESTA, asi que
-- dejan la pregunta 'hecha' en la visita vigente (el momento de preguntar se prueba en gps_place_after_decl).
CREATE OR REPLACE FUNCTION pg_temp.asked() RETURNS void LANGUAGE sql AS $$
  UPDATE public.panelist_context SET context_data = context_data || '{"place_asked": true, "place_pending": false}'::jsonb
   WHERE context_type = 'gps_visit' AND context_data->>'panelist_id' = 'e1000000-0000-0000-0000-000000000001'
     AND created_at > now() - interval '30 minutes';
$$;

-- ===== si_guarda_pobox + si_needs_review + doble_pulsacion + expired =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.fx(true, 'v3');
DO $$
DECLARE r jsonb; c record; loc uuid; n int; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
  D1 constant uuid := 'd1000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM public.gps_visit_start(P, '1001');
  r := public.gps_save_location(P, '1001', -1.29800, 36.82000, NULL, now(), 'm1');   -- ~2 km de la oficina
  PERFORM pg_temp.asked();
  PERFORM pg_temp.fail_if(r->>'status' <> 'far' OR ((r->>'ask_place')::boolean OR (r->>'place_pending')::boolean) IS NOT TRUE, 'far + pregunta: ' || r::text);
  loc := (r->>'location_id')::uuid;
  PERFORM public.gps_mark_declaration(D1, 'sent', P);
  PERFORM pg_temp.fail_if((SELECT sent_gps_status FROM public.allocation_plan_details WHERE id = D1) <> 'far', 'D1 far');

  r := public.gps_answer_place(P, 'yes', pg_temp.texts());
  PERFORM pg_temp.fail_if(r->>'action' <> 'reference_saved' OR r->>'place_kind' <> 'pobox', 'si_guarda_pobox: ' || r::text);
  SELECT * INTO c FROM public.panelist_location_reference WHERE panelist_id = P AND active;
  PERFORM pg_temp.fail_if(c.kind <> 'pobox' OR c.source <> 'declaration' OR c.location_id <> loc
                          OR c.latitude <> -1.29800 OR c.longitude <> 36.82000
                          OR c.account_id <> 'a0000000-0000-0000-0000-000000000001', 'referencia: ' || row_to_json(c)::text);
  -- si_needs_review: a > 1000 m de la oficina
  PERFORM pg_temp.fail_if(NOT c.needs_review OR c.review_reason <> 'pobox_far_from_postal_center'
                          OR c.distance_to_postal_center_m < 1900, 'needs_review: ' || row_to_json(c)::text);
  PERFORM pg_temp.fail_if((SELECT status FROM public.declaration_location WHERE id = loc) <> 'ok', 'posicion -> ok');
  PERFORM pg_temp.fail_if((SELECT sent_gps_status || '/' || sent_self_reported_place FROM public.allocation_plan_details WHERE id = D1)
                          <> 'ok/pobox', 'D1 -> ok/pobox');
  SELECT count(*) INTO n FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location';
  PERFORM pg_temp.fail_if(n <> 0, 'Si no abre incidencia, hay ' || n);
  -- otra declaracion en la misma visita: ok y pobox
  PERFORM public.gps_mark_declaration('d3000000-0000-0000-0000-000000000003', 'sent', P);
  PERFORM pg_temp.fail_if((SELECT sent_gps_status || '/' || sent_self_reported_place FROM public.allocation_plan_details
                            WHERE id = 'd3000000-0000-0000-0000-000000000003') <> 'ok/pobox', 'D3 misma visita -> ok/pobox');

  -- doble_pulsacion (Review Focus 2)
  r := public.gps_answer_place(P, 'yes', pg_temp.texts());
  PERFORM pg_temp.fail_if(r->>'action' <> 'already_answered', 'doble: ' || r::text);
  r := public.gps_answer_place(P, 'no', pg_temp.texts());
  PERFORM pg_temp.fail_if(r->>'action' <> 'already_answered', 'doble (no): ' || r::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_location_reference WHERE panelist_id = P) <> 1, 'una sola referencia');
  -- expired
  UPDATE public.panelist_context SET created_at = created_at - interval '31 minutes'
   WHERE context_type = 'gps_visit' AND context_data->>'panelist_id' = P::text;
  r := public.gps_answer_place(P, 'no', pg_temp.texts());
  PERFORM pg_temp.fail_if(r->>'action' <> 'expired', 'expired: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_context WHERE context_type = 'gps_visit'
                            AND context_data->>'panelist_id' = P::text AND created_at > now() - interval '30 minutes') <> 0,
                          'expired no crea visita');
END $$;
ROLLBACK;

-- ===== si_reemplaza (Review Focus 4) =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.fx(true, 'v3');
DO $$
DECLARE r jsonb; old uuid; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO public.panelist_location_reference (account_id, panelist_id, kind, latitude, longitude, source)
  VALUES ('a0000000-0000-0000-0000-000000000001', P, 'pobox', -1.25000, 36.82000, 'declaration') RETURNING id INTO old;
  r := public.gps_save_location(P, '1001', -1.28090, 36.82000, NULL, now(), 'm1');   -- lejos de la ref, cerca de la oficina
  PERFORM pg_temp.asked();
  PERFORM pg_temp.fail_if(r->>'status' <> 'far' OR ((r->>'ask_place')::boolean OR (r->>'place_pending')::boolean) IS NOT TRUE, 'far contra ref: ' || r::text);
  r := public.gps_answer_place(P, 'yes', pg_temp.texts());
  PERFORM pg_temp.fail_if(r->>'action' <> 'reference_saved', 'reemplazo: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT active FROM public.panelist_location_reference WHERE id = old), 'antigua inactiva');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_location_reference WHERE panelist_id = P AND active) <> 1, '1 activa');
  PERFORM pg_temp.fail_if((SELECT needs_review FROM public.panelist_location_reference WHERE panelist_id = P AND active), 'cerca de la oficina: sin revision');
END $$;
ROLLBACK;

-- ===== no_recordatorio + no_luego_declara =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.fx(true, 'v3');
DO $$
DECLARE r jsonb; c record; loc uuid; inc uuid; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
  D1 constant uuid := 'd1000000-0000-0000-0000-000000000001'; D3 constant uuid := 'd3000000-0000-0000-0000-000000000003';
BEGIN
  PERFORM public.gps_visit_start(P, '1001');
  r := public.gps_save_location(P, '1001', -1.28360, 36.82000, NULL, now(), 'm1');   -- ~400 m
  PERFORM pg_temp.asked();
  loc := (r->>'location_id')::uuid;
  PERFORM public.gps_mark_declaration(D1, 'sent', P);
  r := public.gps_answer_place(P, 'no', pg_temp.texts());
  PERFORM pg_temp.fail_if(r->>'action' <> 'reminder' OR r->>'incident_id' IS NULL OR r->>'place_kind' <> 'pobox', 'no: ' || r::text);
  inc := (r->>'incident_id')::uuid;
  SELECT * INTO c FROM public.panelist_incident WHERE id = inc;
  PERFORM pg_temp.fail_if(c.category <> 'gps_location' OR c.status <> 'auto_resolved' OR c.resolved_at IS NULL
                          OR c.created_via <> 'telegram'
                          OR c.description <> '📍 Panelist confirmed declaring from a place that is not the correct one',
                          'incidencia: ' || row_to_json(c)::text);
  PERFORM pg_temp.fail_if(c.payload->>'reason' <> 'wrong_place' OR c.payload->>'place_kind' <> 'pobox'
                          OR c.payload->>'location_id' <> loc::text OR c.payload->'visit_started_at' IS NULL
                          OR (c.payload->>'ref_distance_m')::numeric NOT BETWEEN 390 AND 410
                          OR c.payload ? 'details'
                          OR NOT c.payload->'declarations' @> jsonb_build_array(jsonb_build_object('detail_id', D1, 'kind', 'sent')),
                          'payload: ' || c.payload::text);
  PERFORM pg_temp.fail_if((SELECT string_agg(direction || ':' || author || ':' || status || ':' || body, '|' ORDER BY created_at, body)
                             FROM public.incident_message WHERE incident_id = inc AND incident_kind = 'reported')
                          IS DISTINCT FROM 'outbound:bot:sent:Q|inbound:panelist:received:A|outbound:bot:sent:R',
                          'mensajes: ' || (SELECT string_agg(direction || ':' || author || ':' || body, '|' ORDER BY created_at, body)
                                             FROM public.incident_message WHERE incident_id = inc));
  PERFORM pg_temp.fail_if((SELECT sent_gps_status || '/' || sent_self_reported_place FROM public.allocation_plan_details WHERE id = D1)
                          <> 'far/other', 'D1 far/other');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_location_reference WHERE panelist_id = P), 'No no guarda referencia');
  -- no_luego_declara
  PERFORM public.gps_mark_declaration(D3, 'sent', P);
  SELECT * INTO c FROM public.panelist_incident WHERE id = inc;
  PERFORM pg_temp.fail_if(c.status <> 'auto_resolved' OR jsonb_array_length(c.payload->'declarations') <> 2,
                          'D3 se anade: ' || c.payload::text);
  PERFORM pg_temp.fail_if((SELECT sent_self_reported_place FROM public.allocation_plan_details WHERE id = D3) <> 'other', 'D3 other');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location') <> 1,
                          'una sola incidencia');
END $$;
ROLLBACK;

-- ===== si_sin_posicion (Review Focus 3) =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.fx(true, 'v3');
DO $$
DECLARE r jsonb; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM public.gps_visit_start(P, '1001');
  PERFORM public.gps_set_unavailable(P, '1001');
  r := public.gps_answer_place(P, 'yes', pg_temp.texts());
  -- 20261123190200: sin posicion no hubo pregunta en la visita -> 'expired' (antes 'no_location'); nada se guarda
  PERFORM pg_temp.fail_if(r->>'action' NOT IN ('expired','no_location'), 'sin posicion: ' || r::text);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_location_reference WHERE panelist_id = P), 'nada guardado');
  -- error controlado: respuesta invalida -> error, sin lanzar
  r := public.gps_answer_place(P, 'maybe', pg_temp.texts());
  PERFORM pg_temp.fail_if(r->>'action' <> 'error', 'respuesta invalida: ' || r::text);
  r := public.gps_answer_place(gen_random_uuid(), 'yes', pg_temp.texts());
  PERFORM pg_temp.fail_if(r->>'action' <> 'error', 'panelista inexistente: ' || r::text);
END $$;
ROLLBACK;

-- ===== home_necesita_v4 + home_far_from_city =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.fx(false, 'v3');
DO $$
DECLARE r jsonb; c record; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM pg_temp.fail_if(public.gps_consent_version(P) <> 'v3', 'version v3');
  r := public.gps_save_location(P, '1001', -1.25000, 36.82000, NULL, now(), 'm1');   -- ~3,3 km del centro de City1
  PERFORM pg_temp.asked();
  PERFORM pg_temp.fail_if(r->>'status' <> 'no_reference' OR ((r->>'ask_place')::boolean OR (r->>'place_pending')::boolean) IS NOT TRUE, 'home sin ref: ' || r::text);
  r := public.gps_answer_place(P, 'yes', pg_temp.texts());
  PERFORM pg_temp.fail_if(r->>'action' <> 'need_v4' OR r->>'place_kind' <> 'home', 'need_v4: ' || r::text);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_location_reference WHERE panelist_id = P), 'sin v4 no guarda');
  PERFORM public.gps_record_consent(P, 'granted', 'es', 'v4', 'texto v4', NULL);
  PERFORM pg_temp.fail_if(public.gps_consent_version(P) <> 'v4', 'version v4');
  r := public.gps_answer_place(P, 'yes', pg_temp.texts());
  PERFORM pg_temp.fail_if(r->>'action' <> 'reference_saved' OR r->>'place_kind' <> 'home', 'tras v4: ' || r::text);
  SELECT * INTO c FROM public.panelist_location_reference WHERE panelist_id = P AND active;
  PERFORM pg_temp.fail_if(c.kind <> 'home' OR c.needs_review, 'casa a 3,3 km: sin revision ' || row_to_json(c)::text);
  r := public.gps_answer_place(P, 'yes', pg_temp.texts());
  PERFORM pg_temp.fail_if(r->>'action' <> 'already_answered', 'tras guardar: ' || r::text);
END $$;
ROLLBACK;

BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.fx(false, 'v4');
DO $$
DECLARE r jsonb; c record; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  r := public.gps_save_location(P, '1001', -1.22000, 36.82000, NULL, now(), 'm1');   -- ~6,7 km del centro de City1
  PERFORM pg_temp.asked();
  r := public.gps_answer_place(P, 'yes', pg_temp.texts());
  PERFORM pg_temp.fail_if(r->>'action' <> 'reference_saved', 'v4 directo: ' || r::text);
  SELECT * INTO c FROM public.panelist_location_reference WHERE panelist_id = P AND active;
  PERFORM pg_temp.fail_if(NOT c.needs_review OR c.review_reason <> 'home_far_from_city', 'home_far_from_city: ' || row_to_json(c)::text);
END $$;
ROLLBACK;

-- ===== home_declinada =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.fx(false, 'v3');
DO $$
DECLARE r jsonb; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  r := public.gps_save_location(P, '1001', -1.25000, 36.82000, NULL, now(), 'm1');
  PERFORM pg_temp.asked();
  r := public.gps_answer_place(P, 'yes', pg_temp.texts());
  PERFORM pg_temp.fail_if(r->>'action' <> 'need_v4', 'need_v4: ' || r::text);
  r := public.gps_answer_place(P, 'home_declined', pg_temp.texts());
  PERFORM pg_temp.fail_if(r->>'action' <> 'declined_saved', 'declined: ' || r::text);
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.panelist_location_reference WHERE panelist_id = P
      AND kind = 'home' AND source = 'declined' AND NOT active AND latitude IS NULL), 'fila declined');
  PERFORM pg_temp.fail_if(public.gps_current_consent(P) <> 'granted', 'permiso sigue granted');
  UPDATE public.panelist_context SET created_at = created_at - interval '31 minutes'
   WHERE context_type = 'gps_visit' AND context_data->>'panelist_id' = P::text;
  UPDATE public.declaration_location SET received_at = received_at - interval '31 minutes' WHERE panelist_id = P;
  r := public.gps_save_location(P, '1001', -1.25000, 36.82000, NULL, now(), 'm2');
  PERFORM pg_temp.asked();
  PERFORM pg_temp.fail_if(((r->>'ask_place')::boolean OR (r->>'place_pending')::boolean) IS NOT FALSE, 'no se vuelve a preguntar: ' || r::text);
END $$;
ROLLBACK;

-- ===== borrar_mis_datos =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.fx(true, 'v3');
DO $$
DECLARE r jsonb; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  r := public.gps_save_location(P, '1001', -1.29800, 36.82000, NULL, now(), 'm1');
  PERFORM pg_temp.asked();
  r := public.gps_answer_place(P, 'yes', pg_temp.texts());
  r := public.gps_save_location(P, '1001', -1.29800, 36.82000, NULL, now(), 'm2');
  PERFORM pg_temp.asked();
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.declaration_location WHERE panelist_id = P AND ref_distance_m IS NOT NULL) = 0,
                          'hay ref_distance_m antes');
  r := public.gps_erase_panelist_locations(P, 'bot');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_location_reference WHERE panelist_id = P), 'referencias borradas');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.declaration_location WHERE panelist_id = P
      AND (ref_distance_m IS NOT NULL OR latitude IS NOT NULL)), 'ref_distance_m borrada');
END $$;
ROLLBACK;
