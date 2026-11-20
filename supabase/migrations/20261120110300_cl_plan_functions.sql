-- Carrier Link fase 1, tarea 5: cuotas y activacion del plan.
-- cl_plan_quotas solo se escribe por funciones SECURITY DEFINER (authenticated solo tiene SELECT).

-- Autorizacion interna: devuelve el plan o lanza 42501 (mismo mensaje si no existe o es ajeno).
-- auth.uid() NULL (service_role, cron, postgres) pasa; superadmin pasa.
CREATE OR REPLACE FUNCTION public.cl_plan_authorize(p_plan_id uuid, p_level text)
 RETURNS public.cl_plans
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE v_plan public.cl_plans;
BEGIN
  SELECT * INTO v_plan FROM public.cl_plans WHERE id = p_plan_id;
  IF auth.uid() IS NOT NULL AND NOT public.is_superadmin() THEN
    IF NOT FOUND
       OR v_plan.account_id IS DISTINCT FROM public.current_user_account_id()
       OR NOT public.has_any_access(v_plan.account_id, p_level, 'cl_plans') THEN
      RAISE EXCEPTION 'Forbidden: plan not accessible' USING ERRCODE = '42501';
    END IF;
  ELSIF NOT FOUND THEN
    RAISE EXCEPTION 'Forbidden: plan not accessible' USING ERRCODE = '42501';
  END IF;
  RETURN v_plan;
END $$;

CREATE OR REPLACE FUNCTION public.cl_plan_set_quotas(p_plan_id uuid, p_quotas jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_plan public.cl_plans;
  q jsonb;
  v_n integer := 0;
  v_o uuid; v_d uuid; v_y integer; v_w integer; v_s integer;
  v_ps date; v_pe date;
  v_keys text[] := ARRAY[]::text[];
  v_key text;
BEGIN
  v_plan := public.cl_plan_authorize(p_plan_id, 'edit');
  IF v_plan.status = 'closed' THEN
    RAISE EXCEPTION 'CL_PLAN_CLOSED: plan is closed' USING ERRCODE = '22023';
  END IF;
  IF p_quotas IS NULL OR jsonb_typeof(p_quotas) <> 'array' THEN
    RAISE EXCEPTION 'p_quotas must be a JSON array' USING ERRCODE = '22023';
  END IF;

  -- Validar todo antes de borrar nada.
  FOR q IN SELECT * FROM jsonb_array_elements(p_quotas) LOOP
    BEGIN
      IF jsonb_typeof(q) <> 'object' THEN
        RAISE EXCEPTION 'Invalid quota: each element must be an object' USING ERRCODE = '22023';
      END IF;
      IF jsonb_typeof(q->'samples') IS DISTINCT FROM 'number' THEN
        RAISE EXCEPTION 'Invalid quota: samples is required and must be an integer' USING ERRCODE = '22023';
      END IF;
      v_o := (q->>'origin_city_id')::uuid;
      v_d := (q->>'destination_city_id')::uuid;
      v_y := (q->>'iso_year')::integer;
      v_w := (q->>'iso_week')::integer;
      v_s := (q->>'samples')::integer;
      IF v_o IS NULL OR v_d IS NULL OR v_y IS NULL OR v_w IS NULL THEN
        RAISE EXCEPTION 'Invalid quota: origin, destination, iso_year and iso_week are required' USING ERRCODE = '22023';
      END IF;
      IF v_s <= 0 THEN CONTINUE; END IF;
      v_ps := to_date(v_y::text || '-' || lpad(v_w::text, 2, '0'), 'IYYY-IW');
    EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range
              OR invalid_datetime_format OR datetime_field_overflow THEN
      RAISE EXCEPTION 'Invalid quota entry: %', SQLERRM USING ERRCODE = '22023';
    END;
    IF extract(isoyear FROM v_ps)::integer <> v_y OR extract(week FROM v_ps)::integer <> v_w THEN
      RAISE EXCEPTION 'Invalid ISO week %-W%', v_y, v_w USING ERRCODE = '22023';
    END IF;
    v_pe := v_ps + 6;
    IF (SELECT count(*) FROM public.cities WHERE id IN (v_o, v_d) AND account_id = v_plan.account_id)
       <> (SELECT count(DISTINCT x) FROM (VALUES (v_o), (v_d)) t(x)) THEN
      RAISE EXCEPTION 'City does not belong to the plan account' USING ERRCODE = '22023';
    END IF;
    IF v_pe < v_plan.start_date OR v_ps > v_plan.end_date THEN
      RAISE EXCEPTION 'Week %-W% is outside the plan dates', v_y, v_w USING ERRCODE = '22023';
    END IF;
    v_key := v_o::text || '>' || v_d::text || '@' || v_y || '-' || v_w;
    IF v_key = ANY (v_keys) THEN
      RAISE EXCEPTION 'CL_DUPLICATE_QUOTA: route % -> % week %-W% appears twice', v_o, v_d, v_y, v_w USING ERRCODE = '22023';
    END IF;
    v_keys := v_keys || v_key;
    IF EXISTS (SELECT 1 FROM public.cl_plan_quotas x
                WHERE x.plan_id = p_plan_id AND x.origin_city_id = v_o AND x.destination_city_id = v_d
                  AND x.iso_year = v_y AND x.iso_week = v_w AND x.status <> 'pending') THEN
      RAISE EXCEPTION 'CL_QUOTA_LOCKED: route % -> % week %-W% already has a non-pending quota', v_o, v_d, v_y, v_w USING ERRCODE = '22023';
    END IF;
  END LOOP;

  DELETE FROM public.cl_plan_quotas WHERE plan_id = p_plan_id AND status = 'pending';

  FOR q IN SELECT * FROM jsonb_array_elements(p_quotas) LOOP
    v_s := (q->>'samples')::integer;
    IF v_s <= 0 THEN CONTINUE; END IF;
    v_y := (q->>'iso_year')::integer;
    v_w := (q->>'iso_week')::integer;
    v_ps := to_date(v_y::text || '-' || lpad(v_w::text, 2, '0'), 'IYYY-IW');
    INSERT INTO public.cl_plan_quotas
      (account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned)
    VALUES (v_plan.account_id, p_plan_id, (q->>'origin_city_id')::uuid, (q->>'destination_city_id')::uuid,
            v_y, v_w, v_ps, v_ps + 6, v_s);
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $$;

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
    SELECT pc.city_id AS cid, r.e2e_role
      FROM public.readers r
      JOIN public.postal_centers pc ON pc.id = r.postal_center_id
     WHERE r.account_id = v_plan.account_id
       AND r.capture_source = 'carrier_scan'
       AND r.deleted_at IS NULL
       AND r.is_active IS NOT FALSE
       AND r.carrier_id = v_plan.carrier_id
       AND pc.city_id IS NOT NULL
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

CREATE OR REPLACE FUNCTION public.cl_plan_missing_standards(p_plan_id uuid)
 RETURNS TABLE (origin_city_id uuid, destination_city_id uuid)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE v_plan public.cl_plans;
BEGIN
  v_plan := public.cl_plan_authorize(p_plan_id, 'view');
  RETURN QUERY
  SELECT DISTINCT q.origin_city_id, q.destination_city_id
    FROM public.cl_plan_quotas q
   WHERE q.plan_id = p_plan_id
     AND NOT EXISTS (
       SELECT 1 FROM public.delivery_standards ds
        WHERE ds.account_id = v_plan.account_id
          AND ds.carrier_id = v_plan.carrier_id
          AND ds.product_id = v_plan.product_id
          AND ds.origin_city_id = q.origin_city_id
          AND ds.destination_city_id = q.destination_city_id)
   ORDER BY 1, 2;
END $$;

CREATE OR REPLACE FUNCTION public.cl_plan_activate(p_plan_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE v_plan public.cl_plans; v_n integer;
BEGIN
  v_plan := public.cl_plan_authorize(p_plan_id, 'edit');
  IF v_plan.status = 'closed' THEN
    RAISE EXCEPTION 'CL_PLAN_CLOSED: plan is closed' USING ERRCODE = '22023';
  END IF;
  IF v_plan.feed_id IS NULL THEN
    RAISE EXCEPTION 'CL_NO_FEED: plan has no feed' USING ERRCODE = '22023';
  END IF;
  IF (SELECT f.carrier_id FROM public.cl_feeds f WHERE f.id = v_plan.feed_id) IS DISTINCT FROM v_plan.carrier_id THEN
    RAISE EXCEPTION 'CL_FEED_CARRIER_MISMATCH: feed carrier differs from plan carrier' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.cl_plan_quotas WHERE plan_id = p_plan_id) THEN
    RAISE EXCEPTION 'CL_NO_QUOTAS: plan has no quotas' USING ERRCODE = '22023';
  END IF;
  SELECT count(*) INTO v_n FROM public.cl_plan_missing_points(p_plan_id);
  IF v_n > 0 THEN
    RAISE EXCEPTION 'CL_MISSING_POINTS: % city/role without an active carrier point', v_n USING ERRCODE = '22023';
  END IF;
  UPDATE public.cl_plans SET status = 'active' WHERE id = p_plan_id;
END $$;

REVOKE ALL ON FUNCTION public.cl_plan_authorize(uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cl_plan_set_quotas(uuid, jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cl_plan_missing_points(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cl_plan_missing_standards(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cl_plan_activate(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cl_plan_set_quotas(uuid, jsonb) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cl_plan_missing_points(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cl_plan_missing_standards(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.cl_plan_activate(uuid) TO authenticated, service_role;
