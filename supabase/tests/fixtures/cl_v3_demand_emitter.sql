-- Fixture de tests: el emisor de demandas v3 (cl_emit_due_demands), retirado en 20261124100200_cl_delivery_api.sql.
-- Los tests v3 (demandas, sorteo, liquidacion, deshacer) lo usan para montar sus escenarios. Copia literal de la
-- definicion de 20261120110800_cl_final_fixes.sql. Se crea al principio del test y se borra al final:
--   \ir fixtures/cl_v3_demand_emitter.sql      ...      DROP FUNCTION public.cl_emit_due_demands(timestamptz);
-- Solo tests locales: nunca aplicar a una base real.
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
