-- GPS al declarar: el panelista puede borrar el mismo sus datos de ubicacion (boton del bot, Ayuda -> Permiso
-- de ubicacion). Forward-only sobre 20261117150000 / 151000 / 170000.
-- 1) Tabla gps_erasure_log: constancia de cada borrado (quien, cuando, desde donde, cuantas filas). Sobrevive al
--    borrado del panelista y de la cuenta (FKs ON DELETE SET NULL + instantanea panelist_code / panelist_name).
--    RLS de lectura por cuenta como las demas tablas GPS; escrituras solo via la funcion (service_role).
-- 2) gps_erase_panelist_locations(p_panelist_id, p_source): en declaration_location del panelista pone a NULL
--    latitude, longitude, accuracy_m, distance_m y nearest_postal_center_id. Se conservan la fila, su status y sus
--    fechas: las declaraciones mantienen su estado GPS para el estudio. Borra tambien distance_m del payload de
--    sus incidencias gps_location y de sus visitas GPS vivas (panelist_context 'gps_visit').
--    NO borra el historico de permisos (panelist_location_consent): es la prueba legal de lo que decidio.
--    Devuelve {erased: n} (filas de declaration_location que tenian algun dato de ubicacion). Idempotente.

-- 1. Registro de borrados
CREATE TABLE IF NOT EXISTS public.gps_erasure_log (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid,
  panelist_id uuid,
  panelist_code text,
  panelist_name text,
  requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  source text NOT NULL,
  rows_erased int NOT NULL DEFAULT 0,
  CONSTRAINT gps_erasure_log_pkey PRIMARY KEY (id),
  CONSTRAINT gel_source_check CHECK (source IN ('bot','manager')),
  CONSTRAINT gel_panelist_fkey FOREIGN KEY (panelist_id) REFERENCES public.panelists(id) ON DELETE SET NULL,
  CONSTRAINT gel_account_fkey FOREIGN KEY (account_id) REFERENCES public.accounts(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_gel_account ON public.gps_erasure_log (account_id, requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_gel_panelist ON public.gps_erasure_log (panelist_id);

ALTER TABLE public.gps_erasure_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gel_select ON public.gps_erasure_log;
CREATE POLICY gel_select ON public.gps_erasure_log
  FOR SELECT USING (account_id = current_user_account_id() OR is_superadmin());

REVOKE ALL ON public.gps_erasure_log FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.gps_erasure_log TO authenticated;
GRANT ALL ON public.gps_erasure_log TO service_role;

-- 2. Borrado de los datos de ubicacion del panelista
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
     SET latitude = NULL, longitude = NULL, accuracy_m = NULL, distance_m = NULL, nearest_postal_center_id = NULL
   WHERE panelist_id = p_panelist_id
     AND (latitude IS NOT NULL OR longitude IS NOT NULL OR accuracy_m IS NOT NULL OR distance_m IS NOT NULL
          OR nearest_postal_center_id IS NOT NULL);
  GET DIAGNOSTICS v_n = ROW_COUNT;

  -- distancia en las incidencias de GPS (todas, abiertas o cerradas). No se toca updated_at: no es una
  -- novedad para el gestor.
  UPDATE panelist_incident
     SET payload = jsonb_set(payload, '{distance_m}', 'null'::jsonb)
   WHERE panelist_id = p_panelist_id AND category = 'gps_location'
     AND jsonb_typeof(payload) = 'object' AND payload ? 'distance_m'
     AND payload->'distance_m' IS DISTINCT FROM 'null'::jsonb;

  -- distancia en las visitas GPS vivas (se limpian solas al dia, pero no esperamos)
  UPDATE panelist_context
     SET context_data = jsonb_set(context_data, '{distance_m}', 'null'::jsonb)
   WHERE context_type = 'gps_visit' AND context_data->>'panelist_id' = p_panelist_id::text
     AND context_data ? 'distance_m' AND context_data->'distance_m' IS DISTINCT FROM 'null'::jsonb;

  INSERT INTO gps_erasure_log (account_id, panelist_id, panelist_code, panelist_name, source, rows_erased)
  VALUES (v_p.account_id, p_panelist_id, v_p.panelist_code, v_p.name, p_source, v_n);

  RETURN jsonb_build_object('erased', v_n);
END; $$;

REVOKE ALL ON FUNCTION public.gps_erase_panelist_locations(uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gps_erase_panelist_locations(uuid,text) TO service_role;
