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


-- ---------------------------------------------------------------- endurecimiento del plan
ALTER TABLE public.cl_plans
  ADD CONSTRAINT cl_plans_oversampling_valid CHECK (oversampling_factor BETWEEN 1 AND 100),
  ADD CONSTRAINT cl_plans_close_lag_valid CHECK (close_lag_days BETWEEN 0 AND 365),
  ADD CONSTRAINT cl_plans_total_samples_positive CHECK (total_samples > 0);

-- El estado del plan solo cambia por funciones (cl_plan_activate, cl_emit_due_demands).
REVOKE UPDATE ON public.cl_plans FROM authenticated;
GRANT UPDATE (plan_name, carrier_id, product_id, total_samples, start_date, end_date,
              close_lag_days, oversampling_factor, feed_id, feed_diagnosis)
  ON public.cl_plans TO authenticated;

-- Un INSERT de un usuario siempre nace como borrador (backend/cron/service_role pasan sin cambios).
CREATE OR REPLACE FUNCTION public.cl_plans_force_draft()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path = public, extensions
AS $$
BEGIN
  IF current_setting('role') NOT IN ('none', 'service_role', 'postgres', 'supabase_admin') THEN
    NEW.status := 'draft';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.cl_plans_force_draft() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS cl_plans_force_draft ON public.cl_plans;
CREATE TRIGGER cl_plans_force_draft BEFORE INSERT ON public.cl_plans
  FOR EACH ROW EXECUTE FUNCTION public.cl_plans_force_draft();

-- ---------------------------------------------------------------- helpers internos
-- Zona efectiva: la del conector, o la de la cuenta si es valida, o UTC.
CREATE OR REPLACE FUNCTION public.cl_effective_tz(p_account_id uuid, p_feed_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
  SELECT COALESCE(
    (SELECT f.emit_timezone FROM public.cl_feeds f WHERE f.id = p_feed_id),
    (SELECT a.timezone FROM public.accounts a WHERE a.id = p_account_id AND public.cl_is_valid_timezone(a.timezone)),
    'UTC')
$$;

-- Alerta con tope de una por plan+cuota+tipo y dia.
CREATE OR REPLACE FUNCTION public.cl_raise_alert(p_plan_id uuid, p_quota_id uuid, p_type text, p_severity text, p_details jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.cl_alerts a
              WHERE a.plan_id = p_plan_id AND a.quota_id IS NOT DISTINCT FROM p_quota_id
                AND a.alert_type = p_type AND a.created_at::date = now()::date) THEN
    RETURN;
  END IF;
  INSERT INTO public.cl_alerts (account_id, plan_id, quota_id, alert_type, severity, details)
  SELECT p.account_id, p.id, p_quota_id, p_type, p_severity, p_details
    FROM public.cl_plans p WHERE p.id = p_plan_id;
END $$;

-- Construye la demanda de un plan para unas cuotas pending. Interna: sin grants.
-- Una cuota sin puntos de inicio o de fin queda pending (alerta missing_points) y no entra en la demanda.
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
  v_sched jsonb;
  v_strata jsonb := '[]'::jsonb;
  v_ids uuid[] := ARRAY[]::uuid[];
  q record;
  v_start jsonb;
  v_end jsonb;
  v_req integer;
BEGIN
  SELECT * INTO v_plan FROM public.cl_plans WHERE id = p_plan_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'plan not found' USING ERRCODE = '22023'; END IF;
  IF v_plan.feed_id IS NULL THEN RAISE EXCEPTION 'CL_NO_FEED: plan has no feed' USING ERRCODE = '22023'; END IF;
  SELECT jsonb_build_object('days', to_jsonb(f.emit_days), 'hour', f.emit_hour,
                            'timezone', public.cl_effective_tz(f.account_id, f.id))
    INTO v_sched
    FROM public.cl_feeds f WHERE f.id = v_plan.feed_id;
  SELECT code INTO v_carrier FROM public.carriers WHERE id = v_plan.carrier_id;
  SELECT code INTO v_pcode FROM public.products WHERE id = v_plan.product_id;

  SELECT COALESCE(jsonb_agg(m.carrier_value ORDER BY m.carrier_value), to_jsonb(ARRAY[v_pcode]))
    INTO v_products
    FROM public.cl_value_mappings m
   WHERE m.account_id = v_plan.account_id AND m.carrier_id = v_plan.carrier_id
     AND m.kind = 'product' AND m.onems_value = v_pcode;
  IF jsonb_array_length(v_products) = 0 THEN v_products := to_jsonb(ARRAY[v_pcode]); END IF;

  FOR q IN SELECT x.* FROM public.cl_plan_quotas x
            WHERE x.plan_id = p_plan_id AND x.id = ANY (p_quota_ids) AND x.status = 'pending'
            ORDER BY x.period_start, x.id
  LOOP
    v_req := q.samples_planned + q.samples_carried_in - q.samples_obtained;
    CONTINUE WHEN v_req <= 0;
    SELECT COALESCE(jsonb_agg(jsonb_build_object('place_ref', p.place_ref, 'mode_ref', p.mode_ref)
                              ORDER BY p.place_ref, p.mode_ref), '[]'::jsonb)
      INTO v_start
      FROM public.cl_active_points(v_plan.account_id, v_plan.carrier_id) p
     WHERE p.city_id = q.origin_city_id AND p.e2e_role IN ('origin','both');
    SELECT COALESCE(jsonb_agg(jsonb_build_object('place_ref', p.place_ref, 'mode_ref', p.mode_ref)
                              ORDER BY p.place_ref, p.mode_ref), '[]'::jsonb)
      INTO v_end
      FROM public.cl_active_points(v_plan.account_id, v_plan.carrier_id) p
     WHERE p.city_id = q.destination_city_id AND p.e2e_role IN ('destination','both');
    IF jsonb_array_length(v_start) = 0 OR jsonb_array_length(v_end) = 0 THEN
      PERFORM public.cl_raise_alert(p_plan_id, q.id, 'missing_points', 'high',
        jsonb_build_object('start_points', jsonb_array_length(v_start), 'end_points', jsonb_array_length(v_end)));
      CONTINUE;
    END IF;
    v_strata := v_strata || jsonb_build_array(jsonb_build_object(
      'stratum_id', q.id,
      'period', jsonb_build_object('start', q.period_start, 'end', q.period_end,
                  'iso_week', q.iso_year || '-W' || lpad(q.iso_week::text, 2, '0')),
      'start_points', v_start, 'end_points', v_end,
      'samples_required', v_req,
      'candidates_requested', ceil(v_req * v_plan.oversampling_factor)::integer));
    v_ids := v_ids || q.id;
  END LOOP;

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
-- Sin recuperacion: si se pierde el hueco (cron caido) o la hora local no existe (salto de DST), no se emite
-- hasta el siguiente hueco del calendario; igual para cuotas devueltas a 'pending'.
-- Cada plan se procesa aislado: un fallo registra una alerta emit_failed y sigue con el siguiente.
CREATE OR REPLACE FUNCTION public.cl_emit_due_demands(p_now timestamptz DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  r record;
  v_tz text;
  v_local timestamp;
  v_slot timestamptz;
  v_ids uuid[];
  v_demand uuid;
  v_n integer := 0;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('cl_emit_due_demands'));

  FOR r IN
    SELECT p.id, p.account_id, p.feed_id, p.close_lag_days, f.emit_days, f.emit_hour,
           f.emit_timezone, a.timezone AS account_tz
      FROM public.cl_plans p
      JOIN public.accounts a ON a.id = p.account_id
      JOIN public.cl_feeds f ON f.id = p.feed_id
     WHERE p.status = 'active' AND f.status IN ('active','testing')
     ORDER BY p.created_at, p.id
  LOOP
    BEGIN
      v_tz := public.cl_effective_tz(r.account_id, r.feed_id);
      IF r.emit_timezone IS NULL AND r.account_tz IS NOT NULL AND NOT public.cl_is_valid_timezone(r.account_tz) THEN
        PERFORM public.cl_raise_alert(r.id, NULL, 'invalid_timezone', 'medium',
                                      jsonb_build_object('account_timezone', r.account_tz, 'used', 'UTC'));
      END IF;
      v_local := p_now AT TIME ZONE v_tz;
      v_slot := date_trunc('hour', v_local) AT TIME ZONE v_tz;

      IF extract(isodow FROM v_local)::smallint = ANY (r.emit_days)
         AND extract(hour FROM v_local)::smallint = r.emit_hour
         AND NOT EXISTS (SELECT 1 FROM public.cl_demands d   -- un solo hueco horario local por plan
                          WHERE d.plan_id = r.id AND d.requested_at >= v_slot
                            AND d.requested_at < v_slot + interval '1 hour') THEN

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
      END IF;
    EXCEPTION WHEN OTHERS THEN
      PERFORM public.cl_raise_alert(r.id, NULL, 'emit_failed', 'high',
                                    jsonb_build_object('sqlstate', SQLSTATE, 'error', SQLERRM));
    END;
  END LOOP;

  -- Cierre de planes cuya ventana (end_date + close_lag_days) ya paso y no tienen cuotas pending/open
  -- (tambien los que no tienen conector: usan la zona de la cuenta).
  UPDATE public.cl_plans p SET status = 'closed'
   WHERE p.status = 'active'
     AND p.end_date + p.close_lag_days < (p_now AT TIME ZONE public.cl_effective_tz(p.account_id, p.feed_id))::date
     AND NOT EXISTS (SELECT 1 FROM public.cl_plan_quotas q WHERE q.plan_id = p.id AND q.status IN ('pending','open'));

  RETURN v_n;
END $$;

REVOKE ALL ON FUNCTION public.cl_effective_tz(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_raise_alert(uuid, uuid, text, text, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_active_points(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_build_demand(uuid, uuid[]) FROM PUBLIC, anon, authenticated, service_role;
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
