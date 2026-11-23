-- Carrier Link v4, tarea 3: contrato de la Edge Function carrier-link-ingest (GET /config, POST /deliveries,
-- POST /deliveries/{id}/complete, GET /deliveries/{id}). Sobre 20261124100000_cl_deliveries.sql (tarea 1) y
-- 20261124100100_cl_process_delivery.sql (tarea 2).
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
-- Copia de 20261124100000 con un unico cambio: formats.compression = ["none"].
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
                                                     'last_error', a.details->'last_error', 'attempts', a.details->'attempts')
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
