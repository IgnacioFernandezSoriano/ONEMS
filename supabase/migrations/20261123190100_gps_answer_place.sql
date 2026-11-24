-- GPS fase 2, Task 2 (plan docs/superpowers/plans/2026-11-23-gps-fase2-pregunta-lugar.md; spec 2026-11-20 §2 bis).
-- Respuesta del panelista a "¿Estas en tu apartado / domicilio?" (una vez por visita):
--   Si  -> esa posicion pasa a ser su referencia (pobox/home); sin incidencia. Casa: requiere permiso v4.
--   No  -> el bot manda un recordatorio; incidencia gps_location YA RESUELTA (solo estadistica) con la pregunta,
--          la respuesta y el recordatorio en incident_message.
--   home_declined -> no quiere que guardemos su casa (fila 'declined'); no se vuelve a preguntar.
-- Forward-only sobre 20261123180000 (gps_mark_declaration) y 20261117190000 (gps_erase_panelist_locations);
-- cuerpos vivos verificados iguales al repo antes de aplicar.

-- ------------------------------------------------------------------------------------------------ 1. columnas
ALTER TABLE public.allocation_plan_details
  ADD COLUMN IF NOT EXISTS sent_self_reported_place text,
  ADD COLUMN IF NOT EXISTS received_self_reported_place text;
ALTER TABLE public.allocation_plan_details DROP CONSTRAINT IF EXISTS apd_sent_srp_check;
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT apd_sent_srp_check
  CHECK (sent_self_reported_place IN ('pobox','home','other'));
ALTER TABLE public.allocation_plan_details DROP CONSTRAINT IF EXISTS apd_received_srp_check;
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT apd_received_srp_check
  CHECK (received_self_reported_place IN ('pobox','home','other'));

-- ------------------------------------------------------------------------------------------------ 2. version del permiso
-- Version del ultimo permiso concedido ('v4', 'v3'...), o NULL.
CREATE OR REPLACE FUNCTION public.gps_consent_version(p_panelist_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT c.consent_text_version FROM public.panelist_location_consent c
   WHERE c.panelist_id = p_panelist_id AND c.decision = 'granted'
   ORDER BY c.decided_at DESC, c.id DESC LIMIT 1;
$$;

-- ------------------------------------------------------------------------------------------------ 3. respuesta
-- p_answer: 'yes' | 'no' | 'home_declined'. p_texts: {question, answer, reminder} tal como los vio el panelista.
-- action: reference_saved | reminder | need_v4 | declined_saved | no_location | already_answered | expired | error.
-- Nunca lanza.
CREATE OR REPLACE FUNCTION public.gps_answer_place(p_panelist_id uuid, p_answer text, p_texts jsonb)
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

-- ------------------------------------------------------------------------------------------------ 4. gps_mark_declaration
-- Igual que 20261123180000 + la respuesta de lugar de la visita: se copia a *_self_reported_place y, tras un "No",
-- la declaracion se anade a la incidencia resuelta de la visita.
CREATE OR REPLACE FUNCTION public.gps_mark_declaration(p_detail_id uuid, p_kind text, p_panelist_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_p panelists; v_d allocation_plan_details; v panelist_context; v_consent text;
  v_status text; v_loc uuid; v_warn boolean := false; v_ask_consent boolean := false; v_inc uuid; v_inc_status text;
  v_entry jsonb; v_pl jsonb; v_cd jsonb; v_dist numeric; v_place text; v_place_inc uuid;
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

    -- 2026-11-23 fase 2: lo que el panelista dijo en esta visita (Si -> su sitio, No -> 'other')
    v_place := CASE WHEN v_cd->>'place_answer' IN ('yes','no') THEN v_cd->>'place_answer_kind' END;

    IF p_kind = 'sent' THEN
      UPDATE allocation_plan_details SET sent_location_id = v_loc, sent_gps_status = v_status,
             sent_self_reported_place = COALESCE(v_place, sent_self_reported_place) WHERE id = p_detail_id;
    ELSE
      UPDATE allocation_plan_details SET received_location_id = v_loc, received_gps_status = v_status,
             received_self_reported_place = COALESCE(v_place, received_self_reported_place) WHERE id = p_detail_id;
    END IF;

    -- tras un "No": la declaracion entra en la incidencia resuelta de la visita (no se reabre)
    v_place_inc := NULLIF(v_cd->>'place_incident_id', '')::uuid;
    IF v_cd->>'place_answer' = 'no' AND v_place_inc IS NOT NULL THEN
      UPDATE panelist_incident
         SET payload = jsonb_set(payload, '{declarations}',
                         COALESCE((SELECT jsonb_agg(e) FROM jsonb_array_elements(COALESCE(payload->'declarations', '[]'::jsonb)) e
                                    WHERE NOT (e->>'detail_id' = p_detail_id::text AND e->>'kind' = p_kind)), '[]'::jsonb)
                         || jsonb_build_array(jsonb_build_object('detail_id', p_detail_id, 'kind', p_kind))),
             updated_at = now()
       WHERE id = v_place_inc AND panelist_id = p_panelist_id;
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

    -- incidencia de la visita (una por visita): solo declaraciones SIN posicion; 'far' va al informe.
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

-- ------------------------------------------------------------------------------------------------ 5. borrar mis datos
-- Igual que 20261117190000 + borra las referencias de lugar del panelista y ref_distance_m de sus posiciones.
CREATE OR REPLACE FUNCTION public.gps_erase_panelist_locations(p_panelist_id uuid, p_source text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_p panelists; v_n int;
BEGIN
  IF p_source IS NULL OR p_source NOT IN ('bot','manager') THEN RAISE EXCEPTION 'invalid source'; END IF;
  SELECT * INTO v_p FROM panelists WHERE id = p_panelist_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'panelist not found'; END IF;
  -- misma cola que las escrituras de posicion del panelista (consentimiento / visita)
  PERFORM pg_advisory_xact_lock(hashtext('gps_consent:' || p_panelist_id::text));

  UPDATE declaration_location
     SET latitude = NULL, longitude = NULL, accuracy_m = NULL, distance_m = NULL, nearest_postal_center_id = NULL,
         ref_distance_m = NULL
   WHERE panelist_id = p_panelist_id
     AND (latitude IS NOT NULL OR longitude IS NOT NULL OR accuracy_m IS NOT NULL OR distance_m IS NOT NULL
          OR nearest_postal_center_id IS NOT NULL OR ref_distance_m IS NOT NULL);
  GET DIAGNOSTICS v_n = ROW_COUNT;

  -- 2026-11-23 fase 2: referencias de casa / apartado (incluida la marca 'declined')
  DELETE FROM panelist_location_reference WHERE panelist_id = p_panelist_id;

  -- distancia en las incidencias de GPS (todas, abiertas o cerradas). No se toca updated_at.
  UPDATE panelist_incident
     SET payload = jsonb_set(payload, '{distance_m}', 'null'::jsonb)
   WHERE panelist_id = p_panelist_id AND category = 'gps_location'
     AND jsonb_typeof(payload) = 'object' AND payload ? 'distance_m'
     AND payload->'distance_m' IS DISTINCT FROM 'null'::jsonb;
  UPDATE panelist_incident
     SET payload = jsonb_set(payload, '{ref_distance_m}', 'null'::jsonb)
   WHERE panelist_id = p_panelist_id AND category = 'gps_location'
     AND jsonb_typeof(payload) = 'object' AND payload ? 'ref_distance_m'
     AND payload->'ref_distance_m' IS DISTINCT FROM 'null'::jsonb;

  -- distancia en las visitas GPS vivas (se limpian solas al dia, pero no esperamos)
  UPDATE panelist_context
     SET context_data = jsonb_set(context_data, '{distance_m}', 'null'::jsonb)
   WHERE context_type = 'gps_visit' AND context_data->>'panelist_id' = p_panelist_id::text
     AND context_data ? 'distance_m' AND context_data->'distance_m' IS DISTINCT FROM 'null'::jsonb;

  INSERT INTO gps_erasure_log (account_id, panelist_id, panelist_code, panelist_name, source, rows_erased)
  VALUES (v_p.account_id, p_panelist_id, v_p.panelist_code, v_p.name, p_source, v_n);

  RETURN jsonb_build_object('erased', v_n);
END; $$;

-- ------------------------------------------------------------------------------------------------ 6. permisos
REVOKE ALL ON FUNCTION public.gps_consent_version(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_answer_place(uuid,text,jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_mark_declaration(uuid,text,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_erase_panelist_locations(uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gps_consent_version(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_answer_place(uuid,text,jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_mark_declaration(uuid,text,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_erase_panelist_locations(uuid,text) TO service_role;
