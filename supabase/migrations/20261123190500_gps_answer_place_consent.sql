-- GPS fase 2 (24/11, revision de seguridad): gps_answer_place no guarda nada si el permiso de ubicacion vigente no es
-- 'granted' (el panelista lo retiro desde Ayuda con la pregunta aun en pantalla). Devuelve action 'no_consent'; el bot
-- lo trata como cualquier respuesta no aplicada (quita los botones y sigue a la lista).
-- Forward-only sobre 20261123190200 (cuerpo vivo verificado antes de aplicar). Misma firma.

CREATE OR REPLACE FUNCTION public.gps_answer_place(p_panelist_id uuid, p_answer text, p_texts jsonb,
                                                   p_location_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_p panelists; v panelist_context; v_cd jsonb; v_prev text; v_kind text; v_loc declaration_location;
  v_ref uuid; v_review text; v_center_lat numeric; v_center_lon numeric; v_inc uuid; v_decl jsonb; v_first uuid;
  v_place text;
BEGIN
  BEGIN
    IF p_answer IS NULL OR p_answer NOT IN ('yes','no','home_declined') THEN RAISE EXCEPTION 'invalid answer'; END IF;
    SELECT * INTO v_p FROM panelists WHERE id = p_panelist_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'panelist not found'; END IF;
    -- 2026-11-24 (revision de seguridad): si retiro el permiso con la pregunta en pantalla, no se guarda nada
    -- (ni referencia con coordenadas ni incidencia con distancias). gps_consent_version mira el ultimo 'granted',
    -- no la decision vigente: por eso se comprueba aqui la vigente.
    IF public.gps_current_consent(p_panelist_id) IS DISTINCT FROM 'granted' THEN
      RETURN jsonb_build_object('action', 'no_consent', 'place_kind', NULL, 'incident_id', NULL);
    END IF;
    PERFORM pg_advisory_xact_lock(hashtext('gps_visit:' || public.gps_visit_key(p_panelist_id, NULL)));

    -- visita vigente (no se crea una nueva: la pregunta pertenece a una visita concreta)
    SELECT * INTO v FROM panelist_context
     WHERE telegram_id = public.gps_visit_key(p_panelist_id, NULL) AND context_type = 'gps_visit'
       AND created_at > now() - interval '30 minutes'
     ORDER BY created_at DESC, id DESC LIMIT 1;
    v_kind := public.gps_place_kind(p_panelist_id);
    IF NOT FOUND THEN
      RETURN jsonb_build_object('action', 'expired', 'place_kind', v_kind, 'incident_id', NULL);
    END IF;
    v_cd := v.context_data;
    v_prev := v_cd->>'place_answer';
    IF v_prev IN ('yes','no','home_declined')
       OR (v_prev = 'yes_pending_v4' AND p_answer = 'no') THEN
      RETURN jsonb_build_object('action', 'already_answered', 'place_kind', v_kind, 'incident_id', NULL);
    END IF;
    -- 2026-11-23 (revision): la respuesta solo vale para la visita que hizo la pregunta y, si el boton lo dice,
    -- para la posicion por la que se pregunto (un boton viejo de otra visita no cuenta).
    IF NOT COALESCE((v_cd->>'place_asked')::boolean, false)
       OR (p_location_id IS NOT NULL AND p_location_id::text IS DISTINCT FROM v_cd->>'location_id')
       OR (p_answer = 'home_declined' AND v_prev IS DISTINCT FROM 'yes_pending_v4') THEN
      RETURN jsonb_build_object('action', 'expired', 'place_kind', v_kind, 'incident_id', NULL);
    END IF;

    SELECT * INTO v_loc FROM public.gps_visit_location(v_cd);
    v_decl := COALESCE((SELECT jsonb_agg(jsonb_build_object('detail_id', e->>'detail_id', 'kind', e->>'kind'))
                          FROM jsonb_array_elements(COALESCE(v_cd->'details', '[]'::jsonb)) e), '[]'::jsonb);

    -- ---------------------------------------------------------------- No quiere que guardemos su casa
    IF p_answer = 'home_declined' THEN
      IF NOT EXISTS (SELECT 1 FROM panelist_location_reference
                      WHERE panelist_id = p_panelist_id AND kind = 'home' AND source = 'declined') THEN
        INSERT INTO panelist_location_reference (account_id, panelist_id, kind, source, active)
        VALUES (v_p.account_id, p_panelist_id, 'home', 'declined', false);
      END IF;
      UPDATE panelist_context SET context_data = context_data || '{"place_answer": "home_declined"}'::jsonb WHERE id = v.id;
      RETURN jsonb_build_object('action', 'declined_saved', 'place_kind', v_kind, 'incident_id', NULL);
    END IF;

    -- ---------------------------------------------------------------- Si: esa posicion es su sitio
    IF p_answer = 'yes' THEN
      IF v_loc.id IS NULL OR v_loc.latitude IS NULL THEN
        RETURN jsonb_build_object('action', 'no_location', 'place_kind', v_kind, 'incident_id', NULL);
      END IF;
      IF v_kind = 'home' AND public.gps_consent_version(p_panelist_id) IS DISTINCT FROM 'v4' THEN
        UPDATE panelist_context SET context_data = context_data || '{"place_answer": "yes_pending_v4"}'::jsonb WHERE id = v.id;
        RETURN jsonb_build_object('action', 'need_v4', 'place_kind', v_kind, 'incident_id', NULL);
      END IF;

      -- comprobaciones (no bloquean: solo marcan para que el gestor lo revise)
      IF v_kind = 'pobox' AND v_loc.distance_m > COALESCE(public.gps_setting('ref_review_pobox_m'), 1000) THEN
        v_review := 'pobox_far_from_postal_center';
      ELSIF v_kind = 'home' THEN
        SELECT avg(pc.latitude), avg(pc.longitude) INTO v_center_lat, v_center_lon
          FROM postal_centers pc JOIN nodes n ON n.city_id = pc.city_id
         WHERE n.id = v_p.node_id AND pc.account_id = v_p.account_id
           AND pc.latitude IS NOT NULL AND pc.longitude IS NOT NULL AND pc.deleted_at IS NULL;
        IF v_center_lat IS NOT NULL
           AND public.gps_distance_m(v_loc.latitude, v_loc.longitude, v_center_lat, v_center_lon)
               > COALESCE(public.gps_setting('ref_review_home_city_m'), 5000) THEN
          v_review := 'home_far_from_city';
        END IF;
      END IF;

      UPDATE panelist_location_reference SET active = false
       WHERE panelist_id = p_panelist_id AND kind = v_kind AND active;
      INSERT INTO panelist_location_reference (account_id, panelist_id, kind, latitude, longitude, captured_at, source,
                                               location_id, distance_to_postal_center_m, needs_review, review_reason)
      VALUES (v_p.account_id, p_panelist_id, v_kind, v_loc.latitude, v_loc.longitude, v_loc.captured_at, 'declaration',
              v_loc.id, v_loc.distance_m, v_review IS NOT NULL, v_review)
      RETURNING id INTO v_ref;

      -- la posicion de la visita queda en su sitio, y sus declaraciones tambien
      UPDATE declaration_location SET status = 'ok', ref_kind = v_kind, reference_id = v_ref, ref_distance_m = 0
       WHERE id = v_loc.id;
      v_place := v_kind;
    ELSE
    -- ---------------------------------------------------------------- No: recordatorio + incidencia resuelta
      SELECT (e->>'detail_id')::uuid INTO v_first FROM jsonb_array_elements(v_decl) e LIMIT 1;
      v_inc := public.insert_panelist_incident_auto(p_panelist_id, 'gps_location',
        '📍 Panelist confirmed declaring from a place that is not the correct one',
        jsonb_build_object('reason', 'wrong_place', 'place_kind', v_kind, 'visit_started_at', v.created_at,
                           'location_id', v_loc.id, 'ref_distance_m', v_loc.ref_distance_m, 'declarations', v_decl),
        v_first, 'auto_resolved');
      INSERT INTO incident_message (account_id, panelist_id, incident_kind, incident_id, direction, author, body, status,
                                    sent_at, created_at)
      VALUES
        (v_p.account_id, p_panelist_id, 'reported', v_inc, 'outbound', 'bot', COALESCE(p_texts->>'question', ''), 'sent',
         now(), clock_timestamp()),
        (v_p.account_id, p_panelist_id, 'reported', v_inc, 'inbound', 'panelist', COALESCE(p_texts->>'answer', ''), 'received',
         NULL, clock_timestamp()),
        (v_p.account_id, p_panelist_id, 'reported', v_inc, 'outbound', 'bot', COALESCE(p_texts->>'reminder', ''), 'sent',
         now(), clock_timestamp());
      v_place := 'other';
    END IF;

    -- lo que dijo, en cada declaracion ya hecha en la visita (y su estado, si ahora esta en su sitio)
    UPDATE allocation_plan_details d
       SET sent_self_reported_place = CASE WHEN x.kind = 'sent' THEN v_place ELSE d.sent_self_reported_place END,
           received_self_reported_place = CASE WHEN x.kind = 'received' THEN v_place ELSE d.received_self_reported_place END,
           sent_gps_status = CASE WHEN x.kind = 'sent' AND p_answer = 'yes' AND d.sent_location_id = v_loc.id
                                  THEN 'ok' ELSE d.sent_gps_status END,
           received_gps_status = CASE WHEN x.kind = 'received' AND p_answer = 'yes' AND d.received_location_id = v_loc.id
                                      THEN 'ok' ELSE d.received_gps_status END
      FROM (SELECT DISTINCT (e->>'detail_id')::uuid AS detail_id, e->>'kind' AS kind
              FROM jsonb_array_elements(v_decl) e) x
     WHERE d.id = x.detail_id AND d.account_id = v_p.account_id;

    UPDATE panelist_context
       SET context_data = context_data || jsonb_build_object('place_answer', p_answer, 'place_answer_kind', v_place,
                                                             'place_incident_id', v_inc)
     WHERE id = v.id;

    RETURN jsonb_build_object('action', CASE WHEN p_answer = 'yes' THEN 'reference_saved' ELSE 'reminder' END,
                              'place_kind', v_kind, 'incident_id', v_inc);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'gps_answer_place(%, %): %', p_panelist_id, p_answer, SQLERRM;
    RETURN jsonb_build_object('action', 'error', 'place_kind', NULL, 'incident_id', NULL);
  END;
END; $$;

REVOKE ALL ON FUNCTION public.gps_answer_place(uuid,text,jsonb,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gps_answer_place(uuid,text,jsonb,uuid) TO service_role;
