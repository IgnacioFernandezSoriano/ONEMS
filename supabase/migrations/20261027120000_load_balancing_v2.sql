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
