-- GPS al declarar: pedir permiso y ubicacion UNA sola vez por visita (revision Task 4, 2026-11-17).
-- Forward-only sobre 20261117150000_gps_declaracion.sql. Solo CREATE OR REPLACE de dos funciones; mismas firmas.
-- 1) gps_visit_start: need_location solo si la visita aun no la pidio (context_data.location_asked); al devolver
--    need_location = true marca location_asked = true (mismo patron que consent_asked).
-- 2) gps_mark_declaration: devuelve ademas ask_consent = true UNA vez por visita cuando la declaracion queda 'no_answer'
--    y la visita aun no pregunto el permiso (marca consent_asked = true). Sigue sin lanzar nunca.
-- 3) gps_record_consent: cuando devuelve need_location = true (el bot manda el teclado tras "Acepto") marca tambien
--    location_asked = true en la visita.

CREATE OR REPLACE FUNCTION public.gps_visit_start(p_panelist_id uuid, p_telegram_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v panelist_context; v_consent text; v_need_consent boolean; v_need_location boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM panelists WHERE id = p_panelist_id) THEN RAISE EXCEPTION 'panelist not found'; END IF;
  v := public.gps_get_visit(p_panelist_id, p_telegram_id);
  v_consent := public.gps_current_consent(p_panelist_id);
  v_need_consent := v_consent IS NULL AND NOT COALESCE((v.context_data->>'consent_asked')::boolean, false);
  -- 2026-11-17 (ask once): la ubicacion se pide UNA sola vez por visita; despues el recordatorio es el aviso
  -- posterior a la declaracion (gps_mark_declaration warn).
  v_need_location := v_consent = 'granted'
                     AND (public.gps_visit_location(v.context_data)).id IS NULL
                     AND NOT COALESCE((v.context_data->>'gps_unavailable')::boolean, false)
                     AND NOT COALESCE((v.context_data->>'location_asked')::boolean, false);
  IF v_need_consent THEN
    UPDATE panelist_context SET context_data = context_data || '{"consent_asked": true}'::jsonb WHERE id = v.id;
  END IF;
  IF COALESCE(v_need_location, false) THEN
    UPDATE panelist_context SET context_data = context_data || '{"location_asked": true}'::jsonb WHERE id = v.id;
  END IF;
  RETURN jsonb_build_object('need_consent', v_need_consent, 'need_location', COALESCE(v_need_location, false),
                            'consent', v_consent);
END; $$;

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

    -- 2026-11-17 (ask once): sin decision de permiso y aun no preguntado en esta visita (p. ej. declara mandando la
    -- foto directamente, sin pulsar "Confirmar..."): el bot pregunta el permiso UNA vez despues del resultado.
    IF v_status = 'no_answer' AND NOT COALESCE((v_cd->>'consent_asked')::boolean, false) THEN
      v_ask_consent := true;
      v_cd := v_cd || '{"consent_asked": true}'::jsonb;
    END IF;

    -- incidencia de la visita (una por visita)
    IF v_status IN ('no_location','gps_unavailable','low_accuracy','far') THEN
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

CREATE OR REPLACE FUNCTION public.gps_record_consent(
  p_panelist_id uuid, p_decision text, p_language text, p_text_version text, p_text text, p_message_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_p panelists; v_prev text; v_id uuid; v_inc uuid; v panelist_context; v_need_location boolean;
BEGIN
  IF p_decision IS NULL OR p_decision NOT IN ('granted','denied') THEN RAISE EXCEPTION 'invalid decision'; END IF;
  SELECT * INTO v_p FROM panelists WHERE id = p_panelist_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'panelist not found'; END IF;
  PERFORM pg_advisory_xact_lock(hashtext('gps_consent:' || p_panelist_id::text));
  v_prev := public.gps_current_consent(p_panelist_id);

  INSERT INTO panelist_location_consent (account_id, panelist_id, telegram_id, decision, language,
                                         consent_text_version, consent_text, telegram_message_id, source)
  VALUES (v_p.account_id, p_panelist_id, v_p.telegram_id, p_decision, p_language,
          p_text_version, p_text, p_message_id, 'bot')
  RETURNING id INTO v_id;

  IF p_decision = 'denied' AND v_prev IS DISTINCT FROM 'denied' THEN
    v_inc := public.insert_panelist_incident_auto(p_panelist_id, 'gps_location',
      '📍 Panelist did not accept sharing their location when declaring',
      '{"reason":"consent_denied"}'::jsonb, NULL, 'open');
  END IF;

  v := public.gps_get_visit(p_panelist_id, v_p.telegram_id);
  v_need_location := p_decision = 'granted' AND (public.gps_visit_location(v.context_data)).id IS NULL
                     AND NOT COALESCE((v.context_data->>'gps_unavailable')::boolean, false);
  -- 2026-11-17 (ask once): el bot manda el teclado de ubicacion justo despues del "Acepto": cuenta como la peticion
  -- de la visita, para que el siguiente "Confirmar..." de esa visita no la repita.
  IF v_need_location THEN
    UPDATE panelist_context SET context_data = context_data || '{"location_asked": true}'::jsonb WHERE id = v.id;
  END IF;
  RETURN jsonb_build_object('consent_id', v_id, 'decision', p_decision, 'incident_id', v_inc,
    'need_location', v_need_location);
END; $$;

-- Permisos identicos a 20261117150000: solo service_role (y el dueno).
REVOKE ALL ON FUNCTION public.gps_visit_start(uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_mark_declaration(uuid,text,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_record_consent(uuid,text,text,text,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gps_visit_start(uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_mark_declaration(uuid,text,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_record_consent(uuid,text,text,text,text,text) TO service_role;
