-- Carrier Link fase 1, tarea 6: emision de demandas.
-- cl_demands / cl_plan_quotas / cl_plans solo se escriben desde funciones SECURITY DEFINER.

-- Calendario local de emision por conector (evita interferir con la base de datos del carrier).
CREATE OR REPLACE FUNCTION public.cl_is_valid_timezone(p_tz text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path = public, extensions
AS $$ SELECT p_tz IS NULL OR EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = p_tz) $$;

ALTER TABLE public.cl_feeds
  ADD COLUMN emit_days smallint[] NOT NULL DEFAULT '{1}',
  ADD COLUMN emit_hour smallint NOT NULL DEFAULT 3,
  ADD COLUMN emit_timezone text,   -- NULL = zona horaria de la cuenta
  ADD CONSTRAINT cl_feeds_emit_days_valid CHECK (cardinality(emit_days) >= 1 AND emit_days <@ ARRAY[1,2,3,4,5,6,7]::smallint[]),
  ADD CONSTRAINT cl_feeds_emit_hour_valid CHECK (emit_hour BETWEEN 0 AND 23),
  ADD CONSTRAINT cl_feeds_emit_timezone_valid CHECK (public.cl_is_valid_timezone(emit_timezone));

-- Predicado unico de "punto de carrier activo" (lo usan cl_plan_missing_points y cl_build_demand).
CREATE OR REPLACE FUNCTION public.cl_active_points(p_account_id uuid, p_carrier_id uuid)
 RETURNS TABLE (city_id uuid, e2e_role text, place_ref text, mode_ref text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
  SELECT pc.city_id, r.e2e_role::text, r.carrier_place_ref::text, r.carrier_mode_ref::text
    FROM public.readers r
    JOIN public.postal_centers pc ON pc.id = r.postal_center_id
   WHERE r.account_id = p_account_id
     AND r.capture_source = 'carrier_scan'
     AND r.deleted_at IS NULL
     AND r.is_active IS NOT FALSE
     AND r.carrier_id = p_carrier_id
     AND pc.city_id IS NOT NULL
$$;

-- Misma logica que antes, ahora apoyada en el predicado compartido.
CREATE OR REPLACE FUNCTION public.cl_plan_missing_points(p_plan_id uuid)
 RETURNS TABLE (city_id uuid, city_name text, missing text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE v_plan public.cl_plans;
BEGIN
  v_plan := public.cl_plan_authorize(p_plan_id, 'view');
  RETURN QUERY
  WITH pts AS (
    SELECT a.city_id AS cid, a.e2e_role
      FROM public.cl_active_points(v_plan.account_id, v_plan.carrier_id) a
  ), need AS (
    SELECT DISTINCT q.origin_city_id AS cid, 'origin'::text AS kind
      FROM public.cl_plan_quotas q WHERE q.plan_id = p_plan_id
    UNION
    SELECT DISTINCT q.destination_city_id, 'destination'::text
      FROM public.cl_plan_quotas q WHERE q.plan_id = p_plan_id
  )
  SELECT n.cid, c.name::text, n.kind
    FROM need n
    JOIN public.cities c ON c.id = n.cid
   WHERE NOT EXISTS (
     SELECT 1 FROM pts p
      WHERE p.cid = n.cid
        AND p.e2e_role = ANY (CASE n.kind WHEN 'origin' THEN ARRAY['origin','both'] ELSE ARRAY['destination','both'] END))
   ORDER BY c.name, n.kind;
END $$;

-- Construye la demanda de un plan para unas cuotas pending. Interna: sin grants.
CREATE OR REPLACE FUNCTION public.cl_build_demand(p_plan_id uuid, p_quota_ids uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_plan public.cl_plans;
  v_id uuid := gen_random_uuid();
  v_carrier text;
  v_pcode text;
  v_products jsonb;
  v_strata jsonb;
  v_ids uuid[];
  v_sched jsonb;
BEGIN
  SELECT * INTO v_plan FROM public.cl_plans WHERE id = p_plan_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'plan not found' USING ERRCODE = '22023'; END IF;
  IF v_plan.feed_id IS NULL THEN RAISE EXCEPTION 'CL_NO_FEED: plan has no feed' USING ERRCODE = '22023'; END IF;
  SELECT jsonb_build_object('days', to_jsonb(f.emit_days), 'hour', f.emit_hour,
                            'timezone', COALESCE(f.emit_timezone, a.timezone))
    INTO v_sched
    FROM public.cl_feeds f JOIN public.accounts a ON a.id = f.account_id
   WHERE f.id = v_plan.feed_id;
  SELECT code INTO v_carrier FROM public.carriers WHERE id = v_plan.carrier_id;
  SELECT code INTO v_pcode FROM public.products WHERE id = v_plan.product_id;

  SELECT COALESCE(jsonb_agg(m.carrier_value ORDER BY m.carrier_value), to_jsonb(ARRAY[v_pcode]))
    INTO v_products
    FROM public.cl_value_mappings m
   WHERE m.account_id = v_plan.account_id AND m.carrier_id = v_plan.carrier_id
     AND m.kind = 'product' AND m.onems_value = v_pcode;
  IF jsonb_array_length(v_products) = 0 THEN v_products := to_jsonb(ARRAY[v_pcode]); END IF;

  WITH q AS (
    SELECT x.*, (x.samples_planned + x.samples_carried_in - x.samples_obtained) AS req
      FROM public.cl_plan_quotas x
     WHERE x.plan_id = p_plan_id AND x.id = ANY (p_quota_ids) AND x.status = 'pending'
  ), ok AS (SELECT * FROM q WHERE req > 0)
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'stratum_id', ok.id,
           'period', jsonb_build_object('start', ok.period_start, 'end', ok.period_end,
                       'iso_week', ok.iso_year || '-W' || lpad(ok.iso_week::text, 2, '0')),
           'start_points', COALESCE((SELECT jsonb_agg(jsonb_build_object('place_ref', p.place_ref, 'mode_ref', p.mode_ref)
                                        ORDER BY p.place_ref, p.mode_ref)
                              FROM public.cl_active_points(v_plan.account_id, v_plan.carrier_id) p
                             WHERE p.city_id = ok.origin_city_id AND p.e2e_role IN ('origin','both')), '[]'::jsonb),
           'end_points', COALESCE((SELECT jsonb_agg(jsonb_build_object('place_ref', p.place_ref, 'mode_ref', p.mode_ref)
                                        ORDER BY p.place_ref, p.mode_ref)
                              FROM public.cl_active_points(v_plan.account_id, v_plan.carrier_id) p
                             WHERE p.city_id = ok.destination_city_id AND p.e2e_role IN ('destination','both')), '[]'::jsonb),
           'samples_required', ok.req,
           'candidates_requested', ceil(ok.req * v_plan.oversampling_factor)::integer
         ) ORDER BY ok.period_start, ok.id), '[]'::jsonb),
         COALESCE(array_agg(ok.id), ARRAY[]::uuid[])
    INTO v_strata, v_ids
    FROM ok;

  IF jsonb_array_length(v_strata) = 0 THEN RETURN NULL; END IF;

  INSERT INTO public.cl_demands (id, account_id, plan_id, feed_id, status, random_seed, payload)
  VALUES (v_id, v_plan.account_id, p_plan_id, v_plan.feed_id, 'open',
          encode(gen_random_bytes(16), 'hex'),
          jsonb_build_object('schema_version', '1.1', 'demand_id', v_id, 'carrier', v_carrier,
                             'products', v_products, 'include_all_scans', v_plan.feed_diagnosis,
                             'schedule', v_sched,
                             'strata', v_strata));

  UPDATE public.cl_plan_quotas SET status = 'open', demands_count = demands_count + 1 WHERE id = ANY (v_ids);
  RETURN v_id;
END $$;

-- Emision periodica. Devuelve el numero de demandas emitidas.
-- El cron corre cada hora (solo lee tablas de ONEMS, es barato); el calendario local del conector
-- (emit_days / emit_hour / emit_timezone) decide cuando se emite de verdad.
CREATE OR REPLACE FUNCTION public.cl_emit_due_demands(p_now timestamptz DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  r record;
  v_local timestamp;
  v_slot timestamptz;
  v_ids uuid[];
  v_demand uuid;
  v_n integer := 0;
BEGIN
  FOR r IN
    SELECT p.id, p.close_lag_days, f.emit_days, f.emit_hour,
           COALESCE(f.emit_timezone, a.timezone) AS tz
      FROM public.cl_plans p
      JOIN public.accounts a ON a.id = p.account_id
      JOIN public.cl_feeds f ON f.id = p.feed_id
     WHERE p.status = 'active' AND f.status IN ('active','testing')
     ORDER BY p.created_at, p.id
  LOOP
    v_local := p_now AT TIME ZONE r.tz;
    CONTINUE WHEN extract(isodow FROM v_local)::smallint <> ALL (r.emit_days)
               OR extract(hour FROM v_local)::smallint <> r.emit_hour;

    -- Un solo hueco horario local por plan.
    v_slot := date_trunc('hour', v_local) AT TIME ZONE r.tz;
    CONTINUE WHEN EXISTS (SELECT 1 FROM public.cl_demands d
                           WHERE d.plan_id = r.id AND d.requested_at >= v_slot
                             AND d.requested_at < v_slot + interval '1 hour');

    -- Cuotas vencidas sin nada que pedir (requerido <= 0): se dan por cumplidas.
    UPDATE public.cl_plan_quotas q SET status = 'fulfilled'
     WHERE q.plan_id = r.id AND q.status = 'pending'
       AND q.period_end + r.close_lag_days <= v_local::date
       AND q.samples_planned + q.samples_carried_in - q.samples_obtained <= 0;

    SELECT array_agg(q.id) INTO v_ids
      FROM public.cl_plan_quotas q
     WHERE q.plan_id = r.id AND q.status = 'pending'
       AND q.period_end + r.close_lag_days <= v_local::date;

    IF v_ids IS NOT NULL THEN
      v_demand := public.cl_build_demand(r.id, v_ids);
      IF v_demand IS NOT NULL THEN
        UPDATE public.cl_demands SET requested_at = p_now WHERE id = v_demand;
        v_n := v_n + 1;
      END IF;
    END IF;
  END LOOP;

  -- Cierre de planes cuya ventana (end_date + close_lag_days) ya paso y no tienen cuotas pending/open.
  UPDATE public.cl_plans p SET status = 'closed'
    FROM public.accounts a, public.cl_feeds f
   WHERE a.id = p.account_id AND f.id = p.feed_id AND p.status = 'active'
     AND p.end_date + p.close_lag_days < (p_now AT TIME ZONE COALESCE(f.emit_timezone, a.timezone))::date
     AND NOT EXISTS (SELECT 1 FROM public.cl_plan_quotas q WHERE q.plan_id = p.id AND q.status IN ('pending','open'));

  RETURN v_n;
END $$;

-- cl_is_valid_timezone se usa en un CHECK de cl_feeds: debe ser ejecutable por quien inserta (es inocua).
REVOKE ALL ON FUNCTION public.cl_active_points(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cl_build_demand(uuid, uuid[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cl_emit_due_demands(timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cl_emit_due_demands(timestamptz) TO service_role;

-- pg_cron (idempotente): sin token ni HTTP.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cl-emit-demands') THEN
    PERFORM cron.unschedule('cl-emit-demands');
  END IF;
  PERFORM cron.schedule('cl-emit-demands', '15 * * * *', 'SELECT public.cl_emit_due_demands();');
END $$;
