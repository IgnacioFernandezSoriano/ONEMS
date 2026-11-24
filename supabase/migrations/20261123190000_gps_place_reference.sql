-- GPS fase 2, Task 1 (plan docs/superpowers/plans/2026-11-23-gps-fase2-pregunta-lugar.md; spec 2026-11-20 §2 bis).
-- Referencias de lugar por panelista (apartado en ciudad POBOX, casa en ciudad sin POBOX) y clasificacion de cada
-- posicion contra la referencia que le toca. Forward-only sobre 20261123180000 (gps_save_location viva = repo).
-- - Sitio correcto: POBOX -> referencia 'pobox' o, si no hay, la oficina mas cercana (como hasta ahora);
--   sin POBOX -> referencia 'home' o, si no hay, 'no_reference' (la oficina no es la referencia correcta).
-- - distance_m sigue siendo la distancia a la oficina (el informe no cambia); ref_kind/reference_id/ref_distance_m
--   dicen contra que se juzgo.
-- - gps_save_location devuelve ademas ask_place (preguntar "¿estas en tu apartado/domicilio?", una vez por visita)
--   y place_kind.

-- ------------------------------------------------------------------------------------------------ 1. referencias
CREATE TABLE IF NOT EXISTS public.panelist_location_reference (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  panelist_id uuid NOT NULL,
  kind text NOT NULL,
  latitude numeric(10,7),
  longitude numeric(10,7),
  captured_at timestamptz NOT NULL DEFAULT now(),
  source text NOT NULL,
  location_id uuid,
  distance_to_postal_center_m numeric,
  needs_review boolean NOT NULL DEFAULT false,
  review_reason text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT panelist_location_reference_pkey PRIMARY KEY (id),
  CONSTRAINT plr_kind_check CHECK (kind IN ('pobox','home')),
  -- 'declined' = el panelista no quiere que guardemos su casa (sin coordenadas, active = false)
  CONSTRAINT plr_source_check CHECK (source IN ('declaration','registration','declined')),
  CONSTRAINT plr_coords_check CHECK (source = 'declined' OR (latitude IS NOT NULL AND longitude IS NOT NULL)),
  CONSTRAINT plr_panelist_fkey FOREIGN KEY (panelist_id) REFERENCES public.panelists(id) ON DELETE CASCADE,
  CONSTRAINT plr_account_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE CASCADE,
  CONSTRAINT plr_location_fkey FOREIGN KEY (location_id) REFERENCES public.declaration_location(id) ON DELETE SET NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_plr_active ON public.panelist_location_reference (panelist_id, kind)
  WHERE active AND source <> 'declined';
CREATE INDEX IF NOT EXISTS idx_plr_account ON public.panelist_location_reference (account_id);

ALTER TABLE public.panelist_location_reference ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS plr_select ON public.panelist_location_reference;
CREATE POLICY plr_select ON public.panelist_location_reference
  FOR SELECT USING (account_id = current_user_account_id() OR is_superadmin());
REVOKE ALL ON public.panelist_location_reference FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.panelist_location_reference TO authenticated;
GRANT ALL ON public.panelist_location_reference TO service_role;

-- ------------------------------------------------------------------------------------------------ 2. columnas y ajustes
ALTER TABLE public.declaration_location
  ADD COLUMN IF NOT EXISTS ref_kind text,
  ADD COLUMN IF NOT EXISTS reference_id uuid,
  ADD COLUMN IF NOT EXISTS ref_distance_m numeric;
ALTER TABLE public.declaration_location DROP CONSTRAINT IF EXISTS dl_ref_kind_check;
ALTER TABLE public.declaration_location ADD CONSTRAINT dl_ref_kind_check
  CHECK (ref_kind IN ('postal_center','pobox','home'));
ALTER TABLE public.declaration_location DROP CONSTRAINT IF EXISTS dl_reference_fkey;
ALTER TABLE public.declaration_location ADD CONSTRAINT dl_reference_fkey
  FOREIGN KEY (reference_id) REFERENCES public.panelist_location_reference(id) ON DELETE SET NULL;

INSERT INTO public.gps_settings (key, value) VALUES
  ('ref_review_pobox_m', 1000), ('ref_review_home_city_m', 5000)
ON CONFLICT (key) DO NOTHING;

-- ------------------------------------------------------------------------------------------------ 3. helpers
-- 'pobox' si la ciudad del nodo (o, sin ciudad, la cuenta) tiene POBOX; si no, 'home'. Nunca lanza.
CREATE OR REPLACE FUNCTION public.gps_place_kind(p_panelist_id uuid)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT CASE WHEN COALESCE(
           (SELECT ecp.pobox_enabled FROM public.panelists p
              JOIN public.nodes n ON n.id = p.node_id
              CROSS JOIN LATERAL public.effective_city_policy(n.city_id) ecp
             WHERE p.id = p_panelist_id AND n.city_id IS NOT NULL),
           (SELECT ac.pobox_enabled FROM public.panelists p
              JOIN public.account_config ac ON ac.account_id = p.account_id
             WHERE p.id = p_panelist_id),
           false) THEN 'pobox' ELSE 'home' END;
$$;

-- Referencia vigente (activa, con coordenadas) del panelista para ese tipo, o NULL.
CREATE OR REPLACE FUNCTION public.gps_active_reference(p_panelist_id uuid, p_kind text)
RETURNS public.panelist_location_reference LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT r.* FROM public.panelist_location_reference r
   WHERE r.panelist_id = p_panelist_id AND r.kind = p_kind AND r.active AND r.source <> 'declined'
   ORDER BY r.created_at DESC LIMIT 1;
$$;

-- ------------------------------------------------------------------------------------------------ 4. gps_save_location
CREATE OR REPLACE FUNCTION public.gps_save_location(
  p_panelist_id uuid, p_telegram_id text, p_lat numeric, p_lon numeric, p_accuracy numeric,
  p_msg_date timestamptz, p_msg_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_p panelists; v panelist_context; v_city uuid;
  v_center uuid; v_dist numeric; v_status text; v_loc uuid; v_inc uuid; v_linked jsonb;
  v_kind text; v_ref panelist_location_reference; v_ref_kind text; v_ref_dist numeric; v_ask boolean := false;
BEGIN
  SELECT * INTO v_p FROM panelists WHERE id = p_panelist_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'panelist not found'; END IF;
  -- Sin permiso concedido nunca se guardan coordenadas.
  IF public.gps_current_consent(p_panelist_id) IS DISTINCT FROM 'granted' THEN
    RETURN jsonb_build_object('action', 'no_consent', 'status', NULL, 'location_id', NULL, 'distance_m', NULL,
                              'ask_place', false, 'place_kind', NULL);
  END IF;
  IF p_lat IS NULL OR p_lon IS NULL OR p_lat NOT BETWEEN -90 AND 90 OR p_lon NOT BETWEEN -180 AND 180 THEN
    RAISE EXCEPTION 'invalid coordinates'; END IF;

  IF p_msg_date IS NOT NULL AND p_msg_date < now() - interval '5 minutes' THEN
    RETURN jsonb_build_object('action', 'stale', 'status', NULL, 'location_id', NULL, 'distance_m', NULL,
                              'ask_place', false, 'place_kind', NULL);
  END IF;

  v := public.gps_get_visit(p_panelist_id, p_telegram_id);

  -- oficina con coordenadas mas cercana de la ciudad del nodo (distance_m, como hasta ahora)
  SELECT n.city_id INTO v_city FROM nodes n WHERE n.id = v_p.node_id;
  SELECT pc.id, public.gps_distance_m(p_lat, p_lon, pc.latitude, pc.longitude)
    INTO v_center, v_dist
    FROM postal_centers pc
   WHERE v_city IS NOT NULL AND pc.city_id = v_city AND pc.account_id = v_p.account_id
     AND pc.latitude IS NOT NULL AND pc.longitude IS NOT NULL AND pc.deleted_at IS NULL
   ORDER BY public.gps_distance_m(p_lat, p_lon, pc.latitude, pc.longitude), pc.id
   LIMIT 1;

  -- 2026-11-23 fase 2: se juzga contra el sitio que le toca
  v_kind := public.gps_place_kind(p_panelist_id);
  v_ref := public.gps_active_reference(p_panelist_id, v_kind);
  IF v_ref.id IS NOT NULL THEN
    v_ref_kind := v_kind;
    v_ref_dist := public.gps_distance_m(p_lat, p_lon, v_ref.latitude, v_ref.longitude);
    v_status := CASE WHEN v_ref_dist > COALESCE(public.gps_setting('ok_radius_m'), 300) THEN 'far' ELSE 'ok' END;
  ELSIF v_kind = 'pobox' THEN
    v_status := public.gps_classify(v_center, v_dist);
    IF v_center IS NOT NULL THEN v_ref_kind := 'postal_center'; v_ref_dist := v_dist; END IF;
  ELSE
    v_status := 'no_reference';
  END IF;

  -- una sola pregunta de lugar por visita: si la posicion no cuadra o, sin POBOX, mientras falte la casa
  IF NOT COALESCE((v.context_data->>'place_asked')::boolean, false)
     AND (v_status = 'far'
          OR (v_kind = 'home' AND v_ref.id IS NULL
              AND NOT EXISTS (SELECT 1 FROM panelist_location_reference r
                               WHERE r.panelist_id = p_panelist_id AND r.kind = 'home' AND r.source = 'declined'))) THEN
    v_ask := true;
  END IF;

  INSERT INTO declaration_location (account_id, panelist_id, telegram_id, captured_at, received_at, latitude,
                                    longitude, accuracy_m, nearest_postal_center_id, distance_m, status,
                                    telegram_message_id, ref_kind, reference_id, ref_distance_m)
  VALUES (v_p.account_id, p_panelist_id, COALESCE(NULLIF(btrim(p_telegram_id), ''), v_p.telegram_id),
          COALESCE(p_msg_date, now()), now(), p_lat, p_lon, p_accuracy, v_center, v_dist, v_status, p_msg_id,
          v_ref_kind, v_ref.id, v_ref_dist)
  RETURNING id INTO v_loc;

  UPDATE panelist_context
     SET context_data = context_data || jsonb_build_object('location_id', v_loc, 'location_status', v_status,
                                                           'distance_m', v_dist)
                        || CASE WHEN v_ask THEN '{"place_asked": true}'::jsonb ELSE '{}'::jsonb END
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

  RETURN jsonb_build_object('action', 'saved', 'status', v_status, 'location_id', v_loc, 'distance_m', v_dist,
                            'ask_place', v_ask, 'place_kind', v_kind);
END; $$;

-- ------------------------------------------------------------------------------------------------ 5. permisos
REVOKE ALL ON FUNCTION public.gps_place_kind(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_active_reference(uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.gps_save_location(uuid,text,numeric,numeric,numeric,timestamptz,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gps_place_kind(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_active_reference(uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.gps_save_location(uuid,text,numeric,numeric,numeric,timestamptz,text) TO service_role;
