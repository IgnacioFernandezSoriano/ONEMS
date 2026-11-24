-- 20261124210000 Carrier Link v4: el "rechazo alto" (alerta rejected_ratio -> incidencia high_rejection) mide solo
-- la calidad de los datos del carrier.
-- Prueba en DEV 24/11: en semanas sin cuota todos los envios salen no_stratum y el % llegaba al 100 %, abriendo
-- high_rejection y avisando al carrier por algo que no es culpa suya (entrega TODOS los envios del periodo).
-- Ahora el denominador excluye no_stratum, already_sampled y reader_without_city; el resto de motivos (registro sin
-- inicio/fin, producto desconocido o que no es del plan, fuera de periodo, llegada antes de la salida...) cuentan.
-- Solo redefine cl_delivery_phase_finish (misma firma); nada mas cambia.
SET LOCAL lock_timeout = '5s';

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
  v_ign   bigint;   -- 20261124210000: envios que no cuentan para el % de rechazo
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
         count(*) FILTER (WHERE i.reason = 'already_sampled'),
         count(*) FILTER (WHERE i.reason IN ('already_sampled', 'no_stratum', 'reader_without_city'))
    INTO v_tot, v_valid, v_drawn, v_used, v_ign
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
    -- 20261124210000: el % de rechazo mide solo la calidad de los datos del carrier. No cuentan los envios que el plan
    -- no necesita (no_stratum: el carrier entrega TODOS los envios del periodo), los ya muestreados (already_sampled)
    -- ni los de un lector sin ciudad (reader_without_city: falta de configuracion en ONEMS, con su propia alerta).
    IF v_tot - v_ign > 0 AND (v_tot - v_ign - v_valid)::numeric / (v_tot - v_ign) > 0.2 THEN
      PERFORM public.cl_delivery_alert(p_d.id, NULL, NULL, 'rejected_ratio', 'medium',
        jsonb_build_object('rejected', v_tot - v_ign - v_valid, 'shipments', v_tot - v_ign,
                           'ratio', round((v_tot - v_ign - v_valid)::numeric / (v_tot - v_ign), 3), 'reasons', v_ship));
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

REVOKE ALL ON FUNCTION public.cl_delivery_phase_finish(public.cl_deliveries, public.cl_feeds) FROM PUBLIC, anon, authenticated, service_role;
