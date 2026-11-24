-- GPS fase 1: la posicion se juzga SOLO por la distancia (plan docs/superpowers/plans/2026-11-20-gps-fase1-solo-distancia.md,
-- spec 2026-11-20-gps-casa-apartado-design.md §5.1). Forward-only sobre 20261117150000 / 20261117151000.
-- Motivo: Telegram no envia horizontal_accuracy en una ubicacion compartida una vez -> con la regla del 17/11 todas
-- las posiciones salian 'low_accuracy', abrian incidencia y el bot pedia "Reintentar" sin motivo.
-- Cambios (mismas firmas, cuerpos vivos verificados iguales al repo el 23/11):
-- 1) gps_settings + gps_setting(): radio "en el sitio correcto" configurable (300 m).
-- 2) gps_classify(centro, distancia): 'no_reference' | 'far' | 'ok'. accuracy_m se guarda pero no cuenta.
-- 3) gps_save_location: usa gps_classify; desaparece el paso 'low_accuracy_retry'.
-- 4) gps_mark_declaration: la incidencia por visita solo se abre por 'no_location' / 'gps_unavailable'.
-- 5) gps_refresh_incident: pasa a auto_resolved cuando ningun detalle queda en 'no_location' / 'gps_unavailable'.

-- ------------------------------------------------------------------------------------------------ 1. ajustes
CREATE TABLE IF NOT EXISTS public.gps_settings (
  key text PRIMARY KEY,
  value numeric NOT NULL
);
INSERT INTO public.gps_settings (key, value) VALUES ('ok_radius_m', 300) ON CONFLICT (key) DO NOTHING;
-- Ajustes globales (no son datos de cuenta): RLS sin politicas, solo las leen funciones SECURITY DEFINER.
ALTER TABLE public.gps_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.gps_settings FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.gps_settings TO service_role;

CREATE OR REPLACE FUNCTION public.gps_setting(p_key text)
RETURNS numeric LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT s.value FROM public.gps_settings s WHERE s.key = p_key;
$$;

-- ------------------------------------------------------------------------------------------------ 2. clasificacion
CREATE OR REPLACE FUNCTION public.gps_classify(p_center uuid, p_dist numeric)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT CASE
    WHEN p_center IS NULL OR p_dist IS NULL THEN 'no_reference'
    WHEN p_dist > COALESCE(public.gps_setting('ok_radius_m'), 300) THEN 'far'
    ELSE 'ok' END;
$$;

-- ------------------------------------------------------------------------------------------------ 3. gps_save_location
-- action: 'stale' (mensaje de hace > 5 min, se ignora), 'saved' (guardada; enlaza retroactivamente las declaraciones
-- sin posicion de los 30 min anteriores), 'no_consent' (permiso vigente no 'granted': no se guarda nada).
CREATE OR REPLACE FUNCTION public.gps_save_location(
  p_panelist_id uuid, p_telegram_id text, p_lat numeric, p_lon numeric, p_accuracy numeric,
  p_msg_date timestamptz, p_msg_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_p panelists; v panelist_context; v_city uuid;
  v_center uuid; v_dist numeric; v_status text; v_loc uuid; v_inc uuid; v_linked jsonb;
BEGIN
  SELECT * INTO v_p FROM panelists WHERE id = p_panelist_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'panelist not found'; END IF;
  -- Sin permiso concedido nunca se guardan coordenadas.
  IF public.gps_current_consent(p_panelist_id) IS DISTINCT FROM 'granted' THEN
    RETURN jsonb_build_object('action', 'no_consent', 'status', NULL, 'location_id', NULL, 'distance_m', NULL);
  END IF;
  IF p_lat IS NULL OR p_lon IS NULL OR p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'invalid coordinates'; END IF;

  IF p_msg_date IS NOT NULL AND p_msg_date < now() - interval '5 minutes' THEN
    RETURN jsonb_build_object('action', 'stale', 'status', NULL, 'location_id', NULL, 'distance_m', NULL);
  END IF;

  v := public.gps_get_visit(p_panelist_id, p_telegram_id);

  -- referencia: centro con coordenadas mas cercano de la ciudad del nodo del panelista
  SELECT n.city_id INTO v_city FROM nodes n WHERE n.id = v_p.node_id;
  SELECT pc.id, public.gps_distance_m(p_lat, p_lon, pc.latitude, pc.longitude)
    INTO v_center, v_dist
    FROM postal_centers pc
   WHERE v_city IS NOT NULL AND pc.city_id = v_city AND pc.account_id = v_p.account_id
     AND pc.latitude IS NOT NULL AND pc.longitude IS NOT NULL AND pc.deleted_at IS NULL
   ORDER BY public.gps_distance_m(p_lat, p_lon, pc.latitude, pc.longitude), pc.id
   LIMIT 1;

  -- 2026-11-23: solo distancia (la precision se guarda como dato, no cambia el estado)
  v_status := public.gps_classify(v_center, v_dist);

  INSERT INTO declaration_location (account_id, panelist_id, telegram_id, captured_at, received_at, latitude,
                                    longitude, accuracy_m, nearest_postal_center_id, distance_m, status,
                                    telegram_message_id)
  VALUES (v_p.account_id, p_panelist_id, COALESCE(NULLIF(btrim(p_telegram_id), ''), v_p.telegram_id),
          COALESCE(p_msg_date, now()), now(), p_lat, p_lon, p_accuracy, v_center, v_dist, v_status, p_msg_id)
  RETURNING id INTO v_loc;

  UPDATE panelist_context
     SET context_data = context_data || jsonb_build_object('location_id', v_loc, 'location_status', v_status,
                                                           'distance_m', v_dist)
   WHERE id = v.id;

  -- Enlace retroactivo: declaraciones del panelista marcadas en los ultimos 30 min (registro de las visitas
  -- recientes) que siguen en no_location / no_answer.
  WITH led AS (
    SELECT DISTINCT (e->>'detail_id')::uuid AS detail_id, e->>'kind' AS kind
      FROM panelist_context c, jsonb_array_elements(COALESCE(c.context_data->'details', '[]'::jsonb)) e
     WHERE c.telegram_id = v.telegram_id AND c.context_type = 'gps_visit'
       AND c.created_at > now() - interval '1 hour'
       AND (e->>'at')::timestamptz >= now() - interval '30 minutes'),
  upd AS (
  UPDATE allocation_plan_details d
     SET sent_location_id = CASE WHEN led.kind = 'sent' THEN v_loc ELSE d.sent_location_id END,
         sent_gps_status  = CASE WHEN led.kind = 'sent' THEN v_status ELSE d.sent_gps_status END,
         received_location_id = CASE WHEN led.kind = 'received' THEN v_loc ELSE d.received_location_id END,
         received_gps_status  = CASE WHEN led.kind = 'received' THEN v_status ELSE d.received_gps_status END
    FROM led
   WHERE d.id = led.detail_id AND d.account_id = v_p.account_id
     AND ((led.kind = 'sent' AND d.sent_gps_status IN ('no_location','no_answer'))
       OR (led.kind = 'received' AND d.received_gps_status IN ('no_location','no_answer')))
  RETURNING d.id AS detail_id, led.kind)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('detail_id', upd.detail_id, 'kind', upd.kind)), '[]'::jsonb)
    INTO v_linked FROM upd;

  -- Solo las incidencias (aun no cerradas por el gestor) que contienen alguna declaracion enlazada ahora.
  FOR v_inc IN
    SELECT DISTINCT pi.id
      FROM panelist_incident pi
      CROSS JOIN LATERAL jsonb_array_elements(COALESCE(pi.payload->'details', '[]'::jsonb)) e
     WHERE pi.panelist_id = p_panelist_id AND pi.category = 'gps_location'
       AND pi.status IN ('open','in_progress','auto_resolved')
       AND jsonb_typeof(pi.payload->'details') = 'array'
       AND v_linked @> jsonb_build_array(jsonb_build_object('detail_id', e->>'detail_id', 'kind', e->>'kind'))
  LOOP
    PERFORM public.gps_refresh_incident(v_inc, v_dist);
  END LOOP;

  RETURN jsonb_build_object('action', 'saved', 'status', v_status, 'location_id', v_loc, 'distance_m', v_dist);
END; $$;

-- ------------------------------------------------------------------------------------------------ 4. gps_refresh_incident
-- Rehace el payload de la incidencia de GPS a partir de las marcas reales de sus declaraciones y la pasa a
-- auto_resolved si ya no queda ninguna sin posicion (no_location / gps_unavailable). No toca las cerradas por el gestor.
CREATE OR REPLACE FUNCTION public.gps_refresh_incident(p_incident_id uuid, p_distance_m numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_pl jsonb; v_details jsonb; v_clear boolean;
BEGIN
  SELECT payload INTO v_pl FROM panelist_incident
   WHERE id = p_incident_id AND category = 'gps_location' AND status NOT IN ('resolved','dismissed');
  IF NOT FOUND OR v_pl IS NULL OR jsonb_typeof(v_pl->'details') IS DISTINCT FROM 'array' THEN RETURN; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_set(e, '{status}', to_jsonb(COALESCE(
             CASE e->>'kind' WHEN 'sent' THEN d.sent_gps_status ELSE d.received_gps_status END,
             e->>'status'))) ORDER BY o), '[]'::jsonb)
    INTO v_details
    FROM jsonb_array_elements(v_pl->'details') WITH ORDINALITY AS x(e, o)
    LEFT JOIN allocation_plan_details d ON d.id = (e->>'detail_id')::uuid;
  v_clear := jsonb_array_length(v_details) > 0
             AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_details) e
                              WHERE e->>'status' IN ('no_location','gps_unavailable'));
  UPDATE panelist_incident
     SET payload = jsonb_set(jsonb_set(v_pl, '{details}', v_details), '{distance_m}',
                             COALESCE(to_jsonb(p_distance_m), v_pl->'distance_m', 'null'::jsonb)),
         status = CASE WHEN v_clear AND status = 'open' THEN 'auto_resolved' ELSE status END,
         resolved_at = CASE WHEN v_clear AND status = 'open' THEN now() ELSE resolved_at END,
         updated_at = now()
   WHERE id = p_incident_id;
END; $$;

-- ------------------------------------------------------------------------------------------------ 5. gps_mark_declaration
-- Igual que 20261117151000 salvo la condicion de la incidencia por visita (solo sin posicion).
CREATE OR REPLACE FUNCTION public.gps_mark_declaration(p_detail_id uuid, p_kind text, p_panelist_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_p panelists; v_d allocation_plan_details; v panelist_context; v_consent text;
  v_status text; v_loc uuid; v_warn boolean := false; v_ask_consent boolean := false; v_inc uuid; v_inc_status text;
  v_entry jsonb; v_pl jsonb; v_cd jsonb; v_dist numeric;
BEGIN
  BEGIN
    IF p_kind IS NULL OR p_kind NOT IN ('sent','received') THEN RAISE EXCEPTION 'invalid kind'; END IF;
    SELECT * INTO v_p FROM panelists WHERE id = p_panelist_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'panelist not found'; END IF;
    SELECT * INTO v_d FROM allocation_plan_details WHERE id = p_detail_id;
    IF NOT FOUND OR v_d.account_id IS DISTINCT FROM v_p.account_id THEN RAISE EXCEPTION 'detail not found'; END IF;

    v := public.gps_get_visit(p_panelist_id, NULL);
    v_cd := v.context_data;
    v_consent := public.gps_current_consent(p_panelist_id);

    IF v_consent IS NULL THEN
      v_status := 'no_answer';
    ELSIF v_consent = 'denied' THEN
      v_status := 'no_consent';
    ELSE
      -- posicion de la visita solo si se recibio hace <= 30 min
      SELECT l.id, l.status, l.distance_m INTO v_loc, v_status, v_dist FROM public.gps_visit_location(v_cd) l;
      IF v_loc IS NULL THEN
        v_status := CASE WHEN COALESCE((v_cd->>'gps_unavailable')::boolean, false)
                         THEN 'gps_unavailable' ELSE 'no_location' END;
      END IF;
    END IF;

    IF p_kind = 'sent' THEN
      UPDATE allocation_plan_details SET sent_location_id = v_loc, sent_gps_status = v_status WHERE id = p_detail_id;
    ELSE
      UPDATE allocation_plan_details SET received_location_id = v_loc, received_gps_status = v_status WHERE id = p_detail_id;
    END IF;

    -- registro de la visita (para el enlace retroactivo y "GPS no funciona")
    v_cd := jsonb_set(v_cd, '{details}',
              COALESCE((SELECT jsonb_agg(e) FROM jsonb_array_elements(COALESCE(v_cd->'details', '[]'::jsonb)) e
                         WHERE NOT (e->>'detail_id' = p_detail_id::text AND e->>'kind' = p_kind)), '[]'::jsonb)
              || jsonb_build_array(jsonb_build_object('detail_id', p_detail_id, 'kind', p_kind, 'at', now())));

    IF v_status = 'no_location' AND NOT COALESCE((v_cd->>'warned')::boolean, false) THEN
      v_warn := true;
      v_cd := v_cd || '{"warned": true}'::jsonb;
    END IF;

    -- sin decision de permiso y aun no preguntado en esta visita: el bot pregunta el permiso UNA vez.
    IF v_status = 'no_answer' AND NOT COALESCE((v_cd->>'consent_asked')::boolean, false) THEN
      v_ask_consent := true;
      v_cd := v_cd || '{"consent_asked": true}'::jsonb;
    END IF;

    -- incidencia de la visita (una por visita). 2026-11-23: solo declaraciones SIN posicion; 'far' va al informe.
    IF v_status IN ('no_location','gps_unavailable') THEN
      v_entry := jsonb_build_object('detail_id', p_detail_id, 'tag', COALESCE(v_d.tag_id, v_d.idtag),
                                    'kind', p_kind, 'status', v_status);
      v_inc := NULLIF(v_cd->>'incident_id', '')::uuid;
      IF v_inc IS NOT NULL THEN
        SELECT payload, status INTO v_pl, v_inc_status FROM panelist_incident WHERE id = v_inc;
        -- cerrada por el gestor (resolved/dismissed) o inexistente -> incidencia NUEVA, no se anade a escondidas
        IF NOT FOUND OR v_inc_status IN ('resolved','dismissed') THEN v_inc := NULL; END IF;
      END IF;
      IF v_inc IS NULL THEN
        v_inc := public.insert_panelist_incident_auto(p_panelist_id, 'gps_location',
          '📍 Declaration without a valid GPS position',
          jsonb_build_object('visit_started_at', v.created_at, 'details', jsonb_build_array(v_entry),
                             'distance_m', v_dist),
          p_detail_id, 'open');
        v_cd := v_cd || jsonb_build_object('incident_id', v_inc);
      ELSE
        v_pl := jsonb_set(COALESCE(v_pl, '{}'::jsonb), '{details}',
                  COALESCE((SELECT jsonb_agg(e) FROM jsonb_array_elements(COALESCE(v_pl->'details', '[]'::jsonb)) e
                             WHERE NOT (e->>'detail_id' = p_detail_id::text AND e->>'kind' = p_kind)), '[]'::jsonb)
                  || jsonb_build_array(v_entry));
        UPDATE panelist_incident
           SET payload = v_pl,
               status = CASE WHEN status = 'auto_resolved' THEN 'open' ELSE status END,
               resolved_at = CASE WHEN status = 'auto_resolved' THEN NULL ELSE resolved_at END,
               updated_at = now()
         WHERE id = v_inc;
      END IF;
    END IF;

    UPDATE panelist_context SET context_data = v_cd WHERE id = v.id;
    RETURN jsonb_build_object('status', v_status, 'warn', v_warn, 'ask_consent', v_ask_consent);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'gps_mark_declaration(%, %, %): %', p_detail_id, p_kind, p_panelist_id, SQLERRM;
    RETURN jsonb_build_object('status', NULL, 'warn', false, 'ask_consent', false);
  END;
END; $$;

-- ------------------------------------------------------------------------------------------------ 6. permisos
REVOKE ALL ON FUNCTION public.gps_setting(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_classify(uuid,numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_save_location(uuid,text,numeric,numeric,numeric,timestamptz,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_refresh_incident(uuid,numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_mark_declaration(uuid,text,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gps_setting(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_classify(uuid,numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_save_location(uuid,text,numeric,numeric,numeric,timestamptz,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_refresh_incident(uuid,numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_mark_declaration(uuid,text,uuid) TO service_role;
