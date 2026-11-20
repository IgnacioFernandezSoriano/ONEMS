-- Carrier Link: la API (PostgREST) de Supabase carga pg-safeupdate, que rechaza todo UPDATE/DELETE sin WHERE
-- (error 21000 "UPDATE requires a WHERE clause"). cl_ingest_batch tenia 3 UPDATE sobre sus tablas temporales sin
-- WHERE: fallaba al llamarla carrier-link-ingest. Se recrea el cuerpo vivo (= 20261120110700) con WHERE true en
-- esos 3 UPDATE; nada mas cambia.
CREATE OR REPLACE FUNCTION public.cl_ingest_batch(p_feed_id uuid, p_payload jsonb, p_dry_run boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  c_method   constant text := 'uniform_random_within_stratum';
  c_max_rows constant integer := 5000;     -- margen frente al statement timeout de la instancia
  c_max_id   constant integer := 200;      -- item_id / place_ref / mode_ref (limite de fila del indice btree)
  c_max_extra constant integer := 500;     -- valor de un campo adicional
  v_dry      boolean := COALESCE(p_dry_run, false);
  v_demand   public.cl_demands;
  v_feed     public.cl_feeds;
  v_plan     public.cl_plans;
  v_demand_id uuid;
  v_cbatch   text;
  v_strata   jsonb;
  v_batch    uuid := gen_random_uuid();
  v_existing public.cl_batches;
  v_summary  jsonb;
  v_strata_summary jsonb;
  v_raw      jsonb;
  v_bad      jsonb;
  v_total    bigint;
  f_item text; f_product text; f_scan text; f_place text; f_mode text; v_fmt text; v_map_tz text;
  v_scan_tz  text;
  v_acc_tz   text;
  v_extra    text[];
  v_allowed  text[];
  v_mapped   text[];
  v_st       record;
  v_denom    bigint;
  v_rej      bigint;
  v_vals     jsonb;
BEGIN
  IF p_feed_id IS NULL OR p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'CL_BAD_PAYLOAD: the batch must be a JSON object' USING ERRCODE = '22023';
  END IF;
  BEGIN
    v_demand_id := (p_payload->>'demand_id')::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    v_demand_id := NULL;
  END;
  v_cbatch := p_payload->>'batch_id';   -- se guarda tal cual
  IF v_cbatch IS NULL OR btrim(v_cbatch) = '' OR length(v_cbatch) > 200 THEN
    RAISE EXCEPTION 'CL_BAD_PAYLOAD: batch_id is required (max 200 characters)' USING ERRCODE = '22023';
  END IF;

  -- 1. La demanda tiene que ser del conector autenticado (p_feed_id viene de la clave, nunca del cuerpo).
  --    El bloqueo serializa dos entregas simultaneas de la misma demanda.
  SELECT d.* INTO v_demand FROM public.cl_demands d
   WHERE d.id = v_demand_id AND d.feed_id = p_feed_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CL_DEMAND_NOT_OPEN: demand not found for this connector' USING ERRCODE = 'P0001';
  END IF;

  -- 2. Lote repetido: su resumen, sin escribir nada (tambien si la demanda ya se cerro, para reintentos del conector).
  SELECT b.* INTO v_existing FROM public.cl_batches b
   WHERE b.demand_id = v_demand.id AND b.connector_batch_id = v_cbatch;
  IF FOUND THEN
    RETURN v_existing.summary;
  END IF;
  IF v_demand.status <> 'open' THEN
    RAISE EXCEPTION 'CL_DEMAND_NOT_OPEN: demand is %', v_demand.status USING ERRCODE = 'P0001';
  END IF;

  -- 2b. Conector pausado: no acepta lotes nuevos (ni de prueba); los ya guardados se devuelven arriba.
  SELECT f.* INTO v_feed FROM public.cl_feeds f WHERE f.id = p_feed_id;
  IF v_feed.status = 'paused' THEN
    RAISE EXCEPTION 'CL_FEED_PAUSED: the connector is paused' USING ERRCODE = '22023';
  END IF;

  SELECT p.* INTO v_plan FROM public.cl_plans p WHERE p.id = v_demand.plan_id;
  IF v_feed.carrier_id IS DISTINCT FROM v_plan.carrier_id THEN
    RAISE EXCEPTION 'CL_FEED_CARRIER_MISMATCH: connector and plan use different carriers' USING ERRCODE = '22023';
  END IF;

  -- Forma del lote.
  v_strata := p_payload->'strata';
  IF v_strata IS NULL OR jsonb_typeof(v_strata) <> 'array' OR jsonb_array_length(v_strata) = 0 THEN
    RAISE EXCEPTION 'CL_BAD_PAYLOAD: strata must be a non-empty array' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_strata) e
              WHERE jsonb_typeof(e) <> 'object' OR jsonb_typeof(e->'rows') IS DISTINCT FROM 'array') THEN
    RAISE EXCEPTION 'CL_BAD_PAYLOAD: every stratum needs a rows array' USING ERRCODE = '22023';
  END IF;
  SELECT sum(jsonb_array_length(e->'rows')) INTO v_total FROM jsonb_array_elements(v_strata) e;
  IF v_total > c_max_rows THEN
    RAISE EXCEPTION 'CL_TOO_MANY_ROWS: % rows (max %)', v_total, c_max_rows USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_strata) e
              WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_demand.payload->'strata') d
                                 WHERE d->>'stratum_id' = e->>'stratum_id')) THEN
    RAISE EXCEPTION 'CL_UNKNOWN_STRATUM: a stratum is not part of this demand' USING ERRCODE = '22023';
  END IF;
  IF (SELECT count(*) <> count(DISTINCT e->>'stratum_id') FROM jsonb_array_elements(v_strata) e) THEN
    RAISE EXCEPTION 'CL_BAD_PAYLOAD: repeated stratum_id' USING ERRCODE = '22023';
  END IF;
  -- Tarea 9: una demanda puede llegar en varios lotes (tope de filas), pero cada estrato solo una vez: se rechaza un
  -- estrato ya sorteado o ya entregado en otro lote validated/sampled de esta demanda (tambien en dry_run).
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_strata) e
              WHERE EXISTS (SELECT 1 FROM public.cl_batches b
                             WHERE b.demand_id = v_demand.id
                               AND (EXISTS (SELECT 1 FROM public.cl_sampling_runs r
                                             WHERE r.batch_id = b.id AND r.stratum_id::text = e->>'stratum_id')
                                    OR (b.status IN ('validated','sampled')
                                        AND EXISTS (SELECT 1 FROM jsonb_array_elements(b.summary->'strata') s
                                                     WHERE s->>'stratum_id' = e->>'stratum_id'))))) THEN
    RAISE EXCEPTION 'CL_STRATUM_ALREADY_DELIVERED: a stratum of this batch was already delivered for this demand'
      USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_strata) e
              WHERE CASE WHEN jsonb_typeof(e->'population_size') = 'number'
                         THEN (e->>'population_size')::numeric < 0
                           OR (e->>'population_size')::numeric > 2147483647
                           OR (e->>'population_size')::numeric <> trunc((e->>'population_size')::numeric)
                         ELSE true END) THEN
    RAISE EXCEPTION 'CL_BAD_PAYLOAD: population_size must be a non-negative integer' USING ERRCODE = '22023';
  END IF;

  -- 3. Metodo de seleccion distinto: lote rechazado entero.
  SELECT jsonb_agg(jsonb_build_object('stratum_id', e->>'stratum_id',
                                      'selection_method', left(e->>'selection_method', 100)) ORDER BY o)
    INTO v_bad
    FROM jsonb_array_elements(v_strata) WITH ORDINALITY x(e, o)
   WHERE e->>'selection_method' IS DISTINCT FROM c_method;
  IF v_bad IS NOT NULL THEN
    v_summary := jsonb_build_object('batch', CASE WHEN v_dry THEN NULL ELSE v_batch END, 'status', 'rejected',
                                    'reason', 'selection_method', 'expected', c_method, 'strata', v_bad);
    IF v_dry THEN
      RETURN v_summary || jsonb_build_object('dry_run', true);
    END IF;
    INSERT INTO public.cl_batches (id, account_id, demand_id, connector_batch_id, status, summary)
    VALUES (v_batch, v_plan.account_id, v_demand.id, v_cbatch, 'rejected', v_summary);
    PERFORM public.cl_raise_alert(v_plan.id, NULL, 'selection_method', 'high',
      jsonb_build_object('batch_id', v_batch, 'demand_id', v_demand.id, 'expected', c_method, 'strata', v_bad));
    UPDATE public.cl_feeds SET last_batch_at = now() WHERE id = p_feed_id;
    RETURN v_summary;
  END IF;

  -- Equivalencias del carrier.
  SELECT max(m.carrier_field) FILTER (WHERE m.standard_field = 'item_id'),
         max(m.carrier_field) FILTER (WHERE m.standard_field = 'product'),
         max(m.carrier_field) FILTER (WHERE m.standard_field = 'scan_at'),
         max(m.carrier_field) FILTER (WHERE m.standard_field = 'place_ref'),
         max(m.carrier_field) FILTER (WHERE m.standard_field = 'mode_ref'),
         max(m.format)        FILTER (WHERE m.standard_field = 'scan_at'),
         max(m.timezone)      FILTER (WHERE m.standard_field = 'scan_at')
    INTO f_item, f_product, f_scan, f_place, f_mode, v_fmt, v_map_tz
    FROM public.cl_field_mappings m
   WHERE m.account_id = v_plan.account_id AND m.carrier_id = v_plan.carrier_id;
  IF f_item IS NULL OR f_scan IS NULL OR f_place IS NULL THEN
    RAISE EXCEPTION 'CL_MAPPING_INCOMPLETE: item_id, scan_at and place_ref must be mapped' USING ERRCODE = '22023';
  END IF;
  SELECT COALESCE(array_agg(x.carrier_field), ARRAY[]::text[]) INTO v_extra
    FROM public.cl_extra_fields x
   WHERE x.account_id = v_plan.account_id AND x.carrier_id = v_plan.carrier_id;
  v_mapped := array_remove(ARRAY[f_item, f_product, f_scan, f_place, f_mode], NULL);
  v_allowed := v_mapped || v_extra;

  -- Zonas: lecturas sin desfase -> zona del mapeo (si es valida) o de la cuenta; fecha local del fin -> cuenta.
  v_acc_tz := COALESCE((SELECT a.timezone FROM public.accounts a
                         WHERE a.id = v_plan.account_id AND a.timezone IS NOT NULL
                           AND public.cl_is_valid_timezone(a.timezone)), 'UTC');
  v_scan_tz := CASE WHEN v_map_tz IS NOT NULL AND btrim(v_map_tz) <> '' AND public.cl_is_valid_timezone(v_map_tz)
                    THEN v_map_tz ELSE v_acc_tz END;

  -- 4. Una fila por lectura; los campos no permitidos no llegan ni a la tabla temporal.
  DROP TABLE IF EXISTS pg_temp.cl_ingest_rows;
  DROP TABLE IF EXISTS pg_temp.cl_ingest_cands;
  CREATE TEMP TABLE cl_ingest_rows (
    s_ord       bigint NOT NULL,
    r_ord       bigint NOT NULL,
    stratum_id  uuid NOT NULL,
    is_obj      boolean NOT NULL,
    row_obj     jsonb,     -- solo campos mapeados y permitidos
    extra       jsonb,     -- solo cl_extra_fields
    item_id     text,
    product_raw text,
    scan_raw    text,
    place_ref   text,
    mode_ref    text,
    product_id  uuid,
    scan_at     timestamptz,
    reader_id   uuid,
    resolved_mode text,    -- modo del punto resuelto por D4 (NULL = punto "cualquier modo")
    oversize    boolean NOT NULL,  -- item_id / place_ref / mode_ref de mas de c_max_id (ya sustituido por NULL)
    is_start    boolean NOT NULL DEFAULT false,
    is_end      boolean NOT NULL DEFAULT false,
    row_reason  text,      -- motivo propio de la lectura
    reject_reason text     -- motivo final (propio o del candidato)
  ) ON COMMIT DROP;
  CREATE TEMP TABLE cl_ingest_cands (
    stratum_id  uuid NOT NULL,
    item_id     text NOT NULL,
    start_r_ord bigint,
    start_at    timestamptz,
    n_end       bigint NOT NULL DEFAULT 0,
    end_at      timestamptz,
    unknown_product  boolean NOT NULL,
    product_mismatch boolean NOT NULL,
    reason      text
  ) ON COMMIT DROP;

  INSERT INTO pg_temp.cl_ingest_rows (s_ord, r_ord, stratum_id, is_obj, row_obj, extra, item_id, product_raw, scan_raw,
                                      place_ref, mode_ref, oversize)
  SELECT s.o, r.o, (s.e->>'stratum_id')::uuid, jsonb_typeof(r.v) = 'object',
         CASE WHEN jsonb_typeof(r.v) = 'object' THEN
           (SELECT jsonb_object_agg(j.key,
                     CASE WHEN (j.key = f_item AND length(j.value #>> '{}') > c_max_id)
                            OR (j.key IN (f_place, f_mode) AND length(btrim(j.value #>> '{}')) > c_max_id)
                          THEN 'null'::jsonb ELSE j.value END)
              FROM jsonb_each(r.v) j
             WHERE j.key = ANY (v_allowed)
               AND (j.key = ANY (v_mapped)
                    OR (jsonb_typeof(j.value) IN ('string','number','boolean') AND length(j.value #>> '{}') <= c_max_extra))) END,
         CASE WHEN jsonb_typeof(r.v) = 'object' THEN
           (SELECT jsonb_object_agg(j.key, j.value) FROM jsonb_each(r.v) j
             WHERE j.key = ANY (v_extra)
               AND jsonb_typeof(j.value) IN ('string','number','boolean') AND length(j.value #>> '{}') <= c_max_extra) END,
         CASE WHEN length(x.it) > c_max_id THEN NULL ELSE x.it END,
         CASE WHEN jsonb_typeof(r.v) = 'object' AND f_product IS NOT NULL THEN r.v->>f_product END,
         CASE WHEN jsonb_typeof(r.v) = 'object' THEN r.v->>f_scan END,
         CASE WHEN length(x.pl) > c_max_id THEN NULL ELSE x.pl END,
         CASE WHEN length(x.md) > c_max_id THEN NULL ELSE x.md END,
         COALESCE(length(x.it), 0) > c_max_id OR COALESCE(length(x.pl), 0) > c_max_id OR COALESCE(length(x.md), 0) > c_max_id
    FROM jsonb_array_elements(v_strata) WITH ORDINALITY s(e, o)
   CROSS JOIN LATERAL jsonb_array_elements(s.e->'rows') WITH ORDINALITY r(v, o)
   CROSS JOIN LATERAL (SELECT
           CASE WHEN jsonb_typeof(r.v) = 'object' THEN r.v->>f_item END AS it,
           CASE WHEN jsonb_typeof(r.v) = 'object' THEN NULLIF(btrim(r.v->>f_place), '') END AS pl,
           CASE WHEN jsonb_typeof(r.v) = 'object' AND f_mode IS NOT NULL THEN NULLIF(btrim(r.v->>f_mode), '') END AS md) x;

  UPDATE pg_temp.cl_ingest_rows t SET scan_at = public.cl_parse_scan_at(t.scan_raw, v_fmt, v_scan_tz)
   WHERE t.scan_raw IS NOT NULL AND btrim(t.scan_raw) <> '';

  -- Producto: equivalencia del carrier -> products.code; sin equivalencia, el valor como codigo ONEMS.
  -- Sin campo de producto mapeado, la lectura es del producto del plan.
  IF f_product IS NULL THEN
    UPDATE pg_temp.cl_ingest_rows SET product_id = v_plan.product_id
   WHERE true;
  ELSE
    UPDATE pg_temp.cl_ingest_rows t SET product_id = COALESCE(
      (SELECT p.id FROM public.cl_value_mappings m
         JOIN public.products p ON p.account_id = m.account_id AND p.carrier_id = m.carrier_id AND p.code = m.onems_value
        WHERE m.account_id = v_plan.account_id AND m.carrier_id = v_plan.carrier_id
          AND m.kind = 'product' AND m.carrier_value = t.product_raw),
      (SELECT p.id FROM public.products p
        WHERE p.account_id = v_plan.account_id AND p.carrier_id = v_plan.carrier_id AND p.code = t.product_raw))
     WHERE t.product_raw IS NOT NULL;
  END IF;

  -- 5. Punto de lectura (D4): lugar + modo exacto; si no, el punto "cualquier modo" del lugar.
  --    Solo puntos vivos: una lectura en un punto borrado o desactivado despues de emitir la demanda queda
  --    unknown_reading_point aunque el punto este en la foto de la demanda (aceptado en la fase 1).
  UPDATE pg_temp.cl_ingest_rows t SET (reader_id, resolved_mode) = (
    SELECT r.id, r.carrier_mode_ref FROM public.readers r
     WHERE r.account_id = v_plan.account_id
       AND r.capture_source = 'carrier_scan'
       AND r.carrier_id = v_plan.carrier_id
       AND r.deleted_at IS NULL
       AND r.is_active IS NOT FALSE
       AND r.carrier_place_ref = t.place_ref
       AND (r.carrier_mode_ref = t.mode_ref OR r.carrier_mode_ref IS NULL)
     ORDER BY (r.carrier_mode_ref IS NULL), r.id
     LIMIT 1)
   WHERE t.place_ref IS NOT NULL;

  -- 6. Motivo por lectura.
  UPDATE pg_temp.cl_ingest_rows t SET row_reason = CASE
      WHEN t.oversize THEN 'bad_value'
      WHEN NOT t.is_obj
        OR t.item_id IS NULL OR btrim(t.item_id) = ''
        OR t.scan_raw IS NULL OR btrim(t.scan_raw) = ''
        OR t.place_ref IS NULL OR btrim(t.place_ref) = ''
        OR (f_product IS NOT NULL AND (t.product_raw IS NULL OR btrim(t.product_raw) = '')) THEN 'missing_field'
      WHEN t.scan_at IS NULL   THEN 'bad_timestamp'
      WHEN t.product_id IS NULL THEN 'unknown_product'
      WHEN t.reader_id IS NULL THEN 'unknown_reading_point'
    END
   WHERE true;

  -- Inicio / fin contra la foto de la demanda (D13), con la precedencia de D4: cuenta el punto al que se resolvio
  -- la lectura (mismo lugar y mismo modo del punto resuelto). Asi una lectura en un punto especifico intermedio no
  -- cuenta como inicio por un punto "cualquier modo" del mismo lugar.
  UPDATE pg_temp.cl_ingest_rows t
     SET is_start = EXISTS (SELECT 1 FROM jsonb_array_elements(sn.d->'start_points') p
                             WHERE p->>'place_ref' = t.place_ref
                               AND (p->>'mode_ref') IS NOT DISTINCT FROM t.resolved_mode),
         is_end   = EXISTS (SELECT 1 FROM jsonb_array_elements(sn.d->'end_points') p
                             WHERE p->>'place_ref' = t.place_ref
                               AND (p->>'mode_ref') IS NOT DISTINCT FROM t.resolved_mode)
    FROM jsonb_array_elements(v_demand.payload->'strata') sn(d)
   WHERE sn.d->>'stratum_id' = t.stratum_id::text AND t.row_reason IS NULL;

  -- 7. Candidatos por estrato e item_id (D5): inicio = primera lectura de inicio; fin = ultima lectura de fin que no
  --    sea la misma lectura que el inicio (una sola lectura en un punto 'both' no hace un envio: same_reading).
  CREATE INDEX ON pg_temp.cl_ingest_rows (stratum_id, item_id);
  INSERT INTO pg_temp.cl_ingest_cands (stratum_id, item_id, unknown_product, product_mismatch)
  SELECT t.stratum_id, t.item_id,
         COALESCE(bool_or(t.row_reason = 'unknown_product'), false),
         COALESCE(bool_or(t.row_reason IS NULL AND t.product_id <> v_plan.product_id), false)
    FROM pg_temp.cl_ingest_rows t
   WHERE t.item_id IS NOT NULL AND btrim(t.item_id) <> ''
   GROUP BY t.stratum_id, t.item_id;

  UPDATE pg_temp.cl_ingest_cands c SET start_r_ord = x.r_ord, start_at = x.scan_at
    FROM (SELECT DISTINCT ON (t.stratum_id, t.item_id) t.stratum_id, t.item_id, t.r_ord, t.scan_at
            FROM pg_temp.cl_ingest_rows t
           WHERE t.row_reason IS NULL AND t.is_start
           ORDER BY t.stratum_id, t.item_id, t.scan_at, t.is_end, t.r_ord) x   -- a igual hora gana la lectura solo de inicio
   WHERE x.stratum_id = c.stratum_id AND x.item_id = c.item_id;

  UPDATE pg_temp.cl_ingest_cands c SET
         n_end  = (SELECT count(*) FROM pg_temp.cl_ingest_rows t
                    WHERE t.stratum_id = c.stratum_id AND t.item_id = c.item_id AND t.row_reason IS NULL AND t.is_end),
         end_at = (SELECT max(t.scan_at) FROM pg_temp.cl_ingest_rows t
                    WHERE t.stratum_id = c.stratum_id AND t.item_id = c.item_id AND t.row_reason IS NULL AND t.is_end
                      AND t.r_ord IS DISTINCT FROM c.start_r_ord)
   WHERE true;

  UPDATE pg_temp.cl_ingest_cands c SET reason = CASE
      WHEN EXISTS (SELECT 1 FROM public.cl_samples sm
                    WHERE sm.account_id = v_plan.account_id AND sm.carrier_id = v_plan.carrier_id
                      AND sm.item_id = c.item_id AND sm.status = 'active') THEN 'already_sampled'
      WHEN c.unknown_product  THEN 'unknown_product'
      WHEN c.product_mismatch THEN 'product_mismatch'
      WHEN c.start_at IS NULL THEN 'no_start'
      WHEN c.end_at IS NULL AND c.n_end > 0 THEN 'same_reading'
      WHEN c.end_at IS NULL   THEN 'no_end'
      WHEN c.start_at > c.end_at THEN 'start_after_end'
      WHEN (c.end_at AT TIME ZONE v_acc_tz)::date NOT BETWEEN (sn.d->'period'->>'start')::date
                                                          AND (sn.d->'period'->>'end')::date THEN 'end_out_of_period'
    END
    FROM jsonb_array_elements(v_demand.payload->'strata') sn(d)
   WHERE sn.d->>'stratum_id' = c.stratum_id::text;

  -- Estado final de cada lectura: su motivo propio o, si no tiene, el de su candidato.
  -- Asi, candidatos validos = item_id con alguna lectura 'valid' en el estrato.
  UPDATE pg_temp.cl_ingest_rows t SET reject_reason = COALESCE(t.row_reason, c.reason)
    FROM pg_temp.cl_ingest_cands c
   WHERE c.stratum_id = t.stratum_id AND c.item_id = t.item_id;
  UPDATE pg_temp.cl_ingest_rows t SET reject_reason = t.row_reason
   WHERE t.reject_reason IS NULL AND t.row_reason IS NOT NULL;

  -- Resumen.
  SELECT jsonb_agg(jsonb_build_object(
           'stratum_id', x.e->>'stratum_id',
           'population_size', (x.e->>'population_size')::numeric::bigint,
           'rows', jsonb_array_length(x.e->'rows'),
           'candidates', (SELECT count(*) FROM pg_temp.cl_ingest_cands c WHERE c.stratum_id::text = x.e->>'stratum_id'),
           'candidates_valid', (SELECT count(*) FROM pg_temp.cl_ingest_cands c
                                 WHERE c.stratum_id::text = x.e->>'stratum_id' AND c.reason IS NULL),
           'rejected', COALESCE((SELECT jsonb_object_agg(z.reason, z.n) FROM (
                          SELECT c.reason, count(*) AS n FROM pg_temp.cl_ingest_cands c
                           WHERE c.stratum_id::text = x.e->>'stratum_id' AND c.reason IS NOT NULL
                           GROUP BY c.reason) z), '{}'::jsonb),
           'rows_rejected', COALESCE((SELECT jsonb_object_agg(z.row_reason, z.n) FROM (
                          SELECT t.row_reason, count(*) AS n FROM pg_temp.cl_ingest_rows t
                           WHERE t.stratum_id::text = x.e->>'stratum_id' AND t.row_reason IS NOT NULL
                           GROUP BY t.row_reason) z), '{}'::jsonb)
         ) ORDER BY x.o)
    INTO v_strata_summary
    FROM jsonb_array_elements(v_strata) WITH ORDINALITY x(e, o);

  -- 8. dry_run: solo el resumen; nada se escribe en tablas reales.
  IF v_dry THEN
    DROP TABLE pg_temp.cl_ingest_rows;
    DROP TABLE pg_temp.cl_ingest_cands;
    RETURN jsonb_build_object('batch', NULL, 'status', 'validated', 'dry_run', true, 'strata', v_strata_summary);
  END IF;

  -- 9. Guardar.
  v_summary := jsonb_build_object('batch', v_batch, 'status', 'validated', 'strata', v_strata_summary);
  SELECT jsonb_build_object('demand_id', v_demand.id, 'batch_id', v_cbatch, 'strata',
           jsonb_agg(jsonb_build_object(
             'stratum_id', x.e->'stratum_id', 'population_size', x.e->'population_size',
             'selection_method', x.e->'selection_method',
             'rows', COALESCE((SELECT jsonb_agg(CASE WHEN t.is_obj THEN COALESCE(t.row_obj, '{}'::jsonb) ELSE 'null'::jsonb END
                                                ORDER BY t.r_ord)
                                 FROM pg_temp.cl_ingest_rows t WHERE t.s_ord = x.o), '[]'::jsonb))
           ORDER BY x.o))
    INTO v_raw
    FROM jsonb_array_elements(v_strata) WITH ORDINALITY x(e, o);

  INSERT INTO public.cl_batches (id, account_id, demand_id, connector_batch_id, status, summary, raw_payload)
  VALUES (v_batch, v_plan.account_id, v_demand.id, v_cbatch, 'validated', v_summary, v_raw);

  INSERT INTO public.cl_batch_scans (account_id, batch_id, stratum_id, item_id, product_id, scan_at, place_ref, mode_ref,
                                     reader_id, status, reject_reason, extra)
  SELECT v_plan.account_id, v_batch, t.stratum_id,
         t.item_id, t.product_id, t.scan_at, t.place_ref, t.mode_ref,
         t.reader_id, CASE WHEN t.reject_reason IS NULL THEN 'valid' ELSE 'rejected' END, t.reject_reason, t.extra
    FROM pg_temp.cl_ingest_rows t
   ORDER BY t.s_ord, t.r_ord;

  -- Alertas por estrato (already_sampled no cuenta para rejected_ratio).
  FOR v_st IN SELECT (e->>'stratum_id')::uuid AS sid, (e->>'population_size')::bigint AS pop,
                  (e->>'candidates')::bigint AS cands, (e->>'candidates_valid')::bigint AS valid,
                  COALESCE((e->'rejected'->>'already_sampled')::bigint, 0) AS used
             FROM jsonb_array_elements(v_strata_summary) e
  LOOP
    v_denom := v_st.cands - v_st.used;
    v_rej := v_st.cands - v_st.valid - v_st.used;
    IF v_denom > 0 AND v_rej::numeric / v_denom > 0.2 THEN
      PERFORM public.cl_raise_alert(v_plan.id, v_st.sid, 'rejected_ratio', 'medium',
        jsonb_build_object('batch_id', v_batch, 'rejected', v_rej, 'candidates', v_denom,
                           'ratio', round(v_rej::numeric / v_denom, 3)));
    END IF;
    IF v_st.pop = 0 THEN
      PERFORM public.cl_raise_alert(v_plan.id, v_st.sid, 'empty_stratum', 'medium',
        jsonb_build_object('batch_id', v_batch));
    END IF;
    IF v_st.pop < v_st.cands THEN
      PERFORM public.cl_raise_alert(v_plan.id, v_st.sid, 'population_incoherent', 'high',
        jsonb_build_object('batch_id', v_batch, 'population_size', v_st.pop, 'candidates', v_st.cands));
    END IF;
  END LOOP;

  SELECT jsonb_agg(DISTINCT left(t.product_raw, 100)) INTO v_vals
    FROM pg_temp.cl_ingest_rows t WHERE t.row_reason = 'unknown_product';
  IF v_vals IS NOT NULL THEN
    PERFORM public.cl_raise_alert(v_plan.id, NULL, 'unknown_product', 'medium',
      jsonb_build_object('batch_id', v_batch, 'values', v_vals));
  END IF;
  SELECT jsonb_agg(DISTINCT jsonb_build_object('place_ref', left(t.place_ref, 100), 'mode_ref', left(t.mode_ref, 100)))
    INTO v_vals
    FROM pg_temp.cl_ingest_rows t WHERE t.row_reason = 'unknown_reading_point';
  IF v_vals IS NOT NULL THEN
    PERFORM public.cl_raise_alert(v_plan.id, NULL, 'unknown_reading_point', 'medium',
      jsonb_build_object('batch_id', v_batch, 'points', v_vals));
  END IF;

  UPDATE public.cl_feeds SET last_batch_at = now() WHERE id = p_feed_id;

  DROP TABLE pg_temp.cl_ingest_rows;
  DROP TABLE pg_temp.cl_ingest_cands;
  RETURN v_summary;
END $function$;
