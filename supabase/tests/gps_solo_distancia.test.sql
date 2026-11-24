-- GPS fase 1 (plan 2026-11-20-gps-fase1-solo-distancia): la posicion se juzga solo por la distancia (Telegram no
-- envia la precision), 'far' no abre incidencia y el recalculo corrige lo guardado desde el 17/11.
-- Misma fixture que gps_declaracion.test.sql. Centro A en (-1.28000, 36.82000); 0.0009 grados lat ~ 100 m.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT FALSE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

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
    ('dd000000-0000-0000-0000-00000000000c','a0000000-0000-0000-0000-000000000001','PCC','Centro C',
     'c2000000-0000-0000-0000-000000000002', NULL, NULL);
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

-- ===== Task 1: clasificacion por distancia =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; n int; c record; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
        P4 constant uuid := 'e4000000-0000-0000-0000-000000000004';
BEGIN
  PERFORM public.gps_record_consent(P, 'granted', 'es', 'v1', 't', NULL);
  PERFORM public.gps_record_consent(P4, 'granted', 'es', 'v1', 't', NULL);
  PERFORM pg_temp.fail_if(public.gps_setting('ok_radius_m') IS DISTINCT FROM 300, 'radio por defecto 300');

  -- sin_precision_cerca (~200 m, sin precision) -> ok y guardada
  r := public.gps_save_location(P, '1001', -1.28180, 36.82000, NULL, now(), 'm1');
  PERFORM pg_temp.fail_if(r->>'action' <> 'saved' OR r->>'status' <> 'ok', 'sin_precision_cerca: ' || r::text);
  SELECT * INTO c FROM public.declaration_location WHERE id = (r->>'location_id')::uuid;
  PERFORM pg_temp.fail_if(c.accuracy_m IS NOT NULL OR c.status <> 'ok', 'sin_precision_cerca fila');

  -- sin_precision_lejos (~400 m) -> far
  r := public.gps_save_location(P, '1001', -1.28360, 36.82000, NULL, now(), 'm2');
  PERFORM pg_temp.fail_if(r->>'action' <> 'saved' OR r->>'status' <> 'far', 'sin_precision_lejos: ' || r::text);

  -- precision_mala_no_cambia (~200 m, precision 900) -> ok, se guarda la precision, nunca reintento
  r := public.gps_save_location(P, '1001', -1.28180, 36.82000, 900, now(), 'm3');
  PERFORM pg_temp.fail_if(r->>'action' <> 'saved' OR r->>'status' <> 'ok', 'precision_mala: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT accuracy_m FROM public.declaration_location WHERE id = (r->>'location_id')::uuid) <> 900,
                          'precision_mala: accuracy_m guardada');
  r := public.gps_save_location(P, '1001', -1.28180, 36.82000, 5000, now(), 'm3b');
  PERFORM pg_temp.fail_if(r->>'action' = 'low_accuracy_retry', 'nunca low_accuracy_retry: ' || r::text);

  -- sin_referencia: P4 en City2 (centro sin coordenadas)
  r := public.gps_save_location(P4, '1004', -1.28180, 36.82000, NULL, now(), 'm4');
  PERFORM pg_temp.fail_if(r->>'action' <> 'saved' OR r->>'status' <> 'no_reference', 'sin_referencia: ' || r::text);

  -- umbral_configurable: radio 100 -> el punto de ~200 m es far
  UPDATE public.gps_settings SET value = 100 WHERE key = 'ok_radius_m';
  r := public.gps_save_location(P, '1001', -1.28180, 36.82000, NULL, now(), 'm5');
  PERFORM pg_temp.fail_if(r->>'status' <> 'far', 'umbral_configurable: ' || r::text);

  -- gps_classify directa
  PERFORM pg_temp.fail_if(public.gps_classify(NULL, 10) <> 'no_reference', 'classify sin centro');
  PERFORM pg_temp.fail_if(public.gps_classify('dd000000-0000-0000-0000-00000000000a', 100) <> 'ok', 'classify 100 = ok (<=)');
  PERFORM pg_temp.fail_if(public.gps_classify('dd000000-0000-0000-0000-00000000000a', 101) <> 'far', 'classify 101 = far');
END $$;
ROLLBACK;

-- far_no_abre_incidencia
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; n int; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM public.gps_record_consent(P, 'granted', 'es', 'v1', 't', NULL);
  PERFORM public.gps_visit_start(P, '1001');
  r := public.gps_save_location(P, '1001', -1.28360, 36.82000, NULL, now(), 'm1');
  PERFORM pg_temp.fail_if(r->>'status' <> 'far', 'far: ' || r::text);
  r := public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'sent', P);
  PERFORM pg_temp.fail_if(r->>'status' <> 'far', 'marca far: ' || r::text);
  SELECT count(*) INTO n FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location';
  PERFORM pg_temp.fail_if(n <> 0, 'far no abre incidencia, hay ' || n);
END $$;
ROLLBACK;

-- sin_posicion_si_abre + refresh_cierra_sin_problemas (llega posicion far por enlace retroactivo)
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; n int; inc uuid; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM public.gps_record_consent(P, 'granted', 'es', 'v1', 't', NULL);
  PERFORM public.gps_visit_start(P, '1001');
  r := public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'sent', P);
  PERFORM pg_temp.fail_if(r->>'status' <> 'no_location', 'sin posicion: ' || r::text);
  SELECT count(*), max(id::text)::uuid INTO n, inc FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location';
  PERFORM pg_temp.fail_if(n <> 1 OR (SELECT status FROM public.panelist_incident WHERE id = inc) <> 'open',
                          'sin posicion abre 1 incidencia open, hay ' || n);
  r := public.gps_save_location(P, '1001', -1.28360, 36.82000, NULL, now(), 'm1');
  PERFORM pg_temp.fail_if(r->>'status' <> 'far', 'retro far: ' || r::text);
  PERFORM pg_temp.fail_if((SELECT sent_gps_status FROM public.allocation_plan_details
                            WHERE id = 'd1000000-0000-0000-0000-000000000001') <> 'far', 'D1 enlazada far');
  PERFORM pg_temp.fail_if((SELECT status FROM public.panelist_incident WHERE id = inc) <> 'auto_resolved',
                          'far retroactiva cierra la incidencia');
  PERFORM pg_temp.fail_if((SELECT resolved_at FROM public.panelist_incident WHERE id = inc) IS NULL, 'resolved_at');
END $$;
ROLLBACK;

-- gps_unavailable sigue abriendo y no se cierra
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; inc uuid; P constant uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  PERFORM public.gps_record_consent(P, 'granted', 'es', 'v1', 't', NULL);
  PERFORM public.gps_visit_start(P, '1001');
  PERFORM public.gps_mark_declaration('d1000000-0000-0000-0000-000000000001', 'sent', P);
  PERFORM public.gps_set_unavailable(P, '1001');
  SELECT id INTO inc FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location';
  PERFORM pg_temp.fail_if((SELECT status FROM public.panelist_incident WHERE id = inc) <> 'open', 'gps_unavailable sigue open');
END $$;
ROLLBACK;

-- ===== Task 2: recalculo de lo guardado con la regla antigua =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT pg_temp.gps_fixture();
DO $$
DECLARE r jsonb; r2 jsonb; c record; inc_solo uuid; inc_mixta uuid; inc_consent uuid; inc_closed uuid;
  A constant uuid := 'a0000000-0000-0000-0000-000000000001';
  P constant uuid := 'e1000000-0000-0000-0000-000000000001';
  CA constant uuid := 'dd000000-0000-0000-0000-00000000000a';
  D1 constant uuid := 'd1000000-0000-0000-0000-000000000001';
  D2 constant uuid := 'd2000000-0000-0000-0000-000000000002';
  D3 constant uuid := 'd3000000-0000-0000-0000-000000000003';
  L_cerca uuid := gen_random_uuid(); L_lejos uuid := gen_random_uuid(); L_sinref uuid := gen_random_uuid();
  L_okviejo uuid := gen_random_uuid();
  NOTE constant text := 'Regla corregida el 20/11: Telegram no envía la precisión; la posición se juzga solo por la distancia.';
BEGIN
  -- recalc_location: filas "antiguas"
  INSERT INTO public.declaration_location (id, account_id, panelist_id, telegram_id, captured_at, latitude, longitude,
                                           accuracy_m, nearest_postal_center_id, distance_m, status) VALUES
    (L_cerca,  A, P, '1001', now(), -1.2813, 36.82, NULL, CA,   150,  'low_accuracy'),
    (L_lejos,  A, P, '1001', now(), -1.2980, 36.82, NULL, CA,   2000, 'low_accuracy'),
    (L_sinref, A, P, '1001', now(), -1.2813, 36.82, NULL, NULL, NULL, 'low_accuracy'),
    (L_okviejo,A, P, '1001', now(), -1.2840, 36.82, 50,   CA,   450,  'ok');  -- ok antiguo (450-50 <= 500) -> far
  -- recalc_marcas
  UPDATE public.allocation_plan_details SET sent_location_id = L_cerca, sent_gps_status = 'low_accuracy' WHERE id = D1;
  UPDATE public.allocation_plan_details SET received_location_id = NULL, received_gps_status = 'no_location' WHERE id = D2;
  UPDATE public.allocation_plan_details SET sent_location_id = L_lejos, sent_gps_status = 'low_accuracy' WHERE id = D3;
  -- incidencias
  INSERT INTO public.panelist_incident (id, account_id, panelist_id, category, status, description, payload, created_via)
  VALUES (gen_random_uuid(), A, P, 'gps_location', 'open', 'x',
          jsonb_build_object('details', jsonb_build_array(
            jsonb_build_object('detail_id', D1, 'kind', 'sent', 'status', 'low_accuracy'),
            jsonb_build_object('detail_id', D3, 'kind', 'sent', 'status', 'low_accuracy'))), 'telegram')
  RETURNING id INTO inc_solo;
  INSERT INTO public.panelist_incident (id, account_id, panelist_id, category, status, description, payload, created_via)
  VALUES (gen_random_uuid(), A, P, 'gps_location', 'open', 'x',
          jsonb_build_object('details', jsonb_build_array(
            jsonb_build_object('detail_id', D1, 'kind', 'sent', 'status', 'low_accuracy'),
            jsonb_build_object('detail_id', D2, 'kind', 'received', 'status', 'no_location'))), 'telegram')
  RETURNING id INTO inc_mixta;
  INSERT INTO public.panelist_incident (id, account_id, panelist_id, category, status, description, payload, created_via)
  VALUES (gen_random_uuid(), A, P, 'gps_location', 'open', 'x', '{"reason":"consent_denied"}', 'telegram')
  RETURNING id INTO inc_consent;
  INSERT INTO public.panelist_incident (id, account_id, panelist_id, category, status, description, payload, created_via,
                                        resolution_note, resolved_at)
  VALUES (gen_random_uuid(), A, P, 'gps_location', 'resolved', 'x',
          jsonb_build_object('details', jsonb_build_array(
            jsonb_build_object('detail_id', D1, 'kind', 'sent', 'status', 'low_accuracy'))), 'telegram',
          'cerrada por el gestor', now() - interval '1 day')
  RETURNING id INTO inc_closed;

  r := public.gps_recalc_distance_rule();

  -- recalc_location
  PERFORM pg_temp.fail_if((SELECT status FROM public.declaration_location WHERE id = L_cerca) <> 'ok', '150 m -> ok');
  PERFORM pg_temp.fail_if((SELECT status FROM public.declaration_location WHERE id = L_lejos) <> 'far', '2000 m -> far');
  PERFORM pg_temp.fail_if((SELECT status FROM public.declaration_location WHERE id = L_sinref) <> 'no_reference', 'sin centro');
  PERFORM pg_temp.fail_if((SELECT status FROM public.declaration_location WHERE id = L_okviejo) <> 'far', 'ok antiguo 450 m -> far');
  -- recalc_marcas
  PERFORM pg_temp.fail_if((SELECT sent_gps_status FROM public.allocation_plan_details WHERE id = D1) <> 'ok', 'D1 -> ok');
  PERFORM pg_temp.fail_if((SELECT sent_gps_status FROM public.allocation_plan_details WHERE id = D3) <> 'far', 'D3 -> far');
  PERFORM pg_temp.fail_if((SELECT received_gps_status FROM public.allocation_plan_details WHERE id = D2) <> 'no_location', 'D2 intacta');
  -- recalc_incidencia_solo_precision
  SELECT * INTO c FROM public.panelist_incident WHERE id = inc_solo;
  PERFORM pg_temp.fail_if(c.status <> 'auto_resolved' OR c.resolved_at IS NULL OR c.resolution_note IS DISTINCT FROM NOTE,
                          'solo precision -> auto_resolved: ' || row_to_json(c)::text);
  PERFORM pg_temp.fail_if(NOT c.payload->'details' @> jsonb_build_array(jsonb_build_object('detail_id', D1, 'status', 'ok'),
                                                                         jsonb_build_object('detail_id', D3, 'status', 'far')),
                          'detalles actualizados: ' || c.payload::text);
  -- recalc_incidencia_mixta
  SELECT * INTO c FROM public.panelist_incident WHERE id = inc_mixta;
  PERFORM pg_temp.fail_if(c.status <> 'open' OR c.resolved_at IS NOT NULL, 'mixta sigue open');
  PERFORM pg_temp.fail_if(NOT c.payload->'details' @> jsonb_build_array(jsonb_build_object('detail_id', D1, 'status', 'ok'),
                                                                         jsonb_build_object('detail_id', D2, 'status', 'no_location')),
                          'mixta detalles: ' || c.payload::text);
  -- recalc_no_consent
  SELECT * INTO c FROM public.panelist_incident WHERE id = inc_consent;
  PERFORM pg_temp.fail_if(c.status <> 'open' OR c.payload <> '{"reason":"consent_denied"}'::jsonb, 'no acepto intacta');
  -- cerrada por el gestor: intacta
  SELECT * INTO c FROM public.panelist_incident WHERE id = inc_closed;
  PERFORM pg_temp.fail_if(c.status <> 'resolved' OR c.resolution_note <> 'cerrada por el gestor'
                          OR c.payload->'details'->0->>'status' <> 'low_accuracy', 'cerrada por gestor intacta');
  -- recuentos
  PERFORM pg_temp.fail_if((r->>'locations')::int <> 4 OR (r->>'incidents_resolved')::int <> 1, 'recuentos: ' || r::text);

  -- recalc_idempotente
  r2 := public.gps_recalc_distance_rule();
  PERFORM pg_temp.fail_if((r2->>'locations')::int <> 0 OR (r2->>'marks')::int <> 0 OR (r2->>'incidents_resolved')::int <> 0,
                          'segunda pasada sin cambios: ' || r2::text);
  PERFORM pg_temp.fail_if((SELECT status FROM public.panelist_incident WHERE id = inc_mixta) <> 'open', 'mixta tras 2a pasada');
END $$;
ROLLBACK;
