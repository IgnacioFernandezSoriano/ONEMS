-- Posicion GPS al declarar envios y recepciones (spec docs/superpowers/specs/2026-11-17-gps-declaracion-design.md).
-- Forward-only. NO toca el baseline.
-- Toda la logica vive en BD: el bot (n8n, service_role) solo llama a estas funciones.
-- Regla de oro: una declaracion NUNCA se bloquea ni falla por el GPS (gps_mark_declaration nunca lanza).
-- Visita = fila panelist_context (context_type 'gps_visit'), valida 30 min desde created_at.
-- Umbrales: precision 200 m; "lejos" = distancia - precision > 500 m; ubicacion vieja > 5 min.

-- ============================================================================================================
-- 1. Tablas
-- ============================================================================================================
-- Historico de decisiones de permiso (nunca se borra). Decision vigente = ultima fila del panelista.
CREATE TABLE IF NOT EXISTS public.panelist_location_consent (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  panelist_id uuid NOT NULL,
  telegram_id text,
  decision text NOT NULL,
  decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  language text,
  consent_text_version text,
  consent_text text,
  telegram_message_id text,
  source text NOT NULL DEFAULT 'bot',
  CONSTRAINT panelist_location_consent_pkey PRIMARY KEY (id),
  CONSTRAINT plc_decision_check CHECK (decision IN ('granted','denied')),
  CONSTRAINT plc_source_check CHECK (source IN ('bot')),
  CONSTRAINT plc_panelist_fkey FOREIGN KEY (panelist_id) REFERENCES public.panelists(id) ON DELETE CASCADE,
  CONSTRAINT plc_account_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_plc_panelist_decided ON public.panelist_location_consent (panelist_id, decided_at DESC);
CREATE INDEX IF NOT EXISTS idx_plc_account ON public.panelist_location_consent (account_id);

-- Una fila por posicion recibida. latitude/longitude se ponen a NULL a los 12 meses (gps_purge_coordinates).
CREATE TABLE IF NOT EXISTS public.declaration_location (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  panelist_id uuid NOT NULL,
  telegram_id text,
  captured_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  latitude numeric(10,7),
  longitude numeric(10,7),
  accuracy_m numeric,
  nearest_postal_center_id uuid,
  distance_m numeric,
  status text NOT NULL,
  telegram_message_id text,
  CONSTRAINT declaration_location_pkey PRIMARY KEY (id),
  CONSTRAINT dl_status_check CHECK (status IN ('ok','far','low_accuracy','no_reference')),
  CONSTRAINT dl_panelist_fkey FOREIGN KEY (panelist_id) REFERENCES public.panelists(id) ON DELETE CASCADE,
  CONSTRAINT dl_account_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE,
  CONSTRAINT dl_center_fkey FOREIGN KEY (nearest_postal_center_id) REFERENCES public.postal_centers(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_dl_panelist_received ON public.declaration_location (panelist_id, received_at DESC);
CREATE INDEX IF NOT EXISTS idx_dl_account_captured ON public.declaration_location (account_id, captured_at);
CREATE INDEX IF NOT EXISTS idx_dl_purge ON public.declaration_location (captured_at) WHERE latitude IS NOT NULL;

-- RLS por account_id, mismo patron que panelist_incident. Solo lectura para la app: las escrituras van por
-- las funciones SECURITY DEFINER (service_role). El permiso no se borra ni se edita nunca.
ALTER TABLE public.panelist_location_consent ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.declaration_location ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS plc_select ON public.panelist_location_consent;
CREATE POLICY plc_select ON public.panelist_location_consent
  FOR SELECT USING (account_id = current_user_account_id() OR is_superadmin());
DROP POLICY IF EXISTS dl_select ON public.declaration_location;
CREATE POLICY dl_select ON public.declaration_location
  FOR SELECT USING (account_id = current_user_account_id() OR is_superadmin());

REVOKE ALL ON public.panelist_location_consent FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.declaration_location FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.panelist_location_consent TO authenticated;
GRANT SELECT ON public.declaration_location TO authenticated;
GRANT ALL ON public.panelist_location_consent TO service_role;
GRANT ALL ON public.declaration_location TO service_role;

-- ============================================================================================================
-- 2. Marca en cada declaracion (NULL = antes del GPS)
-- ============================================================================================================
ALTER TABLE public.allocation_plan_details
  ADD COLUMN IF NOT EXISTS sent_location_id uuid,
  ADD COLUMN IF NOT EXISTS sent_gps_status text,
  ADD COLUMN IF NOT EXISTS received_location_id uuid,
  ADD COLUMN IF NOT EXISTS received_gps_status text;

ALTER TABLE public.allocation_plan_details DROP CONSTRAINT IF EXISTS apd_sent_location_fkey;
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT apd_sent_location_fkey
  FOREIGN KEY (sent_location_id) REFERENCES public.declaration_location(id) ON DELETE SET NULL;
ALTER TABLE public.allocation_plan_details DROP CONSTRAINT IF EXISTS apd_received_location_fkey;
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT apd_received_location_fkey
  FOREIGN KEY (received_location_id) REFERENCES public.declaration_location(id) ON DELETE SET NULL;

ALTER TABLE public.allocation_plan_details DROP CONSTRAINT IF EXISTS apd_sent_gps_status_check;
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT apd_sent_gps_status_check CHECK (sent_gps_status IN
  ('ok','far','low_accuracy','no_reference','no_location','gps_unavailable','no_consent','no_answer'));
ALTER TABLE public.allocation_plan_details DROP CONSTRAINT IF EXISTS apd_received_gps_status_check;
ALTER TABLE public.allocation_plan_details ADD CONSTRAINT apd_received_gps_status_check CHECK (received_gps_status IN
  ('ok','far','low_accuracy','no_reference','no_location','gps_unavailable','no_consent','no_answer'));

CREATE INDEX IF NOT EXISTS idx_apd_sent_location ON public.allocation_plan_details (sent_location_id) WHERE sent_location_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_apd_received_location ON public.allocation_plan_details (received_location_id) WHERE received_location_id IS NOT NULL;

-- ============================================================================================================
-- 3. Categoria de incidencia 'gps_location'
-- ============================================================================================================
ALTER TABLE public.panelist_incident DROP CONSTRAINT IF EXISTS pi_category_check;
ALTER TABLE public.panelist_incident ADD CONSTRAINT pi_category_check CHECK (category IN (
  'missing_materials','unreadable_label_receipt','parcel_damaged','parcel_returned',
  'how_to_send','unavailability_request','tag_photo_problem','contact_data_change','other','gps_location'));

-- Igual que la version de 20261020170000 (verificada igual a la viva el 2026-11-17), con 'gps_location'.
CREATE OR REPLACE FUNCTION public.insert_panelist_incident_auto(
  p_panelist_id uuid, p_category text, p_description text DEFAULT NULL,
  p_payload jsonb DEFAULT NULL, p_detail_id uuid DEFAULT NULL,
  p_status text DEFAULT 'auto_resolved')
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_account uuid; v_detail_account uuid; v_new uuid;
BEGIN
  IF p_status IS NULL OR p_status NOT IN ('open','auto_resolved') THEN
    RAISE EXCEPTION 'invalid status'; END IF;
  IF p_category IS NULL OR p_category NOT IN ('missing_materials','unreadable_label_receipt',
      'parcel_damaged','parcel_returned','how_to_send','unavailability_request',
      'tag_photo_problem','contact_data_change','other','gps_location') THEN
    RAISE EXCEPTION 'invalid category'; END IF;
  SELECT account_id INTO v_account FROM panelists WHERE id = p_panelist_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'panelist not found'; END IF;
  -- Guarda multi-tenant ANTES de comparar la muestra: un usuario de otra cuenta no puede
  -- averiguar a que cuenta pertenece una muestra por el mensaje de error.
  PERFORM assert_same_account(v_account);
  IF p_detail_id IS NOT NULL THEN
    SELECT account_id INTO v_detail_account FROM allocation_plan_details WHERE id = p_detail_id;
    IF v_detail_account IS DISTINCT FROM v_account THEN
      RAISE EXCEPTION 'detail belongs to another account'; END IF;
  END IF;
  INSERT INTO panelist_incident (account_id, panelist_id, category, description, payload,
                                 allocation_plan_detail_id, status, created_via, resolved_at)
  VALUES (v_account, p_panelist_id, p_category, p_description, p_payload,
          p_detail_id, p_status, 'telegram',
          CASE WHEN p_status = 'auto_resolved' THEN now() END)
  RETURNING id INTO v_new;
  RETURN v_new;
END; $$;

REVOKE ALL ON FUNCTION public.insert_panelist_incident_auto(uuid,text,text,jsonb,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.insert_panelist_incident_auto(uuid,text,text,jsonb,uuid,text) TO authenticated, service_role;

-- ============================================================================================================
-- 4. Ayudantes internos (no expuestos)
-- ============================================================================================================
-- Distancia haversine en metros (radio 6371000 m).
CREATE OR REPLACE FUNCTION public.gps_distance_m(p_lat1 numeric, p_lon1 numeric, p_lat2 numeric, p_lon2 numeric)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT round((2 * 6371000 * asin(sqrt(
           power(sin(radians((p_lat2 - p_lat1)::float8) / 2), 2)
         + cos(radians(p_lat1::float8)) * cos(radians(p_lat2::float8))
           * power(sin(radians((p_lon2 - p_lon1)::float8) / 2), 2))))::numeric, 1);
$$;

-- Decision de permiso vigente: 'granted' | 'denied' | NULL (sin responder).
CREATE OR REPLACE FUNCTION public.gps_current_consent(p_panelist_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT decision FROM panelist_location_consent
   WHERE panelist_id = p_panelist_id
   ORDER BY decided_at DESC, id DESC LIMIT 1;
$$;

-- Clave de la visita en panelist_context (columna telegram_id): SIEMPRE derivada del panelista, nunca del
-- telegram_id que pasa el llamador, para que todas las funciones (con o sin telegram_id) caigan en la misma visita.
-- p_telegram_id se ignora a proposito (se mantiene en la firma por compatibilidad interna).
CREATE OR REPLACE FUNCTION public.gps_visit_key(p_panelist_id uuid, p_telegram_id text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT 'gps:panelist:' || p_panelist_id::text;
$$;

-- Posicion de la visita que sigue siendo valida: una posicion cubre declaraciones solo durante 30 min desde que
-- se recibio (received_at), aunque la visita siga viva.
CREATE OR REPLACE FUNCTION public.gps_visit_location(p_context_data jsonb)
RETURNS public.declaration_location LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT dl.* FROM declaration_location dl
   WHERE dl.id = NULLIF(p_context_data->>'location_id', '')::uuid
     AND dl.received_at > now() - interval '30 minutes';
$$;

-- Visita vigente (<30 min) o una nueva. Una visita nueva hereda la ultima posicion 'ok'/'far' del panelista
-- de los ultimos 30 min ("si no hay una posicion valida de los ultimos 30 minutos" se pide); esa posicion solo
-- cubre hasta 30 min despues de su received_at (gps_visit_location).
CREATE OR REPLACE FUNCTION public.gps_get_visit(p_panelist_id uuid, p_telegram_id text)
RETURNS public.panelist_context LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_key text := public.gps_visit_key(p_panelist_id, p_telegram_id); v panelist_context; v_loc declaration_location;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('gps_visit:' || v_key));
  SELECT * INTO v FROM panelist_context
   WHERE telegram_id = v_key AND context_type = 'gps_visit' AND created_at > now() - interval '30 minutes'
   ORDER BY created_at DESC, id DESC LIMIT 1;
  IF FOUND THEN RETURN v; END IF;

  -- limpieza: visitas de hace mas de 1 dia (las de <1 h se guardan para el enlace retroactivo)
  DELETE FROM panelist_context
   WHERE telegram_id = v_key AND context_type = 'gps_visit' AND created_at < now() - interval '1 day';

  SELECT * INTO v_loc FROM declaration_location
   WHERE panelist_id = p_panelist_id AND received_at > now() - interval '30 minutes'
     AND status IN ('ok','far')
   ORDER BY received_at DESC LIMIT 1;

  INSERT INTO panelist_context (telegram_id, context_type, context_data, created_at)
  VALUES (v_key, 'gps_visit', jsonb_build_object(
            'panelist_id', p_panelist_id,
            'location_id', v_loc.id,
            'location_status', v_loc.status,
            'distance_m', v_loc.distance_m,
            'gps_unavailable', false,
            'warned', false,
            'consent_asked', false,
            'low_accuracy_retry', false,
            'incident_id', NULL,
            'details', '[]'::jsonb),
          now())
  RETURNING * INTO v;
  RETURN v;
END; $$;

-- Rehace el payload de la incidencia de GPS a partir de las marcas reales de sus declaraciones y la pasa a
-- auto_resolved si todas quedan 'ok' (solo si sigue abierta). No toca las cerradas por el gestor.
CREATE OR REPLACE FUNCTION public.gps_refresh_incident(p_incident_id uuid, p_distance_m numeric)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_pl jsonb; v_details jsonb; v_all_ok boolean;
BEGIN
  -- las cerradas por el gestor no se tocan
  SELECT payload INTO v_pl FROM panelist_incident
   WHERE id = p_incident_id AND category = 'gps_location' AND status NOT IN ('resolved','dismissed');
  IF NOT FOUND OR v_pl IS NULL OR jsonb_typeof(v_pl->'details') IS DISTINCT FROM 'array' THEN RETURN; END IF;
  SELECT COALESCE(jsonb_agg(jsonb_set(e, '{status}', to_jsonb(COALESCE(
             CASE e->>'kind' WHEN 'sent' THEN d.sent_gps_status ELSE d.received_gps_status END,
             e->>'status'))) ORDER BY o), '[]'::jsonb)
    INTO v_details
    FROM jsonb_array_elements(v_pl->'details') WITH ORDINALITY AS x(e, o)
    LEFT JOIN allocation_plan_details d ON d.id = (e->>'detail_id')::uuid;
  v_all_ok := jsonb_array_length(v_details) > 0
              AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_details) e WHERE e->>'status' IS DISTINCT FROM 'ok');
  UPDATE panelist_incident
     SET payload = jsonb_set(jsonb_set(v_pl, '{details}', v_details), '{distance_m}',
                             COALESCE(to_jsonb(p_distance_m), v_pl->'distance_m', 'null'::jsonb)),
         status = CASE WHEN v_all_ok AND status = 'open' THEN 'auto_resolved' ELSE status END,
         resolved_at = CASE WHEN v_all_ok AND status = 'open' THEN now() ELSE resolved_at END,
         updated_at = now()
   WHERE id = p_incident_id;
END; $$;

-- ============================================================================================================
-- 5. API para el bot (service_role)
-- ============================================================================================================
-- Al pulsar "Confirmar un envio / una recepcion": crea o reutiliza la visita y dice que hay que pedir.
-- need_consent: sin decision y aun no preguntado en esta visita. need_location: permiso concedido, sin posicion
-- valida en la visita y sin "Mi GPS no funciona".
CREATE OR REPLACE FUNCTION public.gps_visit_start(p_panelist_id uuid, p_telegram_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v panelist_context; v_consent text; v_need_consent boolean; v_need_location boolean;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM panelists WHERE id = p_panelist_id) THEN RAISE EXCEPTION 'panelist not found'; END IF;
  v := public.gps_get_visit(p_panelist_id, p_telegram_id);
  v_consent := public.gps_current_consent(p_panelist_id);
  v_need_consent := v_consent IS NULL AND NOT COALESCE((v.context_data->>'consent_asked')::boolean, false);
  v_need_location := v_consent = 'granted'
                     AND (public.gps_visit_location(v.context_data)).id IS NULL
                     AND NOT COALESCE((v.context_data->>'gps_unavailable')::boolean, false);
  IF v_need_consent THEN
    UPDATE panelist_context SET context_data = context_data || '{"consent_asked": true}'::jsonb WHERE id = v.id;
  END IF;
  RETURN jsonb_build_object('need_consent', v_need_consent, 'need_location', COALESCE(v_need_location, false),
                            'consent', v_consent);
END; $$;

-- Registra la decision de permiso (fila nueva siempre). Al pasar a 'denied' abre UNA incidencia para el gestor.
CREATE OR REPLACE FUNCTION public.gps_record_consent(
  p_panelist_id uuid, p_decision text, p_language text, p_text_version text, p_text text, p_message_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_p panelists; v_prev text; v_id uuid; v_inc uuid; v panelist_context;
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
  RETURN jsonb_build_object('consent_id', v_id, 'decision', p_decision, 'incident_id', v_inc,
    'need_location', p_decision = 'granted' AND (public.gps_visit_location(v.context_data)).id IS NULL
                     AND NOT COALESCE((v.context_data->>'gps_unavailable')::boolean, false));
END; $$;

-- Posicion recibida de Telegram. action: 'stale' (mensaje de hace > 5 min, se ignora),
-- 'low_accuracy_retry' (primera posicion poco precisa de la visita: no se guarda, el bot pide reintentar),
-- 'saved' (guardada; enlaza retroactivamente las declaraciones sin posicion de los 30 min anteriores),
-- 'no_consent' (el permiso vigente no es 'granted': no se guarda nada, ni coordenadas).
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

  v_status := CASE
    WHEN p_accuracy IS NULL OR p_accuracy > 200 THEN 'low_accuracy'
    WHEN v_center IS NULL THEN 'no_reference'
    WHEN v_dist - COALESCE(p_accuracy, 0) > 500 THEN 'far'
    ELSE 'ok' END;

  IF v_status = 'low_accuracy' AND NOT COALESCE((v.context_data->>'low_accuracy_retry')::boolean, false) THEN
    UPDATE panelist_context SET context_data = context_data || '{"low_accuracy_retry": true}'::jsonb WHERE id = v.id;
    RETURN jsonb_build_object('action', 'low_accuracy_retry', 'status', 'low_accuracy', 'location_id', NULL,
                              'distance_m', v_dist);
  END IF;

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

  -- Solo las incidencias (aun no cerradas por el gestor) que contienen alguna declaracion enlazada ahora:
  -- payload al dia y auto_resolved si todo queda ok. Las demas no se tocan.
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

-- "Mi GPS no funciona": marca la visita y pasa a gps_unavailable sus declaraciones en no_location.
CREATE OR REPLACE FUNCTION public.gps_set_unavailable(p_panelist_id uuid, p_telegram_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_p panelists; v panelist_context; v_n int; v_inc uuid;
BEGIN
  SELECT * INTO v_p FROM panelists WHERE id = p_panelist_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'panelist not found'; END IF;
  v := public.gps_get_visit(p_panelist_id, p_telegram_id);
  UPDATE panelist_context SET context_data = context_data || '{"gps_unavailable": true}'::jsonb WHERE id = v.id;

  WITH led AS (
    SELECT DISTINCT (e->>'detail_id')::uuid AS detail_id, e->>'kind' AS kind
      FROM jsonb_array_elements(COALESCE(v.context_data->'details', '[]'::jsonb)) e)
  UPDATE allocation_plan_details d
     SET sent_gps_status = CASE WHEN led.kind = 'sent' THEN 'gps_unavailable' ELSE d.sent_gps_status END,
         received_gps_status = CASE WHEN led.kind = 'received' THEN 'gps_unavailable' ELSE d.received_gps_status END
    FROM led
   WHERE d.id = led.detail_id AND d.account_id = v_p.account_id
     AND ((led.kind = 'sent' AND d.sent_gps_status = 'no_location')
       OR (led.kind = 'received' AND d.received_gps_status = 'no_location'));
  GET DIAGNOSTICS v_n = ROW_COUNT;

  v_inc := (v.context_data->>'incident_id')::uuid;
  IF v_inc IS NOT NULL THEN
    PERFORM public.gps_refresh_incident(v_inc, NULL);
  END IF;
  RETURN jsonb_build_object('status', 'gps_unavailable', 'updated', v_n, 'incident_id', v_inc);
END; $$;

-- Marca una declaracion registrada con exito (mismo punto donde el bot escribe sent_at / received_at).
-- warn = true solo la primera vez por visita que queda 'no_location' (el bot avisa "no hemos podido obtener tu
-- posicion"). Abre o amplia la incidencia de la visita. NUNCA lanza: ante cualquier error {status:null, warn:false}.
CREATE OR REPLACE FUNCTION public.gps_mark_declaration(p_detail_id uuid, p_kind text, p_panelist_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_p panelists; v_d allocation_plan_details; v panelist_context; v_consent text;
  v_status text; v_loc uuid; v_warn boolean := false; v_inc uuid; v_inc_status text;
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
    RETURN jsonb_build_object('status', v_status, 'warn', v_warn);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'gps_mark_declaration(%, %, %): %', p_detail_id, p_kind, p_panelist_id, SQLERRM;
    RETURN jsonb_build_object('status', NULL, 'warn', false);
  END;
END; $$;

-- Retencion: coordenadas exactas a NULL a los 12 meses (se conservan distancia, estado y centro).
CREATE OR REPLACE FUNCTION public.gps_purge_coordinates()
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n int;
BEGIN
  UPDATE declaration_location SET latitude = NULL, longitude = NULL
   WHERE captured_at < now() - interval '12 months' AND (latitude IS NOT NULL OR longitude IS NOT NULL);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END; $$;

-- ============================================================================================================
-- 6. Permisos: solo service_role (n8n)
-- ============================================================================================================
REVOKE ALL ON FUNCTION public.gps_distance_m(numeric,numeric,numeric,numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_current_consent(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_visit_key(uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_visit_location(jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_get_visit(uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_refresh_incident(uuid,numeric) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_visit_start(uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_record_consent(uuid,text,text,text,text,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_save_location(uuid,text,numeric,numeric,numeric,timestamptz,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_set_unavailable(uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_mark_declaration(uuid,text,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_purge_coordinates() FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.gps_distance_m(numeric,numeric,numeric,numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_current_consent(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_visit_key(uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_visit_location(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_get_visit(uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_refresh_incident(uuid,numeric) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_visit_start(uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_record_consent(uuid,text,text,text,text,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_save_location(uuid,text,numeric,numeric,numeric,timestamptz,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_set_unavailable(uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_mark_declaration(uuid,text,uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_purge_coordinates() TO service_role;

-- ============================================================================================================
-- 7. pg_cron: borrado mensual de coordenadas (dia 1, 03:00 UTC; idempotente)
-- ============================================================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'gps-purge-coordinates') THEN
    PERFORM cron.unschedule('gps-purge-coordinates');
  END IF;
  PERFORM cron.schedule('gps-purge-coordinates', '0 3 1 * *', 'SELECT public.gps_purge_coordinates()');
END $$;
