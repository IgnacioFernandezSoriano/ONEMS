-- Carrier Link: correcciones de la revision final de la rama (I1-I4, M1, M2).
-- Spec: docs/superpowers/specs/2026-11-19-carrier-link-design.md
--
-- I1  Un lote no se sortea despues de que su demanda caduque: cl_sample_stratum exige demanda 'open' (lo ya
--     sorteado se sigue devolviendo); la caducidad de 7 dias toma el mismo candado que el sorteo, liquida TODAS las
--     cuotas aun 'open' de la demanda y pasa sus lotes 'validated' a 'expired' (estado final nuevo).
-- I2  Un conector en 'testing' no gasta las peticiones del plan: sus demandas no suman demands_count y, al caducar,
--     sus cuotas vuelven a 'pending' sin liquidarse (sin reparto ni unfilled).
-- I3  Plan no borrador: carrier, producto, conector y fecha de inicio no se cambian por UPDATE de usuario; las cuotas
--     solo se fijan en borrador.
-- I4  Los puntos de lectura del transportista (readers.capture_source = 'carrier_scan') no aparecen como lectores
--     RFID (informe de operacion, v_mobile_readers).
-- M1  La emision bloquea las cuotas pending del plan (orden por id) antes de tocarlas.
-- M2  reenrich_processed_events solo usa filas one_db de panelistas (source = 'panelist').
-- Cada CREATE OR REPLACE parte de la ultima definicion (repo o, para ops_report._data, v_mobile_readers y
-- reenrich_processed_events, la definicion viva de produccion) y solo cambia lo indicado.

-- ---------------------------------------------------------------- I1: estado 'expired' del lote
ALTER TABLE public.cl_batches DROP CONSTRAINT cl_batches_status_check;
ALTER TABLE public.cl_batches ADD CONSTRAINT cl_batches_status_check
  CHECK (status IN ('received','validated','sampled','rejected','undone','expired'));

-- ---------------------------------------------------------------- I2: demanda emitida con el conector en prueba
ALTER TABLE public.cl_demands ADD COLUMN feed_testing boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.cl_demands.feed_testing IS
  'true si se emitio con el conector en testing: no suma demands_count y al caducar sus cuotas vuelven a pending sin liquidarse';

-- ---------------------------------------------------------------- I3: campos fijos de un plan no borrador
-- Mismo criterio de "backend" que cl_plans_force_draft (cron, service_role, postgres pasan sin cambios).
CREATE OR REPLACE FUNCTION public.cl_plans_lock_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path = public, extensions
AS $$
BEGIN
  IF OLD.status <> 'draft'
     AND current_setting('role') NOT IN ('none', 'service_role', 'postgres', 'supabase_admin')
     AND (NEW.carrier_id IS DISTINCT FROM OLD.carrier_id
       OR NEW.product_id IS DISTINCT FROM OLD.product_id
       OR NEW.feed_id    IS DISTINCT FROM OLD.feed_id
       OR NEW.start_date IS DISTINCT FROM OLD.start_date) THEN
    RAISE EXCEPTION 'CL_PLAN_LOCKED_FIELD: carrier, product, connector and start date are fixed once the plan is not a draft'
      USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.cl_plans_lock_fields() FROM PUBLIC, anon, authenticated;
DROP TRIGGER IF EXISTS cl_plans_lock_fields ON public.cl_plans;
CREATE TRIGGER cl_plans_lock_fields BEFORE UPDATE ON public.cl_plans
  FOR EACH ROW EXECUTE FUNCTION public.cl_plans_lock_fields();

-- ================================================================ I3: cl_plan_set_quotas (de 20261120110300, + CL_PLAN_NOT_DRAFT)
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
  IF v_plan.status <> 'draft' THEN
    RAISE EXCEPTION 'CL_PLAN_NOT_DRAFT: quotas can only be set on a draft plan' USING ERRCODE = '22023';
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
REVOKE ALL ON FUNCTION public.cl_plan_set_quotas(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cl_plan_set_quotas(uuid, jsonb) TO authenticated, service_role;

-- ================================================================ I2: cl_build_demand (de 20261120110400)
-- Cambio: con el conector en 'testing' la demanda se marca feed_testing y no suma demands_count.
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
  v_testing boolean;
BEGIN
  SELECT * INTO v_plan FROM public.cl_plans WHERE id = p_plan_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'plan not found' USING ERRCODE = '22023'; END IF;
  IF v_plan.feed_id IS NULL THEN RAISE EXCEPTION 'CL_NO_FEED: plan has no feed' USING ERRCODE = '22023'; END IF;
  SELECT jsonb_build_object('days', to_jsonb(f.emit_days), 'hour', f.emit_hour,
                            'timezone', public.cl_effective_tz(f.account_id, f.id)),
         f.status = 'testing'
    INTO v_sched, v_testing
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

  INSERT INTO public.cl_demands (id, account_id, plan_id, feed_id, status, random_seed, payload, feed_testing)
  VALUES (v_id, v_plan.account_id, p_plan_id, v_plan.feed_id, 'open',
          encode(gen_random_bytes(16), 'hex'),
          jsonb_build_object('schema_version', '1.1', 'demand_id', v_id, 'carrier', v_carrier,
                             'products', v_products, 'include_all_scans', v_plan.feed_diagnosis,
                             'schedule', v_sched,
                             'strata', v_strata),
          COALESCE(v_testing, false));

  -- I2: una demanda de prueba no cuenta como una de las 3 peticiones de la cuota.
  UPDATE public.cl_plan_quotas
     SET status = 'open',
         demands_count = demands_count + CASE WHEN COALESCE(v_testing, false) THEN 0 ELSE 1 END
   WHERE id = ANY (v_ids);
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.cl_build_demand(uuid, uuid[]) FROM PUBLIC, anon, authenticated, service_role;

-- ================================================================ I1: cl_sample_stratum (de 20261120110600)
-- Cambio: tras el candado por cuenta+carrier y el del lote, bloquea la demanda (mismo orden que cl_finish_batch y
-- cl_undo_batch: candado -> lote -> demanda -> cuota) y lanza CL_DEMAND_NOT_OPEN si ya no esta 'open' (caducada o
-- deshecha). Un estrato ya sorteado sigue devolviendo su sorteo guardado (idempotente).
-- ---------------------------------------------------------------- sorteo de un estrato
-- Orden: md5(semilla || ':' || item_id), desempate item_id COLLATE "C"; se toman los primeros samples_required
-- (el valor de la foto de la demanda). Semilla = cl_demands.random_seed, fijada al emitir (D10). La semilla no se
-- devuelve (queda en cl_sampling_runs para el auditor).
CREATE OR REPLACE FUNCTION public.cl_sample_stratum(p_batch_id uuid, p_stratum_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_batch  public.cl_batches;
  v_demand public.cl_demands;
  v_plan   public.cl_plans;
  v_quota  public.cl_plan_quotas;
  v_run    public.cl_sampling_runs;
  v_snap   jsonb;
  v_pop    integer;
  v_req    integer;
  v_valid  integer;
  v_sel    text[];
  v_item   text;
  v_sid    uuid;
  v_st     record;
  v_mis    jsonb := '[]'::jsonb;
  v_n      bigint;
  v_all_ok boolean;
  v_nocity jsonb;
  v_acc    uuid;
  v_car    uuid;
BEGIN
  -- Serializa los sorteos de la misma cuenta y carrier (dos lotes no pueden elegir a la vez el mismo item_id, D12)
  -- y, despues, los de un mismo lote.
  SELECT p.account_id, p.carrier_id INTO v_acc, v_car
    FROM public.cl_batches b JOIN public.cl_demands d ON d.id = b.demand_id JOIN public.cl_plans p ON p.id = d.plan_id
   WHERE b.id = p_batch_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CL_BATCH_NOT_FOUND: batch not found' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('cl_sample:' || v_acc::text || ':' || v_car::text));
  SELECT * INTO v_batch FROM public.cl_batches WHERE id = p_batch_id FOR UPDATE;

  -- Idempotente por (lote, estrato).
  SELECT * INTO v_run FROM public.cl_sampling_runs WHERE batch_id = p_batch_id AND stratum_id = p_stratum_id;
  IF FOUND THEN
    RETURN public.cl_run_summary(v_run);
  END IF;

  IF v_batch.status <> 'validated' THEN
    RAISE EXCEPTION 'CL_BATCH_NOT_VALIDATED: batch is %', v_batch.status USING ERRCODE = '22023';
  END IF;
  SELECT (e->>'population_size')::integer INTO v_pop
    FROM jsonb_array_elements(v_batch.summary->'strata') e WHERE e->>'stratum_id' = p_stratum_id::text;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CL_UNKNOWN_STRATUM: stratum is not part of this batch' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_demand FROM public.cl_demands WHERE id = v_batch.demand_id FOR UPDATE;
  IF v_demand.status <> 'open' THEN
    RAISE EXCEPTION 'CL_DEMAND_NOT_OPEN: demand is %', v_demand.status USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_plan FROM public.cl_plans WHERE id = v_demand.plan_id;
  SELECT * INTO v_quota FROM public.cl_plan_quotas WHERE id = p_stratum_id;
  SELECT sn.d INTO v_snap FROM jsonb_array_elements(v_demand.payload->'strata') sn(d)
   WHERE sn.d->>'stratum_id' = p_stratum_id::text;
  v_req := GREATEST(COALESCE((v_snap->>'samples_required')::integer, 0), 0);

  DROP TABLE IF EXISTS pg_temp.cl_sampler_rows;
  CREATE TEMP TABLE cl_sampler_rows ON COMMIT DROP AS
    SELECT * FROM public.cl_stratum_endpoints(p_batch_id, p_stratum_id);

  -- Candidatos (se calculan una vez y sirven para candidates_valid y para el sorteo): item_id con inicio y fin;
  -- los que ya son muestra activa del carrier (p. ej. el mismo envio en otro estrato del mismo lote) se descartan
  -- como en D12.
  DROP TABLE IF EXISTS pg_temp.cl_sampler_cands;
  CREATE TEMP TABLE cl_sampler_cands ON COMMIT DROP AS
    SELECT DISTINCT r.item_id, r.start_scan_id, r.end_scan_id,
           a.reader_id AS start_reader_id, a.city_id AS start_city_id,
           z.reader_id AS end_reader_id, z.city_id AS end_city_id
      FROM pg_temp.cl_sampler_rows r
      JOIN pg_temp.cl_sampler_rows a ON a.scan_id = r.start_scan_id
      JOIN pg_temp.cl_sampler_rows z ON z.scan_id = r.end_scan_id
     WHERE NOT EXISTS (SELECT 1 FROM public.cl_samples sm
                        WHERE sm.account_id = v_plan.account_id AND sm.carrier_id = v_plan.carrier_id
                          AND sm.item_id = r.item_id AND sm.status = 'active');

  -- Un punto de inicio/fin cuyo centro postal no tiene ciudad no da ciudades reales (D6): ese candidato no se sortea
  -- y se avisa (asi un punto mal dado de alta no bloquea el estrato para siempre).
  SELECT jsonb_build_object(
           'batch_id', p_batch_id,
           'reader_ids', (SELECT jsonb_agg(DISTINCT x.rid) FROM pg_temp.cl_sampler_cands c2
                            CROSS JOIN LATERAL (VALUES (CASE WHEN c2.start_city_id IS NULL THEN c2.start_reader_id END),
                                                       (CASE WHEN c2.end_city_id IS NULL THEN c2.end_reader_id END)) x(rid)
                           WHERE x.rid IS NOT NULL),
           'item_ids', jsonb_agg(c.item_id ORDER BY c.item_id COLLATE "C"))
    INTO v_nocity
    FROM pg_temp.cl_sampler_cands c
   WHERE c.start_city_id IS NULL OR c.end_city_id IS NULL
  HAVING count(*) > 0;
  IF v_nocity IS NOT NULL THEN
    DELETE FROM pg_temp.cl_sampler_cands WHERE start_city_id IS NULL OR end_city_id IS NULL;
    PERFORM public.cl_raise_alert(v_plan.id, p_stratum_id, 'reader_without_city', 'high', v_nocity);
  END IF;

  SELECT count(*) INTO v_valid FROM pg_temp.cl_sampler_cands;

  SELECT COALESCE(array_agg(c.item_id ORDER BY c.k, c.item_id COLLATE "C"), ARRAY[]::text[]) INTO v_sel
    FROM (SELECT c0.item_id, md5(v_demand.random_seed || ':' || c0.item_id) AS k
            FROM pg_temp.cl_sampler_cands c0
           ORDER BY k, c0.item_id COLLATE "C"
           LIMIT v_req) c;

  FOREACH v_item IN ARRAY v_sel LOOP
    SELECT c.start_scan_id, c.end_scan_id INTO v_st FROM pg_temp.cl_sampler_cands c WHERE c.item_id = v_item;

    INSERT INTO public.cl_samples (account_id, plan_id, quota_id, batch_id, carrier_id, product_id, item_id,
                                   start_reader_id, start_at, end_reader_id, end_at, origin_city_id, destination_city_id,
                                   extra)
    SELECT v_plan.account_id, v_plan.id, p_stratum_id, p_batch_id, v_plan.carrier_id, v_plan.product_id, v_item,
           a.reader_id, a.scan_at, z.reader_id, z.scan_at, a.city_id, z.city_id,
           COALESCE((SELECT jsonb_object_agg(x.key, x.value) FROM (
                       SELECT DISTINCT ON (e.key) e.key, e.value
                         FROM pg_temp.cl_sampler_rows r CROSS JOIN LATERAL jsonb_each(COALESCE(r.extra, '{}'::jsonb)) e
                        WHERE r.item_id = v_item
                        ORDER BY e.key, r.scan_at DESC, r.row_ord DESC) x), '{}'::jsonb)
      FROM pg_temp.cl_sampler_rows a, pg_temp.cl_sampler_rows z
     WHERE a.scan_id = v_st.start_scan_id AND z.scan_id = v_st.end_scan_id
    RETURNING id INTO v_sid;

    -- Todas sus lecturas de inicio y de fin (R15). Papel: las elegidas como inicio/fin; si no, segun el punto;
    -- un punto de inicio y fin a la vez cuenta como inicio hasta la hora del inicio elegido y como fin despues.
    INSERT INTO public.cl_sample_scans (account_id, sample_id, reader_id, scan_at, role, place_ref, mode_ref)
    SELECT v_plan.account_id, v_sid, r.reader_id, r.scan_at,
           CASE WHEN r.scan_id = r.start_scan_id THEN 'start'
                WHEN r.scan_id = r.end_scan_id THEN 'end'
                WHEN (r.is_start OR r.live_start) AND NOT (r.is_end OR r.live_end) THEN 'start'
                WHEN (r.is_end OR r.live_end) AND NOT (r.is_start OR r.live_start) THEN 'end'
                WHEN r.scan_at <= (SELECT a.scan_at FROM pg_temp.cl_sampler_rows a WHERE a.scan_id = r.start_scan_id) THEN 'start'
                ELSE 'end' END,
           r.place_ref, r.mode_ref
      FROM pg_temp.cl_sampler_rows r
     WHERE r.item_id = v_item AND (r.is_start OR r.is_end OR r.live_start OR r.live_end)
     ORDER BY r.row_ord;

    -- Posible mal encaminado (D5, regla del controlador): (a) la ciudad real de inicio o de fin no es la de la cuota,
    -- o (b) alguna lectura de inicio o de fin en un punto de una ciudad que no es ni el origen ni el destino de la
    -- cuota. Varias lecturas dentro de las ciudades de la propia ruta (admision + expedicion, un punto "cualquier
    -- modo" con otro papel en la misma ciudad) NO lo son. Una lectura no elegida en un punto sin ciudad no decide.
    UPDATE public.cl_samples sm SET possible_misrouting = true
     WHERE sm.id = v_sid
       AND (sm.origin_city_id IS DISTINCT FROM v_quota.origin_city_id
         OR sm.destination_city_id IS DISTINCT FROM v_quota.destination_city_id
         OR EXISTS (SELECT 1 FROM pg_temp.cl_sampler_rows r
                     WHERE r.item_id = v_item AND (r.is_start OR r.is_end OR r.live_start OR r.live_end)
                       AND r.city_id IS NOT NULL
                       AND r.city_id NOT IN (v_quota.origin_city_id, v_quota.destination_city_id)));
    IF FOUND THEN
      v_mis := v_mis || jsonb_build_array(jsonb_build_object('sample_id', v_sid, 'item_id', v_item));
    END IF;

    PERFORM public.cl_transfer_sample(v_sid);
  END LOOP;

  -- Cuenta para la cuota de la que se extrajo, aunque sea un posible mal encaminado (R15).
  UPDATE public.cl_plan_quotas SET samples_obtained = samples_obtained + cardinality(v_sel) WHERE id = p_stratum_id;

  INSERT INTO public.cl_sampling_runs (account_id, demand_id, batch_id, stratum_id, population_size, candidates_valid,
                                       samples_required, samples_selected, random_seed, selected_item_ids)
  VALUES (v_plan.account_id, v_demand.id, p_batch_id, p_stratum_id, v_pop, v_valid, v_req, cardinality(v_sel),
          v_demand.random_seed, v_sel)
  RETURNING * INTO v_run;

  -- Alertas.
  IF v_valid < v_req THEN
    PERFORM public.cl_raise_alert(v_plan.id, p_stratum_id, 'insufficient_candidates', 'medium',
      jsonb_build_object('batch_id', p_batch_id, 'candidates_valid', v_valid, 'samples_required', v_req));
  END IF;
  IF jsonb_array_length(v_mis) > 0 THEN
    PERFORM public.cl_raise_alert(v_plan.id, p_stratum_id, 'possible_misrouting', 'medium',
      jsonb_build_object('batch_id', p_batch_id, 'samples', v_mis,
                         'item_ids', (SELECT jsonb_agg(m->'item_id') FROM jsonb_array_elements(v_mis) m)));
  END IF;
  -- Distribucion sospechosa: n >= 20 muestras de la cuota con "en plazo" y todas en plazo.
  SELECT count(*), bool_and(o.on_time_delivery) INTO v_n, v_all_ok
    FROM public.cl_samples sm JOIN public.one_db o ON o.cl_sample_id = sm.id
   WHERE sm.quota_id = p_stratum_id AND sm.status = 'active' AND o.on_time_delivery IS NOT NULL;
  IF v_n >= 20 AND v_all_ok THEN
    PERFORM public.cl_raise_alert(v_plan.id, p_stratum_id, 'suspicious_distribution', 'medium',
      jsonb_build_object('batch_id', p_batch_id, 'samples', v_n, 'on_time_ratio', 1));
  END IF;

  DROP TABLE pg_temp.cl_sampler_rows;
  DROP TABLE pg_temp.cl_sampler_cands;
  RETURN public.cl_run_summary(v_run);
END $$;
REVOKE ALL ON FUNCTION public.cl_sample_stratum(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cl_sample_stratum(uuid, uuid) TO service_role;

-- ================================================================ I1: cl_undo_batch (de 20261120110700)
-- Cambio: un lote 'expired' (demanda caducada con el lote a medio sortear) tambien se puede deshacer, para no dejar
-- sin vuelta atras las muestras que ya tenia (antes de este cambio ese lote seguia 'validated' y se podia deshacer).
CREATE OR REPLACE FUNCTION public.cl_undo_batch(p_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_acc     uuid;
  v_car     uuid;
  v_plan    uuid;
  v_found   boolean;
  v_batch   public.cl_batches;
  v_demand  public.cl_demands;
  v_quotas  uuid[];
  v_one     integer;
  v_voided  integer;
  v_pending uuid[] := ARRAY[]::uuid[];
  v_carried uuid[] := ARRAY[]::uuid[];
  v_kept    uuid[] := ARRAY[]::uuid[];
  r         record;
BEGIN
  SELECT p.account_id, p.carrier_id, p.id INTO v_acc, v_car, v_plan
    FROM public.cl_batches b JOIN public.cl_demands d ON d.id = b.demand_id JOIN public.cl_plans p ON p.id = d.plan_id
   WHERE b.id = p_batch_id;
  v_found := FOUND;
  IF NOT v_found
     OR NOT (auth.uid() IS NULL
             OR public.is_superadmin()
             OR (v_acc = public.current_user_account_id() AND public.has_any_access(v_acc, 'edit', 'cl_monitor'))) THEN
    RAISE EXCEPTION 'Forbidden: batch not accessible' USING ERRCODE = '42501';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('cl_sample:' || v_acc::text || ':' || v_car::text));
  SELECT * INTO v_batch FROM public.cl_batches WHERE id = p_batch_id FOR UPDATE;
  IF v_batch.status = 'undone' THEN
    RAISE EXCEPTION 'CL_BATCH_ALREADY_UNDONE: batch is already undone' USING ERRCODE = '22023';
  END IF;
  IF v_batch.status NOT IN ('validated', 'sampled', 'expired') THEN
    RAISE EXCEPTION 'CL_BATCH_NOT_UNDOABLE: batch is %', v_batch.status USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_demand FROM public.cl_demands WHERE id = v_batch.demand_id FOR UPDATE;

  SELECT array_agg(DISTINCT x.qid) INTO v_quotas
    FROM (SELECT s.quota_id FROM public.cl_samples s WHERE s.batch_id = p_batch_id AND s.status = 'active'
          UNION SELECT r2.stratum_id FROM public.cl_sampling_runs r2 WHERE r2.batch_id = p_batch_id
          UNION SELECT (d->>'stratum_id')::uuid FROM jsonb_array_elements(v_demand.payload->'strata') d
                 WHERE NOT EXISTS (SELECT 1 FROM public.cl_sampling_runs r3 JOIN public.cl_batches b3 ON b3.id = r3.batch_id
                                    WHERE b3.demand_id = v_demand.id AND b3.id <> p_batch_id
                                      AND r3.stratum_id::text = d->>'stratum_id')) x(qid)
   WHERE x.qid IS NOT NULL;
  PERFORM 1 FROM public.cl_plan_quotas q WHERE q.id = ANY (v_quotas) ORDER BY q.id FOR UPDATE;

  DELETE FROM public.one_db o
   USING public.cl_samples s
   WHERE o.cl_sample_id = s.id AND s.batch_id = p_batch_id AND s.status = 'active';
  GET DIAGNOSTICS v_one = ROW_COUNT;

  WITH v AS (
    UPDATE public.cl_samples SET status = 'voided'
     WHERE batch_id = p_batch_id AND status = 'active'
    RETURNING quota_id
  ), u AS (
    UPDATE public.cl_plan_quotas q SET samples_obtained = GREATEST(q.samples_obtained - c.n, 0)
      FROM (SELECT v.quota_id, count(*)::integer AS n FROM v WHERE v.quota_id IS NOT NULL GROUP BY v.quota_id) c
     WHERE q.id = c.quota_id
    RETURNING q.id
  )
  SELECT count(*) INTO v_voided FROM v;

  DELETE FROM public.cl_sampling_runs WHERE batch_id = p_batch_id;
  UPDATE public.cl_batches SET status = 'undone' WHERE id = p_batch_id;
  UPDATE public.cl_demands SET status = 'failed' WHERE id = v_demand.id;

  FOR r IN SELECT q.id, q.status FROM public.cl_plan_quotas q WHERE q.id = ANY (v_quotas) ORDER BY q.period_start, q.id LOOP
    IF r.status = 'carried' THEN
      v_carried := v_carried || r.id;
      -- Una alerta por cuota y por lote deshecho (cada deshacer es un hecho a revisar; sin tope diario).
      INSERT INTO public.cl_alerts (account_id, plan_id, batch_id, quota_id, alert_type, severity, details)
      VALUES (v_acc, v_plan, p_batch_id, r.id, 'undo_after_carry', 'high',
              jsonb_build_object('batch_id', p_batch_id, 'demand_id', v_demand.id));
    ELSIF r.status = 'open' AND EXISTS (
            SELECT 1 FROM public.cl_demands d2
             WHERE d2.plan_id = v_plan AND d2.id <> v_demand.id AND d2.status = 'open'
               AND d2.payload->'strata' @> jsonb_build_array(jsonb_build_object('stratum_id', r.id))) THEN
      v_kept := v_kept || r.id;
    ELSE
      IF r.status <> 'pending' THEN
        UPDATE public.cl_plan_quotas SET status = 'pending' WHERE id = r.id;
      END IF;
      UPDATE public.cl_alerts a
         SET status = 'dismissed',
             details = COALESCE(a.details, '{}'::jsonb) || jsonb_build_object('dismissed_by_undo', p_batch_id)
       WHERE a.quota_id = r.id AND a.alert_type = 'quota_unfilled' AND a.status = 'open';
      v_pending := v_pending || r.id;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('batch_id', p_batch_id, 'status', 'undone', 'demand_id', v_demand.id,
                            'demand_status', 'failed', 'samples_voided', v_voided, 'one_db_deleted', v_one,
                            'quotas_pending', to_jsonb(v_pending), 'quotas_carried', to_jsonb(v_carried),
                            'quotas_kept_open', to_jsonb(v_kept));
END $$;
REVOKE ALL ON FUNCTION public.cl_undo_batch(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cl_undo_batch(uuid) TO authenticated, service_role;

-- ================================================================ I1, I2, M1: cl_emit_due_demands (de 20261120110700)
-- Cambios:
--   I1 caducidad (7 dias): toma primero el candado 'cl_sample:<cuenta>:<carrier>' del sorteo y bloquea en el mismo
--      orden (candado -> lotes -> demanda -> cuotas); si la demanda sigue 'open': failed + feed_silent, sus lotes
--      'validated' pasan a 'expired' (ya no se sortean) y se liquidan TODAS sus cuotas aun 'open' (tambien las de un
--      estrato ya sorteado en un lote sin cerrar), salvo las que esten 'open' en otra demanda abierta.
--   I2 demanda emitida con el conector en prueba (feed_testing): sus cuotas 'open' vuelven a 'pending' sin
--      cl_settle_quota (sin reparto ni unfilled).
--   M1 antes de tocar las cuotas pending del plan, se bloquean en orden de id.
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
  v_old record;
  v_qid uuid;
  v_status text;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('cl_emit_due_demands'));

  -- Tarea 9: demandas abiertas sin respuesta completa en 7 dias -> failed + alerta feed_silent; sus cuotas aun 'open'
  -- se liquidan (poblacion desconocida = se vuelven a pedir mientras demands_count < 3). En cada ejecucion,
  -- antes del calendario. Cada demanda aislada: un fallo deja alerta emit_failed y sigue.
  FOR v_old IN SELECT d.id, d.plan_id, d.payload, d.requested_at, d.feed_testing, p.account_id, p.carrier_id
                 FROM public.cl_demands d JOIN public.cl_plans p ON p.id = d.plan_id
                WHERE d.status = 'open' AND d.requested_at < p_now - interval '7 days'
                ORDER BY d.requested_at, d.id
  LOOP
    BEGIN
      -- Mismo candado y orden que cl_sample_stratum / cl_finish_batch / cl_undo_batch.
      PERFORM pg_advisory_xact_lock(hashtext('cl_sample:' || v_old.account_id::text || ':' || v_old.carrier_id::text));
      PERFORM 1 FROM public.cl_batches b WHERE b.demand_id = v_old.id AND b.status = 'validated' ORDER BY b.id FOR UPDATE;
      SELECT d.status INTO v_status FROM public.cl_demands d WHERE d.id = v_old.id FOR UPDATE;
      CONTINUE WHEN v_status IS DISTINCT FROM 'open';
      UPDATE public.cl_demands SET status = 'failed' WHERE id = v_old.id;
      -- Tras el bloqueo de la demanda ya no puede entrar un lote nuevo: tambien caduca uno guardado mientras se esperaba.
      UPDATE public.cl_batches SET status = 'expired' WHERE demand_id = v_old.id AND status = 'validated';
      PERFORM public.cl_raise_alert(v_old.plan_id, NULL, 'feed_silent', 'high',
        jsonb_build_object('demand_id', v_old.id, 'requested_at', v_old.requested_at));
      PERFORM 1 FROM public.cl_plan_quotas q
       WHERE q.id IN (SELECT (sd->>'stratum_id')::uuid FROM jsonb_array_elements(v_old.payload->'strata') sd)
         AND q.status = 'open'
       ORDER BY q.id
         FOR UPDATE;
      FOR v_qid IN SELECT q.id
                     FROM jsonb_array_elements(v_old.payload->'strata') sd
                     JOIN public.cl_plan_quotas q ON q.id = (sd->>'stratum_id')::uuid
                    WHERE q.status = 'open'
                      AND NOT EXISTS (SELECT 1 FROM public.cl_demands d2
                                       WHERE d2.plan_id = v_old.plan_id AND d2.id <> v_old.id AND d2.status = 'open'
                                         AND d2.payload->'strata' @> jsonb_build_array(jsonb_build_object('stratum_id', q.id)))
                    ORDER BY q.period_start, q.id
      LOOP
        IF v_old.feed_testing THEN
          UPDATE public.cl_plan_quotas SET status = 'pending' WHERE id = v_qid;
        ELSE
          PERFORM public.cl_settle_quota(v_qid);
        END IF;
      END LOOP;
    EXCEPTION WHEN OTHERS THEN
      PERFORM public.cl_raise_alert(v_old.plan_id, NULL, 'emit_failed', 'high',
                                    jsonb_build_object('demand_id', v_old.id, 'sqlstate', SQLSTATE, 'error', SQLERRM));
    END;
  END LOOP;

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

        -- M1: las cuotas pending del plan se bloquean primero, en orden de id (como cl_settle_quota).
        PERFORM 1 FROM public.cl_plan_quotas q WHERE q.plan_id = r.id AND q.status = 'pending' ORDER BY q.id FOR UPDATE;

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
REVOKE ALL ON FUNCTION public.cl_emit_due_demands(timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cl_emit_due_demands(timestamptz) TO service_role;

-- ================================================================ I4: ops_report._data (definicion VIVA de produccion)
-- Cambio: solo lectores RFID (capture_source = 'rfid') en la lista de lectores por centro, en las lecturas por centro y
-- en la seccion 'readers'. La copia del repo (20261117160000) difiere de la viva solo en el contacto
-- allocation_plan_manager (y comentarios); se parte de la viva.
CREATE OR REPLACE FUNCTION ops_report._data(p_account uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_tz text; v_today date; v_out jsonb;
BEGIN
  SELECT a.timezone INTO v_tz FROM public.accounts a WHERE a.id = p_account;
  IF v_tz IS NULL THEN RAISE EXCEPTION 'ops_report: cuenta no encontrada'; END IF;
  v_today := (now() AT TIME ZONE v_tz)::date;

  WITH
  pp AS (
    SELECT p.id, p.panelist_code AS code, p.name, p.email, p.mobile, p.node_id, p.city_id, p.telegram_id,
           p.language, p.created_at, p.address_city, n.auto_id AS node, c.name AS city, c.id AS node_city_id,
           COALESCE((SELECT e.pobox_enabled FROM public.effective_city_policy(c.id) e), false) AS pobox
      FROM public.panelists p
      LEFT JOIN public.nodes n ON n.id = p.node_id
      LEFT JOIN public.cities c ON c.id = n.city_id
     WHERE p.account_id = p_account AND p.status = 'active'),
  wd AS (SELECT g::date AS d FROM generate_series(p_from, p_to, interval '1 day') g WHERE extract(isodow FROM g) < 6),
  unav AS (SELECT u.panelist_id, g::date AS d, u.review_status
             FROM public.panelist_unavailability u
             CROSS JOIN LATERAL generate_series(u.start_date, u.end_date, interval '1 day') g
            WHERE u.account_id = p_account AND u.status = 'active'),
  apd AS (SELECT d.*, (d.sent_at AT TIME ZONE v_tz) AS sent_l, (d.received_at AT TIME ZONE v_tz) AS recv_l
            FROM public.allocation_plan_details d WHERE d.account_id = p_account),
  act AS (
    SELECT pp.id AS pid, a.sent_l::date AS d FROM pp JOIN apd a ON a.origin_node_id = pp.node_id WHERE a.sent_at IS NOT NULL
    UNION SELECT pp.id, a.recv_l::date FROM pp JOIN apd a ON a.destination_node_id = pp.node_id WHERE a.received_at IS NOT NULL
    UNION SELECT r.panelist_id, (r.last_attempt_at AT TIME ZONE v_tz)::date FROM public.receipt_case r WHERE r.account_id = p_account
    UNION SELECT i.panelist_id, (i.reported_at AT TIME ZONE v_tz)::date FROM public.panelist_incident i WHERE i.account_id = p_account
    UNION SELECT m.panelist_id, (m.created_at AT TIME ZONE v_tz)::date FROM public.incident_message m
           WHERE m.account_id = p_account AND m.direction = 'inbound'),
  prog AS (SELECT a.origin_node_id AS node_id, a.fecha_programada AS f, a.sent_l::date AS s
             FROM apd a WHERE a.fecha_programada BETWEEN p_from AND p_to AND a.status <> 'cancelled'),
  pan AS (
    SELECT pp.*,
      (SELECT count(*) FROM prog WHERE prog.node_id = pp.node_id) AS scheduled,
      (SELECT count(*) FROM prog WHERE prog.node_id = pp.node_id AND prog.s = prog.f) AS on_time,
      (SELECT count(*) FROM prog WHERE prog.node_id = pp.node_id AND prog.s > prog.f) AS late,
      (SELECT max(prog.s - prog.f) FROM prog WHERE prog.node_id = pp.node_id AND prog.s > prog.f) AS max_late_days,
      (SELECT count(*) FROM prog WHERE prog.node_id = pp.node_id AND prog.s < prog.f) AS early,
      (SELECT count(*) FROM prog WHERE prog.node_id = pp.node_id AND prog.s IS NULL) AS unsent,
      (SELECT count(*) FROM apd a WHERE a.origin_node_id = pp.node_id AND a.fecha_programada < v_today
                                    AND a.status IN ('pending','notified')) AS unsent_total,
      (SELECT count(*) FROM apd a WHERE a.origin_node_id = pp.node_id AND a.sent_l::date BETWEEN p_from AND p_to
                                    AND (extract(hour FROM a.sent_l) < 7 OR extract(hour FROM a.sent_l) >= 19)) AS odd_hour,
      (SELECT count(*) FROM apd a WHERE a.origin_node_id = pp.node_id AND a.sent_l::date BETWEEN p_from AND p_to
                                    AND extract(isodow FROM a.sent_l) > 5) AS weekend,
      (SELECT count(*) FROM (SELECT date_trunc('minute', a.sent_at) AS m FROM apd a
                              WHERE a.origin_node_id = pp.node_id AND a.sent_l::date BETWEEN p_from AND p_to
                              GROUP BY 1 HAVING count(*) >= 2 AND count(DISTINCT a.fecha_programada) >= 2) x) AS bursts,
      (SELECT count(*) FROM public.receipt_case r WHERE r.culprit_panelist_id = pp.id AND r.reason = 'pobox_absent_no_visit') AS pobox_no_visit,
      (SELECT COALESCE(jsonb_object_agg(x.reason, x.n), '{}'::jsonb) FROM (
         SELECT r.reason, count(*) AS n FROM public.receipt_case r JOIN apd a ON a.id = r.detail_id
          WHERE a.origin_node_id = pp.node_id AND r.reason NOT IN ('ok','ok_same_city') GROUP BY 1) x) AS sent_problems,
      (SELECT count(*) FROM public.receipt_case r WHERE r.culprit_panelist_id = pp.id AND r.culprit_role = 'sender') AS sender_fault,
      (SELECT COALESCE(jsonb_object_agg(x.k, x.n), '{}'::jsonb) FROM (
         SELECT r.reason || CASE WHEN r.status IN ('pending','needs_decision') THEN ':open' ELSE '' END AS k, count(*) AS n
           FROM public.receipt_case r WHERE r.panelist_id = pp.id
            AND r.reason NOT IN ('ok','ok_same_city','ok_typo_fixed') GROUP BY 1) x) AS recv_problems,
      (SELECT count(*) FROM public.panelist_incident i WHERE i.panelist_id = pp.id AND i.category = 'unreadable_label_receipt') AS unreadable,
      (SELECT count(*) FROM apd a WHERE a.destination_node_id = pp.node_id AND a.received_at IS NOT NULL) AS received_total,
      (SELECT count(*) FROM apd a WHERE a.destination_node_id = pp.node_id AND a.status = 'sent' AND a.sent_at < now() - interval '7 days') AS waiting_7d,
      (SELECT min(a.sent_l)::date FROM apd a WHERE a.destination_node_id = pp.node_id AND a.status = 'sent') AS oldest_waiting,
      (SELECT count(*) FROM apd a WHERE a.origin_node_id = pp.node_id AND a.sent_at IS NOT NULL) AS sent_total,
      (SELECT max(a.sent_l)::date FROM apd a WHERE a.origin_node_id = pp.node_id) AS last_sent,
      (SELECT COALESCE(jsonb_agg(to_char(wd.d,'YYYY-MM-DD') ORDER BY wd.d), '[]'::jsonb) FROM wd
        WHERE wd.d >= (pp.created_at AT TIME ZONE v_tz)::date
          AND NOT EXISTS (SELECT 1 FROM act WHERE act.pid = pp.id AND act.d = wd.d)
          AND NOT EXISTS (SELECT 1 FROM unav WHERE unav.panelist_id = pp.id AND unav.d = wd.d)) AS inactive_days,
      (SELECT max(act.d) FROM act WHERE act.pid = pp.id) AS last_activity,
      (SELECT count(DISTINCT unav.d) FROM unav WHERE unav.panelist_id = pp.id AND unav.review_status = 'reviewed'
          AND date_trunc('month', unav.d) = date_trunc('month', v_today::timestamp) AND extract(isodow FROM unav.d) < 6) AS leave_month_ok,
      (SELECT count(DISTINCT unav.d) FROM unav WHERE unav.panelist_id = pp.id AND unav.review_status <> 'reviewed'
          AND date_trunc('month', unav.d) = date_trunc('month', v_today::timestamp) AND extract(isodow FROM unav.d) < 6) AS leave_month_pending,
      (SELECT count(DISTINCT unav.d) FROM unav WHERE unav.panelist_id = pp.id AND unav.review_status = 'reviewed'
          AND extract(year FROM unav.d) = extract(year FROM v_today) AND extract(isodow FROM unav.d) < 6) AS leave_year_ok,
      (SELECT count(DISTINCT unav.d) FROM unav WHERE unav.panelist_id = pp.id AND unav.review_status <> 'reviewed'
          AND extract(year FROM unav.d) = extract(year FROM v_today) AND extract(isodow FROM unav.d) < 6) AS leave_year_pending,
      (SELECT count(*) FROM public.material_hold h WHERE h.panelist_id = pp.id AND h.released_at IS NULL) AS held,
      (SELECT jsonb_build_object('total', count(*),
                'ok', count(*) FILTER (WHERE g.s = 'ok'), 'far', count(*) FILTER (WHERE g.s = 'far'),
                'low_accuracy', count(*) FILTER (WHERE g.s = 'low_accuracy'),
                'no_reference', count(*) FILTER (WHERE g.s = 'no_reference'),
                'no_location', count(*) FILTER (WHERE g.s = 'no_location'),
                'gps_unavailable', count(*) FILTER (WHERE g.s = 'gps_unavailable'),
                'no_consent', count(*) FILTER (WHERE g.s = 'no_consent'),
                'no_answer', count(*) FILTER (WHERE g.s = 'no_answer'),
                'consent', (SELECT c.decision FROM public.panelist_location_consent c WHERE c.panelist_id = pp.id
                             ORDER BY c.decided_at DESC, c.id DESC LIMIT 1))
         FROM (SELECT a.sent_gps_status AS s FROM apd a
                WHERE a.sent_gps_status IS NOT NULL AND a.sent_l::date BETWEEN p_from AND p_to
                  AND (a.origin_panelist_id = pp.id OR (a.origin_panelist_id IS NULL AND a.origin_node_id = pp.node_id))
               UNION ALL
               SELECT a.received_gps_status FROM apd a
                WHERE a.received_gps_status IS NOT NULL AND a.recv_l::date BETWEEN p_from AND p_to
                  AND (a.destination_panelist_id = pp.id
                       OR (a.destination_panelist_id IS NULL AND a.destination_node_id = pp.node_id))) g) AS gps
    FROM pp),
  pcs AS (
    SELECT pc.id, pc.name, pc.city_id,
           (SELECT COALESCE(jsonb_agg(r.reader_id ORDER BY r.reader_id), '[]'::jsonb) FROM public.readers r
             WHERE r.postal_center_id = pc.id AND r.deleted_at IS NULL AND r.is_active
               AND r.capture_source = 'rfid') AS readers
      FROM public.postal_centers pc WHERE pc.account_id = p_account AND pc.deleted_at IS NULL AND pc.is_active),
  trips AS (SELECT a.tag_id, a.sent_l, a.recv_l, a.sent_at, no.city_id AS oc, nd.city_id AS dc
              FROM apd a JOIN public.nodes no ON no.id = a.origin_node_id JOIN public.nodes nd ON nd.id = a.destination_node_id
             WHERE a.sent_at IS NOT NULL),
  reads AS (SELECT DISTINCT r.postal_center_id AS pc, e.tag_id FROM public.rfid_events_raw e
              JOIN public.readers r ON r.reader_id = e.reader_id AND r.account_id = p_account AND r.capture_source = 'rfid'
             WHERE e.account_id = p_account)
  SELECT jsonb_build_object(
    'account', (SELECT jsonb_build_object('name', a.name, 'timezone', a.timezone, 'language', a.default_language,
                  'today', v_today, 'from', p_from, 'to', p_to,
                  'contacts', jsonb_build_object('account_manager', a.email_account_manager,
                     'panelist_manager', a.email_panelist_manager, 'materials_supplier', a.email_materials_supplier,
                     'do_coordinator', a.email_do_coordinator, 'upu_account_manager', a.email_upu_account_manager, 'allocation_plan_manager', a.email_allocation_plan_manager))
                  FROM public.accounts a WHERE a.id = p_account),
    'material', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                   'code', pp.code, 'name', pp.name, 'email', pp.email, 'mobile', pp.mobile, 'city', btrim(pp.city), 'node', pp.node,
                   'missing', (SELECT jsonb_agg(jsonb_build_object('name', m->>'name', 'quantity', m->'quantity', 'unit', m->>'unit'))
                                 FROM jsonb_array_elements(COALESCE(i.payload->'materials', '[]'::jsonb)) m),
                   'reported', (i.reported_at AT TIME ZONE v_tz)::date, 'seen', i.manager_seen_at IS NOT NULL,
                   'shipment_status', (SELECT s.status FROM public.material_shipments s WHERE s.id = i.linked_material_shipment_id),
                   'held', (SELECT count(*) FROM public.material_hold h WHERE h.panelist_id = i.panelist_id AND h.released_at IS NULL),
                   'held_since', (SELECT min(h.held_since AT TIME ZONE v_tz)::date FROM public.material_hold h
                                   WHERE h.panelist_id = i.panelist_id AND h.released_at IS NULL)) ORDER BY i.reported_at), '[]'::jsonb)
                   FROM public.panelist_incident i JOIN pp ON pp.id = i.panelist_id
                  WHERE i.account_id = p_account AND i.category = 'missing_materials' AND i.status = 'open'),
    'panelists', (SELECT COALESCE(jsonb_agg(to_jsonb(pan) - 'id' - 'node_id' - 'city_id' - 'node_city_id' - 'telegram_id'
                                              - 'created_at' || jsonb_build_object('created', (pan.created_at AT TIME ZONE v_tz)::date,
                                                 'city', btrim(pan.city), 'has_telegram', pan.telegram_id IS NOT NULL,
                                                 'city_mismatch', pan.node_id IS NOT NULL AND pan.city_id IS DISTINCT FROM pan.node_city_id)
                                   ORDER BY pan.code), '[]'::jsonb) FROM pan),
    'pending_leave', (SELECT COALESCE(jsonb_agg(jsonb_build_object('code', pp.code, 'name', pp.name, 'start', u.start_date,
                        'end', u.end_date, 'requested', (u.created_at AT TIME ZONE v_tz)::date) ORDER BY u.start_date, pp.code), '[]'::jsonb)
                        FROM public.panelist_unavailability u JOIN pp ON pp.id = u.panelist_id
                       WHERE u.status = 'active' AND u.review_status <> 'reviewed' AND u.end_date >= v_today),
    'free_nodes', (SELECT COALESCE(jsonb_agg(jsonb_build_object('node', n.auto_id, 'city', btrim(c.name)) ORDER BY n.auto_id), '[]'::jsonb)
                     FROM public.nodes n JOIN public.cities c ON c.id = n.city_id
                    WHERE n.account_id = p_account AND n.status = 'active'
                      AND NOT EXISTS (SELECT 1 FROM pp WHERE pp.node_id = n.id)),
    'rfid_study', (SELECT COALESCE(jsonb_agg(jsonb_build_object('postal_center', pcs.name, 'readers', pcs.readers,
        'out', (SELECT count(*) FROM trips t WHERE t.oc = pcs.city_id AND t.sent_l::date BETWEEN p_from AND p_to),
        'out_read', (SELECT count(*) FROM trips t WHERE t.oc = pcs.city_id AND t.sent_l::date BETWEEN p_from AND p_to
                       AND EXISTS (SELECT 1 FROM reads WHERE reads.pc = pcs.id AND reads.tag_id = t.tag_id)),
        'in', (SELECT count(*) FROM trips t WHERE t.dc = pcs.city_id AND t.recv_l::date BETWEEN p_from AND p_to),
        'in_read', (SELECT count(*) FROM trips t WHERE t.dc = pcs.city_id AND t.recv_l::date BETWEEN p_from AND p_to
                       AND EXISTS (SELECT 1 FROM reads WHERE reads.pc = pcs.id AND reads.tag_id = t.tag_id)),
        'out_total', (SELECT count(*) FROM trips t WHERE t.oc = pcs.city_id),
        'out_total_read', (SELECT count(*) FROM trips t WHERE t.oc = pcs.city_id
                       AND EXISTS (SELECT 1 FROM reads WHERE reads.pc = pcs.id AND reads.tag_id = t.tag_id)))
        ORDER BY pcs.name), '[]'::jsonb) FROM pcs),
    'config', jsonb_build_object(
      'sla_count', (SELECT count(*) FROM public.slas s WHERE s.account_id = p_account)
                 + (SELECT count(*) FROM public.sla_definitions s WHERE s.account_id = p_account),
      'lanes', (WITH l AS (SELECT DISTINCT ap.product_id, no.city_id AS oc, nd.city_id AS dc
                             FROM apd a JOIN public.allocation_plans ap ON ap.id = a.plan_id
                             JOIN public.nodes no ON no.id = a.origin_node_id JOIN public.nodes nd ON nd.id = a.destination_node_id
                            WHERE a.status <> 'cancelled'),
                     m AS (SELECT * FROM l WHERE NOT EXISTS (SELECT 1 FROM public.delivery_standards s
                             WHERE s.product_id = l.product_id AND s.origin_city_id = l.oc AND s.destination_city_id = l.dc))
                SELECT jsonb_build_object('total', (SELECT count(*) FROM l), 'missing', (SELECT count(*) FROM m),
                  'cities', (SELECT COALESCE(jsonb_agg(x.c ORDER BY x.n DESC), '[]'::jsonb) FROM (
                     SELECT btrim(c.name) AS c, count(*) AS n FROM m JOIN public.cities c ON c.id IN (m.oc, m.dc)
                      GROUP BY 1 HAVING count(*) >= 10) x))),
      'pc_total', (SELECT count(*) FROM pcs),
      'pc_no_hours', (SELECT count(*) FROM public.postal_centers p WHERE p.account_id = p_account AND p.deleted_at IS NULL
                         AND (p.opening_hour IS NULL OR p.working_hours_end IS NULL)),
      'pc_no_city', (SELECT COALESCE(jsonb_agg(p.name ORDER BY p.name), '[]'::jsonb) FROM public.postal_centers p
                      WHERE p.account_id = p_account AND p.deleted_at IS NULL AND p.city_id IS NULL),
      'city_no_pc', (SELECT COALESCE(jsonb_agg(btrim(c.name) ORDER BY c.name), '[]'::jsonb) FROM public.cities c
                      WHERE c.account_id = p_account AND EXISTS (SELECT 1 FROM public.nodes n WHERE n.city_id = c.id)
                        AND NOT EXISTS (SELECT 1 FROM public.postal_centers p WHERE p.city_id = c.id AND p.deleted_at IS NULL)),
      'city_spaces', (SELECT COALESCE(jsonb_agg(btrim(c.name) ORDER BY c.name), '[]'::jsonb) FROM public.cities c
                       WHERE c.account_id = p_account AND c.name <> btrim(c.name)),
      'panelists_total', (SELECT count(*) FROM pp WHERE pp.node_id IS NOT NULL),
      'panelists_with_stock', (SELECT count(DISTINCT s.panelist_id) FROM public.panelist_material_stocks s JOIN pp ON pp.id = s.panelist_id),
      'blocking_materials', (SELECT count(*) FROM public.material_catalog m WHERE m.account_id = p_account AND m.is_blocking),
      'held_total', (SELECT count(*) FROM public.material_hold h WHERE h.account_id = p_account AND h.released_at IS NULL),
      'product_desc_mismatch', (SELECT COALESCE(jsonb_agg(p.code ORDER BY p.code), '[]'::jsonb) FROM public.products p
                                 WHERE p.account_id = p_account AND p.status = 'active' AND (
                                   (p.code ILIKE '%express%' AND p.description ILIKE '%economy%')
                                OR (p.code ILIKE '%economy%' AND p.description ILIKE '%express%')
                                OR (p.code ILIKE '%standard%' AND (p.description ILIKE '%express%' OR p.description ILIKE '%economy%')))),
      'account_country', (SELECT a.country_code FROM public.accounts a WHERE a.id = p_account),
      'account_admin_email', (SELECT a.admin_email IS NOT NULL FROM public.accounts a WHERE a.id = p_account),
      'pobox_no_shares', (SELECT c.pobox_enabled AND jsonb_array_length(COALESCE(c.pobox_product_shares, '[]'::jsonb)) = 0
                            FROM public.account_config c WHERE c.account_id = p_account),
      'dup_mobile', (SELECT COALESCE(jsonb_agg(x.codes), '[]'::jsonb) FROM (
                       SELECT jsonb_agg(pp.code ORDER BY pp.code) AS codes FROM pp WHERE COALESCE(pp.mobile,'') <> ''
                        GROUP BY regexp_replace(pp.mobile, '\D', '', 'g') HAVING count(*) > 1) x),
      'dup_email', (SELECT COALESCE(jsonb_agg(x.codes), '[]'::jsonb) FROM (
                       SELECT jsonb_agg(pp.code ORDER BY pp.code) AS codes FROM pp WHERE COALESCE(pp.email,'') <> ''
                        GROUP BY lower(pp.email) HAVING count(*) > 1) x),
      'gps_reference', (WITH gc AS (SELECT DISTINCT pp.node_city_id AS id, btrim(pp.city) AS name FROM pp
                                     WHERE pp.node_city_id IS NOT NULL),
                             med AS (SELECT pc.city_id,
                                            percentile_cont(0.5) WITHIN GROUP (ORDER BY dl.distance_m::float8) AS m,
                                            count(*) AS n
                                       FROM public.declaration_location dl
                                       JOIN public.postal_centers pc ON pc.id = dl.nearest_postal_center_id
                                      WHERE dl.account_id = p_account AND dl.status IN ('ok','far')
                                        AND dl.distance_m IS NOT NULL
                                        AND (dl.received_at AT TIME ZONE v_tz)::date BETWEEN p_from AND p_to
                                      GROUP BY pc.city_id)
                        SELECT COALESCE(jsonb_agg(y.x ORDER BY y.x->>'city', y.x->>'reason'), '[]'::jsonb) FROM (
                          SELECT jsonb_build_object('city', gc.name, 'reason', 'no_coords') AS x FROM gc
                           WHERE NOT EXISTS (SELECT 1 FROM public.postal_centers p
                                              WHERE p.city_id = gc.id AND p.account_id = p_account AND p.deleted_at IS NULL
                                                AND p.latitude IS NOT NULL AND p.longitude IS NOT NULL)
                          UNION ALL
                          SELECT jsonb_build_object('city', btrim(c.name), 'reason', 'median_far',
                                                    'median_m', round(med.m::numeric), 'n', med.n)
                            FROM med JOIN public.cities c ON c.id = med.city_id
                           WHERE med.m > 500) y)),
    'readers', (SELECT COALESCE(jsonb_agg(jsonb_build_object('lpi', r.reader_id, 'name', r.name, 'postal_center', pc.name)
                  ORDER BY r.reader_id), '[]'::jsonb)
                  FROM public.readers r LEFT JOIN public.postal_centers pc ON pc.id = r.postal_center_id
                 WHERE r.account_id = p_account AND r.deleted_at IS NULL AND r.is_active
                   AND r.capture_source = 'rfid'),
    'has_schedule', EXISTS (SELECT 1 FROM apd a WHERE a.status <> 'cancelled' AND a.fecha_programada <= p_to)
  ) INTO v_out;
  RETURN v_out;
END $function$
;

-- ================================================================ I4: v_mobile_readers (definicion VIVA; igual que el baseline)
-- Cambio: solo lectores RFID. Mismas columnas y orden; sin opciones de vista (como la viva).
CREATE OR REPLACE VIEW public.v_mobile_readers AS
 SELECT r.id AS reader_id,
    r.account_id,
    r.reader_id AS reader_code,
    r.name AS reader_name,
    r.type AS reader_type,
    r.postal_center_id AS current_center_id,
    pc.code AS current_center_code,
    pc.name AS current_center_name,
    rlh_current.assigned_at AS current_assignment_since,
    rlh_current.notes AS current_assignment_notes,
    ( SELECT count(*) AS count
           FROM public.reader_location_history rlh2
          WHERE rlh2.reader_id = r.id) AS total_assignments,
    ( SELECT count(*) > 1
           FROM public.reader_location_history rlh3
          WHERE rlh3.reader_id = r.id) AS is_mobile,
    r.is_active,
    r.created_at,
    r.updated_at
   FROM public.readers r
     LEFT JOIN public.postal_centers pc ON pc.id = r.postal_center_id
     LEFT JOIN public.reader_location_history rlh_current ON rlh_current.reader_id = r.id AND rlh_current.unassigned_at IS NULL
  WHERE r.is_active = true AND r.capture_source = 'rfid';

-- ================================================================ M2: reenrich_processed_events (definicion VIVA; igual que 20261030142158)
-- Cambio: el enriquecimiento por tag_id solo usa filas one_db de panelistas (las muestras del transportista no
-- tienen tag RFID y no deben cruzarse con processed_events).
CREATE OR REPLACE FUNCTION public.reenrich_processed_events(p_account_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_n integer;
BEGIN
  UPDATE processed_events pe
     SET origin_city_name      = COALESCE(pe.origin_city_name, o.origin_city_name),
         destination_city_name = COALESCE(pe.destination_city_name, o.destination_city_name),
         carrier_id            = COALESCE(pe.carrier_id, c.id),
         product_id            = COALESCE(pe.product_id, p.id)
    FROM (
          SELECT DISTINCT ON (tag_id)
                 tag_id, carrier_name, product_name, origin_city_name, destination_city_name
            FROM one_db
           WHERE account_id = p_account_id
             AND source = 'panelist'
             AND tag_id IS NOT NULL
           ORDER BY tag_id, sent_at DESC NULLS LAST, created_at DESC
         ) o
    LEFT JOIN carriers c ON c.account_id = p_account_id AND c.name = o.carrier_name
    LEFT JOIN LATERAL (
           SELECT pr.id FROM products pr
            WHERE pr.carrier_id = c.id
              AND (pr.code = o.product_name OR pr.description = o.product_name)
            ORDER BY (pr.code = o.product_name) DESC, pr.code
            LIMIT 1
         ) p ON TRUE
   WHERE pe.account_id = p_account_id
     AND pe.tag_id = o.tag_id
     AND (   pe.origin_city_name IS NULL
          OR (pe.carrier_id IS NULL AND c.id IS NOT NULL)
          OR (pe.product_id IS NULL AND p.id IS NOT NULL));

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$function$
;
