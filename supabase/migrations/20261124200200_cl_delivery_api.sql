-- Carrier Link v4, tarea 3: contrato de la Edge Function carrier-link-ingest (GET /config, POST /deliveries,
-- POST /deliveries/{id}/complete, GET /deliveries/{id}). Sobre 20261124200000_cl_deliveries.sql (tarea 1) y
-- 20261124200100_cl_process_delivery.sql (tarea 2).
--
--   1. Sin compresion en v4: cl_delivery_open y cl_manual_delivery_open ya no reciben p_compression (siempre 'none');
--      cl_connector_config anuncia solo 'none'. El nucleo interno (cl_delivery_open_core) no cambia.
--   2. cl_delivery_open recibe el tamano declarado (p_size_bytes, obligatorio): mayor que max_file_bytes del
--      conector -> CL_FILE_TOO_LARGE antes de crear la entrega (no se emite una URL de subida inutil).
--   3. cl_delivery_status(feed, entrega): GET /deliveries/{id}. La entrega de otro conector o inexistente da el MISMO
--      CL_DELIVERY_NOT_FOUND (sin fuga de existencia). Anade las alertas que el transportista puede ver.
--   4. Retirada del motor de demandas v3: fuera el job cl-emit-demands y la funcion cl_emit_due_demands. Las tablas de
--      demandas y lotes se quedan (historial); no se emiten demandas nuevas.
-- Forward-only.
-- Bloqueos (revision final I2): ADD CONSTRAINT en cl_deliveries (nueva de v4), retirada del job vivo cl-emit-demands
-- (filas de cron.job) y DROP de su funcion. lock_timeout de 5 s: falla enseguida en vez de esperar en cola. Aplicar en
-- UNA transaccion.
SET LOCAL lock_timeout = '5s';

-- ================================================================ 1-2. abrir una entrega (sin compresion, con tamano)
DROP FUNCTION IF EXISTS public.cl_delivery_open(uuid, date, date, text, jsonb, text, text);
DROP FUNCTION IF EXISTS public.cl_manual_delivery_open(uuid, date, date, text, jsonb, text, text);

-- Edge Function (service_role; p_feed_id sale de la clave del conector, nunca del cuerpo).
CREATE OR REPLACE FUNCTION public.cl_delivery_open(
  p_feed_id uuid, p_period_start date, p_period_end date, p_sha256 text, p_control_totals jsonb,
  p_format text DEFAULT 'jsonl', p_size_bytes bigint DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE v_max bigint;
BEGIN
  IF p_size_bytes IS NULL OR p_size_bytes < 1 THEN
    RAISE EXCEPTION 'CL_BAD_REQUEST: size_bytes must be a positive integer' USING ERRCODE = '22023';
  END IF;
  SELECT (public.cl_delivery_limits(f.config)->>'max_file_bytes')::bigint INTO v_max
    FROM public.cl_feeds f WHERE f.id = p_feed_id;
  IF p_size_bytes > v_max THEN
    RAISE EXCEPTION 'CL_FILE_TOO_LARGE: size_bytes % is over the limit of % bytes', p_size_bytes, v_max
      USING ERRCODE = '22023';
  END IF;
  RETURN public.cl_delivery_open_core(p_feed_id, p_period_start, p_period_end, p_sha256, p_control_totals,
                                      p_format, 'none', 'api', NULL, now());
END $$;

-- Web (Conectores, subida manual): Edit en cl_connectors de la cuenta del conector, o superadmin. El tope lo aplican
-- el bucket y cl_manual_delivery_complete.
CREATE OR REPLACE FUNCTION public.cl_manual_delivery_open(
  p_feed_id uuid, p_period_start date, p_period_end date, p_sha256 text, p_control_totals jsonb,
  p_format text DEFAULT 'jsonl')
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
BEGIN
  PERFORM public.cl_delivery_authorize_manual(p_feed_id);
  RETURN public.cl_delivery_open_core(p_feed_id, p_period_start, p_period_end, p_sha256, p_control_totals,
                                      p_format, 'none', 'manual', auth.uid(), now());
END $$;

REVOKE ALL ON FUNCTION public.cl_delivery_open(uuid, date, date, text, jsonb, text, bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cl_delivery_open(uuid, date, date, text, jsonb, text, bigint) TO service_role;
REVOKE ALL ON FUNCTION public.cl_manual_delivery_open(uuid, date, date, text, jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cl_manual_delivery_open(uuid, date, date, text, jsonb, text) TO authenticated;

-- ================================================================ 1. configuracion: solo 'none'
-- Copia de 20261124200000 con un unico cambio: formats.compression = ["none"].
CREATE OR REPLACE FUNCTION public.cl_connector_config(p_feed_id uuid, p_now timestamptz DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_feed   public.cl_feeds;
  v_n      integer;
  v_fields jsonb;
  v_last   jsonb;
BEGIN
  SELECT f.* INTO v_feed FROM public.cl_feeds f WHERE f.id = p_feed_id;
  IF v_feed.id IS NULL THEN
    RAISE EXCEPTION 'CL_FEED_NOT_FOUND' USING ERRCODE = '22023';
  END IF;
  v_n := cardinality(v_feed.emit_days);

  SELECT jsonb_build_object(
           'item_id',   (SELECT jsonb_build_object('field', m.carrier_field) FROM public.cl_field_mappings m
                          WHERE m.account_id = v_feed.account_id AND m.carrier_id = v_feed.carrier_id AND m.standard_field = 'item_id'),
           'product',   (SELECT jsonb_build_object('field', m.carrier_field) FROM public.cl_field_mappings m
                          WHERE m.account_id = v_feed.account_id AND m.carrier_id = v_feed.carrier_id AND m.standard_field = 'product'),
           'scan_at',   (SELECT jsonb_build_object('field', m.carrier_field, 'format', m.format, 'timezone', m.timezone)
                           FROM public.cl_field_mappings m
                          WHERE m.account_id = v_feed.account_id AND m.carrier_id = v_feed.carrier_id AND m.standard_field = 'scan_at'),
           'place_ref', (SELECT jsonb_build_object('field', m.carrier_field) FROM public.cl_field_mappings m
                          WHERE m.account_id = v_feed.account_id AND m.carrier_id = v_feed.carrier_id AND m.standard_field = 'place_ref'),
           'mode_ref',  (SELECT jsonb_build_object('field', m.carrier_field) FROM public.cl_field_mappings m
                          WHERE m.account_id = v_feed.account_id AND m.carrier_id = v_feed.carrier_id AND m.standard_field = 'mode_ref'))
    INTO v_fields;

  SELECT jsonb_build_object('delivery_id', d.id, 'period_start', d.period_start, 'period_end', d.period_end,
                            'status', d.status)
    INTO v_last
    FROM public.cl_deliveries d
   WHERE d.feed_id = p_feed_id
   ORDER BY d.period_end DESC, d.created_at DESC LIMIT 1;

  RETURN jsonb_build_object(
    'schema_version', '4.0',
    'connector', jsonb_build_object('id', v_feed.id, 'name', v_feed.name, 'status', v_feed.status,
                                    'carrier', (SELECT c.code FROM public.carriers c WHERE c.id = v_feed.carrier_id)),
    'date_timezone', public.cl_account_date_tz(v_feed.account_id),
    'calendar', jsonb_build_object(
       'delivery_days', to_jsonb(v_feed.emit_days),
       'delivery_hour', v_feed.emit_hour,
       'timezone', public.cl_effective_tz(v_feed.account_id, v_feed.id),
       'deliveries_per_week', v_n,
       'frequency', CASE v_n WHEN 7 THEN 'daily' WHEN 1 THEN 'weekly' ELSE 'several_per_week' END),
    'fields', v_fields,
    'mapping_complete', jsonb_typeof(v_fields->'item_id') = 'object' AND jsonb_typeof(v_fields->'scan_at') = 'object'
                        AND jsonb_typeof(v_fields->'place_ref') = 'object',
    'extra_fields', COALESCE((SELECT jsonb_agg(x.carrier_field ORDER BY x.carrier_field)
                                FROM public.cl_extra_fields x
                               WHERE x.account_id = v_feed.account_id AND x.carrier_id = v_feed.carrier_id), '[]'::jsonb),
    'include_all_scans', COALESCE((SELECT bool_or(p.feed_diagnosis) FROM public.cl_plans p
                                    WHERE p.feed_id = p_feed_id AND p.carrier_id = v_feed.carrier_id
                                      AND p.status = 'active'), false),
    'plans', COALESCE((SELECT jsonb_agg(jsonb_build_object('product', pr.code, 'start_date', p.start_date,
                                                           'end_date', p.end_date, 'include_all_scans', p.feed_diagnosis)
                                        ORDER BY p.start_date, pr.code)
                         FROM public.cl_plans p JOIN public.products pr ON pr.id = p.product_id
                        WHERE p.feed_id = p_feed_id AND p.carrier_id = v_feed.carrier_id AND p.status = 'active'),
                      '[]'::jsonb),
    'products', COALESCE((SELECT jsonb_agg(jsonb_build_object('code', z.code, 'carrier_codes', z.cc) ORDER BY z.code)
                            FROM (SELECT pr.code,
                                         COALESCE((SELECT jsonb_agg(m.carrier_value ORDER BY m.carrier_value)
                                                     FROM public.cl_value_mappings m
                                                    WHERE m.account_id = v_feed.account_id AND m.carrier_id = v_feed.carrier_id
                                                      AND m.kind = 'product' AND m.onems_value = pr.code),
                                                  jsonb_build_array(pr.code)) AS cc
                                    FROM public.products pr
                                   WHERE pr.id IN (SELECT p.product_id FROM public.cl_plans p
                                                    WHERE p.feed_id = p_feed_id AND p.carrier_id = v_feed.carrier_id
                                                      AND p.status = 'active')) z), '[]'::jsonb),
    'points', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                  'place_ref', r.carrier_place_ref, 'mode_ref', r.carrier_mode_ref,
                                  'role', CASE r.e2e_role WHEN 'none' THEN 'intermediate' ELSE r.e2e_role END,
                                  'city_id', pc.city_id, 'city', ci.name)
                                ORDER BY r.carrier_place_ref, r.carrier_mode_ref NULLS FIRST)
                          FROM public.readers r
                          LEFT JOIN public.postal_centers pc ON pc.id = r.postal_center_id
                          LEFT JOIN public.cities ci ON ci.id = pc.city_id
                         WHERE r.account_id = v_feed.account_id AND r.capture_source = 'carrier_scan'
                           AND r.carrier_id = v_feed.carrier_id AND r.deleted_at IS NULL
                           AND r.is_active IS NOT FALSE), '[]'::jsonb),
    'next_period', public.cl_delivery_next_period(p_feed_id, p_now),
    'last_delivery', v_last,
    'formats', jsonb_build_object('format', jsonb_build_array('jsonl','csv'),
                                  'compression', jsonb_build_array('none')),
    'limits', public.cl_delivery_limits(v_feed.config));
END $$;

-- ================================================================ 3. estado de una entrega (GET /deliveries/{id})
-- Resumen (cl_delivery_summary) + alertas visibles para el transportista: solo las de calidad del fichero y de la
-- entrega. Las que revelan el sorteo o el juicio del regulador no salen (possible_misrouting lleva los item_id
-- sorteados; suspicious_distribution, quota_already_settled). Detalle solo donde es dato del propio transportista
-- (sus codigos de producto y de punto desconocidos, recuentos de rechazo, ultimo error).
CREATE OR REPLACE FUNCTION public.cl_delivery_status(p_feed_id uuid, p_delivery_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
BEGIN
  IF p_feed_id IS NULL OR p_delivery_id IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.cl_deliveries d WHERE d.id = p_delivery_id AND d.feed_id = p_feed_id) THEN
    RAISE EXCEPTION 'CL_DELIVERY_NOT_FOUND' USING ERRCODE = '22023';
  END IF;
  RETURN public.cl_delivery_summary(p_delivery_id) || jsonb_build_object(
    'alerts', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'type', a.alert_type, 'severity', a.severity, 'created_at', a.created_at,
               'details', CASE a.alert_type
                            WHEN 'unknown_product' THEN jsonb_build_object('values', a.details->'values')
                            WHEN 'unknown_reading_point' THEN jsonb_build_object('points', a.details->'points')
                            WHEN 'rejected_ratio' THEN jsonb_build_object('rejected', a.details->'rejected',
                                                     'shipments', a.details->'shipments', 'ratio', a.details->'ratio')
                            WHEN 'delivery_retries_exhausted' THEN jsonb_build_object(
                                                     'last_error', to_jsonb(public.cl_delivery_safe_error(a.details->>'last_error')),
                                                     'attempts', a.details->'attempts')
                            ELSE '{}'::jsonb END)
             ORDER BY a.created_at, a.alert_type)
        FROM public.cl_alerts a
       WHERE a.delivery_id = p_delivery_id AND a.status <> 'dismissed'
         AND a.alert_type IN ('unknown_product','unknown_reading_point','rejected_ratio','reader_without_city',
                              'insufficient_candidates','delivery_retries_exhausted')), '[]'::jsonb));
END $$;

REVOKE ALL ON FUNCTION public.cl_delivery_status(uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cl_delivery_status(uuid, uuid) TO service_role;

-- ================================================================ 4. retirada del motor de demandas v3
-- Seguro si el job o la funcion ya no existen (o si pg_cron no esta instalado).
DO $$
BEGIN
  IF to_regclass('cron.job') IS NOT NULL AND EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cl-emit-demands') THEN
    PERFORM cron.unschedule('cl-emit-demands');
  END IF;
END $$;
DROP FUNCTION IF EXISTS public.cl_emit_due_demands(timestamptz);

-- ================================================================ 5. mantenimiento sin demandas (cl_housekeeping)
-- Sustituye las tareas de cl_emit_due_demands que no eran emitir demandas (revision tarea 3, Important 1):
--   a) cuotas pending vencidas (period_end + close_lag_days <= hoy local) sin nada que pedir (planificado + arrastrado
--      - obtenido <= 0): se liquidan por el mismo camino que el paso finish de la tarea 2 (pending -> open ->
--      cl_settle_quota, que con falta <= 0 la deja fulfilled). Solo se toman cuotas 'pending': lo ya liquidado por una
--      entrega (o por una ejecucion anterior) no se vuelve a tocar.
--   b) alerta invalid_timezone (zona de la cuenta invalida y conector sin zona propia): una sola mientras no se descarte.
--   c) cierre de planes active -> closed tras end_date + close_lag_days sin cuotas pending/open.
-- Bloqueo como el proceso de entregas: conector FOR UPDATE (SKIP LOCKED), candado 'cl_sample:<cuenta>:<carrier>' y
-- cuotas por id. Los conectores con una entrega en vuelo se saltan (ronda 2 de la revision).
-- Un conector que falla deja la alerta housekeeping_failed (solo SQLSTATE) en sus planes y no para a los demas.
-- GANCHO tarea 8: la liquidacion de semanas vencidas CON falta (> 0) que ninguna entrega cubrio (3 dias tras el fin de
-- la semana) va en este mismo bucle, en el punto marcado "TAREA 8"; no crear otro job.
CREATE OR REPLACE FUNCTION public.cl_housekeeping(p_now timestamptz DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  r           record;
  v_feed      record;
  v_today     date;
  v_qid       uuid;
  v_settled   integer := 0;
  v_closed    integer := 0;
  v_n         integer;
  v_tz_alerts integer := 0;
  v_skipped   integer := 0;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('cl_housekeeping'));

  -- b) zona horaria invalida (una alerta mientras no se descarte). No toca cuotas ni planes.
  FOR r IN SELECT p.id, f.emit_timezone, a.timezone AS account_tz
             FROM public.cl_plans p
             JOIN public.accounts a ON a.id = p.account_id
             LEFT JOIN public.cl_feeds f ON f.id = p.feed_id
            WHERE p.status = 'active'
            ORDER BY p.created_at, p.id
  LOOP
    IF r.emit_timezone IS NULL AND r.account_tz IS NOT NULL AND NOT public.cl_is_valid_timezone(r.account_tz)
       AND NOT EXISTS (SELECT 1 FROM public.cl_alerts x WHERE x.plan_id = r.id AND x.alert_type = 'invalid_timezone'
                                                        AND x.status <> 'dismissed') THEN
      PERFORM public.cl_raise_alert(r.id, NULL, 'invalid_timezone', 'medium',
                                    jsonb_build_object('account_timezone', r.account_tz, 'used', 'UTC'));
      v_tz_alerts := v_tz_alerts + 1;
    END IF;
  END LOOP;

  -- a) y c), POR CONECTOR (ronda 2 de la revision). Orden de bloqueo del proceso de entregas: conector FOR UPDATE
  -- (SKIP LOCKED: si una entrega lo tiene, se reintenta en la siguiente hora), luego candado del sorteo y cuotas por id.
  -- Un conector con una entrega en vuelo (received, processing o failed, que siempre se reintenta: el fallo terminal
  -- la deja rejected) no se liquida ni cierra: su transfer ya pudo sumar samples_obtained y un abort lo restaria.
  -- Planes sin conector (feed_id NULL): no tienen entregas; se tratan sin bloqueo de conector.
  FOR v_feed IN SELECT DISTINCT p.feed_id, p.account_id, p.carrier_id
                  FROM public.cl_plans p WHERE p.status = 'active'
                 ORDER BY p.feed_id NULLS LAST, p.account_id, p.carrier_id
  LOOP
    BEGIN
      IF v_feed.feed_id IS NOT NULL THEN
        PERFORM 1 FROM public.cl_feeds f WHERE f.id = v_feed.feed_id FOR UPDATE SKIP LOCKED;
        IF NOT FOUND THEN v_skipped := v_skipped + 1; CONTINUE; END IF;
        -- Solo las entregas reales en vuelo frenan la liquidacion (las de prueba no tocan cuotas).
        IF EXISTS (SELECT 1 FROM public.cl_deliveries d
                    WHERE d.feed_id = v_feed.feed_id AND NOT d.is_test
                      AND d.status IN ('received','processing','failed')) THEN
          v_skipped := v_skipped + 1;
          CONTINUE;
        END IF;
      END IF;

      PERFORM pg_advisory_xact_lock(hashtext('cl_sample:' || v_feed.account_id::text || ':' || v_feed.carrier_id::text));

      FOR r IN SELECT p.id, p.account_id, p.feed_id, p.close_lag_days FROM public.cl_plans p
                WHERE p.status = 'active' AND p.feed_id IS NOT DISTINCT FROM v_feed.feed_id
                  AND p.account_id = v_feed.account_id AND p.carrier_id = v_feed.carrier_id
                ORDER BY p.id
      LOOP
        v_today := (p_now AT TIME ZONE public.cl_effective_tz(r.account_id, r.feed_id))::date;

        -- a) semanas vencidas sin nada que pedir.
        FOR v_qid IN SELECT q.id FROM public.cl_plan_quotas q
                      WHERE q.plan_id = r.id AND q.status = 'pending'
                        AND q.period_end + r.close_lag_days <= v_today
                        AND q.samples_planned + q.samples_carried_in - q.samples_obtained <= 0
                      ORDER BY q.id
                        FOR UPDATE
        LOOP
          UPDATE public.cl_plan_quotas q SET status = 'open' WHERE q.id = v_qid AND q.status = 'pending';
          PERFORM public.cl_settle_quota(v_qid);
          v_settled := v_settled + 1;
        END LOOP;

        -- TAREA 8: aqui, semanas vencidas con falta > 0 sin entrega que las cubra (3 dias tras el fin de la semana).

        -- c) cierre del plan.
        UPDATE public.cl_plans p SET status = 'closed'
         WHERE p.id = r.id AND p.status = 'active'
           AND p.end_date + p.close_lag_days < v_today
           AND NOT EXISTS (SELECT 1 FROM public.cl_plan_quotas q WHERE q.plan_id = p.id AND q.status IN ('pending','open'));
        GET DIAGNOSTICS v_n = ROW_COUNT;
        v_closed := v_closed + v_n;
      END LOOP;
    EXCEPTION WHEN OTHERS THEN
      PERFORM public.cl_raise_alert(p.id, NULL, 'housekeeping_failed', 'high', jsonb_build_object('sqlstate', SQLSTATE))
         FROM public.cl_plans p
        WHERE p.status = 'active' AND p.feed_id IS NOT DISTINCT FROM v_feed.feed_id
          AND p.account_id = v_feed.account_id AND p.carrier_id = v_feed.carrier_id;
    END;
  END LOOP;

  RETURN jsonb_build_object('quotas_settled', v_settled, 'plans_closed', v_closed, 'timezone_alerts', v_tz_alerts,
                            'feeds_skipped', v_skipped);
END $$;
REVOKE ALL ON FUNCTION public.cl_housekeeping(timestamptz) FROM PUBLIC, anon, authenticated, service_role;

-- pg_cron (como postgres), cada hora; idempotente.
DO $$
BEGIN
  IF to_regclass('cron.job') IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cl-housekeeping') THEN
      PERFORM cron.unschedule('cl-housekeeping');
    END IF;
    PERFORM cron.schedule('cl-housekeeping', '20 * * * *', 'SELECT public.cl_housekeeping();');
  END IF;
END $$;

-- ================================================================ 6. el campo error solo lleva codigos CL_
-- Revision tarea 3: delivery.error (y last_error de las alertas, que sale de progress.final_error) llega al
-- transportista. Solo puede ser un codigo CL_ con, como mucho, un SQLSTATE (p. ej. 'CL_PROCESSING_ERROR 22P02').
-- Nunca SQLERRM ni valores de filas. Hoy ningun camino guarda texto libre; esto lo garantiza:
--   - cl_delivery_mark_abort (punto unico de final_error) sustituye cualquier otra cosa por CL_PROCESSING_ERROR;
--   - CHECK en cl_deliveries.error;
--   - cl_delivery_status filtra last_error con la misma funcion.
CREATE OR REPLACE FUNCTION public.cl_delivery_safe_error(p_error text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path = public, extensions
AS $$
  SELECT CASE WHEN p_error IS NULL THEN NULL
              WHEN p_error ~ '^CL_[A-Z0-9_]{1,60}( [0-9A-Z]{5})?$' THEN p_error
              ELSE 'CL_PROCESSING_ERROR' END
$$;
REVOKE ALL ON FUNCTION public.cl_delivery_safe_error(text) FROM PUBLIC, anon, authenticated, service_role;

ALTER TABLE public.cl_deliveries
  ADD CONSTRAINT cl_deliveries_error_code_only CHECK (error IS NULL OR error ~ '^CL_[A-Z0-9_]{1,60}( [0-9A-Z]{5})?$');

-- Copia de 20261124200100 con un unico cambio: final_error = cl_delivery_safe_error(p_error).
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
                                                     'final_error', public.cl_delivery_safe_error(p_error),
                                                     'lease_token', NULL, 'lease_until', NULL)
   WHERE d.id = p_delivery_id AND d.status = 'processing';
END $$;
REVOKE ALL ON FUNCTION public.cl_delivery_mark_abort(uuid, text, text) FROM PUBLIC, anon, authenticated, service_role;

-- ================================================================ 7. deshacer una entrega: aviso si deja corta una cuota ya liquidada
-- Copia de 20261124200100 con un unico cambio (revision tarea 3, ronda 2, defensivo): tras restar las muestras
-- anuladas, una cuota ya liquidada (ni pending ni open) que queda por debajo de su objetivo NO se reabre (reabrirla
-- volveria a repartir un deficit que cl_settle_quota ya arrastro o dio por unfilled): se levanta la alerta
-- quota_short_after_undo (high) con lo que falta, para que el regulador decida. Con cl_housekeeping bloqueando el
-- conector y saltando las entregas en vuelo, este caso no deberia darse; queda como red.
CREATE OR REPLACE FUNCTION public.cl_delivery_undo_samples(p_d public.cl_deliveries)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_carrier uuid := (SELECT f.carrier_id FROM public.cl_feeds f WHERE f.id = p_d.feed_id);
  v_n integer;
  v_q uuid[];
  v_r record;
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
  )
  SELECT COALESCE(array_agg(v.quota_id) FILTER (WHERE v.quota_id IS NOT NULL), '{}'::uuid[]), count(*)::integer
    INTO v_q, v_n FROM v;

  UPDATE public.cl_plan_quotas q SET samples_obtained = GREATEST(q.samples_obtained - c.n, 0)
    FROM (SELECT x AS quota_id, count(*)::integer AS n FROM unnest(v_q) x GROUP BY x) c
   WHERE q.id = c.quota_id;

  FOR v_r IN SELECT q.id, q.plan_id, q.status, q.samples_planned + q.samples_carried_in - q.samples_obtained AS falta
               FROM public.cl_plan_quotas q
              WHERE q.id = ANY (v_q) AND q.status NOT IN ('pending','open')
                AND q.samples_planned + q.samples_carried_in - q.samples_obtained > 0
              ORDER BY q.id
  LOOP
    PERFORM public.cl_raise_alert(v_r.plan_id, v_r.id, 'quota_short_after_undo', 'high',
      jsonb_build_object('delivery_id', p_d.id, 'quota_status', v_r.status, 'missing', v_r.falta));
  END LOOP;
  RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.cl_delivery_undo_samples(public.cl_deliveries) FROM PUBLIC, anon, authenticated, service_role;
