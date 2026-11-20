-- Carrier Link fase 2, revision final (I3): lugares/modos escaneados sin punto de lectura, agregados en el servidor.
-- Antes la web leia cl_batch_scans fila a fila (.limit(5000), que PostgREST corta en 1.000) y sin indice por cuenta:
-- recorrido completo de la tabla en cada apertura de Reading Points. Ahora:
-- 1. cl_unknown_places(cuenta, carrier, dias): lecturas sin lector (reader_id NULL) de los ultimos p_days dias (scan_at)
--    de lotes cuyo plan es de ese carrier (cl_batches -> cl_demands -> cl_plans), sin lugar vacio, agrupadas por lugar
--    y modo recortados (modo vacio = NULL), de mas a menos lecturas, como mucho 500 filas.
--    Autorizacion: superadmin, o cuenta propia con View en cl_reading_points o cl_monitor. Si no, 42501 CL_FORBIDDEN
--    (igual para cuenta ajena o inexistente).
-- 2. Indice parcial cl_batch_scans (account_id, scan_at) WHERE reader_id IS NULL para esa consulta.

CREATE INDEX IF NOT EXISTS cl_batch_scans_unknown_place_idx
  ON public.cl_batch_scans (account_id, scan_at)
  WHERE reader_id IS NULL;

CREATE OR REPLACE FUNCTION public.cl_unknown_places(p_account_id uuid, p_carrier_id uuid, p_days integer DEFAULT 90)
 RETURNS TABLE(place_ref text, mode_ref text, readings bigint)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_days integer := LEAST(GREATEST(COALESCE(p_days, 90), 1), 366);
BEGIN
  IF p_account_id IS NULL
     OR NOT (public.is_superadmin()
             OR (p_account_id = public.current_user_account_id()
                 AND public.has_any_access(p_account_id, 'view', 'cl_reading_points', 'cl_monitor'))) THEN
    RAISE EXCEPTION 'CL_FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT u.place, u.mode, count(*)::bigint
    FROM (SELECT btrim(s.place_ref) AS place, NULLIF(btrim(s.mode_ref), '') AS mode
            FROM public.cl_batch_scans s
            JOIN public.cl_batches b ON b.id = s.batch_id
            JOIN public.cl_demands d ON d.id = b.demand_id
            JOIN public.cl_plans p ON p.id = d.plan_id
           WHERE s.account_id = p_account_id
             AND s.reader_id IS NULL
             AND s.scan_at >= now() - make_interval(days => v_days)
             AND p.carrier_id = p_carrier_id
             AND NULLIF(btrim(s.place_ref), '') IS NOT NULL) u
   GROUP BY u.place, u.mode
   ORDER BY count(*) DESC, u.place, u.mode NULLS FIRST
   LIMIT 500;
END $$;
REVOKE ALL ON FUNCTION public.cl_unknown_places(uuid, uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cl_unknown_places(uuid, uuid, integer) TO authenticated;
