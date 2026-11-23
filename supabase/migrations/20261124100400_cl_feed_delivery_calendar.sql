-- Carrier Link v4, tarea 5 (pantallas): calendario de entregas de un conector para la web (Conectores).
-- La pantalla necesita la frecuencia (diaria ... semanal), el proximo periodo a entregar (para proponerlo en la subida
-- manual) y el margen de "no recibido". Esos datos ya los calcula cl_connector_config (tarea 1/3), pero esa funcion es
-- solo service_role. Esta es una envoltura de SOLO LECTURA para authenticated que devuelve un subconjunto, sin
-- equivalencias, puntos ni claves.
--
-- Permiso: superadmin, o la cuenta activa del usuario con View en cl_connectors. Conector ajeno, inexistente, NULL o
-- sin derecho: el mismo 42501 CL_FORBIDDEN (sin oraculo de existencia). Forward-only; no cambia nada existente.

CREATE OR REPLACE FUNCTION public.cl_feed_delivery_calendar(p_feed_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_feed public.cl_feeds;
  v_cfg  jsonb;
BEGIN
  SELECT f.* INTO v_feed FROM public.cl_feeds f WHERE f.id = p_feed_id;
  IF v_feed.id IS NULL
     OR NOT (public.is_superadmin()
             OR (v_feed.account_id = public.current_user_account_id()
                 AND public.has_any_access(v_feed.account_id, 'view', 'cl_connectors'))) THEN
    RAISE EXCEPTION 'CL_FORBIDDEN' USING ERRCODE = '42501';
  END IF;
  v_cfg := public.cl_connector_config(p_feed_id, now());
  RETURN jsonb_build_object(
    'calendar', v_cfg->'calendar',
    'date_timezone', v_cfg->'date_timezone',
    'next_period', v_cfg->'next_period',
    'last_delivery', v_cfg->'last_delivery',
    'missing_grace_hours', public.cl_feed_missing_grace_hours(v_feed.config),
    'max_file_bytes', v_cfg->'limits'->'max_file_bytes');
END $$;

REVOKE ALL ON FUNCTION public.cl_feed_delivery_calendar(uuid) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.cl_feed_delivery_calendar(uuid) TO authenticated;
