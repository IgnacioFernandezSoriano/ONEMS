-- Carrier Link fase 2, tarea 5: balanceo de cuotas (espejo del Load Balancing E2E, sin maximo por panelista) y
-- totales de cuotas de un plan.
--
-- 1. cl_plan_rebalance_quotas(plan, cambios, fence): aplica una propuesta de balanceo como valores ABSOLUTOS de
--    samples_planned por (ruta, semana ISO). Igual que rpc_balance_city_v2 en E2E:
--    - El total se conserva (E2E mueve envios sin crear ni borrar; aqui la suma de samples_planned del plan no cambia:
--      si cambia, CL_REBALANCE_TOTAL_CHANGED y no se escribe nada).
--    - Fence: de hoy al dia del fence (incluidos) no se toca nada; se reparte desde el dia siguiente y nunca en el
--      pasado. Sin fence explicito, el de la pantalla E2E: el domingo de la semana actual. Un fence anterior a hoy
--      equivale a "sin fence" (se puede tocar desde hoy). "Hoy" es el de la zona del plan (conector o cuenta).
--      Una cuota es movible si period_start > fence efectivo.
--    - Solo se mueve lo pendiente (E2E: allocation_plan_details.status = 'pending'; aqui cl_plan_quotas.status =
--      'pending'). Plan en borrador: cualquier semana (aun no hay nada en curso) salvo cuotas no pendientes. Plan
--      activo: solo cuotas pendientes con period_start > fence. Lo demas: CL_QUOTA_LOCKED. Plan cerrado:
--      CL_PLAN_CLOSED.
--    - Las entradas que no cambian nada (mismo valor) se ignoran: reenviar la misma propuesta no hace nada.
--    - Cuota nueva (ruta/semana sin fila): se crea con period_start/period_end como cl_plan_set_quotas. Cuota que
--      queda a 0: se borra si esta pendiente y sin nada colgado (arrastre, obtenidas, demandas, muestras, alertas);
--      si tiene algo colgado se deja a 0.
--    - Todo se valida antes de escribir; dos balanceos del mismo plan se serializan (bloqueo consultivo + filas).
--    Devuelve {changed, created, deleted, fence}.
-- 2. cl_plan_quota_totals: totales (cuotas, planificadas, arrastradas, obtenidas, demandas) de un plan con filtros
--    opcionales, para la pantalla de Planes de Asignacion (sin traer las 15.000 filas al navegador).
-- 3. Indice (plan_id, iso_year, iso_week, origin_city_id, destination_city_id, id): orden de la pantalla y totales.

-- ================================================================ 1. cl_plan_rebalance_quotas
CREATE OR REPLACE FUNCTION public.cl_plan_rebalance_quotas(p_plan_id uuid, p_changes jsonb, p_fence date DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_plan public.cl_plans;
  v_status text;
  v_today date;
  v_fence date;          -- ultimo dia congelado (NULL en borrador)
  v_delta bigint;
  v_o uuid; v_d uuid; v_y integer; v_w integer;
  v_exp_upd integer; v_exp_del integer; v_exp_ins integer;
  v_changed integer := 0; v_created integer := 0; v_deleted integer := 0;
BEGIN
  BEGIN
    v_plan := public.cl_plan_authorize(p_plan_id, 'edit');
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE EXCEPTION 'CL_FORBIDDEN' USING ERRCODE = '42501';
  END;

  -- Dos balanceos del mismo plan se serializan; el estado del plan se relee bloqueado (no cambia hasta el final).
  PERFORM pg_advisory_xact_lock(hashtext('cl_plan_rebalance_quotas:' || p_plan_id::text));
  SELECT p.status INTO v_status FROM public.cl_plans p WHERE p.id = p_plan_id FOR SHARE;
  IF v_status = 'closed' THEN
    RAISE EXCEPTION 'CL_PLAN_CLOSED: plan is closed' USING ERRCODE = '22023';
  END IF;

  IF p_changes IS NULL OR jsonb_typeof(p_changes) <> 'array' THEN
    RAISE EXCEPTION 'p_changes must be a JSON array' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_changes) e WHERE jsonb_typeof(e) <> 'object') THEN
    RAISE EXCEPTION 'Invalid change: each element must be an object' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_changes) e WHERE jsonb_typeof(e->'samples') IS DISTINCT FROM 'number') THEN
    RAISE EXCEPTION 'Invalid change: samples is required and must be an integer' USING ERRCODE = '22023';
  END IF;

  -- Fence efectivo (solo plan activo). Mismo criterio que rpc_balance_city_v2 + pantalla E2E.
  IF v_status = 'active' THEN
    v_today := (now() AT TIME ZONE public.cl_effective_tz(v_plan.account_id, v_plan.feed_id))::date;
    v_fence := GREATEST(COALESCE(p_fence, v_today + (7 - extract(isodow FROM v_today)::integer)), v_today - 1);
  END IF;

  IF to_regclass('pg_temp.cl_rb') IS NOT NULL THEN DROP TABLE pg_temp.cl_rb; END IF;   -- sin NOTICE (D5 de cl_wave2)
  CREATE TEMP TABLE cl_rb (
    i bigint NOT NULL, o uuid, d uuid, y integer, w integer, s integer, ps date,
    q_id uuid, q_status text, q_old integer, q_free boolean
  ) ON COMMIT DROP;

  BEGIN
    INSERT INTO pg_temp.cl_rb (i, o, d, y, w, s)
    SELECT r.i, r.origin_city_id::uuid, r.destination_city_id::uuid, r.iso_year::integer, r.iso_week::integer,
           r.samples::integer
      FROM ROWS FROM (jsonb_to_recordset(p_changes)
             AS (origin_city_id text, destination_city_id text, iso_year text, iso_week text, samples text))
           WITH ORDINALITY AS r(origin_city_id, destination_city_id, iso_year, iso_week, samples, i);
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
    RAISE EXCEPTION 'Invalid change entry: %', SQLERRM USING ERRCODE = '22023';
  END;
  IF EXISTS (SELECT 1 FROM pg_temp.cl_rb WHERE o IS NULL OR d IS NULL OR y IS NULL OR w IS NULL) THEN
    RAISE EXCEPTION 'Invalid change: origin, destination, iso_year and iso_week are required' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_temp.cl_rb WHERE s < 0) THEN
    RAISE EXCEPTION 'Invalid change: samples must be 0 or more' USING ERRCODE = '22023';
  END IF;

  BEGIN
    UPDATE pg_temp.cl_rb SET ps = to_date(y::text || '-' || lpad(w::text, 2, '0'), 'IYYY-IW') WHERE true;
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range
            OR invalid_datetime_format OR datetime_field_overflow THEN
    RAISE EXCEPTION 'Invalid change entry: %', SQLERRM USING ERRCODE = '22023';
  END;
  SELECT t.y, t.w INTO v_y, v_w FROM pg_temp.cl_rb t
   WHERE extract(isoyear FROM t.ps)::integer <> t.y OR extract(week FROM t.ps)::integer <> t.w
   ORDER BY t.i LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'Invalid ISO week %-W%', v_y, v_w USING ERRCODE = '22023';
  END IF;

  IF EXISTS (SELECT 1
               FROM (SELECT o FROM pg_temp.cl_rb UNION SELECT d FROM pg_temp.cl_rb) c(id)
              WHERE NOT EXISTS (SELECT 1 FROM public.cities ci
                                 WHERE ci.id = c.id AND ci.account_id = v_plan.account_id)) THEN
    RAISE EXCEPTION 'City does not belong to the plan account' USING ERRCODE = '22023';
  END IF;

  SELECT t.y, t.w INTO v_y, v_w FROM pg_temp.cl_rb t
   WHERE t.ps + 6 < v_plan.start_date OR t.ps > v_plan.end_date
   ORDER BY t.i LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'Week %-W% is outside the plan dates', v_y, v_w USING ERRCODE = '22023';
  END IF;

  SELECT t.o, t.d, t.y, t.w INTO v_o, v_d, v_y, v_w FROM pg_temp.cl_rb t
   GROUP BY t.o, t.d, t.y, t.w HAVING count(*) > 1
   ORDER BY min(t.i) LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'CL_DUPLICATE_QUOTA: route % -> % week %-W% appears twice', v_o, v_d, v_y, v_w USING ERRCODE = '22023';
  END IF;

  -- Cuotas existentes afectadas: se bloquean (su estado no cambia hasta el final) y se leen.
  PERFORM 1 FROM public.cl_plan_quotas q
    JOIN pg_temp.cl_rb t ON q.plan_id = p_plan_id AND q.origin_city_id = t.o AND q.destination_city_id = t.d
                        AND q.iso_year = t.y AND q.iso_week = t.w
   ORDER BY q.id
     FOR UPDATE OF q;
  UPDATE pg_temp.cl_rb t
     SET q_id = q.id, q_status = q.status, q_old = q.samples_planned, ps = q.period_start,
         q_free = q.samples_carried_in = 0 AND q.samples_obtained = 0 AND q.demands_count = 0
                  AND NOT EXISTS (SELECT 1 FROM public.cl_samples s WHERE s.quota_id = q.id)
                  AND NOT EXISTS (SELECT 1 FROM public.cl_alerts a WHERE a.quota_id = q.id)
    FROM public.cl_plan_quotas q
   WHERE q.plan_id = p_plan_id AND q.origin_city_id = t.o AND q.destination_city_id = t.d
     AND q.iso_year = t.y AND q.iso_week = t.w;

  -- Lo que no cambia nada no cuenta (ni bloquea): reenviar la misma propuesta es inocuo.
  DELETE FROM pg_temp.cl_rb WHERE s = COALESCE(q_old, 0);

  SELECT t.o, t.d, t.y, t.w INTO v_o, v_d, v_y, v_w FROM pg_temp.cl_rb t
   WHERE (t.q_id IS NOT NULL AND t.q_status <> 'pending')
      OR (v_fence IS NOT NULL AND t.ps <= v_fence)
   ORDER BY t.i LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'CL_QUOTA_LOCKED: route % -> % week %-W% is not pending or is inside the fence (%)',
      v_o, v_d, v_y, v_w, COALESCE(v_fence::text, 'none') USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(sum(t.s - COALESCE(t.q_old, 0)), 0) INTO v_delta FROM pg_temp.cl_rb t;
  IF v_delta <> 0 THEN
    RAISE EXCEPTION 'CL_REBALANCE_TOTAL_CHANGED: the changes alter the plan total by %', v_delta USING ERRCODE = '22023';
  END IF;

  SELECT count(*) FILTER (WHERE q_id IS NOT NULL AND (s > 0 OR NOT q_free)),
         count(*) FILTER (WHERE q_id IS NOT NULL AND s = 0 AND q_free),
         count(*) FILTER (WHERE q_id IS NULL)
    INTO v_exp_upd, v_exp_del, v_exp_ins
    FROM pg_temp.cl_rb;

  -- Escritura (todo validado).
  IF v_exp_del > 0 THEN
    DELETE FROM public.cl_plan_quotas q
     USING pg_temp.cl_rb t
     WHERE q.id = t.q_id AND t.s = 0 AND t.q_free AND q.plan_id = p_plan_id AND q.status = 'pending';
    GET DIAGNOSTICS v_deleted = ROW_COUNT;
  END IF;
  IF v_exp_upd > 0 THEN
    UPDATE public.cl_plan_quotas q
       SET samples_planned = t.s
      FROM pg_temp.cl_rb t
     WHERE q.id = t.q_id AND (t.s > 0 OR NOT t.q_free) AND q.plan_id = p_plan_id AND q.status = 'pending';
    GET DIAGNOSTICS v_changed = ROW_COUNT;
  END IF;
  IF v_exp_ins > 0 THEN
    INSERT INTO public.cl_plan_quotas
      (account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned)
    SELECT v_plan.account_id, p_plan_id, t.o, t.d, t.y, t.w, t.ps, t.ps + 6, t.s
      FROM pg_temp.cl_rb t
     WHERE t.q_id IS NULL
     ORDER BY t.i;
    GET DIAGNOSTICS v_created = ROW_COUNT;
  END IF;
  IF v_deleted <> v_exp_del OR v_changed <> v_exp_upd OR v_created <> v_exp_ins THEN
    RAISE EXCEPTION 'Rebalance aborted: expected %/%/% (changed/created/deleted), wrote %/%/%',
      v_exp_upd, v_exp_ins, v_exp_del, v_changed, v_created, v_deleted;
  END IF;

  IF to_regclass('pg_temp.cl_rb') IS NOT NULL THEN DROP TABLE pg_temp.cl_rb; END IF;   -- sin NOTICE (D5 de cl_wave2)
  RETURN jsonb_build_object('changed', v_changed, 'created', v_created, 'deleted', v_deleted, 'fence', v_fence);
END $$;
REVOKE ALL ON FUNCTION public.cl_plan_rebalance_quotas(uuid, jsonb, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cl_plan_rebalance_quotas(uuid, jsonb, date) TO authenticated, service_role;

-- ================================================================ 2. cl_plan_quota_totals
CREATE OR REPLACE FUNCTION public.cl_plan_quota_totals(p_plan_id uuid, p_origin uuid DEFAULT NULL,
  p_destination uuid DEFAULT NULL, p_iso_year integer DEFAULT NULL, p_iso_week integer DEFAULT NULL,
  p_status text DEFAULT NULL)
 RETURNS TABLE (quotas bigint, planned bigint, carried bigint, obtained bigint, demands bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
BEGIN
  BEGIN
    PERFORM public.cl_plan_authorize(p_plan_id, 'view');
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE EXCEPTION 'CL_FORBIDDEN' USING ERRCODE = '42501';
  END;
  RETURN QUERY
  SELECT count(*), COALESCE(sum(q.samples_planned), 0)::bigint, COALESCE(sum(q.samples_carried_in), 0)::bigint,
         COALESCE(sum(q.samples_obtained), 0)::bigint, COALESCE(sum(q.demands_count), 0)::bigint
    FROM public.cl_plan_quotas q
   WHERE q.plan_id = p_plan_id
     AND (p_origin IS NULL OR q.origin_city_id = p_origin)
     AND (p_destination IS NULL OR q.destination_city_id = p_destination)
     AND (p_iso_year IS NULL OR q.iso_year = p_iso_year)
     AND (p_iso_week IS NULL OR q.iso_week = p_iso_week)
     AND (p_status IS NULL OR q.status = p_status);
END $$;
REVOKE ALL ON FUNCTION public.cl_plan_quota_totals(uuid, uuid, uuid, integer, integer, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cl_plan_quota_totals(uuid, uuid, uuid, integer, integer, text) TO authenticated, service_role;

-- ================================================================ 3. indice para orden y totales
CREATE INDEX IF NOT EXISTS cl_plan_quotas_plan_week_route_idx
  ON public.cl_plan_quotas (plan_id, iso_year, iso_week, origin_city_id, destination_city_id, id);
