-- Load Balancing v2: politicas de fechas por cuenta/ciudad, POBOX y dias laborables reales.
--
-- Esta migracion se construye por tareas (ver docs/superpowers/specs/2026-10-27-load-balancing-v2-design.md).
-- Parte 1 (base):
--   * columnas de politica: account_config.date_policy ('weekly'|'daily') y pobox_enabled; las ciudades
--     pueden sobrescribirlas (NULL = hereda de la cuenta); cities.balance_rotation_offset;
--   * allocation_plan_details / generated_allocation_plan_details.generation_source ('plan'|'pobox');
--   * is_account_working_day: dia laborable segun weekly_schedule de la cuenta (day_of_week 0=domingo ..
--     6=sabado; sin filas => lunes-viernes) y non_working_days;
--   * working_day_in_range (misma firma) delega en is_account_working_day en vez de asumir lunes-viernes;
--   * effective_city_policy: politica efectiva de una ciudad; POBOX activo fuerza 'daily'.

ALTER TABLE public.account_config
  ADD COLUMN IF NOT EXISTS date_policy text NOT NULL DEFAULT 'daily',
  ADD COLUMN IF NOT EXISTS pobox_enabled boolean NOT NULL DEFAULT false;
ALTER TABLE public.account_config
  DROP CONSTRAINT IF EXISTS account_config_date_policy_check,
  ADD CONSTRAINT account_config_date_policy_check CHECK (date_policy IN ('weekly','daily'));

ALTER TABLE public.cities
  ADD COLUMN IF NOT EXISTS date_policy text NULL,
  ADD COLUMN IF NOT EXISTS pobox_enabled boolean NULL,
  ADD COLUMN IF NOT EXISTS balance_rotation_offset integer NOT NULL DEFAULT 0;
ALTER TABLE public.cities
  DROP CONSTRAINT IF EXISTS cities_date_policy_check,
  ADD CONSTRAINT cities_date_policy_check CHECK (date_policy IN ('weekly','daily'));

ALTER TABLE public.allocation_plan_details
  ADD COLUMN IF NOT EXISTS generation_source text NOT NULL DEFAULT 'plan';
ALTER TABLE public.allocation_plan_details
  DROP CONSTRAINT IF EXISTS allocation_plan_details_generation_source_check,
  ADD CONSTRAINT allocation_plan_details_generation_source_check CHECK (generation_source IN ('plan','pobox'));

ALTER TABLE public.generated_allocation_plan_details
  ADD COLUMN IF NOT EXISTS generation_source text NOT NULL DEFAULT 'plan';
ALTER TABLE public.generated_allocation_plan_details
  DROP CONSTRAINT IF EXISTS generated_allocation_plan_details_generation_source_check,
  ADD CONSTRAINT generated_allocation_plan_details_generation_source_check CHECK (generation_source IN ('plan','pobox'));

CREATE OR REPLACE FUNCTION public.is_account_working_day(p_account_id uuid, p_date date)
RETURNS boolean
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT NOT EXISTS (SELECT 1 FROM public.non_working_days n
                      WHERE n.account_id = p_account_id AND n.postal_center_id IS NULL AND n.date = p_date)
     AND CASE
           WHEN EXISTS (SELECT 1 FROM public.weekly_schedule w WHERE w.account_id = p_account_id)
           THEN EXISTS (SELECT 1 FROM public.weekly_schedule w
                         WHERE w.account_id = p_account_id
                           AND w.day_of_week = EXTRACT(dow FROM p_date)::int
                           AND w.is_working_day)
           ELSE EXTRACT(isodow FROM p_date) <= 5
         END;
$$;

CREATE OR REPLACE FUNCTION public.working_day_in_range(
  p_account_id uuid, p_preferred date, p_from date, p_to date)
RETURNS date
LANGUAGE sql STABLE
SET search_path = public
AS $$
  -- Dia laborable de la cuenta mas cercano a p_preferred dentro de [p_from, p_to]:
  -- primero el propio p_preferred, luego hacia delante, luego hacia atras. NULL si no hay ninguno.
  WITH days AS (
    SELECT d::date AS d
      FROM generate_series(p_from, p_to, interval '1 day') d
     WHERE public.is_account_working_day(p_account_id, d::date)
  )
  SELECT d FROM days
   ORDER BY CASE WHEN d = p_preferred THEN 0 WHEN d > p_preferred THEN 1 ELSE 2 END,
            abs(d - p_preferred)
   LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.effective_city_policy(p_city_id uuid)
RETURNS TABLE(account_id uuid, date_policy text, pobox_enabled boolean)
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT c.account_id,
         CASE WHEN COALESCE(c.pobox_enabled, ac.pobox_enabled, false) THEN 'daily'
              ELSE COALESCE(c.date_policy, ac.date_policy, 'daily') END,
         COALESCE(c.pobox_enabled, ac.pobox_enabled, false)
    FROM public.cities c
    LEFT JOIN public.account_config ac ON ac.account_id = c.account_id
   WHERE c.id = p_city_id;
$$;

-- Parte 2 (vista diaria): carga por nodo y dia para la vista dia/mes del balanceo.
-- Una fila por (nodo con ciudad, dia del periodo). SECURITY DEFINER (omite RLS), por eso:
--   * todas las lecturas se filtran por p_account_id;
--   * guarda: con sesion de usuario (auth.uid() no nulo) solo se permite a miembros de p_account_id o a
--     superadmin (mismo patron que generate_reassignment_proposals / list_reroute_candidates); con
--     auth.uid() NULL (llamadas internas / service_role) se permite, como en esas funciones;
--   * se revoca EXECUTE a PUBLIC/anon para que una peticion anonima (uid NULL) no la alcance.
CREATE OR REPLACE FUNCTION public.rpc_get_node_load_by_day(p_account_id uuid, p_start_date date, p_end_date date)
RETURNS TABLE(city_id uuid, city_name text, node_id uuid, node_code text, panelist_name text, day date,
              shipment_count integer, pending_count integer, is_working_day boolean, is_unavailable boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_superadmin()
     AND p_account_id IS DISTINCT FROM (SELECT p.account_id FROM public.profiles p WHERE p.id = auth.uid()) THEN
    RAISE EXCEPTION 'No autorizado para esta cuenta' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH days AS (
    SELECT d::date AS d, public.is_account_working_day(p_account_id, d::date) AS wd
      FROM generate_series(p_start_date, p_end_date, interval '1 day') d
  ),
  nds AS (
    SELECT n.id, n.auto_id, c.id AS cid, c.name AS cname,
           (SELECT pa.name::text FROM public.panelists pa
             WHERE pa.node_id = n.id AND pa.account_id = p_account_id AND pa.status = 'active'
             ORDER BY pa.created_at LIMIT 1) AS pname
      FROM public.nodes n
      JOIN public.cities c ON c.id = n.city_id AND c.account_id = p_account_id
     WHERE n.account_id = p_account_id
  ),
  ship AS (
    SELECT a.origin_node_id AS nid, a.fecha_programada AS d,
           count(*)::int AS total, (count(*) FILTER (WHERE a.status = 'pending'))::int AS pend
      FROM public.allocation_plan_details a
     WHERE a.account_id = p_account_id
       AND a.fecha_programada BETWEEN p_start_date AND p_end_date
     GROUP BY a.origin_node_id, a.fecha_programada
  ),
  una AS (
    SELECT DISTINCT pa.node_id AS nid, dd.d
      FROM public.panelist_unavailability u
      JOIN public.panelists pa ON pa.id = u.panelist_id AND pa.account_id = p_account_id AND pa.status = 'active'
      JOIN days dd ON dd.d BETWEEN u.start_date AND u.end_date
     WHERE u.account_id = p_account_id AND u.status = 'active' AND pa.node_id IS NOT NULL
  )
  SELECT nds.cid, nds.cname, nds.id, nds.auto_id, nds.pname, days.d,
         COALESCE(ship.total, 0), COALESCE(ship.pend, 0), days.wd, (una.nid IS NOT NULL)
    FROM nds
    CROSS JOIN days
    LEFT JOIN ship ON ship.nid = nds.id AND ship.d = days.d
    LEFT JOIN una  ON una.nid  = nds.id AND una.d  = days.d
   ORDER BY nds.cname, nds.auto_id, days.d;
END;
$$;
REVOKE ALL ON FUNCTION public.rpc_get_node_load_by_day(uuid, date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_get_node_load_by_day(uuid, date, date) TO authenticated, service_role;
