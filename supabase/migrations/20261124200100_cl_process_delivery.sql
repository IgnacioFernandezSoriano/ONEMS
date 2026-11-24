-- Carrier Link v4, tarea 2: proceso de una entrega completa (spec 2026-11-19-carrier-link-design.md, v4: R24-R28,
-- D20-D21). Sobre el modelo de la tarea 1 (20261124200000_cl_deliveries.sql).
--
-- Dos mitades:
--   A. CARGA del fichero (Edge Function carrier-link-worker, service_role). Lee el objeto de Storage por trozos (HTTP
--      Range), calcula el sha256 de forma incremental y mete las filas en la zona de paso con cl_delivery_load_rows.
--      El cursor (byte de inicio del siguiente registro, filas cargadas, estado del sha256) vive en
--      cl_deliveries.progress->'load' y se guarda en la MISMA transaccion que las filas: tras una caida se reanuda en
--      el ultimo trozo confirmado. Un registro partido entre dos trozos no se guarda: el siguiente trozo empieza en su
--      primer byte (se vuelve a leer; el sha256 solo consume los bytes nuevos, sha_offset).
--   B. PROCESO en la base (pg_cron como postgres, CALL cl_delivery_process_run() cada minuto; cada paso es una
--      transaccion acotada con COMMIT entre pasos): equivalencias y validacion por fila (resolve), envios (items),
--      poblacion y cuota por estrato (strata), sorteo md5(seed || item_id) (draw), paso a cl_samples / cl_sample_scans /
--      one_db (transfer), recuentos, alertas y liquidacion de semanas cerradas (finish) y vaciado de la zona de paso
--      (cleanup). Todo reanudable: el cursor de cada fase esta en progress.
--
-- Fases (progress->>'phase'): load -> resolve -> items -> strata -> draw -> transfer -> finish -> cleanup -> done.
--   abort -> cleanup: fallo (failed, reanudable) o rechazo (rejected: sha256 distinto, demasiadas filas, fichero
--   ilegible...). La zona de paso se vacia SIEMPRE antes de salir de 'processing' (el disparador guarda lo exige, M1).
-- Una sola entrega 'processing' a la vez (indice de la tarea 1); orden de bloqueo: conector y despues entrega.
-- Entregas de prueba (is_test): se validan y cuentan; sin sorteo, sin muestras, sin one_db, sin alertas, sin liquidar.
-- Diagnostico (planes con feed_diagnosis): lo anade la tarea 7 (20261124200500_cl_diagnosis.sql).
-- Forward-only. No toca cl_ingest_batch, demandas ni la carga manual por lotes.

-- Bloqueos (revision final I2): solo tablas nuevas de v4 (cl_delivery_items, cl_delivery_strata) y filas de cron.job;
-- lock_timeout de 5 s por si algo las tiene (falla enseguida en vez de esperar). Aplicar en UNA transaccion.
SET LOCAL lock_timeout = '5s';

-- ================================================================ 1. zona de paso de envios
-- Un envio (item_id) por fila de la entrega en proceso. UNLOGGED como cl_delivery_rows; se vacia con ella.
CREATE UNLOGGED TABLE public.cl_delivery_items (
  delivery_id     uuid NOT NULL,
  item_id         text NOT NULL,
  n_rows          integer NOT NULL,
  unknown_product boolean NOT NULL,
  n_products      integer NOT NULL,
  product_id      uuid,
  start_row       bigint,
  start_at        timestamptz,
  start_reader_id uuid,
  start_city_id   uuid,
  end_row         bigint,
  end_at          timestamptz,
  end_reader_id   uuid,
  end_city_id     uuid,
  n_end           integer NOT NULL,
  plan_id         uuid,
  quota_id        uuid,
  reason          text,                  -- NULL = envio completo y valido (entra en la poblacion de su estrato)
  drawn           boolean NOT NULL DEFAULT false,
  skipped_settled boolean NOT NULL DEFAULT false,   -- elegido pero su cuota ya estaba liquidada: no se pasa
  sample_id       uuid,
  PRIMARY KEY (delivery_id, item_id)
);
CREATE INDEX cl_delivery_items_quota_idx ON public.cl_delivery_items (delivery_id, quota_id) WHERE reason IS NULL;
ALTER TABLE public.cl_delivery_items ENABLE ROW LEVEL SECURITY;
-- Elegidos que no se pasaron porque su cuota ya estaba liquidada (fulfilled / carried / unfilled): traza del sorteo.
ALTER TABLE public.cl_delivery_strata ADD COLUMN skipped_settled integer NOT NULL DEFAULT 0 CHECK (skipped_settled >= 0);
REVOKE ALL ON public.cl_delivery_items FROM PUBLIC, anon, authenticated, service_role;

-- ================================================================ 2. guarda de estados (de 20261124200000) + M1
-- Cambio: una entrega no sale de 'processing' mientras tenga filas en la zona de paso (R25).
CREATE OR REPLACE FUNCTION public.cl_deliveries_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path = public, extensions
AS $$
BEGIN
  IF (NEW.account_id, NEW.feed_id, NEW.period_start, NEW.period_end, NEW.source, NEW.is_test, NEW.format,
      NEW.compression, NEW.file_path, NEW.sha256, NEW.control_totals, NEW.created_at)
     IS DISTINCT FROM
     (OLD.account_id, OLD.feed_id, OLD.period_start, OLD.period_end, OLD.source, OLD.is_test, OLD.format,
      OLD.compression, OLD.file_path, OLD.sha256, OLD.control_totals, OLD.created_at) THEN
    RAISE EXCEPTION 'CL_DELIVERY_IMMUTABLE: identity fields of a delivery cannot change' USING ERRCODE = '22023';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status AND NOT (
       (OLD.status = 'pending_upload' AND NEW.status IN ('received','rejected'))
    OR (OLD.status = 'received'       AND NEW.status IN ('processing','failed','rejected'))
    OR (OLD.status = 'processing'     AND NEW.status IN ('processed','failed','rejected'))
    OR (OLD.status = 'failed'         AND NEW.status IN ('processing','rejected'))) THEN
    RAISE EXCEPTION 'CL_DELIVERY_BAD_TRANSITION: % -> %', OLD.status, NEW.status USING ERRCODE = '22023';
  END IF;
  IF OLD.status = 'processing' AND NEW.status <> 'processing'
     AND (EXISTS (SELECT 1 FROM public.cl_delivery_rows r WHERE r.delivery_id = OLD.id)
          OR EXISTS (SELECT 1 FROM public.cl_delivery_items i WHERE i.delivery_id = OLD.id)) THEN
    RAISE EXCEPTION 'CL_STAGING_NOT_EMPTY: empty the staging rows of the delivery before it leaves processing'
      USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.cl_deliveries_guard() FROM PUBLIC, anon, authenticated, service_role;

-- ================================================================ 3. resumen (de 20261124200000) + avance
-- Cambio: anade phase, bytes_loaded, rows_loaded, attempts y processing_started_at (para GET /deliveries/{id}).
CREATE OR REPLACE FUNCTION public.cl_delivery_summary(p_delivery_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
  SELECT jsonb_build_object(
    'delivery_id', d.id, 'feed_id', d.feed_id, 'status', d.status, 'is_test', d.is_test, 'source', d.source,
    'period_start', d.period_start, 'period_end', d.period_end, 'format', d.format, 'compression', d.compression,
    'file_path', d.file_path, 'file_bytes', d.file_bytes, 'sha256', d.sha256,
    'rows_total', d.rows_total, 'rows_rejected', d.rows_rejected, 'shipments_total', d.shipments_total,
    'shipments_valid', d.shipments_valid, 'shipments_drawn', d.shipments_drawn,
    'rejected_reasons', d.rejected_reasons, 'error', d.error,
    'created_at', d.created_at, 'received_at', d.received_at, 'finished_at', d.finished_at,
    'processing_started_at', d.processing_started_at,
    'phase', d.progress->>'phase',
    'bytes_loaded', (d.progress->'load'->>'offset')::bigint,
    'rows_loaded', (d.progress->'load'->>'rows')::bigint,
    'attempts', COALESCE((d.progress->>'attempts')::integer, 0))
    FROM public.cl_deliveries d WHERE d.id = p_delivery_id
$$;
REVOKE ALL ON FUNCTION public.cl_delivery_summary(uuid) FROM PUBLIC, anon, authenticated, service_role;

-- ================================================================ 4. helpers internos (sin grants)
-- Dias laborables de la cuenta en [p_from, p_to] (is_account_working_day: calendario semanal + non_working_days).
CREATE OR REPLACE FUNCTION public.cl_delivery_working_days(p_account_id uuid, p_from date, p_to date)
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path = public, extensions
AS $$
  SELECT count(*)::integer FROM generate_series(p_from, p_to, interval '1 day') g(d)
   WHERE p_from <= p_to AND public.is_account_working_day(p_account_id, g.d::date)
$$;

-- Cuota de la entrega para un estrato (D21): lo que falta de la semana x dias laborables de la entrega dentro de la
-- semana / dias laborables que quedan de la semana (desde el primer dia de la entrega en ella). La entrega que cubre
-- el ultimo dia de la semana pide todo lo que falta (el deficit lo liquida cl_settle_quota al cerrar la semana).
-- Redondeo al entero mas cercano (cada entrega recalcula sobre lo que aun falta).
CREATE OR REPLACE FUNCTION public.cl_delivery_quota_share(p_account_id uuid, p_remaining integer,
                                                          p_d_start date, p_d_end date, p_q_start date, p_q_end date)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE
 SET search_path = public, extensions
AS $$
DECLARE
  v_from date := GREATEST(p_d_start, p_q_start);
  v_in   integer;
  v_left integer;
BEGIN
  IF p_remaining IS NULL OR p_remaining <= 0 OR p_d_end < p_q_start OR p_d_start > p_q_end THEN RETURN 0; END IF;
  IF p_d_end >= p_q_end THEN RETURN p_remaining; END IF;
  v_in := public.cl_delivery_working_days(p_account_id, v_from, LEAST(p_d_end, p_q_end));
  v_left := public.cl_delivery_working_days(p_account_id, v_from, p_q_end);
  IF v_left = 0 THEN RETURN 0; END IF;
  RETURN round(p_remaining::numeric * v_in / v_left)::integer;
END $$;

-- La zona de paso se perdio (UNLOGGED: se vacia tras una caida del servidor) si falta la ultima fila confirmada.
CREATE OR REPLACE FUNCTION public.cl_delivery_staging_lost(p_delivery_id uuid, p_rows bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path = public, extensions
AS $$
  SELECT COALESCE(p_rows, 0) > 0
     AND NOT EXISTS (SELECT 1 FROM public.cl_delivery_rows r WHERE r.delivery_id = p_delivery_id AND r.row_no = p_rows)
$$;

-- Avance inicial de la carga (desde el byte 0).
CREATE OR REPLACE FUNCTION public.cl_delivery_load_start()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path = public, extensions
AS $$ SELECT jsonb_build_object('offset', 0, 'rows', 0, 'sha', NULL, 'sha_offset', 0, 'header', NULL) $$;

-- Alerta de una entrega (una por entrega + plan + cuota + tipo). plan_id NULL = alerta del conector/entrega.
CREATE OR REPLACE FUNCTION public.cl_delivery_alert(p_delivery_id uuid, p_plan_id uuid, p_quota_id uuid, p_type text,
                                                    p_severity text, p_details jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.cl_alerts a
              WHERE a.delivery_id = p_delivery_id AND a.plan_id IS NOT DISTINCT FROM p_plan_id
                AND a.quota_id IS NOT DISTINCT FROM p_quota_id AND a.alert_type = p_type) THEN
    RETURN;
  END IF;
  INSERT INTO public.cl_alerts (account_id, plan_id, quota_id, delivery_id, alert_type, severity, details)
  SELECT d.account_id, p_plan_id, p_quota_id, d.id, p_type, p_severity,
         COALESCE(p_details, '{}'::jsonb) || jsonb_build_object('delivery_id', d.id)
    FROM public.cl_deliveries d WHERE d.id = p_delivery_id;
END $$;

-- Pasa la entrega a 'abort' (el paso cleanup vacia la zona de paso y la deja failed / rejected).
CREATE OR REPLACE FUNCTION public.cl_delivery_mark_abort(p_delivery_id uuid, p_status text, p_error text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
BEGIN
  IF p_status NOT IN ('failed','rejected') THEN
    RAISE EXCEPTION 'CL_BAD_REQUEST: abort status must be failed or rejected' USING ERRCODE = '22023';
  END IF;
  UPDATE public.cl_deliveries d
     SET progress = d.progress || jsonb_build_object('phase', 'abort', 'final_status', p_status,
                                                     'final_error', left(p_error, 200),
                                                     'lease_token', NULL, 'lease_until', NULL)
   WHERE d.id = p_delivery_id AND d.status = 'processing';
END $$;

-- ================================================================ 5. carga (Edge Function, service_role)
-- 5.1 Tomar trabajo. p_token identifica la invocacion del worker (arriendo de p_lease_seconds: dos invocaciones no
-- cargan a la vez la misma entrega). Devuelve {action}:
--   'load'  -> delivery_id, file_path, format, file_bytes, fields (campos permitidos del carrier), load (cursor).
--   'busy'  -> otra invocacion tiene el arriendo.
--   'sql'   -> la entrega en proceso esta en la fase de base de datos (nada que hacer para el worker).
--   'idle'  -> no hay entregas pendientes.
-- Sin entrega en proceso toma la mas antigua 'received' (o 'failed' con menos de 3 intentos y 5 min de espera):
-- pasa a 'processing' con el cursor a cero. compression <> 'none' -> rejected CL_COMPRESSION_UNSUPPORTED (v4 no
-- admite gzip: no se puede reanudar desde un byte). Si la zona de paso se perdio (caida), el cursor vuelve a cero.
CREATE OR REPLACE FUNCTION public.cl_delivery_worker_claim(p_token text, p_lease_seconds integer DEFAULT 120,
                                                           p_now timestamptz DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_id     uuid;
  v_feed   public.cl_feeds;
  v_d      public.cl_deliveries;
  v_fields text[];
  v_lease  interval := make_interval(secs => LEAST(GREATEST(COALESCE(p_lease_seconds, 120), 10), 900));
BEGIN
  IF p_token IS NULL OR length(p_token) NOT BETWEEN 8 AND 100 THEN
    RAISE EXCEPTION 'CL_BAD_REQUEST: token required' USING ERRCODE = '22023';
  END IF;
  PERFORM pg_advisory_xact_lock(hashtext('cl_delivery_claim'));

  SELECT d.id INTO v_id FROM public.cl_deliveries d WHERE d.status = 'processing';
  IF v_id IS NULL THEN
    -- Por conector, estrictamente en orden de periodo: no se toma una entrega real mientras otra real anterior del
    -- mismo conector siga recibida, en proceso o fallida (reintentable). Asi un reintento nunca llega despues de que
    -- una entrega posterior haya liquidado la semana. Las entregas de prueba (is_test) no liquidan nada: no esperan a
    -- ninguna y ninguna real las espera (una prueba fallida o atascada nunca bloquea las reales).
    SELECT d.id INTO v_id FROM public.cl_deliveries d
     WHERE (d.status = 'received'
            OR (d.status = 'failed' AND COALESCE((d.progress->>'attempts')::integer, 0) < 3
                AND COALESCE(d.finished_at, d.received_at) < p_now - interval '5 minutes'
                AND d.file_deleted_at IS NULL))
       AND (d.is_test
            OR NOT EXISTS (SELECT 1 FROM public.cl_deliveries e
                            WHERE e.feed_id = d.feed_id AND e.id <> d.id AND e.period_start < d.period_start
                              AND NOT e.is_test AND e.status IN ('received','processing','failed')))
     ORDER BY d.received_at, d.id
     LIMIT 1;
    IF v_id IS NULL THEN RETURN jsonb_build_object('action', 'idle'); END IF;
  END IF;

  -- Conector primero, despues la entrega (mismo orden que abrir / completar).
  SELECT f.* INTO v_feed FROM public.cl_feeds f
   WHERE f.id = (SELECT d.feed_id FROM public.cl_deliveries d WHERE d.id = v_id) FOR UPDATE;
  SELECT d.* INTO v_d FROM public.cl_deliveries d WHERE d.id = v_id FOR UPDATE;

  IF v_d.status IN ('received','failed') THEN
    IF v_d.compression <> 'none' THEN
      UPDATE public.cl_deliveries d SET status = 'rejected', error = 'CL_COMPRESSION_UNSUPPORTED', finished_at = p_now
       WHERE d.id = v_d.id;
      RETURN jsonb_build_object('action', 'rejected', 'delivery_id', v_d.id, 'error', 'CL_COMPRESSION_UNSUPPORTED');
    END IF;
    UPDATE public.cl_deliveries d
       SET status = 'processing', error = NULL,
           processing_started_at = COALESCE(d.processing_started_at, p_now),
           progress = jsonb_build_object('phase', 'load', 'attempts', COALESCE((d.progress->>'attempts')::integer, 0) + 1,
                                         'claimed_at', p_now,   -- entrada en processing de ESTE intento (alerta de atasco)
                                         'load', public.cl_delivery_load_start(),
                                         'lease_token', p_token, 'lease_until', p_now + v_lease)
     WHERE d.id = v_d.id
    RETURNING d.* INTO v_d;
  ELSIF v_d.status <> 'processing' THEN
    RETURN jsonb_build_object('action', 'idle');
  ELSIF v_d.progress->>'phase' IS DISTINCT FROM 'load' THEN
    RETURN jsonb_build_object('action', 'sql', 'delivery_id', v_d.id, 'phase', v_d.progress->>'phase');
  ELSIF v_d.progress->>'lease_token' IS DISTINCT FROM p_token
        AND (v_d.progress->>'lease_until')::timestamptz > p_now THEN
    RETURN jsonb_build_object('action', 'busy', 'delivery_id', v_d.id);
  ELSE
    -- Toma de un arriendo caducado de OTRO worker (el anterior murio): cuenta como un intento. Agotados los 3, la
    -- entrega pasa a abort/failed y la limpieza la rechaza (CL_RETRIES_EXHAUSTED): un worker que se cae siempre en
    -- el mismo fichero no bloquea la base.
    IF v_d.progress->>'lease_token' IS NOT NULL AND v_d.progress->>'lease_token' IS DISTINCT FROM p_token THEN
      UPDATE public.cl_deliveries d
         SET progress = d.progress || jsonb_build_object('attempts', COALESCE((d.progress->>'attempts')::integer, 0) + 1)
       WHERE d.id = v_d.id
      RETURNING d.* INTO v_d;
      IF (v_d.progress->>'attempts')::integer > 3 THEN
        PERFORM public.cl_delivery_mark_abort(v_d.id, 'failed', 'CL_WORKER_LOST');
        RETURN jsonb_build_object('action', 'sql', 'delivery_id', v_d.id, 'phase', 'abort');
      END IF;
    END IF;
    UPDATE public.cl_deliveries d
       SET progress = d.progress
                      || jsonb_build_object('lease_token', p_token, 'lease_until', p_now + v_lease)
                      || CASE WHEN public.cl_delivery_staging_lost(d.id, (d.progress->'load'->>'rows')::bigint)
                              THEN jsonb_build_object('load', public.cl_delivery_load_start(),
                                                      'staging_lost', COALESCE((d.progress->>'staging_lost')::integer, 0) + 1)
                              ELSE '{}'::jsonb END
     WHERE d.id = v_d.id
    RETURNING d.* INTO v_d;
  END IF;

  SELECT COALESCE(array_agg(DISTINCT x.f ORDER BY x.f), ARRAY[]::text[]) INTO v_fields
    FROM (SELECT m.carrier_field AS f FROM public.cl_field_mappings m
           WHERE m.account_id = v_feed.account_id AND m.carrier_id = v_feed.carrier_id
          UNION ALL
          SELECT x.carrier_field FROM public.cl_extra_fields x
           WHERE x.account_id = v_feed.account_id AND x.carrier_id = v_feed.carrier_id) x;

  RETURN jsonb_build_object(
    'action', 'load', 'delivery_id', v_d.id, 'file_path', v_d.file_path, 'format', v_d.format,
    'file_bytes', v_d.file_bytes, 'sha256', v_d.sha256, 'fields', to_jsonb(v_fields),
    'max_rows', public.cl_delivery_limits(v_feed.config)->'max_rows',
    'load', v_d.progress->'load', 'lease_until', v_d.progress->'lease_until');
END $$;

-- Comprueba arriendo y cursor; devuelve la entrega bloqueada (conector y despues entrega).
CREATE OR REPLACE FUNCTION public.cl_delivery_load_lock(p_delivery_id uuid, p_token text, p_from_offset bigint)
 RETURNS public.cl_deliveries
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_d public.cl_deliveries;
BEGIN
  PERFORM 1 FROM public.cl_feeds f
   WHERE f.id = (SELECT d.feed_id FROM public.cl_deliveries d WHERE d.id = p_delivery_id) FOR KEY SHARE;
  SELECT d.* INTO v_d FROM public.cl_deliveries d WHERE d.id = p_delivery_id FOR UPDATE;
  IF v_d.id IS NULL OR v_d.status <> 'processing' OR v_d.progress->>'phase' IS DISTINCT FROM 'load' THEN
    RAISE EXCEPTION 'CL_DELIVERY_NOT_LOADING: the delivery is not loading' USING ERRCODE = 'P0001';
  END IF;
  IF p_token IS NULL OR v_d.progress->>'lease_token' IS DISTINCT FROM p_token THEN
    RAISE EXCEPTION 'CL_LEASE_LOST: another worker owns this delivery' USING ERRCODE = 'P0001';
  END IF;
  IF (v_d.progress->'load'->>'offset')::bigint IS DISTINCT FROM p_from_offset THEN
    RAISE EXCEPTION 'CL_CURSOR_MISMATCH: expected offset %', v_d.progress->'load'->>'offset' USING ERRCODE = 'P0001';
  END IF;
  RETURN v_d;
END $$;

-- 5.2 Cargar un trozo. p_rows = [{"n": numero de fila (1..), "r": registro con los nombres del carrier | null}],
-- consecutivos desde el ultimo cargado + 1. p_load = cursor tras el trozo {offset, rows, sha, sha_offset, header}.
-- Lista cerrada: solo pasan a la zona de paso los campos mapeados y los extras permitidos (escalares <= 500
-- caracteres). item_id / place_ref / mode_ref de mas de 200 caracteres -> NULL y motivo bad_value; registro que no es
-- un objeto -> bad_record. Idempotente por (entrega, fila). Mas filas que max_rows -> abort rejected CL_TOO_MANY_ROWS.
CREATE OR REPLACE FUNCTION public.cl_delivery_load_rows(p_delivery_id uuid, p_token text, p_from_offset bigint,
                                                        p_rows jsonb, p_load jsonb, p_release boolean DEFAULT false,
                                                        p_lease_seconds integer DEFAULT 120)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  c_max_id    constant integer := 200;
  c_max_extra constant integer := 500;
  v_d     public.cl_deliveries;
  v_feed  public.cl_feeds;
  v_prev  bigint;
  v_n     bigint;
  v_min   bigint;
  v_max   bigint;
  v_cnt   bigint;
  v_dist  bigint;
  v_limit bigint;
  f_item text; f_product text; f_scan text; f_place text; f_mode text;
  v_extra text[];
BEGIN
  v_d := public.cl_delivery_load_lock(p_delivery_id, p_token, p_from_offset);
  SELECT f.* INTO v_feed FROM public.cl_feeds f WHERE f.id = v_d.feed_id;
  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR p_load IS NULL OR jsonb_typeof(p_load) <> 'object'
     OR jsonb_typeof(p_load->'offset') IS DISTINCT FROM 'number' OR jsonb_typeof(p_load->'rows') IS DISTINCT FROM 'number'
     OR jsonb_typeof(p_load->'sha_offset') IS DISTINCT FROM 'number'
     OR (p_load->>'offset')::bigint < p_from_offset THEN
    RAISE EXCEPTION 'CL_BAD_REQUEST: rows array and load cursor required' USING ERRCODE = '22023';
  END IF;
  v_prev := (v_d.progress->'load'->>'rows')::bigint;
  v_n := (p_load->>'rows')::bigint;
  -- Exactamente v_prev+1 .. v_n, cada numero una vez: un numero repetido junto a un hueco (1, 1, 3) cuadraria min, max y
  -- cuenta; por eso tambien se exigen numeros distintos (revision final, T2-m2).
  SELECT min((e->>'n')::bigint), max((e->>'n')::bigint), count(*), count(DISTINCT (e->>'n')::bigint)
    INTO v_min, v_max, v_cnt, v_dist
    FROM jsonb_array_elements(p_rows) e;
  IF v_cnt > 0 AND (v_min <> v_prev + 1 OR v_max <> v_n OR v_cnt <> v_max - v_min + 1 OR v_dist <> v_cnt)
     OR v_cnt = 0 AND v_n <> v_prev THEN
    RAISE EXCEPTION 'CL_BAD_REQUEST: rows must continue at row %', v_prev + 1 USING ERRCODE = '22023';
  END IF;

  v_limit := (public.cl_delivery_limits(v_feed.config)->>'max_rows')::bigint;
  IF v_n > v_limit THEN
    PERFORM public.cl_delivery_mark_abort(v_d.id, 'rejected', 'CL_TOO_MANY_ROWS');
    RETURN jsonb_build_object('stop', true, 'error', 'CL_TOO_MANY_ROWS');
  END IF;

  SELECT max(m.carrier_field) FILTER (WHERE m.standard_field = 'item_id'),
         max(m.carrier_field) FILTER (WHERE m.standard_field = 'product'),
         max(m.carrier_field) FILTER (WHERE m.standard_field = 'scan_at'),
         max(m.carrier_field) FILTER (WHERE m.standard_field = 'place_ref'),
         max(m.carrier_field) FILTER (WHERE m.standard_field = 'mode_ref')
    INTO f_item, f_product, f_scan, f_place, f_mode
    FROM public.cl_field_mappings m
   WHERE m.account_id = v_d.account_id AND m.carrier_id = v_feed.carrier_id;
  IF f_item IS NULL OR f_scan IS NULL OR f_place IS NULL THEN
    PERFORM public.cl_delivery_mark_abort(v_d.id, 'rejected', 'CL_MAPPING_INCOMPLETE');
    RETURN jsonb_build_object('stop', true, 'error', 'CL_MAPPING_INCOMPLETE');
  END IF;
  SELECT COALESCE(array_agg(x.carrier_field), ARRAY[]::text[]) INTO v_extra
    FROM public.cl_extra_fields x WHERE x.account_id = v_d.account_id AND x.carrier_id = v_feed.carrier_id;

  INSERT INTO public.cl_delivery_rows (delivery_id, row_no, item_id, product, scan_at_raw, place_ref, mode_ref, extra,
                                       row_reason)
  SELECT v_d.id, (e->>'n')::bigint,
         CASE WHEN length(x.it) > c_max_id THEN NULL ELSE x.it END,
         CASE WHEN x.obj AND f_product IS NOT NULL THEN left(e->'r'->>f_product, c_max_extra) END,
         CASE WHEN x.obj THEN left(e->'r'->>f_scan, c_max_extra) END,
         CASE WHEN length(x.pl) > c_max_id THEN NULL ELSE x.pl END,
         CASE WHEN length(x.md) > c_max_id THEN NULL ELSE x.md END,
         CASE WHEN x.obj THEN
           (SELECT jsonb_object_agg(j.key, j.value) FROM jsonb_each(e->'r') j
             WHERE j.key = ANY (v_extra)
               AND jsonb_typeof(j.value) IN ('string','number','boolean') AND length(j.value #>> '{}') <= c_max_extra) END,
         CASE WHEN NOT x.obj THEN 'bad_record'
              WHEN COALESCE(length(x.it), 0) > c_max_id OR COALESCE(length(x.pl), 0) > c_max_id
                OR COALESCE(length(x.md), 0) > c_max_id THEN 'bad_value' END
    FROM jsonb_array_elements(p_rows) e
   CROSS JOIN LATERAL (SELECT jsonb_typeof(e->'r') = 'object' AS obj) o
   CROSS JOIN LATERAL (SELECT o.obj,
           CASE WHEN o.obj THEN e->'r'->>f_item END AS it,
           CASE WHEN o.obj THEN NULLIF(btrim(e->'r'->>f_place), '') END AS pl,
           CASE WHEN o.obj AND f_mode IS NOT NULL THEN NULLIF(btrim(e->'r'->>f_mode), '') END AS md) x
  ON CONFLICT (delivery_id, row_no) DO NOTHING;

  UPDATE public.cl_deliveries d
     SET progress = d.progress
                    || jsonb_build_object('load', jsonb_build_object(
                         'offset', (p_load->>'offset')::bigint, 'rows', v_n, 'sha', p_load->'sha',
                         'sha_offset', (p_load->>'sha_offset')::bigint, 'header', p_load->'header'))
                    || CASE WHEN COALESCE(p_release, false)
                            THEN jsonb_build_object('lease_token', NULL, 'lease_until', NULL)
                            ELSE jsonb_build_object('lease_until',
                                   now() + make_interval(secs => LEAST(GREATEST(COALESCE(p_lease_seconds, 120), 10), 900)))
                       END
   WHERE d.id = v_d.id;
  RETURN jsonb_build_object('stop', false, 'rows', v_n, 'offset', (p_load->>'offset')::bigint);
END $$;

-- 5.3 Fin de fichero: el worker manda el sha256 calculado sobre todos los bytes. Distinto del declarado -> abort
-- rejected CL_SHA256_MISMATCH. Si coincide, rows_total y la fase de base de datos (resolve).
CREATE OR REPLACE FUNCTION public.cl_delivery_load_done(p_delivery_id uuid, p_token text, p_from_offset bigint,
                                                        p_sha256 text, p_bytes bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_d public.cl_deliveries;
  v_rows bigint;
BEGIN
  v_d := public.cl_delivery_load_lock(p_delivery_id, p_token, p_from_offset);
  v_rows := (v_d.progress->'load'->>'rows')::bigint;
  IF p_from_offset IS DISTINCT FROM v_d.file_bytes THEN
    RAISE EXCEPTION 'CL_BAD_REQUEST: the whole file must be parsed (% of % bytes)', p_from_offset, v_d.file_bytes
      USING ERRCODE = '22023';
  END IF;
  IF lower(COALESCE(p_sha256, '')) <> v_d.sha256 OR p_bytes IS DISTINCT FROM v_d.file_bytes THEN
    PERFORM public.cl_delivery_mark_abort(v_d.id, 'rejected', 'CL_SHA256_MISMATCH');
    RETURN jsonb_build_object('phase', 'abort', 'error', 'CL_SHA256_MISMATCH');
  END IF;
  IF public.cl_delivery_staging_lost(v_d.id, v_rows) THEN
    UPDATE public.cl_deliveries d
       SET progress = d.progress || jsonb_build_object('load', public.cl_delivery_load_start(), 'lease_token', NULL,
                                                       'lease_until', NULL,
                                                       'staging_lost', COALESCE((d.progress->>'staging_lost')::integer, 0) + 1)
     WHERE d.id = v_d.id;
    RETURN jsonb_build_object('phase', 'load', 'error', 'CL_STAGING_LOST');
  END IF;
  UPDATE public.cl_deliveries d
     SET rows_total = v_rows,
         progress = d.progress || jsonb_build_object('phase', 'resolve', 'cursor', 0, 'lease_token', NULL,
                                                     'lease_until', NULL, 'loaded_at', now())
   WHERE d.id = v_d.id;
  RETURN jsonb_build_object('phase', 'resolve', 'rows_total', v_rows);
END $$;

-- 5.4 El worker no puede seguir: p_final -> rejected (fichero ilegible: CL_FILE_MISSING, CL_RECORD_TOO_LONG,
-- CL_BAD_ENCODING, CL_BAD_CSV_HEADER...), si no failed (reanudable). Solo codigos CL_* (sin texto libre).
CREATE OR REPLACE FUNCTION public.cl_delivery_load_fail(p_delivery_id uuid, p_token text, p_code text, p_final boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_d public.cl_deliveries;
BEGIN
  IF p_code IS NULL OR p_code !~ '^CL_[A-Z0-9_]{1,60}$' THEN
    RAISE EXCEPTION 'CL_BAD_REQUEST: code must be a CL_ token' USING ERRCODE = '22023';
  END IF;
  PERFORM 1 FROM public.cl_feeds f
   WHERE f.id = (SELECT d.feed_id FROM public.cl_deliveries d WHERE d.id = p_delivery_id) FOR KEY SHARE;
  SELECT d.* INTO v_d FROM public.cl_deliveries d WHERE d.id = p_delivery_id FOR UPDATE;
  IF v_d.id IS NULL OR v_d.status <> 'processing' OR v_d.progress->>'phase' IS DISTINCT FROM 'load'
     OR p_token IS NULL OR v_d.progress->>'lease_token' IS DISTINCT FROM p_token THEN
    RAISE EXCEPTION 'CL_LEASE_LOST: another worker owns this delivery' USING ERRCODE = 'P0001';
  END IF;
  PERFORM public.cl_delivery_mark_abort(v_d.id, CASE WHEN p_final THEN 'rejected' ELSE 'failed' END, p_code);
  RETURN jsonb_build_object('phase', 'abort');
END $$;

-- 5.5 Retencion (M3): ficheros a borrar por la API de Storage (el worker; Supabase no deja borrar storage.objects
-- con SQL). Rechazadas (incluidas sustituidas y caducadas) tras 1 hora; procesadas y fallidas tras
-- file_retention_days; objetos del bucket sin entrega (cuentas o conectores borrados) tras 1 dia.
CREATE OR REPLACE FUNCTION public.cl_delivery_sweep_list(p_limit integer DEFAULT 100, p_now timestamptz DEFAULT now())
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
  SELECT COALESCE(jsonb_agg(z.path ORDER BY z.path), '[]'::jsonb)
    FROM (SELECT x.path FROM (
            SELECT d.file_path AS path
              FROM public.cl_deliveries d JOIN public.cl_feeds f ON f.id = d.feed_id
             WHERE d.file_deleted_at IS NULL
               AND ((d.status = 'rejected' AND COALESCE(d.finished_at, d.created_at) < p_now - interval '1 hour')
                 OR (d.status IN ('processed','failed')
                     AND COALESCE(d.finished_at, d.received_at, d.created_at)
                         < p_now - make_interval(days => (public.cl_delivery_limits(f.config)->>'file_retention_days')::integer)))
            UNION
            SELECT o.name FROM storage.objects o
             WHERE o.bucket_id = 'cl-deliveries' AND o.created_at < p_now - interval '1 day'
               AND NOT EXISTS (SELECT 1 FROM public.cl_deliveries d WHERE d.file_path = o.name)) x
          ORDER BY x.path
          LIMIT LEAST(GREATEST(COALESCE(p_limit, 100), 1), 1000)) z
$$;

CREATE OR REPLACE FUNCTION public.cl_delivery_sweep_done(p_paths text[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_n integer;
BEGIN
  UPDATE public.cl_deliveries d SET file_deleted_at = now()
   WHERE d.file_path = ANY (p_paths) AND d.file_deleted_at IS NULL
     AND d.status IN ('rejected','processed','failed');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;

-- ================================================================ 6. proceso en la base (fases)
-- Cada fase hace un trozo acotado y deja su cursor en progress. Internas (sin grants); las llama cl_process_delivery.

-- 6.1 resolve: equivalencias de valor y validacion por fila (mismas reglas que cl_ingest_batch: missing_field,
-- bad_timestamp, unknown_product, unknown_reading_point; precedencia de punto D4: lugar + modo exacto o, si no, el
-- punto "cualquier modo" del lugar). Trozos por numero de fila. Acumula en progress los motivos por fila y hasta 50
-- valores de producto / puntos desconocidos (para las alertas).
CREATE OR REPLACE FUNCTION public.cl_delivery_phase_resolve(p_d public.cl_deliveries, p_feed public.cl_feeds,
                                                            p_chunk integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_from  bigint := COALESCE((p_d.progress->>'cursor')::bigint, 0);
  v_to    bigint := LEAST(COALESCE((p_d.progress->>'cursor')::bigint, 0) + p_chunk, COALESCE(p_d.rows_total, 0));
  f_product text; v_fmt text; v_map_tz text; v_scan_tz text; v_acc_tz text;
  v_single uuid;
  v_nprod  integer;
  v_reasons jsonb;
  v_prods  jsonb;
  v_points jsonb;
BEGIN
  SELECT max(m.carrier_field) FILTER (WHERE m.standard_field = 'product'),
         max(m.format)        FILTER (WHERE m.standard_field = 'scan_at'),
         max(m.timezone)      FILTER (WHERE m.standard_field = 'scan_at')
    INTO f_product, v_fmt, v_map_tz
    FROM public.cl_field_mappings m
   WHERE m.account_id = p_d.account_id AND m.carrier_id = p_feed.carrier_id;
  v_acc_tz := public.cl_account_date_tz(p_d.account_id);
  v_scan_tz := CASE WHEN v_map_tz IS NOT NULL AND btrim(v_map_tz) <> '' AND public.cl_is_valid_timezone(v_map_tz)
                    THEN v_map_tz ELSE v_acc_tz END;
  -- Sin campo de producto: el producto de los planes activos del conector si es uno solo.
  IF f_product IS NULL THEN
    SELECT count(DISTINCT p.product_id), min(p.product_id::text)::uuid INTO v_nprod, v_single
      FROM public.cl_plans p
     WHERE p.feed_id = p_d.feed_id AND p.carrier_id = p_feed.carrier_id AND p.status = 'active';
    IF v_nprod <> 1 THEN
      PERFORM public.cl_delivery_mark_abort(p_d.id, 'rejected', 'CL_MAPPING_INCOMPLETE');
      RETURN 'abort';
    END IF;
  END IF;

  IF v_to > v_from THEN
    WITH pts AS MATERIALIZED (
      SELECT DISTINCT ON (r.carrier_place_ref, r.carrier_mode_ref) r.id, r.carrier_place_ref AS place_ref,
             r.carrier_mode_ref AS mode_ref
        FROM public.readers r
       WHERE r.account_id = p_d.account_id AND r.capture_source = 'carrier_scan' AND r.carrier_id = p_feed.carrier_id
         AND r.deleted_at IS NULL AND r.is_active IS NOT FALSE
       ORDER BY r.carrier_place_ref, r.carrier_mode_ref, r.id
    ), vmap AS MATERIALIZED (
      SELECT m.carrier_value AS v, p.id AS pid
        FROM public.cl_value_mappings m
        JOIN public.products p ON p.account_id = m.account_id AND p.carrier_id = m.carrier_id AND p.code = m.onems_value
       WHERE m.account_id = p_d.account_id AND m.carrier_id = p_feed.carrier_id AND m.kind = 'product'
    ), pcode AS MATERIALIZED (
      SELECT p.code AS v, p.id AS pid FROM public.products p
       WHERE p.account_id = p_d.account_id AND p.carrier_id = p_feed.carrier_id
    ), x AS (
      SELECT t.row_no,
             CASE WHEN f_product IS NULL THEN v_single ELSE COALESCE(vm.pid, pcd.pid) END AS pid,
             CASE WHEN t.scan_at_raw IS NOT NULL AND btrim(t.scan_at_raw) <> ''
                  THEN public.cl_parse_scan_at(t.scan_at_raw, v_fmt, v_scan_tz) END AS sa,
             COALESCE(pe.id, pn.id) AS rid,
             CASE WHEN pe.id IS NOT NULL THEN pe.mode_ref END AS rmode,
             t.item_id IS NULL OR btrim(t.item_id) = ''
               OR t.scan_at_raw IS NULL OR btrim(t.scan_at_raw) = ''
               OR t.place_ref IS NULL OR btrim(t.place_ref) = ''
               OR (f_product IS NOT NULL AND (t.product IS NULL OR btrim(t.product) = '')) AS missing
        FROM public.cl_delivery_rows t
        LEFT JOIN vmap vm ON vm.v = t.product
        LEFT JOIN pcode pcd ON pcd.v = t.product
        LEFT JOIN pts pe ON pe.place_ref = t.place_ref AND pe.mode_ref = t.mode_ref
        LEFT JOIN pts pn ON pn.place_ref = t.place_ref AND pn.mode_ref IS NULL
       WHERE t.delivery_id = p_d.id AND t.row_no > v_from AND t.row_no <= v_to AND t.row_reason IS NULL
    )
    UPDATE public.cl_delivery_rows t
       SET product_id = x.pid, scan_at = x.sa, reader_id = x.rid, resolved_mode = x.rmode,
           row_reason = CASE WHEN x.missing THEN 'missing_field'
                             WHEN x.sa IS NULL THEN 'bad_timestamp'
                             WHEN x.pid IS NULL THEN 'unknown_product'
                             WHEN x.rid IS NULL THEN 'unknown_reading_point' END
      FROM x
     WHERE t.delivery_id = p_d.id AND t.row_no = x.row_no;

    SELECT jsonb_object_agg(z.row_reason, z.n) INTO v_reasons
      FROM (SELECT t.row_reason, count(*) AS n FROM public.cl_delivery_rows t
             WHERE t.delivery_id = p_d.id AND t.row_no > v_from AND t.row_no <= v_to AND t.row_reason IS NOT NULL
             GROUP BY t.row_reason) z;
    SELECT jsonb_agg(DISTINCT y.v) INTO v_prods
      FROM (SELECT DISTINCT left(t.product, 100) AS v FROM public.cl_delivery_rows t
             WHERE t.delivery_id = p_d.id AND t.row_no > v_from AND t.row_no <= v_to
               AND t.row_reason = 'unknown_product'
             LIMIT 50) y;
    SELECT jsonb_agg(DISTINCT y.v) INTO v_points
      FROM (SELECT DISTINCT jsonb_build_object('place_ref', left(t.place_ref, 100), 'mode_ref', left(t.mode_ref, 100)) AS v
              FROM public.cl_delivery_rows t
             WHERE t.delivery_id = p_d.id AND t.row_no > v_from AND t.row_no <= v_to
               AND t.row_reason = 'unknown_reading_point'
             LIMIT 50) y;
  END IF;

  UPDATE public.cl_deliveries d
     SET progress = d.progress || jsonb_build_object(
           'cursor', CASE WHEN v_to >= COALESCE(d.rows_total, 0) THEN NULL ELSE to_jsonb(v_to) END,
           'phase', CASE WHEN v_to >= COALESCE(d.rows_total, 0) THEN 'items' ELSE 'resolve' END,
           'row_reasons', (SELECT COALESCE(jsonb_object_agg(k, s), '{}'::jsonb) FROM (
               SELECT k, sum(v::bigint) AS s FROM (
                 SELECT e.key AS k, e.value AS v FROM jsonb_each_text(COALESCE(d.progress->'row_reasons', '{}'::jsonb)) e
                 UNION ALL
                 SELECT e.key, e.value FROM jsonb_each_text(COALESCE(v_reasons, '{}'::jsonb)) e) u
               GROUP BY k) w),
           'unknown_products', (SELECT COALESCE(jsonb_agg(DISTINCT v), '[]'::jsonb) FROM (
               SELECT v FROM (SELECT DISTINCT v FROM jsonb_array_elements(
                 COALESCE(d.progress->'unknown_products', '[]'::jsonb) || COALESCE(v_prods, '[]'::jsonb)) v) a
               LIMIT 50) b),
           'unknown_points', (SELECT COALESCE(jsonb_agg(DISTINCT v), '[]'::jsonb) FROM (
               SELECT v FROM (SELECT DISTINCT v FROM jsonb_array_elements(
                 COALESCE(d.progress->'unknown_points', '[]'::jsonb) || COALESCE(v_points, '[]'::jsonb)) v) a
               LIMIT 50) b))
   WHERE d.id = p_d.id;
  RETURN 'resolve';
END $$;

-- 6.2 items: un envio por item_id (trozos de p_chunk filas por orden de item_id; las filas de un mismo envio van
-- siempre en el mismo trozo). Regla de inicio / fin de D5 con el papel VIVO del punto (readers.e2e_role):
--   inicio = primera lectura valida en un punto origin/both (a igual hora gana el punto solo de origen, luego la fila);
--   fin    = ultima lectura valida en un punto destination/both que no sea la de inicio (a igual hora, la ultima fila).
-- Ruta = ciudades de los puntos de inicio y fin; estrato = cuota del plan activo del conector con ese producto que
-- contiene la fecha local de llegada (semana ISO de la llegada), con ese origen y destino.
-- Motivos (orden de cl_ingest_batch + v4): already_sampled, unknown_product, product_mismatch (varios productos o
-- ninguno de los planes del conector), no_start, same_reading, no_end, start_after_end, reader_without_city,
-- end_out_of_period (llegada fuera del periodo de la entrega), no_stratum (ruta / semana sin cuota en el plan).
CREATE OR REPLACE FUNCTION public.cl_delivery_phase_items(p_d public.cl_deliveries, p_feed public.cl_feeds,
                                                          p_chunk integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_cur   text := p_d.progress->>'cursor_item';
  v_upper text;
  v_tz    text := public.cl_account_date_tz(p_d.account_id);
BEGIN
  SELECT t.item_id INTO v_upper
    FROM public.cl_delivery_rows t
   WHERE t.delivery_id = p_d.id AND t.item_id IS NOT NULL AND (v_cur IS NULL OR t.item_id > v_cur)
   ORDER BY t.item_id
  OFFSET GREATEST(p_chunk, 1) - 1 LIMIT 1;

  WITH pts AS MATERIALIZED (
    SELECT r.id, r.e2e_role::text AS role, pc.city_id
      FROM public.readers r LEFT JOIN public.postal_centers pc ON pc.id = r.postal_center_id
     WHERE r.account_id = p_d.account_id AND r.capture_source = 'carrier_scan' AND r.carrier_id = p_feed.carrier_id
  ), pl AS MATERIALIZED (
    SELECT p.id, p.product_id, p.start_date, p.end_date, p.created_at
      FROM public.cl_plans p
     WHERE p.feed_id = p_d.feed_id AND p.carrier_id = p_feed.carrier_id AND p.status = 'active'
  ), g AS (
    -- Inicio y fin salen del propio agregado (mismo orden total en cada array: la fila desempata), sin volver a leer
    -- la zona de paso.
    SELECT t.item_id, count(*)::integer AS n,
           COALESCE(bool_or(t.row_reason = 'unknown_product'), false) AS unk,
           (count(DISTINCT t.product_id) FILTER (WHERE t.row_reason IS NULL))::integer AS np,
           (min(t.product_id::text) FILTER (WHERE t.row_reason IS NULL))::uuid AS pid,
           (array_agg(t.row_no ORDER BY t.scan_at, (pt.role = 'both'), t.row_no)
              FILTER (WHERE t.row_reason IS NULL AND pt.role IN ('origin','both')))[1] AS start_row,
           (array_agg(t.scan_at ORDER BY t.scan_at, (pt.role = 'both'), t.row_no)
              FILTER (WHERE t.row_reason IS NULL AND pt.role IN ('origin','both')))[1] AS start_at,
           (array_agg(t.reader_id ORDER BY t.scan_at, (pt.role = 'both'), t.row_no)
              FILTER (WHERE t.row_reason IS NULL AND pt.role IN ('origin','both')))[1] AS start_reader_id,
           (array_agg(t.row_no ORDER BY t.scan_at DESC, t.row_no DESC)
              FILTER (WHERE t.row_reason IS NULL AND pt.role IN ('destination','both')))[1:2] AS e_rows,
           (array_agg(t.scan_at ORDER BY t.scan_at DESC, t.row_no DESC)
              FILTER (WHERE t.row_reason IS NULL AND pt.role IN ('destination','both')))[1:2] AS e_ats,
           (array_agg(t.reader_id ORDER BY t.scan_at DESC, t.row_no DESC)
              FILTER (WHERE t.row_reason IS NULL AND pt.role IN ('destination','both')))[1:2] AS e_rds,
           (count(*) FILTER (WHERE t.row_reason IS NULL AND pt.role IN ('destination','both')))::integer AS n_end
      FROM public.cl_delivery_rows t
      LEFT JOIN pts pt ON pt.id = t.reader_id
     WHERE t.delivery_id = p_d.id AND t.item_id IS NOT NULL AND btrim(t.item_id) <> ''
       AND (v_cur IS NULL OR t.item_id > v_cur) AND (v_upper IS NULL OR t.item_id <= v_upper)
     GROUP BY t.item_id
  ), e AS (
    SELECT g.*, CASE WHEN g.e_rows[1] IS DISTINCT FROM g.start_row THEN 1 ELSE 2 END AS ei
      FROM g
  ), w AS (
    SELECT e.item_id, e.n, e.unk, e.np, e.pid, e.start_row, e.start_at, e.start_reader_id, pa.city_id AS start_city_id,
           e.e_rows[e.ei] AS end_row, e.e_ats[e.ei] AS end_at, e.e_rds[e.ei] AS end_reader_id, pz.city_id AS end_city_id,
           e.n_end, (e.e_ats[e.ei] AT TIME ZONE v_tz)::date AS end_local
      FROM e
      LEFT JOIN pts pa ON pa.id = e.start_reader_id
      LEFT JOIN pts pz ON pz.id = e.e_rds[e.ei]
  ), s AS (
    SELECT w.*,
           (SELECT pl.id FROM pl WHERE pl.product_id = w.pid AND w.end_local BETWEEN pl.start_date AND pl.end_date
             ORDER BY pl.created_at, pl.id LIMIT 1) AS plan_id
      FROM w
  ), k AS (
    SELECT s.*,
           (SELECT q.id FROM public.cl_plan_quotas q
             WHERE q.plan_id = s.plan_id AND q.origin_city_id = s.start_city_id
               AND q.destination_city_id = s.end_city_id
               AND s.end_local BETWEEN q.period_start AND q.period_end
             ORDER BY q.period_start, q.id LIMIT 1) AS quota_id
      FROM s
  )
  INSERT INTO public.cl_delivery_items (delivery_id, item_id, n_rows, unknown_product, n_products, product_id,
                                        start_row, start_at, start_reader_id, start_city_id,
                                        end_row, end_at, end_reader_id, end_city_id, n_end, plan_id, quota_id, reason)
  SELECT p_d.id, k.item_id, k.n, k.unk, k.np, k.pid, k.start_row, k.start_at, k.start_reader_id, k.start_city_id,
         k.end_row, k.end_at, k.end_reader_id, k.end_city_id, k.n_end, k.plan_id, k.quota_id,
         CASE
           WHEN EXISTS (SELECT 1 FROM public.cl_samples sm
                         WHERE sm.account_id = p_d.account_id AND sm.carrier_id = p_feed.carrier_id
                           AND sm.item_id = k.item_id AND sm.status = 'active'
                           AND sm.delivery_id IS DISTINCT FROM p_d.id) THEN 'already_sampled'
           WHEN k.unk THEN 'unknown_product'
           WHEN k.np > 1 OR (k.np = 1 AND NOT EXISTS (SELECT 1 FROM pl WHERE pl.product_id = k.pid)) THEN 'product_mismatch'
           WHEN k.start_row IS NULL THEN 'no_start'
           WHEN k.end_row IS NULL AND k.n_end > 0 THEN 'same_reading'
           WHEN k.end_row IS NULL THEN 'no_end'
           WHEN k.start_at > k.end_at THEN 'start_after_end'
           WHEN k.start_city_id IS NULL OR k.end_city_id IS NULL THEN 'reader_without_city'
           WHEN k.end_local NOT BETWEEN p_d.period_start AND p_d.period_end THEN 'end_out_of_period'
           WHEN k.quota_id IS NULL THEN 'no_stratum'
         END
    FROM k
  ON CONFLICT (delivery_id, item_id) DO NOTHING;

  UPDATE public.cl_deliveries d
     SET progress = d.progress || jsonb_build_object('cursor_item', v_upper,
                                                     'phase', CASE WHEN v_upper IS NULL THEN 'strata' ELSE 'items' END)
   WHERE d.id = p_d.id;
  RETURN 'items';
END $$;

-- 6.3 strata: una fila por cuota de los planes activos del conector que se solapa con el periodo de la entrega:
-- poblacion (envios validos con llegada en esa semana y ruta) y cuota de la entrega (D21). Una vez escrita no se
-- recalcula (reanudar tras una caida da el mismo sorteo; la semilla tampoco cambia).
CREATE OR REPLACE FUNCTION public.cl_delivery_phase_strata(p_d public.cl_deliveries, p_feed public.cl_feeds)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
BEGIN
  INSERT INTO public.cl_delivery_strata (account_id, delivery_id, quota_id, population, quota_for_delivery)
  SELECT p_d.account_id, p_d.id, q.id, COALESCE(pop.n, 0),
         public.cl_delivery_quota_share(p_d.account_id,
           CASE WHEN q.status IN ('pending','open')
                THEN GREATEST(q.samples_planned + q.samples_carried_in - q.samples_obtained, 0) ELSE 0 END,
           p_d.period_start, p_d.period_end, q.period_start, q.period_end)
    FROM public.cl_plan_quotas q
    JOIN public.cl_plans p ON p.id = q.plan_id
    LEFT JOIN (SELECT i.quota_id, count(*)::integer AS n FROM public.cl_delivery_items i
                WHERE i.delivery_id = p_d.id AND i.reason IS NULL GROUP BY i.quota_id) pop ON pop.quota_id = q.id
   WHERE p.feed_id = p_d.feed_id AND p.carrier_id = p_feed.carrier_id AND p.status = 'active'
     AND q.period_start <= p_d.period_end AND q.period_end >= p_d.period_start
   ORDER BY q.id
  ON CONFLICT (delivery_id, quota_id) DO NOTHING;

  UPDATE public.cl_deliveries d
     SET progress = d.progress || jsonb_build_object('phase', CASE WHEN d.is_test THEN 'finish' ELSE 'draw' END)
   WHERE d.id = p_d.id;
  RETURN 'strata';
END $$;

-- 6.4 draw: en cada estrato, los quota_for_delivery primeros envios validos por md5(seed || item_id) (desempate
-- item_id COLLATE "C"). Determinista: repetirlo marca los mismos.
CREATE OR REPLACE FUNCTION public.cl_delivery_phase_draw(p_d public.cl_deliveries)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
BEGIN
  UPDATE public.cl_delivery_items i SET drawn = true
    FROM (SELECT it.item_id, s.quota_for_delivery AS k,
                 row_number() OVER (PARTITION BY it.quota_id ORDER BY md5(s.seed || it.item_id), it.item_id COLLATE "C") AS rn
            FROM public.cl_delivery_items it
            JOIN public.cl_delivery_strata s ON s.delivery_id = p_d.id AND s.quota_id = it.quota_id
           WHERE it.delivery_id = p_d.id AND it.reason IS NULL) x
   WHERE i.delivery_id = p_d.id AND i.item_id = x.item_id AND x.rn <= x.k AND NOT i.drawn;

  UPDATE public.cl_deliveries d SET progress = d.progress || jsonb_build_object('phase', 'transfer')
   WHERE d.id = p_d.id;
  RETURN 'draw';
END $$;

-- 6.5 transfer: hasta p_chunk envios elegidos por paso -> cl_samples (con delivery_id), cl_sample_scans (todas sus
-- lecturas validas en puntos de inicio o de fin, R15; papeles como cl_sample_stratum), possible_misrouting (alguna de
-- esas lecturas en una ciudad que no es ni el origen ni el destino de la cuota), one_db (cl_transfer_sample:
-- equivalencia y en plazo) y samples_obtained de la cuota. Reanudable: un elegido que ya tiene muestra de esta
-- entrega no se vuelve a crear. Mismo candado que el sorteo (cuenta + carrier) y cuotas bloqueadas por id.
CREATE OR REPLACE FUNCTION public.cl_delivery_phase_transfer(p_d public.cl_deliveries, p_feed public.cl_feeds,
                                                             p_chunk integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_it   record;
  v_sid  uuid;
  v_q    public.cl_plan_quotas;
  v_diag boolean;
  v_new  integer := 0;
  v_left boolean;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('cl_sample:' || p_d.account_id::text || ':' || p_feed.carrier_id::text));
  PERFORM 1 FROM public.cl_plan_quotas q
   WHERE q.id IN (SELECT i.quota_id FROM public.cl_delivery_items i
                   WHERE i.delivery_id = p_d.id AND i.drawn AND i.sample_id IS NULL)
   ORDER BY q.id FOR UPDATE;

  -- Defensa: un elegido cuya cuota ya no esta pending/open (liquidada por otra via) no se pasa; queda contado en
  -- cl_delivery_strata.skipped_settled (y alerta quota_already_settled en finish). Un elegido que ya tiene muestra de
  -- esta entrega (intento anterior) se enlaza abajo, no se salta.
  UPDATE public.cl_delivery_items i SET skipped_settled = true
   WHERE i.delivery_id = p_d.id AND i.drawn AND i.sample_id IS NULL AND NOT i.skipped_settled
     AND EXISTS (SELECT 1 FROM public.cl_plan_quotas q WHERE q.id = i.quota_id AND q.status NOT IN ('pending','open'))
     AND NOT EXISTS (SELECT 1 FROM public.cl_samples sm
                      WHERE sm.delivery_id = p_d.id AND sm.item_id = i.item_id AND sm.status = 'active');
  UPDATE public.cl_delivery_strata s SET skipped_settled = x.n
    FROM (SELECT i.quota_id, count(*)::integer AS n FROM public.cl_delivery_items i
           WHERE i.delivery_id = p_d.id AND i.skipped_settled GROUP BY i.quota_id) x
   WHERE s.delivery_id = p_d.id AND s.quota_id = x.quota_id AND s.skipped_settled IS DISTINCT FROM x.n;

  FOR v_it IN SELECT i.* FROM public.cl_delivery_items i
               WHERE i.delivery_id = p_d.id AND i.drawn AND i.sample_id IS NULL AND NOT i.skipped_settled
               ORDER BY i.quota_id, i.item_id COLLATE "C"
               LIMIT GREATEST(p_chunk, 1)
  LOOP
    SELECT sm.id INTO v_sid FROM public.cl_samples sm
     WHERE sm.delivery_id = p_d.id AND sm.item_id = v_it.item_id AND sm.status = 'active';
    IF v_sid IS NULL THEN
      SELECT q.* INTO v_q FROM public.cl_plan_quotas q WHERE q.id = v_it.quota_id;
      INSERT INTO public.cl_samples (account_id, plan_id, quota_id, delivery_id, carrier_id, product_id, item_id,
                                     start_reader_id, start_at, end_reader_id, end_at, origin_city_id,
                                     destination_city_id, extra)
      VALUES (p_d.account_id, v_it.plan_id, v_it.quota_id, p_d.id, p_feed.carrier_id, v_it.product_id, v_it.item_id,
              v_it.start_reader_id, v_it.start_at, v_it.end_reader_id, v_it.end_at, v_it.start_city_id,
              v_it.end_city_id,
              COALESCE((SELECT jsonb_object_agg(x.key, x.value) FROM (
                          SELECT DISTINCT ON (e.key) e.key, e.value
                            FROM public.cl_delivery_rows r CROSS JOIN LATERAL jsonb_each(COALESCE(r.extra, '{}'::jsonb)) e
                           WHERE r.delivery_id = p_d.id AND r.item_id = v_it.item_id
                           ORDER BY e.key, r.scan_at DESC NULLS LAST, r.row_no DESC) x), '{}'::jsonb))
      RETURNING id INTO v_sid;

      INSERT INTO public.cl_sample_scans (account_id, sample_id, reader_id, scan_at, role, place_ref, mode_ref)
      SELECT p_d.account_id, v_sid, r.reader_id, r.scan_at,
             CASE WHEN r.row_no = v_it.start_row THEN 'start'
                  WHEN r.row_no = v_it.end_row THEN 'end'
                  WHEN rd.e2e_role = 'origin' THEN 'start'
                  WHEN rd.e2e_role = 'destination' THEN 'end'
                  WHEN r.scan_at <= v_it.start_at THEN 'start'
                  ELSE 'end' END,
             r.place_ref, r.mode_ref
        FROM public.cl_delivery_rows r JOIN public.readers rd ON rd.id = r.reader_id
       WHERE r.delivery_id = p_d.id AND r.item_id = v_it.item_id AND r.row_reason IS NULL
         AND rd.e2e_role IN ('origin','destination','both')
       ORDER BY r.row_no;

      UPDATE public.cl_samples sm SET possible_misrouting = true
       WHERE sm.id = v_sid
         AND EXISTS (SELECT 1 FROM public.cl_delivery_rows r
                       JOIN public.readers rd ON rd.id = r.reader_id
                       JOIN public.postal_centers pc ON pc.id = rd.postal_center_id
                      WHERE r.delivery_id = p_d.id AND r.item_id = v_it.item_id AND r.row_reason IS NULL
                        AND rd.e2e_role IN ('origin','destination','both') AND pc.city_id IS NOT NULL
                        AND pc.city_id NOT IN (v_q.origin_city_id, v_q.destination_city_id));

      -- TODO tarea 7 (diagnostico, fase 4): si el plan tiene feed_diagnosis, pasar TODAS las lecturas validas del
      -- envio (tambien las intermedias) a la zona de diagnostico (rfid_events_raw con marca de origen). Aqui, antes de
      -- vaciar la zona de paso, es el unico momento en que existen.
      SELECT p.feed_diagnosis INTO v_diag FROM public.cl_plans p WHERE p.id = v_it.plan_id;

      PERFORM public.cl_transfer_sample(v_sid);
      UPDATE public.cl_plan_quotas q SET samples_obtained = q.samples_obtained + 1 WHERE q.id = v_it.quota_id;
      v_new := v_new + 1;
    END IF;
    UPDATE public.cl_delivery_items i SET sample_id = v_sid
     WHERE i.delivery_id = p_d.id AND i.item_id = v_it.item_id;
  END LOOP;

  SELECT EXISTS (SELECT 1 FROM public.cl_delivery_items i
                  WHERE i.delivery_id = p_d.id AND i.drawn AND i.sample_id IS NULL AND NOT i.skipped_settled) INTO v_left;
  UPDATE public.cl_deliveries d
     SET progress = d.progress || jsonb_build_object('phase', CASE WHEN v_left THEN 'transfer' ELSE 'finish' END)
   WHERE d.id = p_d.id;
  RETURN 'transfer';
END $$;

-- 6.6 finish: elegidos por estrato, recuentos de la entrega, alertas y liquidacion (entregas reales) de las cuotas
-- cuya semana termina dentro de la entrega (cl_settle_quota: cumplida, deficit arrastrado o unfilled).
-- rejected_reasons = {"rows": {motivo: n}, "shipments": {motivo: n}}.
CREATE OR REPLACE FUNCTION public.cl_delivery_phase_finish(p_d public.cl_deliveries, p_feed public.cl_feeds)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_ship  jsonb;
  v_tot   bigint;
  v_valid bigint;
  v_drawn bigint;
  v_used  bigint;
  v_rowrej bigint;
  v_st    record;
  v_qid   uuid;
  v_n     bigint;
  v_all_ok boolean;
BEGIN
  UPDATE public.cl_delivery_strata s SET selected = x.n
    FROM (SELECT i.quota_id, count(*)::integer AS n FROM public.cl_delivery_items i
           WHERE i.delivery_id = p_d.id AND i.drawn AND i.sample_id IS NOT NULL GROUP BY i.quota_id) x
   WHERE s.delivery_id = p_d.id AND s.quota_id = x.quota_id AND s.selected IS DISTINCT FROM x.n;

  SELECT count(*), count(*) FILTER (WHERE i.reason IS NULL), count(*) FILTER (WHERE i.drawn AND NOT i.skipped_settled),
         count(*) FILTER (WHERE i.reason = 'already_sampled')
    INTO v_tot, v_valid, v_drawn, v_used
    FROM public.cl_delivery_items i WHERE i.delivery_id = p_d.id;
  SELECT COALESCE(jsonb_object_agg(z.reason, z.n), '{}'::jsonb) INTO v_ship
    FROM (SELECT i.reason, count(*) AS n FROM public.cl_delivery_items i
           WHERE i.delivery_id = p_d.id AND i.reason IS NOT NULL GROUP BY i.reason) z;
  SELECT COALESCE(sum(e.value::bigint), 0) INTO v_rowrej
    FROM jsonb_each_text(COALESCE(p_d.progress->'row_reasons', '{}'::jsonb)) e;

  UPDATE public.cl_deliveries d
     SET rows_rejected = v_rowrej, shipments_total = v_tot, shipments_valid = v_valid,
         shipments_drawn = CASE WHEN d.is_test THEN 0 ELSE v_drawn END,
         rejected_reasons = jsonb_build_object('rows', COALESCE(d.progress->'row_reasons', '{}'::jsonb),
                                               'shipments', v_ship)
   WHERE d.id = p_d.id;

  IF NOT p_d.is_test THEN
    IF jsonb_array_length(COALESCE(p_d.progress->'unknown_products', '[]'::jsonb)) > 0 THEN
      PERFORM public.cl_delivery_alert(p_d.id, NULL, NULL, 'unknown_product', 'medium',
                                       jsonb_build_object('values', p_d.progress->'unknown_products'));
    END IF;
    IF jsonb_array_length(COALESCE(p_d.progress->'unknown_points', '[]'::jsonb)) > 0 THEN
      PERFORM public.cl_delivery_alert(p_d.id, NULL, NULL, 'unknown_reading_point', 'medium',
                                       jsonb_build_object('points', p_d.progress->'unknown_points'));
    END IF;
    IF v_tot - v_used > 0 AND (v_tot - v_used - v_valid)::numeric / (v_tot - v_used) > 0.2 THEN
      PERFORM public.cl_delivery_alert(p_d.id, NULL, NULL, 'rejected_ratio', 'medium',
        jsonb_build_object('rejected', v_tot - v_used - v_valid, 'shipments', v_tot - v_used,
                           'ratio', round((v_tot - v_used - v_valid)::numeric / (v_tot - v_used), 3), 'reasons', v_ship));
    END IF;
    IF EXISTS (SELECT 1 FROM public.cl_delivery_items i WHERE i.delivery_id = p_d.id AND i.reason = 'reader_without_city') THEN
      PERFORM public.cl_delivery_alert(p_d.id, NULL, NULL, 'reader_without_city', 'high',
        jsonb_build_object('reader_ids', (SELECT jsonb_agg(DISTINCT x.rid) FROM public.cl_delivery_items i
                                           CROSS JOIN LATERAL (VALUES (CASE WHEN i.start_city_id IS NULL THEN i.start_reader_id END),
                                                                      (CASE WHEN i.end_city_id IS NULL THEN i.end_reader_id END)) x(rid)
                                          WHERE i.delivery_id = p_d.id AND i.reason = 'reader_without_city'
                                            AND x.rid IS NOT NULL)));
    END IF;
    FOR v_st IN SELECT s.quota_id, s.population, s.quota_for_delivery, s.selected, s.skipped_settled, q.plan_id, q.status
                  FROM public.cl_delivery_strata s JOIN public.cl_plan_quotas q ON q.id = s.quota_id
                 WHERE s.delivery_id = p_d.id ORDER BY s.quota_id
    LOOP
      IF v_st.skipped_settled > 0 THEN
        PERFORM public.cl_delivery_alert(p_d.id, v_st.plan_id, v_st.quota_id, 'quota_already_settled', 'high',
          jsonb_build_object('skipped', v_st.skipped_settled, 'quota_status', v_st.status));
      END IF;
      IF v_st.population < v_st.quota_for_delivery THEN
        PERFORM public.cl_delivery_alert(p_d.id, v_st.plan_id, v_st.quota_id, 'insufficient_candidates', 'medium',
          jsonb_build_object('population', v_st.population, 'quota_for_delivery', v_st.quota_for_delivery));
      END IF;
      IF EXISTS (SELECT 1 FROM public.cl_samples sm
                  WHERE sm.delivery_id = p_d.id AND sm.quota_id = v_st.quota_id AND sm.possible_misrouting) THEN
        PERFORM public.cl_delivery_alert(p_d.id, v_st.plan_id, v_st.quota_id, 'possible_misrouting', 'medium',
          jsonb_build_object('samples', (SELECT jsonb_agg(jsonb_build_object('sample_id', sm.id, 'item_id', sm.item_id)
                                                          ORDER BY sm.item_id)
                                           FROM public.cl_samples sm
                                          WHERE sm.delivery_id = p_d.id AND sm.quota_id = v_st.quota_id
                                            AND sm.possible_misrouting)));
      END IF;
      -- Distribucion sospechosa (como cl_sample_stratum): n >= 20 muestras de la cuota con "en plazo" y todas en plazo.
      SELECT count(*), bool_and(o.on_time_delivery) INTO v_n, v_all_ok
        FROM public.cl_samples sm JOIN public.one_db o ON o.cl_sample_id = sm.id
       WHERE sm.quota_id = v_st.quota_id AND sm.status = 'active' AND o.on_time_delivery IS NOT NULL;
      IF v_st.selected > 0 AND v_n >= 20 AND v_all_ok THEN
        PERFORM public.cl_delivery_alert(p_d.id, v_st.plan_id, v_st.quota_id, 'suspicious_distribution', 'medium',
          jsonb_build_object('samples', v_n, 'on_time_ratio', 1));
      END IF;
    END LOOP;

    -- Semanas cerradas por esta entrega: misma secuencia de bloqueo que el sorteo (candado y cuotas por id).
    PERFORM pg_advisory_xact_lock(hashtext('cl_sample:' || p_d.account_id::text || ':' || p_feed.carrier_id::text));
    FOR v_qid IN SELECT q.id FROM public.cl_plan_quotas q
                   JOIN public.cl_delivery_strata s ON s.delivery_id = p_d.id AND s.quota_id = q.id
                  WHERE q.period_end BETWEEN p_d.period_start AND p_d.period_end AND q.status IN ('pending','open')
                  ORDER BY q.period_start, q.id
    LOOP
      UPDATE public.cl_plan_quotas q SET status = 'open' WHERE q.id = v_qid AND q.status = 'pending';
      PERFORM public.cl_settle_quota(v_qid);
    END LOOP;

    UPDATE public.cl_feeds f SET last_batch_at = now() WHERE f.id = p_d.feed_id;
  END IF;

  UPDATE public.cl_deliveries d
     SET progress = d.progress || jsonb_build_object('phase', 'cleanup', 'final_status', 'processed', 'final_error', NULL)
   WHERE d.id = p_d.id;
  RETURN 'finish';
END $$;

-- 6.7a Deshacer lo que paso una entrega (como cl_undo_batch): borra sus filas de one_db, anula (voided) sus muestras
-- activas (cl_sample_scans quedan con la muestra anulada, igual que al deshacer un lote), descuenta samples_obtained de
-- sus cuotas y cierra (dismissed) sus alertas abiertas y las missing_standard que nombran una muestra suya. Mismo
-- candado que el sorteo (cuenta + carrier) y cuotas bloqueadas por id. Devuelve las muestras anuladas.
CREATE OR REPLACE FUNCTION public.cl_delivery_undo_samples(p_d public.cl_deliveries)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_carrier uuid := (SELECT f.carrier_id FROM public.cl_feeds f WHERE f.id = p_d.feed_id);
  v_n integer;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('cl_sample:' || p_d.account_id::text || ':' || v_carrier::text));
  PERFORM 1 FROM public.cl_plan_quotas q
   WHERE q.id IN (SELECT s.quota_id FROM public.cl_samples s WHERE s.delivery_id = p_d.id AND s.status = 'active')
   ORDER BY q.id FOR UPDATE;

  UPDATE public.cl_alerts a
     SET status = 'dismissed',
         details = COALESCE(a.details, '{}'::jsonb) || jsonb_build_object('dismissed_by_undo_delivery', p_d.id)
   WHERE a.status = 'open' AND a.account_id = p_d.account_id
     AND (a.delivery_id = p_d.id
          OR (a.alert_type = 'missing_standard'
              AND a.details->>'first_sample_id' IN (SELECT s.id::text FROM public.cl_samples s
                                                     WHERE s.delivery_id = p_d.id AND s.status = 'active')));

  DELETE FROM public.one_db o
   USING public.cl_samples s
   WHERE o.cl_sample_id = s.id AND s.delivery_id = p_d.id AND s.status = 'active';

  WITH v AS (
    UPDATE public.cl_samples SET status = 'voided'
     WHERE delivery_id = p_d.id AND status = 'active'
    RETURNING quota_id
  ), u AS (
    UPDATE public.cl_plan_quotas q SET samples_obtained = GREATEST(q.samples_obtained - c.n, 0)
      FROM (SELECT v.quota_id, count(*)::integer AS n FROM v WHERE v.quota_id IS NOT NULL GROUP BY v.quota_id) c
     WHERE q.id = c.quota_id
    RETURNING q.id
  )
  SELECT (SELECT count(*) FROM v)::integer INTO v_n;
  RETURN v_n;
END $$;

-- 6.7 cleanup: vacia la zona de paso de la entrega (TRUNCATE si no hay filas de otra entrega, lo normal por R25; si no,
-- DELETE de hasta p_chunk filas por paso) y la deja en su estado final (processed / failed / rejected).
-- Fallo con los intentos agotados (attempts >= 3): fallo terminal. Se deshace lo que paso la entrega
-- (cl_delivery_undo_samples), queda rejected con CL_RETRIES_EXHAUSTED (el periodo queda libre para reenviarlo y deja
-- de bloquear las entregas posteriores del conector) y alerta delivery_retries_exhausted por plan activo.
CREATE OR REPLACE FUNCTION public.cl_delivery_phase_cleanup(p_d public.cl_deliveries, p_chunk integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_status text := COALESCE(p_d.progress->>'final_status', 'failed');
  v_error  text := COALESCE(p_d.progress->>'final_error', 'CL_PROCESSING_ERROR');
  v_left   boolean;
  v_voided integer;
  v_plan   uuid;
  v_alerted boolean := false;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.cl_delivery_rows r WHERE r.delivery_id < p_d.id)
     AND NOT EXISTS (SELECT 1 FROM public.cl_delivery_rows r WHERE r.delivery_id > p_d.id)
     AND NOT EXISTS (SELECT 1 FROM public.cl_delivery_items i WHERE i.delivery_id < p_d.id)
     AND NOT EXISTS (SELECT 1 FROM public.cl_delivery_items i WHERE i.delivery_id > p_d.id) THEN
    TRUNCATE public.cl_delivery_rows, public.cl_delivery_items;
  ELSE
    DELETE FROM public.cl_delivery_items i
     WHERE i.delivery_id = p_d.id
       AND i.item_id IN (SELECT i2.item_id FROM public.cl_delivery_items i2 WHERE i2.delivery_id = p_d.id
                          LIMIT GREATEST(p_chunk, 1));
    DELETE FROM public.cl_delivery_rows r
     WHERE r.delivery_id = p_d.id
       AND r.row_no IN (SELECT r2.row_no FROM public.cl_delivery_rows r2 WHERE r2.delivery_id = p_d.id
                         LIMIT GREATEST(p_chunk, 1));
    SELECT EXISTS (SELECT 1 FROM public.cl_delivery_rows r WHERE r.delivery_id = p_d.id)
        OR EXISTS (SELECT 1 FROM public.cl_delivery_items i WHERE i.delivery_id = p_d.id) INTO v_left;
    IF v_left THEN RETURN 'cleanup'; END IF;
  END IF;

  IF v_status = 'failed' AND COALESCE((p_d.progress->>'attempts')::integer, 0) >= 3 THEN
    v_voided := public.cl_delivery_undo_samples(p_d);
    FOR v_plan IN SELECT p.id FROM public.cl_plans p
                   WHERE p.feed_id = p_d.feed_id AND p.status = 'active'
                     AND p.start_date <= p_d.period_end AND p.end_date >= p_d.period_start
                   ORDER BY p.id
    LOOP
      PERFORM public.cl_raise_alert(v_plan, NULL, 'delivery_retries_exhausted', 'high',
        jsonb_build_object('delivery_id', p_d.id, 'period_start', p_d.period_start, 'period_end', p_d.period_end,
                           'last_error', v_error, 'attempts', (p_d.progress->>'attempts')::integer,
                           'samples_voided', v_voided));
      v_alerted := true;
    END LOOP;
    -- Traza de la entrega en la alerta (cl_raise_alert no la guarda).
    UPDATE public.cl_alerts a SET delivery_id = p_d.id
     WHERE a.account_id = p_d.account_id AND a.alert_type = 'delivery_retries_exhausted' AND a.delivery_id IS NULL
       AND a.details->>'delivery_id' = p_d.id::text;
    IF NOT v_alerted THEN
      PERFORM public.cl_delivery_alert(p_d.id, NULL, NULL, 'delivery_retries_exhausted', 'high',
        jsonb_build_object('last_error', v_error, 'samples_voided', v_voided));
    END IF;
    v_status := 'rejected';
    v_error := 'CL_RETRIES_EXHAUSTED';
  END IF;

  UPDATE public.cl_deliveries d
     SET status = v_status,
         error = CASE WHEN v_status = 'processed' THEN NULL ELSE v_error END,
         finished_at = now(),
         progress = (d.progress - 'cursor' - 'cursor_item' - 'lease_token' - 'lease_until')
                    || jsonb_build_object('phase', CASE WHEN v_status = 'processed' THEN 'done' ELSE v_status END,
                                          'finished_at', now())
   WHERE d.id = p_d.id;
  RETURN 'cleanup';
END $$;

-- ================================================================ 7. paso del proceso y bucle (pg_cron)
-- cl_process_delivery: UN paso acotado de la entrega en proceso (o de p_delivery_id). Devuelve la fase hecha:
-- 'idle' (nada en proceso), 'load' (la carga es del worker: nada que hacer), 'reset' (zona de paso perdida: vuelve a
-- cargar), 'resolve', 'items', 'strata', 'draw', 'transfer', 'finish', 'cleanup'. p_chunk = filas por paso
-- (resolve / items / cleanup); transfer usa p_chunk / 200 envios por paso.
CREATE OR REPLACE FUNCTION public.cl_process_delivery(p_delivery_id uuid DEFAULT NULL, p_chunk integer DEFAULT 100000)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_id    uuid;
  v_feed  public.cl_feeds;
  v_d     public.cl_deliveries;
  v_phase text;
  v_chunk integer := LEAST(GREATEST(COALESCE(p_chunk, 100000), 1), 2000000);
BEGIN
  SELECT d.id INTO v_id FROM public.cl_deliveries d
   WHERE d.status = 'processing' AND (p_delivery_id IS NULL OR d.id = p_delivery_id);
  IF v_id IS NULL THEN RETURN 'idle'; END IF;
  SELECT f.* INTO v_feed FROM public.cl_feeds f
   WHERE f.id = (SELECT d.feed_id FROM public.cl_deliveries d WHERE d.id = v_id) FOR UPDATE;
  SELECT d.* INTO v_d FROM public.cl_deliveries d WHERE d.id = v_id FOR UPDATE;
  IF v_d.status IS DISTINCT FROM 'processing' THEN RETURN 'idle'; END IF;
  v_phase := v_d.progress->>'phase';
  IF v_phase = 'load' THEN RETURN 'load'; END IF;

  IF v_phase IN ('resolve','items','strata','draw','transfer','finish')
     AND public.cl_delivery_staging_lost(v_d.id, v_d.rows_total) THEN
    UPDATE public.cl_deliveries d
       SET rows_total = NULL,
           progress = (d.progress - 'cursor' - 'cursor_item' - 'row_reasons' - 'unknown_products' - 'unknown_points')
                      || jsonb_build_object('phase', 'load', 'load', public.cl_delivery_load_start(),
                                            'staging_lost', COALESCE((d.progress->>'staging_lost')::integer, 0) + 1)
     WHERE d.id = v_d.id;
    RETURN 'reset';
  END IF;

  RETURN CASE v_phase
    WHEN 'resolve'  THEN public.cl_delivery_phase_resolve(v_d, v_feed, v_chunk)
    WHEN 'items'    THEN public.cl_delivery_phase_items(v_d, v_feed, v_chunk)
    WHEN 'strata'   THEN public.cl_delivery_phase_strata(v_d, v_feed)
    WHEN 'draw'     THEN public.cl_delivery_phase_draw(v_d)
    WHEN 'transfer' THEN public.cl_delivery_phase_transfer(v_d, v_feed, GREATEST(v_chunk / 200, 1))
    WHEN 'finish'   THEN public.cl_delivery_phase_finish(v_d, v_feed)
    WHEN 'cleanup'  THEN public.cl_delivery_phase_cleanup(v_d, v_chunk)
    WHEN 'abort'    THEN public.cl_delivery_phase_cleanup(v_d, v_chunk)
    ELSE 'idle' END;
END $$;

-- Error en un paso: la entrega pasa a abort/failed (reanudable; error = codigo CL_ del mensaje o
-- CL_PROCESSING_ERROR + SQLSTATE: el texto del error puede llevar valores del fichero).
CREATE OR REPLACE FUNCTION public.cl_process_delivery_failed(p_sqlstate text, p_message text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_id uuid;
BEGIN
  SELECT d.id INTO v_id FROM public.cl_deliveries d WHERE d.status = 'processing';
  IF v_id IS NULL THEN RETURN; END IF;
  PERFORM public.cl_delivery_mark_abort(v_id, 'failed',
    COALESCE(substring(p_message FROM '^(CL_[A-Z0-9_]+)'), 'CL_PROCESSING_ERROR ' || COALESCE(p_sqlstate, '')));
END $$;

-- Bucle de pg_cron: pasos con COMMIT entre ellos hasta acabar o agotar p_budget_ms. Un procedimiento con COMMIT no
-- puede ser SECURITY DEFINER ni llevar SET: lo ejecuta postgres (pg_cron) y usa nombres cualificados. Un candado de
-- sesion evita dos bucles a la vez. Un error de un paso deja la entrega en abort (el siguiente paso la vacia y la
-- marca failed); si el propio vaciado falla, se reintenta en la siguiente ejecucion.
CREATE OR REPLACE PROCEDURE public.cl_delivery_process_run(p_budget_ms integer DEFAULT 50000, p_chunk integer DEFAULT 100000)
 LANGUAGE plpgsql
AS $$
DECLARE
  v_t0    timestamptz := pg_catalog.clock_timestamp();
  v_r     text;
  v_state text;
  v_msg   text;
  v_err   boolean;
  v_phase text;
BEGIN
  IF NOT pg_catalog.pg_try_advisory_lock(pg_catalog.hashtext('cl_delivery_process_run')) THEN
    RETURN;
  END IF;
  LOOP
    v_err := false;
    BEGIN
      v_r := public.cl_process_delivery(NULL, p_chunk);
    EXCEPTION WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_msg = MESSAGE_TEXT;
      v_err := true;
    END;
    IF v_err THEN
      RAISE WARNING 'cl_delivery_process_run: step failed (%)', v_state;
      SELECT d.progress->>'phase' INTO v_phase FROM public.cl_deliveries d WHERE d.status = 'processing';
      IF v_phase IN ('abort','cleanup') THEN
        v_r := 'stop';           -- el propio vaciado fallo: se reintenta en la siguiente ejecucion
      ELSE
        PERFORM public.cl_process_delivery_failed(v_state, v_msg);
        v_r := 'failed';
      END IF;
    END IF;
    COMMIT;
    EXIT WHEN v_r IN ('idle','load','stop')
           OR pg_catalog.clock_timestamp() - v_t0 > pg_catalog.make_interval(secs => p_budget_ms / 1000.0);
  END LOOP;
  PERFORM pg_catalog.pg_advisory_unlock(pg_catalog.hashtext('cl_delivery_process_run'));
END $$;

-- ================================================================ 8. cl_settle_quota (de 20261120111000) + v4
-- Cambio: una cuota de un plan con entregas completas (algun cl_delivery_strata de una entrega real en proceso o
-- procesada) tiene la poblacion completa: no se vuelve a pedir (sin rama 'pending'); el deficit se arrastra o queda
-- unfilled como siempre. El resto, igual.
CREATE OR REPLACE FUNCTION public.cl_settle_quota(p_quota_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_q     public.cl_plan_quotas;
  v_falta integer;
  v_pop   bigint;
  v_recv  bigint;
  v_ids   uuid[];
  v_n     integer;
  v_last  uuid;
  v_known boolean;
  v_v4    boolean;
BEGIN
  SELECT * INTO v_q FROM public.cl_plan_quotas WHERE id = p_quota_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CL_QUOTA_NOT_FOUND: quota not found' USING ERRCODE = '22023';
  END IF;
  IF v_q.status <> 'open' THEN
    RETURN v_q.status;
  END IF;

  v_falta := v_q.samples_planned + v_q.samples_carried_in - v_q.samples_obtained;
  IF v_falta <= 0 THEN
    UPDATE public.cl_plan_quotas SET status = 'fulfilled' WHERE id = p_quota_id;
    RETURN 'fulfilled';
  END IF;

  v_v4 := EXISTS (SELECT 1 FROM public.cl_delivery_strata s JOIN public.cl_deliveries d ON d.id = s.delivery_id
                   WHERE s.quota_id = p_quota_id AND NOT d.is_test AND d.status IN ('processing','processed'));

  IF NOT v_v4 THEN
    -- Ultima poblacion informada: la del sorteo del estrato en la ULTIMA demanda que lo pidio (un estrato se entrega
    -- una sola vez por demanda). Sin sorteo en esa demanda (caducada sin respuesta) la poblacion es desconocida -> se
    -- vuelve a pedir mientras demands_count < 3.
    SELECT d.id INTO v_last
      FROM public.cl_demands d
     WHERE d.plan_id = v_q.plan_id
       AND d.payload->'strata' @> jsonb_build_array(jsonb_build_object('stratum_id', p_quota_id))
     ORDER BY d.seq DESC   -- D4: orden de emision (requested_at puede venir de un p_now explicito anterior)
     LIMIT 1;
    SELECT r.population_size INTO v_pop
      FROM public.cl_sampling_runs r JOIN public.cl_batches b ON b.id = r.batch_id
     WHERE b.demand_id = v_last AND r.stratum_id = p_quota_id
     ORDER BY r.executed_at DESC, r.created_at DESC, r.id DESC
     LIMIT 1;
    v_known := FOUND;
    -- Candidatos distintos recibidos en los lotes de las demandas del plan (cualquier estado de lectura), sin contar
    -- los lotes deshechos ni rechazados.
    SELECT count(DISTINCT s.item_id) INTO v_recv
      FROM public.cl_batch_scans s
     WHERE s.batch_id IN (SELECT b.id FROM public.cl_batches b JOIN public.cl_demands d ON d.id = b.demand_id
                           WHERE d.plan_id = v_q.plan_id AND b.status NOT IN ('undone', 'rejected'))
       AND s.stratum_id = p_quota_id
       AND s.item_id IS NOT NULL;

    IF (NOT v_known OR v_pop IS NULL OR v_pop > v_recv) AND v_q.demands_count < 3 THEN
      UPDATE public.cl_plan_quotas SET status = 'pending' WHERE id = p_quota_id;
      RETURN 'pending';
    END IF;
  END IF;

  -- Destinos posibles: se bloquean (orden por id) y despues se eligen con su estado ya bloqueado.
  PERFORM 1 FROM public.cl_plan_quotas q
   WHERE q.plan_id = v_q.plan_id AND q.origin_city_id = v_q.origin_city_id
     AND q.destination_city_id = v_q.destination_city_id
     AND q.status = 'pending' AND q.period_start > v_q.period_start
   ORDER BY q.id
     FOR UPDATE;

  -- El mes mas temprano con cuotas pending posteriores: el mismo mes si lo hay, si no el siguiente que tenga alguna.
  WITH c AS (
    SELECT q.id, q.period_start, date_trunc('month', q.period_start) AS m
      FROM public.cl_plan_quotas q
     WHERE q.plan_id = v_q.plan_id AND q.origin_city_id = v_q.origin_city_id
       AND q.destination_city_id = v_q.destination_city_id
       AND q.status = 'pending' AND q.period_start > v_q.period_start
  )
  SELECT array_agg(c.id ORDER BY c.period_start, c.id) INTO v_ids
    FROM c WHERE c.m = (SELECT min(m) FROM c);

  IF v_ids IS NULL THEN
    UPDATE public.cl_plan_quotas SET status = 'unfilled' WHERE id = p_quota_id;
    PERFORM public.cl_raise_alert(v_q.plan_id, p_quota_id, 'quota_unfilled', 'high',
      jsonb_build_object('missing', v_falta, 'samples_planned', v_q.samples_planned,
                         'samples_carried_in', v_q.samples_carried_in, 'samples_obtained', v_q.samples_obtained,
                         'demands_count', v_q.demands_count));
    RETURN 'unfilled';
  END IF;

  v_n := cardinality(v_ids);
  UPDATE public.cl_plan_quotas q
     SET samples_carried_in = q.samples_carried_in + v_falta / v_n + CASE WHEN x.ord <= v_falta % v_n THEN 1 ELSE 0 END
    FROM unnest(v_ids) WITH ORDINALITY x(id, ord)
   WHERE q.id = x.id;
  UPDATE public.cl_plan_quotas SET status = 'carried' WHERE id = p_quota_id;
  RETURN 'carried';
END $$;
REVOKE ALL ON FUNCTION public.cl_settle_quota(uuid) FROM PUBLIC, anon, authenticated, service_role;

-- ================================================================ 9. arranque del worker (pg_cron + pg_net)
-- Cada minuto: caduca las subidas abandonadas (pending_upload de mas de 7 dias -> rejected CL_UPLOAD_EXPIRED) y, si
-- hay trabajo para el worker (carga en curso, entrega recibida, fallida reintentable o ficheros que borrar), lo llama
-- por pg_net. URL y secreto en Vault: cl_worker_url (https://<ref>.supabase.co/functions/v1/carrier-link-worker) y
-- cl_worker_secret (el mismo valor que la variable CL_WORKER_SECRET de la Edge Function). Sin secretos: no llama.
CREATE OR REPLACE FUNCTION public.cl_delivery_kick_worker(p_now timestamptz DEFAULT now())
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_r      record;
  v_url    text;
  v_secret text;
BEGIN
  FOR v_r IN SELECT d.id, d.feed_id FROM public.cl_deliveries d
              WHERE d.status = 'pending_upload' AND d.created_at < p_now - interval '7 days'
              ORDER BY d.created_at, d.id LIMIT 100
  LOOP
    PERFORM 1 FROM public.cl_feeds f WHERE f.id = v_r.feed_id FOR UPDATE;
    UPDATE public.cl_deliveries d SET status = 'rejected', error = 'CL_UPLOAD_EXPIRED', finished_at = p_now
     WHERE d.id = v_r.id AND d.status = 'pending_upload';
  END LOOP;

  IF NOT (EXISTS (SELECT 1 FROM public.cl_deliveries d
                   WHERE (d.status = 'processing' AND d.progress->>'phase' = 'load')
                      OR d.status = 'received'
                      OR (d.status = 'failed' AND COALESCE((d.progress->>'attempts')::integer, 0) < 3
                          AND COALESCE(d.finished_at, d.received_at) < p_now - interval '5 minutes'
                          AND d.file_deleted_at IS NULL))
          OR jsonb_array_length(public.cl_delivery_sweep_list(1, p_now)) > 0) THEN
    RETURN false;
  END IF;
  IF to_regclass('vault.decrypted_secrets') IS NULL THEN RETURN false; END IF;
  SELECT s.decrypted_secret INTO v_url FROM vault.decrypted_secrets s WHERE s.name = 'cl_worker_url';
  SELECT s.decrypted_secret INTO v_secret FROM vault.decrypted_secrets s WHERE s.name = 'cl_worker_secret';
  IF v_url IS NULL OR v_secret IS NULL THEN RETURN false; END IF;
  PERFORM net.http_post(url := v_url, body := '{}'::jsonb,
                        headers := jsonb_build_object('Content-Type', 'application/json', 'x-cl-worker-secret', v_secret),
                        timeout_milliseconds := 5000);
  RETURN true;
END $$;

-- ================================================================ 10. grants
REVOKE ALL ON FUNCTION public.cl_delivery_working_days(uuid, date, date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_quota_share(uuid, integer, date, date, date, date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_staging_lost(uuid, bigint) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_load_start() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_alert(uuid, uuid, uuid, text, text, jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_mark_abort(uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_load_lock(uuid, text, bigint) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_phase_resolve(public.cl_deliveries, public.cl_feeds, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_phase_items(public.cl_deliveries, public.cl_feeds, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_phase_strata(public.cl_deliveries, public.cl_feeds) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_phase_draw(public.cl_deliveries) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_phase_transfer(public.cl_deliveries, public.cl_feeds, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_phase_finish(public.cl_deliveries, public.cl_feeds) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_phase_cleanup(public.cl_deliveries, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_undo_samples(public.cl_deliveries) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_process_delivery(uuid, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_process_delivery_failed(text, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON PROCEDURE public.cl_delivery_process_run(integer, integer) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_kick_worker(timestamptz) FROM PUBLIC, anon, authenticated, service_role;

-- Edge Function carrier-link-worker (service_role).
REVOKE ALL ON FUNCTION public.cl_delivery_worker_claim(text, integer, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cl_delivery_load_rows(uuid, text, bigint, jsonb, jsonb, boolean, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cl_delivery_load_done(uuid, text, bigint, text, bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cl_delivery_load_fail(uuid, text, text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cl_delivery_sweep_list(integer, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cl_delivery_sweep_done(text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cl_delivery_worker_claim(text, integer, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.cl_delivery_load_rows(uuid, text, bigint, jsonb, jsonb, boolean, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.cl_delivery_load_done(uuid, text, bigint, text, bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.cl_delivery_load_fail(uuid, text, text, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.cl_delivery_sweep_list(integer, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.cl_delivery_sweep_done(text[]) TO service_role;

-- ================================================================ 11. pg_cron (idempotente)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cl-delivery-process') THEN
    PERFORM cron.unschedule('cl-delivery-process');
  END IF;
  PERFORM cron.schedule('cl-delivery-process', '* * * * *', 'CALL public.cl_delivery_process_run();');
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cl-delivery-worker-kick') THEN
    PERFORM cron.unschedule('cl-delivery-worker-kick');
  END IF;
  PERFORM cron.schedule('cl-delivery-worker-kick', '* * * * *', 'SELECT public.cl_delivery_kick_worker();');
END $$;
