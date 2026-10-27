-- Muestras por compensar (deferred samples).
--
-- Cuando el balanceo no puede programar una muestra del plan (ciudad de origen o destino sin panelista, o sin
-- dia valido) la muestra no se pierde: se anota en un registro "por compensar" y se reintroduce mas tarde.
-- Esta migracion (parte 1) aporta:
--   * tabla public.deferred_samples (registro) con RLS por account_id;
--   * generation_source admite tambien 'compensation' (muestras creadas al reintroducir) en
--     allocation_plan_details y generated_allocation_plan_details;
--   * rpc_deferred_samples_summary(account): resumen por ciudad de origen y por plan.
-- Las siguientes partes (RPC de registro/reintroduccion) se anexan a este mismo fichero.

CREATE TABLE IF NOT EXISTS public.deferred_samples (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  plan_id uuid NOT NULL,
  origin_city_id uuid NOT NULL,
  dest_city_id uuid NOT NULL,
  origin_node_id uuid NOT NULL,
  destination_node_id uuid NOT NULL,
  fecha_programada date NOT NULL,
  reason text NOT NULL CHECK (reason IN ('origin_no_panelist','dest_no_panelist','no_valid_day')),
  row_snapshot jsonb NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','reintroduced')),
  waiting_reason text NULL CHECK (waiting_reason IN ('no_origin_panelist','no_dest_panelist','no_capacity','plan_inactive','outside_period')),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid NULL,
  reintroduced_at timestamptz NULL,
  reintroduced_detail_id uuid NULL
);

CREATE INDEX IF NOT EXISTS deferred_samples_account_status_idx ON public.deferred_samples (account_id, status);
CREATE INDEX IF NOT EXISTS deferred_samples_origin_city_status_idx ON public.deferred_samples (origin_city_id, status);
CREATE INDEX IF NOT EXISTS deferred_samples_plan_status_idx ON public.deferred_samples (plan_id, status);

ALTER TABLE public.deferred_samples ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS deferred_samples_select ON public.deferred_samples;
CREATE POLICY deferred_samples_select ON public.deferred_samples
  FOR SELECT TO authenticated
  USING (account_id = public.current_user_account_id() OR public.is_superadmin());

-- generation_source: 'plan' | 'pobox' | 'compensation'
ALTER TABLE public.allocation_plan_details
  DROP CONSTRAINT IF EXISTS allocation_plan_details_generation_source_check,
  ADD CONSTRAINT allocation_plan_details_generation_source_check CHECK (generation_source IN ('plan','pobox','compensation'));

ALTER TABLE public.generated_allocation_plan_details
  DROP CONSTRAINT IF EXISTS generated_allocation_plan_details_generation_source_check,
  ADD CONSTRAINT generated_allocation_plan_details_generation_source_check CHECK (generation_source IN ('plan','pobox','compensation'));

-- Resumen del registro por ciudad de origen y por plan.
CREATE OR REPLACE FUNCTION public.rpc_deferred_samples_summary(p_account_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total int;
  v_by_city jsonb;
  v_by_plan jsonb;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_superadmin()
     AND p_account_id IS DISTINCT FROM (SELECT p.account_id FROM public.profiles p WHERE p.id = auth.uid()) THEN
    RAISE EXCEPTION 'No autorizado para esta cuenta' USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO v_total
    FROM public.deferred_samples d WHERE d.account_id = p_account_id AND d.status = 'pending';

  SELECT COALESCE(jsonb_agg(jsonb_build_object('city_id', x.city_id, 'city_name', x.city_name,
                                               'count', x.cnt, 'waiting_reason', x.waiting_reason)
                            ORDER BY x.city_name), '[]'::jsonb)
    INTO v_by_city
    FROM (
      SELECT d.origin_city_id AS city_id, c.name AS city_name, count(*)::int AS cnt,
             (SELECT d2.waiting_reason FROM public.deferred_samples d2
               WHERE d2.account_id = p_account_id AND d2.status = 'pending'
                 AND d2.origin_city_id = d.origin_city_id AND d2.waiting_reason IS NOT NULL
               GROUP BY d2.waiting_reason ORDER BY count(*) DESC, d2.waiting_reason LIMIT 1) AS waiting_reason
        FROM public.deferred_samples d
        JOIN public.cities c ON c.id = d.origin_city_id
       WHERE d.account_id = p_account_id AND d.status = 'pending'
       GROUP BY d.origin_city_id, c.name
    ) x;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'plan_id', ap.id, 'plan_name', ap.plan_name, 'total_samples', ap.total_samples,
           'scheduled', (SELECT count(*) FROM public.allocation_plan_details a
                          WHERE a.plan_id = ap.id AND a.status IN ('pending','notified')),
           'done', (SELECT count(*) FROM public.allocation_plan_details a
                     WHERE a.plan_id = ap.id AND a.status IN ('sent','received')),
           'deferred', (SELECT count(*) FROM public.deferred_samples d
                         WHERE d.plan_id = ap.id AND d.status = 'pending'),
           'pobox_extra', (SELECT count(*) FROM public.allocation_plan_details a
                            WHERE a.plan_id = ap.id AND a.generation_source = 'pobox'))
         ORDER BY ap.plan_name), '[]'::jsonb)
    INTO v_by_plan
    FROM public.allocation_plans ap
   WHERE ap.account_id = p_account_id
     AND (EXISTS (SELECT 1 FROM public.allocation_plan_details a WHERE a.plan_id = ap.id)
          OR EXISTS (SELECT 1 FROM public.deferred_samples d WHERE d.plan_id = ap.id AND d.status = 'pending'));

  RETURN jsonb_build_object('pending_total', v_total, 'by_city', v_by_city, 'by_plan', v_by_plan);
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_deferred_samples_summary(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_deferred_samples_summary(uuid) TO authenticated, service_role;
