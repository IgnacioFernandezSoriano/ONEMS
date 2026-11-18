-- GPS: el panelista borra sus datos de ubicacion (20261117190000_gps_erase.sql).
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT FALSE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

-- ===== 1) Borra coordenadas, precision, distancia y centro; conserva filas, estado, fechas, marcas y permisos =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$
DECLARE r jsonb; n int; c record; inc_pl jsonb; v_loc_far uuid;
  P constant uuid := 'e1000000-0000-0000-0000-000000000001';
  P4 constant uuid := 'e4000000-0000-0000-0000-000000000004';
  D1 constant uuid := 'd1000000-0000-0000-0000-000000000001';
BEGIN
  UPDATE public.panelists SET telegram_id = '1001' WHERE id = P;
  UPDATE public.panelists SET telegram_id = '1004' WHERE id = P4;
  INSERT INTO public.postal_centers (id, account_id, code, name, city_id, latitude, longitude) VALUES
    ('dd000000-0000-0000-0000-00000000000a','a0000000-0000-0000-0000-000000000001','PCA','Centro A',
     'c1000000-0000-0000-0000-000000000001', -1.28000, 36.82000);
  INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id,
      fecha_programada, status, tag_id, origin_panelist_id, sent_at) VALUES
    (D1,'a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001',
     'b1000000-0000-0000-0000-000000000001','b4000000-0000-0000-0000-000000000004','2027-03-10','sent','11111111',
     P, now());

  PERFORM public.gps_record_consent(P, 'granted', 'es', 'v1', 'Texto del permiso', '555');
  PERFORM public.gps_visit_start(P, '1001');
  r := public.gps_save_location(P, '1001', -1.27910, 36.82000, 20, now(), 'm1');    -- ok, ~100 m
  r := public.gps_save_location(P, '1001', -1.27190, 36.82000, 50, now(), 'm2');    -- far, ~900 m
  PERFORM pg_temp.fail_if(r->>'status' <> 'far', 'far: ' || r::text);
  v_loc_far := (r->>'location_id')::uuid;
  r := public.gps_mark_declaration(D1, 'sent', P);
  PERFORM pg_temp.fail_if(r->>'status' <> 'far', 'marca far: ' || r::text);
  SELECT payload INTO inc_pl FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location'
   AND payload ? 'details';
  PERFORM pg_temp.fail_if(inc_pl->>'distance_m' IS NULL, 'incidencia con distancia antes: ' || coalesce(inc_pl::text,'NULL'));

  -- otro panelista con posicion: no se toca
  PERFORM public.gps_record_consent(P4, 'granted', 'en', 'v1', 'Consent text', '556');
  PERFORM public.gps_visit_start(P4, '1004');
  PERFORM public.gps_save_location(P4, '1004', -1.0, 36.0, 20, now(), 'm9');

  r := public.gps_erase_panelist_locations(P, 'bot');
  PERFORM pg_temp.fail_if((r->>'erased')::int <> 2, 'erased = 2: ' || r::text);

  SELECT count(*) INTO n FROM public.declaration_location WHERE panelist_id = P;
  PERFORM pg_temp.fail_if(n <> 2, 'filas conservadas: ' || n);
  SELECT count(*) INTO n FROM public.declaration_location WHERE panelist_id = P
     AND (latitude IS NOT NULL OR longitude IS NOT NULL OR accuracy_m IS NOT NULL OR distance_m IS NOT NULL
          OR nearest_postal_center_id IS NOT NULL);
  PERFORM pg_temp.fail_if(n <> 0, 'sin datos de ubicacion: ' || n);
  SELECT * INTO c FROM public.declaration_location WHERE id = v_loc_far;
  PERFORM pg_temp.fail_if(c.status <> 'far' OR c.captured_at IS NULL OR c.received_at IS NULL
                          OR c.telegram_message_id <> 'm2', 'estado y fechas conservados');
  PERFORM pg_temp.fail_if((SELECT sent_gps_status FROM public.allocation_plan_details WHERE id = D1) <> 'far'
                          OR (SELECT sent_location_id FROM public.allocation_plan_details WHERE id = D1) <> v_loc_far,
                          'la declaracion conserva su estado GPS');

  -- incidencias y visita sin distancia
  SELECT count(*) INTO n FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location'
     AND payload->'distance_m' IS NOT NULL AND payload->'distance_m' <> 'null'::jsonb;
  PERFORM pg_temp.fail_if(n <> 0, 'incidencias sin distancia: ' || n);
  SELECT payload INTO inc_pl FROM public.panelist_incident WHERE panelist_id = P AND category = 'gps_location'
   AND payload ? 'details';
  PERFORM pg_temp.fail_if(jsonb_array_length(inc_pl->'details') <> 1, 'detalle de la incidencia conservado');
  SELECT count(*) INTO n FROM public.panelist_context WHERE context_type = 'gps_visit'
     AND context_data->>'panelist_id' = P::text AND context_data->'distance_m' IS DISTINCT FROM 'null'::jsonb;
  PERFORM pg_temp.fail_if(n <> 0, 'visita sin distancia: ' || n);

  -- permisos intactos (prueba legal)
  SELECT count(*) INTO n FROM public.panelist_location_consent WHERE panelist_id = P;
  PERFORM pg_temp.fail_if(n <> 1, 'permiso conservado: ' || n);
  PERFORM pg_temp.fail_if(public.gps_current_consent(P) IS DISTINCT FROM 'granted', 'decision vigente intacta');

  -- otro panelista intacto
  SELECT count(*) INTO n FROM public.declaration_location WHERE panelist_id = P4 AND latitude IS NOT NULL;
  PERFORM pg_temp.fail_if(n <> 1, 'P4 intacto: ' || n);

  -- registro del borrado
  SELECT * INTO c FROM public.gps_erasure_log WHERE panelist_id = P;
  PERFORM pg_temp.fail_if(c.source <> 'bot' OR c.rows_erased <> 2 OR c.panelist_code <> 'P1'
                          OR c.account_id <> 'a0000000-0000-0000-0000-000000000001' OR c.requested_at IS NULL,
                          'log: ' || row_to_json(c)::text);

  -- idempotente: segunda vez borra 0 y deja otra constancia
  r := public.gps_erase_panelist_locations(P, 'manager');
  PERFORM pg_temp.fail_if((r->>'erased')::int <> 0, 'segunda vez 0: ' || r::text);
  SELECT count(*) INTO n FROM public.gps_erasure_log WHERE panelist_id = P;
  PERFORM pg_temp.fail_if(n <> 2, 'dos constancias: ' || n);

  -- la constancia sobrevive al borrado del panelista
  DELETE FROM public.panelist_context WHERE context_data->>'panelist_id' = P::text;
  DELETE FROM public.allocation_plan_details WHERE id = D1;
  DELETE FROM public.panelists WHERE id = P;
  SELECT count(*) INTO n FROM public.gps_erasure_log WHERE panelist_id IS NULL AND panelist_code = 'P1';
  PERFORM pg_temp.fail_if(n <> 2, 'constancia tras borrar el panelista: ' || n);
END $$;
ROLLBACK;

-- ===== 2) Errores =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$
DECLARE ok boolean;
BEGIN
  ok := false;
  BEGIN PERFORM public.gps_erase_panelist_locations('e1000000-0000-0000-0000-000000000001', 'x');
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM pg_temp.fail_if(NOT ok, 'source invalido');
  ok := false;
  BEGIN PERFORM public.gps_erase_panelist_locations('00000000-0000-0000-0000-0000000000ff', 'bot');
  EXCEPTION WHEN OTHERS THEN ok := true; END;
  PERFORM pg_temp.fail_if(NOT ok, 'panelista inexistente');
  -- sin datos: 0 y constancia igualmente
  PERFORM pg_temp.fail_if((public.gps_erase_panelist_locations('e1000000-0000-0000-0000-000000000001','bot')->>'erased')::int <> 0,
                          'sin datos -> 0');
END $$;
ROLLBACK;

-- ===== 3) Permisos y RLS =====
DO $$
BEGIN
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated',
    'public.gps_erase_panelist_locations(uuid,text)', 'EXECUTE'), 'authenticated sin EXECUTE');
  PERFORM pg_temp.fail_if(has_function_privilege('anon',
    'public.gps_erase_panelist_locations(uuid,text)', 'EXECUTE'), 'anon sin EXECUTE');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('service_role',
    'public.gps_erase_panelist_locations(uuid,text)', 'EXECUTE'), 'service_role con EXECUTE');
  PERFORM pg_temp.fail_if(NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.gps_erasure_log'::regclass),
    'RLS activada');
  PERFORM pg_temp.fail_if(NOT has_table_privilege('authenticated', 'public.gps_erasure_log', 'SELECT'), 'authenticated SELECT');
  PERFORM pg_temp.fail_if(has_table_privilege('authenticated', 'public.gps_erasure_log', 'INSERT'), 'authenticated sin INSERT');
  PERFORM pg_temp.fail_if(has_table_privilege('anon', 'public.gps_erasure_log', 'SELECT'), 'anon sin SELECT');
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'gps_erasure_log' AND policyname = 'gel_select'),
    'politica de lectura por cuenta');
END $$;
