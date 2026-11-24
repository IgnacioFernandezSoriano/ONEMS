-- GPS fase 1, Task 3: las pruebas diarias del agente (panelista de prueba de DEMO2, que no puede mandar GPS)
-- abren cada mañana una incidencia gps_location "sin posicion" que ops_test_status contaba como "efecto
-- inesperado" y que ops_test._reset no borraba (se acumulaban). Forward-only sobre 20261105160000; cuerpos vivos
-- verificados iguales al repo el 23/11.
-- 1) _expected_incidents: tambien gps_location del panelista de prueba (asi _reset la borra con sus mensajes).
-- 2) ops_test_status: 'incident' sigue significando "se creo la incidencia de paquete danado" (no la GPS).
-- 3) Limpieza puntual de las incidencias GPS acumuladas del panelista de prueba (17-23/11 hasta las 12:00 UTC;
--    las posteriores pueden ser una prueba manual en curso y se dejan).

CREATE OR REPLACE FUNCTION ops_test._expected_incidents()
RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT i.id FROM public.panelist_incident i, ops_test.config c, ops_test.state s
   WHERE c.id = 1 AND s.id = 1 AND s.prepared_at IS NOT NULL
     AND i.account_id = c.account_id AND i.panelist_id = c.tester_panelist_id
     AND ((i.category = 'parcel_damaged' AND i.created_via = 'telegram') OR i.category = 'gps_location')
     AND i.created_at >= s.prepared_at
$$;

CREATE OR REPLACE FUNCTION public.ops_test_status(p_token text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE c ops_test.config; s ops_test.state; v_send record; v_recv record; v_one boolean; v_inc uuid[];
        v_unexp text[] := '{}'; n int;
BEGIN
  PERFORM ops_test._check(p_token);
  SELECT * INTO c FROM ops_test.config WHERE id = 1;
  SELECT * INTO s FROM ops_test.state WHERE id = 1;

  SELECT d.id, d.status, d.tag_id INTO v_send FROM public.allocation_plan_details d
   WHERE d.plan_id = s.plan_id AND d.account_id = c.account_id
     AND d.origin_node_id = (SELECT node_id FROM public.panelists WHERE id = c.tester_panelist_id) LIMIT 1;
  SELECT d.id, d.status INTO v_recv FROM public.allocation_plan_details d
   WHERE d.plan_id = s.plan_id AND d.account_id = c.account_id
     AND d.destination_node_id = (SELECT node_id FROM public.panelists WHERE id = c.tester_panelist_id) LIMIT 1;
  v_one := v_recv.id IS NOT NULL AND EXISTS (SELECT 1 FROM public.one_db o WHERE o.allocation_detail_id = v_recv.id);
  v_inc := ARRAY(SELECT ops_test._expected_incidents());

  -- G5: lo que no debería haber aparecido en DEMO2 desde la preparación
  IF s.prepared_at IS NOT NULL THEN
    SELECT count(*) INTO n FROM public.panelist_notification x WHERE x.account_id = c.account_id AND x.created_at >= s.prepared_at;
    IF n > 0 THEN v_unexp := v_unexp || (n || ' avisos a panelistas (panelist_notification)'); END IF;
    SELECT count(*) INTO n FROM public.receipt_case x WHERE x.account_id = c.account_id AND x.created_at >= s.prepared_at;
    IF n > 0 THEN v_unexp := v_unexp || (n || ' casos de recepción (receipt_case)'); END IF;
    SELECT count(*) INTO n FROM public.panelist_incident x
     WHERE x.account_id = c.account_id AND x.created_at >= s.prepared_at AND NOT (x.id = ANY (v_inc));
    IF n > 0 THEN v_unexp := v_unexp || (n || ' incidencias no esperadas (panelist_incident)'); END IF;
    SELECT count(*) INTO n FROM public.incident_message x
     WHERE x.account_id = c.account_id AND x.created_at >= s.prepared_at
       AND NOT (coalesce(x.incident_id = ANY (v_inc), false) OR coalesce(x.meta ? 'report_flow', false));
    IF n > 0 THEN v_unexp := v_unexp || (n || ' mensajes de incidencia (incident_message)'); END IF;
    SELECT count(*) INTO n FROM public.material_shipments x WHERE x.account_id = c.account_id AND x.created_at >= s.prepared_at;
    IF n > 0 THEN v_unexp := v_unexp || (n || ' envíos de material (material_shipments)'); END IF;
    -- Envios del panelista de prueba que NO son de prueba y han cambiado (p. ej. el agente pulso la fila
    -- equivocada). Lo unico esperado: el bot pasa a 'notified' sus envios pendientes al enseñar la lista.
    SELECT count(*) INTO n FROM public.allocation_plan_details x
     WHERE x.account_id = c.account_id AND x.plan_id IS DISTINCT FROM s.plan_id AND x.updated_at >= s.prepared_at
       AND (SELECT node_id FROM public.panelists WHERE id = c.tester_panelist_id) IN (x.origin_node_id, x.destination_node_id)
       AND NOT (x.status = 'notified' AND x.origin_node_id = (SELECT node_id FROM public.panelists WHERE id = c.tester_panelist_id));
    IF n > 0 THEN v_unexp := v_unexp || (n || ' envíos de DEMO2 que no son de prueba han cambiado (allocation_plan_details)'); END IF;
    SELECT count(*) INTO n FROM public.deferred_samples x WHERE x.account_id = c.account_id AND x.created_at >= s.prepared_at;
    IF n > 0 THEN v_unexp := v_unexp || (n || ' muestras apartadas al registro (deferred_samples)'); END IF;
  END IF;

  -- 2026-11-23: 'incident' = la incidencia de paquete danado de la prueba (la GPS tambien es esperada, pero no cuenta aqui)
  RETURN jsonb_build_object(
    'send_status', v_send.status, 'send_tag', v_send.tag_id, 'receive_status', v_recv.status,
    'one_db', v_one,
    'incident', EXISTS (SELECT 1 FROM public.panelist_incident i WHERE i.id = ANY (v_inc) AND i.category = 'parcel_damaged'),
    'unexpected', to_jsonb(v_unexp));
END $$;

REVOKE ALL ON FUNCTION ops_test._expected_incidents() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_test_status(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_test_status(text) TO anon;

-- Limpieza puntual (solo la cuenta y el panelista de prueba de ops_test.config)
DO $$
DECLARE v_ids uuid[]; n_msg int; n_inc int;
BEGIN
  SELECT array_agg(i.id) INTO v_ids
    FROM public.panelist_incident i, ops_test.config c
   WHERE c.id = 1 AND i.account_id = c.account_id AND i.panelist_id = c.tester_panelist_id
     AND i.category = 'gps_location' AND i.created_at < timestamptz '2026-11-23 12:00+00';
  IF v_ids IS NULL THEN RAISE NOTICE 'ops_test gps cleanup: nada que borrar'; RETURN; END IF;
  DELETE FROM public.incident_message m USING ops_test.config c
   WHERE c.id = 1 AND m.account_id = c.account_id AND m.incident_id = ANY (v_ids);
  GET DIAGNOSTICS n_msg = ROW_COUNT;
  DELETE FROM public.panelist_incident i WHERE i.id = ANY (v_ids);
  GET DIAGNOSTICS n_inc = ROW_COUNT;
  RAISE NOTICE 'ops_test gps cleanup: % incidencias, % mensajes', n_inc, n_msg;
END $$;
