-- Carrier Link fase 2, tarea 1.
-- Spec: docs/superpowers/specs/2026-11-19-carrier-link-design.md
--
-- 1. cl_dry_run_batch: ensayo de un lote desde la web. cl_ingest_batch solo la ejecuta service_role (API del conector);
--    este envoltorio deja a un usuario con Edit en cl_connectors (o al superadmin) ensayar un lote de un feed de SU
--    cuenta. Siempre en modo ensayo: no escribe nada. Feed ajeno, inexistente o sin derecho: el mismo 42501
--    (sin oraculo de existencia).
-- 2. cl_plan_set_quotas por conjuntos: la version anterior (20261120110800) recorria el array y buscaba duplicados con
--    v_key = ANY(v_keys) (O(n^2): ~7-12 s para 15.000 cuotas, por encima del statement_timeout de 8 s de
--    authenticated). Misma firma, permisos, autorizacion, reglas, codigos y mensajes de error; valida todo antes de
--    borrar nada; ignora samples <= 0; un unico INSERT ... SELECT.
--    Si un array tiene varios errores distintos, se informa por tipo de comprobacion (forma, campos, semana ISO,
--    ciudad, fechas del plan, duplicado, bloqueada) y, dentro de cada tipo, del primer elemento que falla.
-- 3. Lo que quedaba lento al guardar 15.000 cuotas (medido en local, 15.660 cuotas: 2,9 s el primer guardado y 5,7 s
--    el reemplazo con solo el punto 2):
--    a) El trigger generico cl_same_account de cl_plan_quotas (to_jsonb(NEW) + 3 EXECUTE dinamicos por fila). En
--       cl_plan_quotas se cambia por una funcion propia con SQL estatico: mismas tres comprobaciones, mismo momento
--       (BEFORE INSERT OR UPDATE, por fila), mismo nombre de trigger, mismo mensaje y SQLSTATE. Las demas tablas
--       siguen con el generico.
--    b) Las claves ajenas cl_samples.quota_id y cl_alerts.quota_id no tenian indice: borrar N cuotas pending hacia
--       2N recorridos completos de esas tablas. Se indexan.

-- ================================================================ 1. cl_dry_run_batch
CREATE OR REPLACE FUNCTION public.cl_dry_run_batch(p_feed_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_account uuid;
BEGIN
  SELECT f.account_id INTO v_account FROM public.cl_feeds f WHERE f.id = p_feed_id;
  IF v_account IS NULL
     OR NOT (public.is_superadmin()
             OR (v_account = public.current_user_account_id()
                 AND public.has_any_access(v_account, 'edit', 'cl_connectors'))) THEN
    RAISE EXCEPTION 'CL_FORBIDDEN' USING ERRCODE = '42501';
  END IF;
  RETURN public.cl_ingest_batch(p_feed_id, p_payload, true);
END $$;
REVOKE ALL ON FUNCTION public.cl_dry_run_batch(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cl_dry_run_batch(uuid, jsonb) TO authenticated;

-- ================================================================ 2. cl_plan_set_quotas (de 20261120110800, por conjuntos)
CREATE OR REPLACE FUNCTION public.cl_plan_set_quotas(p_plan_id uuid, p_quotas jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_plan public.cl_plans;
  v_n integer := 0;
  v_o uuid; v_d uuid; v_y integer; v_w integer;
  -- todas las entradas (en orden), tras convertir tipos
  a_o uuid[]; a_d uuid[]; a_y integer[]; a_w integer[]; a_s integer[];
  -- solo las entradas con samples > 0 (en orden), con el lunes de su semana ISO
  k_o uuid[]; k_d uuid[]; k_y integer[]; k_w integer[]; k_s integer[]; k_ps date[];
BEGIN
  v_plan := public.cl_plan_authorize(p_plan_id, 'edit');
  IF v_plan.status = 'closed' THEN
    RAISE EXCEPTION 'CL_PLAN_CLOSED: plan is closed' USING ERRCODE = '22023';
  END IF;
  IF v_plan.status <> 'draft' THEN
    RAISE EXCEPTION 'CL_PLAN_NOT_DRAFT: quotas can only be set on a draft plan' USING ERRCODE = '22023';
  END IF;
  IF p_quotas IS NULL OR jsonb_typeof(p_quotas) <> 'array' THEN
    RAISE EXCEPTION 'p_quotas must be a JSON array' USING ERRCODE = '22023';
  END IF;

  -- Validar todo antes de borrar nada.
  -- Forma de cada elemento.
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_quotas) e WHERE jsonb_typeof(e) <> 'object') THEN
    RAISE EXCEPTION 'Invalid quota: each element must be an object' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(p_quotas) e WHERE jsonb_typeof(e->'samples') IS DISTINCT FROM 'number') THEN
    RAISE EXCEPTION 'Invalid quota: samples is required and must be an integer' USING ERRCODE = '22023';
  END IF;

  -- Tipos (los campos se leen como texto, igual que q->>'campo').
  BEGIN
    SELECT array_agg(r.origin_city_id::uuid ORDER BY r.i), array_agg(r.destination_city_id::uuid ORDER BY r.i),
           array_agg(r.iso_year::integer ORDER BY r.i), array_agg(r.iso_week::integer ORDER BY r.i),
           array_agg(r.samples::integer ORDER BY r.i)
      INTO a_o, a_d, a_y, a_w, a_s
      FROM ROWS FROM (jsonb_to_recordset(p_quotas)
             AS (origin_city_id text, destination_city_id text, iso_year text, iso_week text, samples text))
           WITH ORDINALITY AS r(origin_city_id, destination_city_id, iso_year, iso_week, samples, i);
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
    RAISE EXCEPTION 'Invalid quota entry: %', SQLERRM USING ERRCODE = '22023';
  END;
  IF EXISTS (SELECT 1 FROM unnest(a_o, a_d, a_y, a_w) t(o, d, y, w)
              WHERE o IS NULL OR d IS NULL OR y IS NULL OR w IS NULL) THEN
    RAISE EXCEPTION 'Invalid quota: origin, destination, iso_year and iso_week are required' USING ERRCODE = '22023';
  END IF;

  -- Entradas que cuentan (samples > 0) y lunes de su semana ISO.
  BEGIN
    SELECT array_agg(t.o ORDER BY t.i), array_agg(t.d ORDER BY t.i), array_agg(t.y ORDER BY t.i),
           array_agg(t.w ORDER BY t.i), array_agg(t.s ORDER BY t.i),
           array_agg(to_date(t.y::text || '-' || lpad(t.w::text, 2, '0'), 'IYYY-IW') ORDER BY t.i)
      INTO k_o, k_d, k_y, k_w, k_s, k_ps
      FROM unnest(a_o, a_d, a_y, a_w, a_s) WITH ORDINALITY t(o, d, y, w, s, i)
     WHERE t.s > 0;
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range
            OR invalid_datetime_format OR datetime_field_overflow THEN
    RAISE EXCEPTION 'Invalid quota entry: %', SQLERRM USING ERRCODE = '22023';
  END;

  SELECT t.y, t.w INTO v_y, v_w
    FROM unnest(k_y, k_w, k_ps) WITH ORDINALITY t(y, w, ps, i)
   WHERE extract(isoyear FROM t.ps)::integer <> t.y OR extract(week FROM t.ps)::integer <> t.w
   ORDER BY t.i LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'Invalid ISO week %-W%', v_y, v_w USING ERRCODE = '22023';
  END IF;

  IF EXISTS (SELECT 1
               FROM (SELECT o FROM unnest(k_o) o UNION SELECT d FROM unnest(k_d) d) c(id)
              WHERE NOT EXISTS (SELECT 1 FROM public.cities ci
                                 WHERE ci.id = c.id AND ci.account_id = v_plan.account_id)) THEN
    RAISE EXCEPTION 'City does not belong to the plan account' USING ERRCODE = '22023';
  END IF;

  SELECT t.y, t.w INTO v_y, v_w
    FROM unnest(k_y, k_w, k_ps) WITH ORDINALITY t(y, w, ps, i)
   WHERE t.ps + 6 < v_plan.start_date OR t.ps > v_plan.end_date
   ORDER BY t.i LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'Week %-W% is outside the plan dates', v_y, v_w USING ERRCODE = '22023';
  END IF;

  SELECT t.o, t.d, t.y, t.w INTO v_o, v_d, v_y, v_w
    FROM unnest(k_o, k_d, k_y, k_w) WITH ORDINALITY t(o, d, y, w, i)
   GROUP BY t.o, t.d, t.y, t.w
  HAVING count(*) > 1
   ORDER BY min(t.i) LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'CL_DUPLICATE_QUOTA: route % -> % week %-W% appears twice', v_o, v_d, v_y, v_w USING ERRCODE = '22023';
  END IF;

  SELECT t.o, t.d, t.y, t.w INTO v_o, v_d, v_y, v_w
    FROM unnest(k_o, k_d, k_y, k_w) WITH ORDINALITY t(o, d, y, w, i)
    JOIN public.cl_plan_quotas x
      ON x.plan_id = p_plan_id AND x.origin_city_id = t.o AND x.destination_city_id = t.d
     AND x.iso_year = t.y AND x.iso_week = t.w AND x.status <> 'pending'
   ORDER BY t.i LIMIT 1;
  IF FOUND THEN
    RAISE EXCEPTION 'CL_QUOTA_LOCKED: route % -> % week %-W% already has a non-pending quota', v_o, v_d, v_y, v_w USING ERRCODE = '22023';
  END IF;

  DELETE FROM public.cl_plan_quotas WHERE plan_id = p_plan_id AND status = 'pending';

  INSERT INTO public.cl_plan_quotas
    (account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned)
  SELECT v_plan.account_id, p_plan_id, t.o, t.d, t.y, t.w, t.ps, t.ps + 6, t.s
    FROM unnest(k_o, k_d, k_y, k_w, k_s, k_ps) WITH ORDINALITY t(o, d, y, w, s, ps, i)
   ORDER BY t.i;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.cl_plan_set_quotas(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cl_plan_set_quotas(uuid, jsonb) TO authenticated, service_role;

-- ================================================================ 3a. cl_same_account de cl_plan_quotas con SQL estatico
-- Equivale a cl_check_same_account('plan_id','cl_plans','origin_city_id','cities','destination_city_id','cities').
-- Las tres columnas son NOT NULL, asi que siempre se comprueban las tres.
CREATE OR REPLACE FUNCTION public.cl_plan_quotas_check_same_account()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.cl_plans t WHERE t.id = NEW.plan_id AND t.account_id = NEW.account_id) THEN
    RAISE EXCEPTION '% % debe pertenecer a la misma cuenta (%)', TG_TABLE_NAME, 'plan_id', 'cl_plans'
      USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.cities t WHERE t.id = NEW.origin_city_id AND t.account_id = NEW.account_id) THEN
    RAISE EXCEPTION '% % debe pertenecer a la misma cuenta (%)', TG_TABLE_NAME, 'origin_city_id', 'cities'
      USING ERRCODE = 'check_violation';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.cities t WHERE t.id = NEW.destination_city_id AND t.account_id = NEW.account_id) THEN
    RAISE EXCEPTION '% % debe pertenecer a la misma cuenta (%)', TG_TABLE_NAME, 'destination_city_id', 'cities'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.cl_plan_quotas_check_same_account() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS cl_same_account ON public.cl_plan_quotas;
CREATE TRIGGER cl_same_account BEFORE INSERT OR UPDATE ON public.cl_plan_quotas
  FOR EACH ROW EXECUTE FUNCTION public.cl_plan_quotas_check_same_account();

-- ================================================================ 3b. indices de las claves ajenas hacia cl_plan_quotas
CREATE INDEX IF NOT EXISTS cl_samples_quota_idx ON public.cl_samples (quota_id);
CREATE INDEX IF NOT EXISTS cl_alerts_quota_idx  ON public.cl_alerts (quota_id);
