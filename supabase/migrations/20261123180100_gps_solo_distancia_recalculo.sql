-- GPS fase 1, Task 2: recalcula con la regla "solo distancia" (20261123180000) lo guardado desde el 17/11.
-- Idempotente: gps_recalc_distance_rule() solo cambia lo que difiere y devuelve los recuentos; se ejecuta una vez
-- al final de esta migracion y se puede repetir sin efecto. No toca:
--   - posiciones cuyas coordenadas ya se borraron (latitude NULL: "borrar mis datos" o purga de 12 meses);
--   - marcas sin posicion (no_location, gps_unavailable, no_consent, no_answer);
--   - incidencias cerradas por el gestor (resolved/dismissed) ni las de "No acepto" (sin details).

CREATE OR REPLACE FUNCTION public.gps_recalc_distance_rule()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  n_loc int; n_sent int; n_recv int; n_upd int := 0; n_res int := 0;
  r record; v_details jsonb; v_clear boolean;
  c_note constant text := 'Regla corregida el 20/11: Telegram no envía la precisión; la posición se juzga solo por la distancia.';
BEGIN
  -- 1. posiciones
  UPDATE declaration_location dl
     SET status = public.gps_classify(dl.nearest_postal_center_id, dl.distance_m)
   WHERE dl.status IN ('low_accuracy','far','ok')
     AND dl.latitude IS NOT NULL
     AND dl.status IS DISTINCT FROM public.gps_classify(dl.nearest_postal_center_id, dl.distance_m);
  GET DIAGNOSTICS n_loc = ROW_COUNT;

  -- 2. marcas de las declaraciones = estado de su posicion
  UPDATE allocation_plan_details d SET sent_gps_status = dl.status
    FROM declaration_location dl
   WHERE dl.id = d.sent_location_id AND dl.account_id = d.account_id
     AND d.sent_gps_status IN ('low_accuracy','far','ok') AND d.sent_gps_status IS DISTINCT FROM dl.status
     AND dl.status IN ('ok','far','no_reference');
  GET DIAGNOSTICS n_sent = ROW_COUNT;
  UPDATE allocation_plan_details d SET received_gps_status = dl.status
    FROM declaration_location dl
   WHERE dl.id = d.received_location_id AND dl.account_id = d.account_id
     AND d.received_gps_status IN ('low_accuracy','far','ok') AND d.received_gps_status IS DISTINCT FROM dl.status
     AND dl.status IN ('ok','far','no_reference');
  GET DIAGNOSTICS n_recv = ROW_COUNT;

  -- 3. incidencias de visita aun abiertas
  FOR r IN
    SELECT pi.id, pi.payload FROM panelist_incident pi
     WHERE pi.category = 'gps_location' AND pi.status IN ('open','in_progress')
       AND jsonb_typeof(pi.payload->'details') = 'array'
     FOR UPDATE
  LOOP
    SELECT COALESCE(jsonb_agg(jsonb_set(e, '{status}', to_jsonb(COALESCE(
               CASE e->>'kind' WHEN 'sent' THEN d.sent_gps_status ELSE d.received_gps_status END,
               e->>'status'))) ORDER BY o), '[]'::jsonb)
      INTO v_details
      FROM jsonb_array_elements(r.payload->'details') WITH ORDINALITY AS x(e, o)
      LEFT JOIN allocation_plan_details d ON d.id = (e->>'detail_id')::uuid;
    v_clear := jsonb_array_length(v_details) > 0
               AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_details) e
                                WHERE e->>'status' IN ('no_location','gps_unavailable'));
    IF v_clear THEN
      UPDATE panelist_incident
         SET payload = jsonb_set(payload, '{details}', v_details), status = 'auto_resolved',
             resolved_at = now(), resolution_note = c_note, updated_at = now()
       WHERE id = r.id;
      n_res := n_res + 1;
    ELSIF v_details IS DISTINCT FROM r.payload->'details' THEN
      UPDATE panelist_incident SET payload = jsonb_set(payload, '{details}', v_details), updated_at = now()
       WHERE id = r.id;
      n_upd := n_upd + 1;
    END IF;
  END LOOP;

  RAISE NOTICE 'gps_recalc_distance_rule: posiciones %, marcas % (envio %, recepcion %), incidencias cerradas %, actualizadas %',
    n_loc, n_sent + n_recv, n_sent, n_recv, n_res, n_upd;
  RETURN jsonb_build_object('locations', n_loc, 'marks', n_sent + n_recv, 'incidents_resolved', n_res,
                            'incidents_updated', n_upd);
END; $$;

REVOKE ALL ON FUNCTION public.gps_recalc_distance_rule() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gps_recalc_distance_rule() TO service_role;

SELECT public.gps_recalc_distance_rule();
