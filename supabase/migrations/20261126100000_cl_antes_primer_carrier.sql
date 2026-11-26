-- 20261126100000 Carrier Link: pendientes antes del primer carrier real (revision final del 24/11).
--   1. cl_delivery_sweep_done (T2-m3): solo marca file_deleted_at si el objeto ya no esta en storage.objects. Antes
--      marcaba todo lo que el worker habia pedido borrar aunque Storage no lo borrase: ese fichero (puede llevar datos
--      personales) se quedaba para siempre. Ahora lo no borrado vuelve a la lista y se reintenta en el minuto siguiente.
--   2. Fallida reintentable cuyo fichero se borro por retencion: pasa a rejected CL_FILE_MISSING (como el fallo
--      terminal: se deshacen sus muestras). Antes seguia 'failed' sin poder reintentarse (no hay fichero) y bloqueaba
--      para siempre las entregas posteriores de su conector. El rechazo abre la incidencia delivery_rejected (el carrier
--      reenvia el periodo).
--   3. cl_delivery_worker_claim: al retomar el arriendo caducado de otro worker (cuenta como intento) se renueva
--      progress.claimed_at, desde donde se miden las 2 h de la alerta delivery_stuck.
--   4. cl_housekeeping, paso g: la alerta delivery_stuck de cada entrega va en su propio bloque EXCEPTION; un fallo ya
--      no para la limpieza horaria entera. Se sigue avisando tambien de las entregas de prueba: hay un solo hueco de
--      proceso en toda la base y una prueba atascada frena a las reales.
--   5. cron_history_purge + tarea diaria 'cron-history-purge' (03:40 UTC): borra de cron.job_run_details las
--      ejecuciones de mas de 14 dias (tres tareas cada minuto suman unas 4.400 filas al dia; Supabase no las purga).
-- Mismas firmas: CREATE OR REPLACE conserva los permisos. Sin cambios en las Edge Functions.
SET LOCAL lock_timeout = '5s';

-- ------------------------------------------------------------------------------------------------ 1 y 2. retencion
CREATE OR REPLACE FUNCTION public.cl_delivery_sweep_done(p_paths text[])
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  r        record;
  v_d      public.cl_deliveries;
  v_voided integer;
  v_n      integer := 0;
BEGIN
  FOR r IN SELECT d.id, d.feed_id, d.status FROM public.cl_deliveries d
            WHERE d.file_path = ANY (p_paths) AND d.file_deleted_at IS NULL
              AND d.status IN ('rejected','processed','failed')
              AND NOT EXISTS (SELECT 1 FROM storage.objects o
                               WHERE o.bucket_id = 'cl-deliveries' AND o.name = d.file_path)
            ORDER BY d.feed_id, d.id
  LOOP
    IF r.status = 'failed' THEN
      -- Conector primero, despues la entrega (mismo orden que el resto del proceso); se vuelve a mirar bloqueada.
      PERFORM 1 FROM public.cl_feeds f WHERE f.id = r.feed_id FOR UPDATE;
      SELECT d.* INTO v_d FROM public.cl_deliveries d WHERE d.id = r.id FOR UPDATE;
      CONTINUE WHEN v_d.status <> 'failed' OR v_d.file_deleted_at IS NOT NULL;
      v_voided := public.cl_delivery_undo_samples(v_d);
      UPDATE public.cl_deliveries d
         SET status = 'rejected', error = 'CL_FILE_MISSING', finished_at = now(), file_deleted_at = now(),
             progress = (d.progress - 'lease_token' - 'lease_until')
                        || jsonb_build_object('phase', 'rejected', 'finished_at', now(), 'file_expired', true,
                                              'samples_voided', v_voided)
       WHERE d.id = v_d.id;
    ELSE
      -- Rechazada o procesada: estado final, solo se anota el borrado.
      UPDATE public.cl_deliveries d SET file_deleted_at = now()
       WHERE d.id = r.id AND d.file_deleted_at IS NULL AND d.status IN ('rejected','processed');
      CONTINUE WHEN NOT FOUND;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  RETURN v_n;
END $$;

-- ------------------------------------------------------------------------------------------------ 3. tomar trabajo
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
         SET progress = d.progress || jsonb_build_object('attempts', COALESCE((d.progress->>'attempts')::integer, 0) + 1,
                                                         'claimed_at', p_now)   -- 20261126100000: intento nuevo
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

-- ------------------------------------------------------------------------------------------------ 4. limpieza horaria
CREATE OR REPLACE FUNCTION public.cl_housekeeping(p_now timestamptz DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  r           record;
  v_feed      record;
  v_f         public.cl_feeds;
  v_today     date;
  v_qid       uuid;
  v_settled   integer := 0;
  v_closed    integer := 0;
  v_n         integer;
  v_tz_alerts integer := 0;
  v_skipped   integer := 0;
  v_missing   integer := 0;
  v_late      integer := 0;
  v_unknown   integer := 0;
  v_stuck     integer := 0;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('cl_housekeeping'));

  -- g) entrega atascada en processing (sin bloquear la entrega: solo lee y anade una alerta).
  FOR r IN SELECT d.id, d.progress->>'phase' AS phase, COALESCE((d.progress->>'attempts')::integer, 0) AS attempts,
                  COALESCE((d.progress->>'claimed_at')::timestamptz, d.processing_started_at) AS since
             FROM public.cl_deliveries d
            WHERE d.status = 'processing'
              AND COALESCE((d.progress->>'claimed_at')::timestamptz, d.processing_started_at) < p_now - interval '2 hours'
              AND NOT EXISTS (SELECT 1 FROM public.cl_alerts a WHERE a.delivery_id = d.id AND a.alert_type = 'delivery_stuck')
  LOOP
    -- 20261126100000: aislado por entrega; un fallo al crear esta alerta no para el resto de la limpieza horaria.
    BEGIN
      PERFORM public.cl_delivery_alert(r.id, NULL, NULL, 'delivery_stuck', 'high',
                                       jsonb_build_object('phase', r.phase, 'attempts', r.attempts, 'processing_since', r.since));
      v_stuck := v_stuck + 1;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'cl_housekeeping: delivery_stuck alert failed (%)', SQLSTATE;
    END;
  END LOOP;

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

  -- d) unknown_data ya dados de alta.
  FOR r IN SELECT i.id FROM public.cl_incidents i
            WHERE i.incident_type = 'unknown_data' AND i.status <> 'resolved' ORDER BY i.id
  LOOP
    IF public.cl_incident_unknown_registered(r.id) AND public.cl_incident_close_core(r.id, 'auto', NULL, NULL, p_now) THEN
      v_unknown := v_unknown + 1;
    END IF;
  END LOOP;

  -- a), c), e) y f), POR CONECTOR (ronda 2 de la revision). Orden de bloqueo del proceso de entregas: conector FOR
  -- UPDATE (SKIP LOCKED: si una entrega lo tiene, se reintenta en la siguiente hora), luego candado del sorteo y cuotas
  -- por id. Un conector con una entrega en vuelo (received, processing o failed, que siempre se reintenta: el fallo
  -- terminal la deja rejected) no se liquida ni cierra ni se vigila: su transfer ya pudo sumar samples_obtained y un
  -- abort lo restaria (y la entrega recibida ya cerro su missing_delivery).
  -- Planes sin conector (feed_id NULL): no tienen entregas; se tratan sin bloqueo de conector (sin e ni f).
  FOR v_feed IN SELECT DISTINCT p.feed_id, p.account_id, p.carrier_id
                  FROM public.cl_plans p WHERE p.status = 'active'
                 ORDER BY p.feed_id NULLS LAST, p.account_id, p.carrier_id
  LOOP
    BEGIN
      v_f := NULL;
      IF v_feed.feed_id IS NOT NULL THEN
        SELECT f.* INTO v_f FROM public.cl_feeds f WHERE f.id = v_feed.feed_id FOR UPDATE SKIP LOCKED;
        IF NOT FOUND THEN v_skipped := v_skipped + 1; CONTINUE; END IF;
        -- Solo las entregas reales en vuelo frenan la liquidacion (las de prueba no tocan cuotas).
        IF EXISTS (SELECT 1 FROM public.cl_deliveries d
                    WHERE d.feed_id = v_feed.feed_id AND NOT d.is_test
                      AND d.status IN ('received','processing','failed')) THEN
          v_skipped := v_skipped + 1;
          CONTINUE;
        END IF;
        -- e) entregas no recibidas.
        v_missing := v_missing + public.cl_incident_check_missing(v_f, p_now);
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

        -- TAREA 8 / f) D27: semanas vencidas con falta > 0 que ninguna entrega cubrio (3 dias tras el fin de la semana
        -- y la entrega que debia cubrir su ultimo dia ya vencida). Se liquidan con lo que haya.
        IF v_f.id IS NOT NULL AND v_f.status <> 'testing' THEN
          FOR v_qid IN SELECT q.id FROM public.cl_plan_quotas q
                        WHERE q.plan_id = r.id AND q.status = 'pending'
                          AND q.period_end + 3 <= v_today
                          AND q.samples_planned + q.samples_carried_in - q.samples_obtained > 0
                          AND public.cl_incident_period_deadline(
                                v_f, (SELECT a.period_end FROM public.cl_delivery_aligned_period(v_f.emit_days, q.period_end) a))
                              <= p_now
                        ORDER BY q.id
                          FOR UPDATE
          LOOP
            UPDATE public.cl_plan_quotas q SET status = 'open' WHERE q.id = v_qid AND q.status = 'pending';
            PERFORM public.cl_settle_quota(v_qid, true);
            v_late := v_late + 1;
          END LOOP;
        END IF;

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
                            'feeds_skipped', v_skipped, 'missing_periods', v_missing, 'late_weeks_settled', v_late,
                            'unknown_closed', v_unknown, 'stuck_alerts', v_stuck);
END $$;

-- ------------------------------------------------------------------------------------------------ 5. historial pg_cron
-- Sin pg_cron (Postgres local de pruebas) no hay tabla: devuelve 0.
CREATE OR REPLACE FUNCTION public.cron_history_purge()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_n integer := 0;
BEGIN
  IF to_regclass('cron.job_run_details') IS NULL THEN RETURN 0; END IF;
  EXECUTE $q$DELETE FROM cron.job_run_details
              WHERE COALESCE(end_time, start_time) < now() - interval '14 days'$q$;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.cron_history_purge() FROM PUBLIC, anon, authenticated, service_role;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cron-history-purge') THEN
    PERFORM cron.unschedule('cron-history-purge');
  END IF;
  PERFORM cron.schedule('cron-history-purge', '40 3 * * *', 'SELECT public.cron_history_purge();');
END $$;
