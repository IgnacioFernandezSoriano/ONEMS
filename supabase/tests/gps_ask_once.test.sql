-- GPS: permiso y ubicacion se piden UNA sola vez por visita (20261117151000_gps_ask_once.sql).
-- Misma fixture que gps_declaracion.test.sql (P1 telegram 1001; D1/D3 enviados por P1, D2 recibido por P1).
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT FALSE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.gps_fixture() RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  UPDATE public.panelists SET telegram_id = '1001' WHERE id = 'e1000000-0000-0000-0000-000000000001';
  INSERT INTO public.postal_centers (id, account_id, code, name, city_id, latitude, longitude) VALUES
    ('dd000000-0000-0000-0000-00000000000a','a0000000-0000-0000-0000-000000000001','PCA','Centro A',
     'c1000000-0000-0000-0000-000000000001', -1.28000, 36.82000);
  INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id,
      fecha_programada, status, tag_id, origin_panelist_id, destination_panelist_id, sent_at, received_at,
      transferred_to_one_db_at) VALUES
    ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
     'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-10','sent','11111111',
     'e1000000-0000-0000-0000-000000000001', NULL, now(), NULL, NULL),
    ('d2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
     'b4000000-0000-0000-0000-000000000004','b1000000-0000-0000-0000-000000000001','2027-03-10','received','22222222',
     NULL, 'e1000000-0000-0000-0000-000000000001', now(), now(), now()),
    ('d3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
     'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-11','sent','33333333',
     'e1000000-0000-0000-0000-000000000001', NULL, now(), NULL, NULL);
END $$;

-- caduca la visita vigente (31 min)
CREATE OR REPLACE FUNCTION pg_temp.expire_visit(p uuid) RETURNS void LANGUAGE sql AS $$
  UPDATE public.panelist_context SET created_at = created_at - interval '31 minutes'
   WHERE context_data->>'panelist_id' = p::text AND context_type = 'gps_visit';
$$;

-- ===== 1) La ubicacion se pide una sola vez por visita =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM public.gps_record_consent(P, 'granted', 'es', 'v1', 't', NULL);
  PERFORM pg_temp.expire_visit(P);  -- visita nueva tras haber dado el permiso en otra anterior
  r := public.gps_visit_start(P, '1001');
  PERFORM pg_temp.fail_if((r->>'need_location')::boolean IS NOT TRUE, '1a pulsacion: pedir ubicacion ' || r::text);
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.panelist_context WHERE context_type = 'gps_visit'
      AND context_data->>'panelist_id' = P::text AND (context_data->>'location_asked')::boolean), 'location_asked marcado');
  -- 2a y 3a pulsacion en la misma visita (Siguiente envio, Volver a declarar...): no se repite
  r := public.gps_visit_start(P, '1001');
  PERFORM pg_temp.fail_if((r->>'need_location')::boolean IS NOT FALSE, '2a pulsacion: no repetir ' || r::text);
  r := public.gps_visit_start(P, '1001');
  PERFORM pg_temp.fail_if((r->>'need_location')::boolean IS NOT FALSE, '3a pulsacion: no repetir ' || r::text);
  -- el recordatorio es el aviso posterior a la declaracion
  r := public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'sent', P);
  PERFORM pg_temp.fail_if(r->>'status' <> 'no_location' OR (r->>'warn')::boolean IS NOT TRUE, 'aviso tras declarar ' || r::text);
  PERFORM pg_temp.fail_if((r->>'ask_consent')::boolean IS NOT FALSE, 'con permiso no se pregunta ' || r::text);
  r := public.gps_visit_start(P, '1001');
  PERFORM pg_temp.fail_if((r->>'need_location')::boolean IS NOT FALSE, 'tras el aviso tampoco ' || r::text);
  -- visita nueva: se vuelve a pedir (una vez)
  PERFORM pg_temp.expire_visit(P);
  r := public.gps_visit_start(P, '1001');
  PERFORM pg_temp.fail_if((r->>'need_location')::boolean IS NOT TRUE, 'visita nueva: pedir otra vez ' || r::text);
  r := public.gps_visit_start(P, '1001');
  PERFORM pg_temp.fail_if((r->>'need_location')::boolean IS NOT FALSE, 'visita nueva: solo una vez ' || r::text);
  -- con posicion valida sigue sin pedirse
  PERFORM public.gps_save_location(P, '1001', -1.27910, 36.82000, 20, now(), 'm1');
  r := public.gps_visit_start(P, '1001');
  PERFORM pg_temp.fail_if((r->>'need_location')::boolean IS NOT FALSE, 'con posicion ' || r::text);
END $$;
ROLLBACK;

-- ===== 2) Sin permiso decidido y declara directamente (sin pulsar Confirmar...): ask_consent una vez por visita =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; n int; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  r := public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'sent', P);
  PERFORM pg_temp.fail_if(r->>'status' <> 'no_answer' OR (r->>'ask_consent')::boolean IS NOT TRUE
                          OR (r->>'warn')::boolean IS NOT FALSE, '1a declaracion: preguntar permiso ' || r::text);
  r := public.gps_mark_declaration('d3000000-0000-0000-0000-000000000003', 'sent', P);
  PERFORM pg_temp.fail_if(r->>'status' <> 'no_answer' OR (r->>'ask_consent')::boolean IS NOT FALSE, '2a declaracion: no repetir ' || r::text);
  r := public.gps_mark_declaration('d2000000-0000-0000-0000-000000000002', 'received', P);
  PERFORM pg_temp.fail_if((r->>'ask_consent')::boolean IS NOT FALSE, 'recepcion misma visita: no repetir ' || r::text);
  -- y pulsar "Confirmar..." en esa visita tampoco lo repite
  r := public.gps_visit_start(P, '1001');
  PERFORM pg_temp.fail_if((r->>'need_consent')::boolean IS NOT FALSE, 'visit_start: ya preguntado ' || r::text);
  -- no_answer no abre incidencia
  SELECT count(*) INTO n FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location';
  PERFORM pg_temp.fail_if(n <> 0, 'no_answer sin incidencia, hay ' || n);
  -- visita siguiente sin responder: se vuelve a preguntar (una vez)
  PERFORM pg_temp.expire_visit(P);
  r := public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'sent', P);
  PERFORM pg_temp.fail_if((r->>'ask_consent')::boolean IS NOT TRUE, 'visita nueva: preguntar otra vez ' || r::text);
  r := public.gps_mark_declaration('d3000000-0000-0000-0000-000000000003', 'sent', P);
  PERFORM pg_temp.fail_if((r->>'ask_consent')::boolean IS NOT FALSE, 'visita nueva: solo una vez ' || r::text);
END $$;
ROLLBACK;

-- ===== 3) Si la visita ya pregunto el permiso (pulso Confirmar...), la declaracion no lo repite =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  r := public.gps_visit_start(P, '1001');
  PERFORM pg_temp.fail_if((r->>'need_consent')::boolean IS NOT TRUE, 'visit_start pregunta ' || r::text);
  r := public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'sent', P);
  PERFORM pg_temp.fail_if(r->>'status' <> 'no_answer' OR (r->>'ask_consent')::boolean IS NOT FALSE, 'ya preguntado ' || r::text);
  -- permiso denegado: nunca ask_consent
  PERFORM public.gps_record_consent(P, 'denied', 'es', 'v1', 't', NULL);
  PERFORM pg_temp.expire_visit(P);
  r := public.gps_mark_declaration('d3000000-0000-0000-0000-000000000003', 'sent', P);
  PERFORM pg_temp.fail_if(r->>'status' <> 'no_consent' OR (r->>'ask_consent')::boolean IS NOT FALSE, 'denied ' || r::text);
  r := public.gps_visit_start(P, '1001');
  PERFORM pg_temp.fail_if((r->>'need_consent')::boolean IS NOT FALSE OR (r->>'need_location')::boolean IS NOT FALSE, 'denied visit ' || r::text);
  -- errores: nunca lanza y ask_consent = false
  r := public.gps_mark_declaration('00000000-0000-0000-0000-0000000000ff', 'sent', P);
  PERFORM pg_temp.fail_if(r->>'status' IS NOT NULL OR (r->>'ask_consent')::boolean IS NOT FALSE, 'error ' || r::text);
  r := public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'bogus', P);
  PERFORM pg_temp.fail_if((r->>'ask_consent')::boolean IS NOT FALSE, 'kind invalido ' || r::text);
END $$;
ROLLBACK;

-- ===== 3b) "Acepto" + teclado: cuenta como la peticion de ubicacion de la visita =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  r := public.gps_visit_start(P, '1001');                      -- pregunta el permiso
  PERFORM pg_temp.fail_if((r->>'need_consent')::boolean IS NOT TRUE, 'pregunta permiso ' || r::text);
  r := public.gps_record_consent(P, 'granted', 'es', 'v1', 't', '1');
  PERFORM pg_temp.fail_if((r->>'need_location')::boolean IS NOT TRUE, 'tras Acepto hay que pedir ubicacion ' || r::text);
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.panelist_context WHERE context_type = 'gps_visit'
      AND context_data->>'panelist_id' = P::text AND (context_data->>'location_asked')::boolean), 'record_consent marca location_asked');
  r := public.gps_visit_start(P, '1001');                      -- siguiente "Confirmar..." en la misma visita
  PERFORM pg_temp.fail_if((r->>'need_location')::boolean IS NOT FALSE, 'no repetir tras Acepto ' || r::text);
  -- un segundo "Acepto" en la misma visita: need_location sigue true (sin posicion) pero ya estaba marcado; visit_start no repite
  r := public.gps_record_consent(P, 'granted', 'es', 'v1', 't', '1');
  r := public.gps_visit_start(P, '1001');
  PERFORM pg_temp.fail_if((r->>'need_location')::boolean IS NOT FALSE, 'segundo Acepto ' || r::text);
  -- "No acepto" no marca location_asked en una visita nueva
  PERFORM pg_temp.expire_visit(P);
  r := public.gps_record_consent(P, 'denied', 'es', 'v1', 't', '2');
  PERFORM pg_temp.fail_if((r->>'need_location')::boolean IS NOT FALSE, 'denied sin ubicacion ' || r::text);
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.panelist_context WHERE context_type = 'gps_visit'
      AND context_data->>'panelist_id' = P::text AND created_at > now() - interval '30 minutes'
      AND (context_data->>'location_asked')::boolean), 'denied no marca location_asked');
  -- con posicion valida en la visita, "Acepto" no pide ni marca
  r := public.gps_record_consent(P, 'granted', 'es', 'v1', 't', '3');   -- marca la visita actual
  PERFORM pg_temp.expire_visit(P);
  PERFORM public.gps_save_location(P, '1001', -1.27910, 36.82000, 20, now(), 'm1');
  r := public.gps_record_consent(P, 'granted', 'es', 'v1', 't', '4');
  PERFORM pg_temp.fail_if((r->>'need_location')::boolean IS NOT FALSE, 'con posicion no pedir ' || r::text);
END $$;
ROLLBACK;

-- ===== 4) Permisos identicos =====
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.gps_visit_start(uuid,text)', 'public.gps_mark_declaration(uuid,text,uuid)',
                           'public.gps_record_consent(uuid,text,text,text,text,text)'] LOOP
    PERFORM pg_temp.fail_if(has_function_privilege('authenticated', f, 'EXECUTE'), 'authenticated no debe ejecutar ' || f);
    PERFORM pg_temp.fail_if(has_function_privilege('anon', f, 'EXECUTE'), 'anon no debe ejecutar ' || f);
    PERFORM pg_temp.fail_if(NOT has_function_privilege('service_role', f, 'EXECUTE'), 'service_role debe ejecutar ' || f);
    PERFORM pg_temp.fail_if(NOT (SELECT prosecdef FROM pg_proc WHERE oid = f::regprocedure), 'SECURITY DEFINER ' || f);
  END LOOP;
END $$;

SELECT 'gps_ask_once OK';
