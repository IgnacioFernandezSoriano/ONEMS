-- Carrier Link fase 1, tarea 9: cuota no cubierta (reparto del deficit) y deshacer un lote.
-- Spec: docs/superpowers/specs/2026-11-19-carrier-link-design.md R17, §5 ("Cuota no cubierta").
--
-- cl_settle_quota(cuota): liquida una cuota 'open' tras el cierre de su lote: fulfilled, vuelta a pending (otra
--   peticion en la misma semana, hasta 3), reparto del deficit (carried) o unfilled con alerta.
-- cl_finish_batch(lote): el de la tarea 8, igual, y al final liquida las cuotas de la demanda no cumplidas.
-- cl_undo_batch(lote): deshace un lote (borra sus filas one_db, anula sus muestras, devuelve las cuotas a pending).
-- No toca allocation_*, transfer_to_one_db ni el ETL RFID.

-- ---------------------------------------------------------------- liquidacion de una cuota
-- Interna (sin EXECUTE para nadie): solo la llaman cl_finish_batch (service_role) y funciones definer. El cron de
-- emision no la necesita: una cuota que vuelve a pending la recoge cl_emit_due_demands en el siguiente hueco del
-- calendario del conector.
-- falta = samples_planned + samples_carried_in - samples_obtained.
--   * falta <= 0 -> fulfilled.
--   * poblacion informada en el ultimo sorteo del estrato > item_id distintos ya recibidos para la cuota (en todos sus
--     lotes, cualquier estado de lectura) y demands_count < 3 -> pending (la siguiente demanda pide solo la falta).
--   * si no: reparto a partes iguales (el resto, a las mas tempranas) entre las cuotas pending de la misma ruta y plan
--     posteriores a esta, primero las del mismo mes natural de period_start; si no hay, las del primer mes posterior
--     que tenga alguna. La cuota queda carried. Sin ninguna -> unfilled + alerta quota_unfilled.
-- Solo actua sobre cuotas 'open'; en cualquier otro estado devuelve el estado actual sin cambiar nada (idempotente).
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

  -- Ultima poblacion informada y candidatos distintos recibidos (lotes de las demandas del plan).
  SELECT r.population_size INTO v_pop
    FROM public.cl_sampling_runs r
   WHERE r.stratum_id = p_quota_id
   ORDER BY r.executed_at DESC, r.created_at DESC, r.id DESC
   LIMIT 1;
  SELECT count(DISTINCT s.item_id) INTO v_recv
    FROM public.cl_batch_scans s
   WHERE s.batch_id IN (SELECT b.id FROM public.cl_batches b JOIN public.cl_demands d ON d.id = b.demand_id
                         WHERE d.plan_id = v_q.plan_id)
     AND s.stratum_id = p_quota_id
     AND s.item_id IS NOT NULL;

  IF COALESCE(v_pop, 0) > v_recv AND v_q.demands_count < 3 THEN
    UPDATE public.cl_plan_quotas SET status = 'pending' WHERE id = p_quota_id;
    RETURN 'pending';
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

-- ---------------------------------------------------------------- deshacer un lote
-- Permiso: superadmin, backend sin usuario (service_role/cron: auth.uid() NULL, como cl_plan_authorize) o usuario de la
-- cuenta del lote con Edit en cl_monitor. Lote inexistente y lote de otra cuenta dan el mismo 42501 (sin oraculo).
-- Mismo candado por cuenta+carrier que cl_sample_stratum: deshacer y sortear no se intercalan.
-- Orden: one_db.cl_sample_id es ON DELETE RESTRICT, asi que primero se borran las filas one_db de sus muestras;
-- despues las muestras pasan a voided (se conservan sus cl_sample_scans), se resta de samples_obtained, se borran sus
-- cl_sampling_runs, lote undone y demanda failed.
-- Cuotas afectadas (las de sus muestras, sus sorteos y la demanda):
--   * carried: se dejan como estan (su deficit ya se repartio) y se abre una alerta undo_after_carry por cuota;
--   * open en OTRA demanda abierta: se quedan open (las liquida el cierre de esa demanda);
--   * el resto (fulfilled, unfilled, open de esta demanda, pending): pending; se vuelven a pedir en el siguiente hueco
--     del calendario del conector.
-- Tras deshacer, los mismos item_id pueden volver a ser muestra (el indice unico solo cubre muestras activas).
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
  IF v_batch.status NOT IN ('validated', 'sampled') THEN
    RAISE EXCEPTION 'CL_BATCH_NOT_UNDOABLE: batch is %', v_batch.status USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_demand FROM public.cl_demands WHERE id = v_batch.demand_id FOR UPDATE;

  SELECT array_agg(DISTINCT x.qid) INTO v_quotas
    FROM (SELECT s.quota_id FROM public.cl_samples s WHERE s.batch_id = p_batch_id AND s.status = 'active'
          UNION SELECT r2.stratum_id FROM public.cl_sampling_runs r2 WHERE r2.batch_id = p_batch_id
          UNION SELECT (d->>'stratum_id')::uuid FROM jsonb_array_elements(v_demand.payload->'strata') d) x(qid)
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

-- ---------------------------------------------------------------- cierre del lote (reemplaza el de la tarea 8)
-- Mismo cuerpo que 20261120110600_cl_sampler.sql; al final liquida (cl_settle_quota) las cuotas de la demanda que no
-- quedaron fulfilled.
CREATE OR REPLACE FUNCTION public.cl_finish_batch(p_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_batch   public.cl_batches;
  v_demand  public.cl_demands;
  v_pending jsonb;
  v_status  text;
  v_qid     uuid;
BEGIN
  SELECT * INTO v_batch FROM public.cl_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CL_BATCH_NOT_FOUND: batch not found' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_demand FROM public.cl_demands WHERE id = v_batch.demand_id FOR UPDATE;

  IF v_batch.status = 'sampled' THEN
    RETURN jsonb_build_object('batch_id', p_batch_id, 'status', 'sampled', 'demand_status', v_demand.status,
                              'strata_pending', '[]'::jsonb);
  END IF;
  IF v_batch.status <> 'validated' THEN
    RAISE EXCEPTION 'CL_BATCH_NOT_VALIDATED: batch is %', v_batch.status USING ERRCODE = '22023';
  END IF;

  SELECT COALESCE(jsonb_agg(e->'stratum_id' ORDER BY o), '[]'::jsonb) INTO v_pending
    FROM jsonb_array_elements(v_batch.summary->'strata') WITH ORDINALITY x(e, o)
   WHERE NOT EXISTS (SELECT 1 FROM public.cl_sampling_runs r
                      WHERE r.batch_id = p_batch_id AND r.stratum_id::text = e->>'stratum_id');
  IF jsonb_array_length(v_pending) > 0 THEN
    RETURN jsonb_build_object('batch_id', p_batch_id, 'status', 'pending', 'demand_status', v_demand.status,
                              'strata_pending', v_pending);
  END IF;

  UPDATE public.cl_batches SET status = 'sampled' WHERE id = p_batch_id;

  v_status := CASE WHEN NOT EXISTS (
                  SELECT 1 FROM jsonb_array_elements(v_demand.payload->'strata') d
                   WHERE NOT EXISTS (SELECT 1 FROM public.cl_sampling_runs r
                                      WHERE r.batch_id = p_batch_id AND r.stratum_id::text = d->>'stratum_id'
                                        AND r.samples_selected >= COALESCE((d->>'samples_required')::integer, 0)))
                THEN 'fulfilled' ELSE 'partial' END;
  IF v_demand.status = 'open' THEN
    UPDATE public.cl_demands SET status = v_status WHERE id = v_demand.id;
  ELSE
    v_status := v_demand.status;
  END IF;

  UPDATE public.cl_plan_quotas q SET status = 'fulfilled'
   WHERE q.id IN (SELECT r.stratum_id FROM public.cl_sampling_runs r WHERE r.batch_id = p_batch_id)
     AND q.status = 'open'
     AND q.samples_obtained >= q.samples_planned + q.samples_carried_in;

  -- Tarea 9 (R17): se liquidan las cuotas de la demanda que no quedaron cumplidas (vuelven a pedirse, reparten su
  -- deficit o quedan unfilled). Orden: de la mas temprana a la mas tardia.
  FOR v_qid IN SELECT q.id
                 FROM jsonb_array_elements(v_demand.payload->'strata') d
                 JOIN public.cl_plan_quotas q ON q.id = (d->>'stratum_id')::uuid
                WHERE q.status <> 'fulfilled'
                ORDER BY q.period_start, q.id
  LOOP
    PERFORM public.cl_settle_quota(v_qid);
  END LOOP;

  RETURN jsonb_build_object('batch_id', p_batch_id, 'status', 'sampled', 'demand_status', v_status,
                            'strata_pending', '[]'::jsonb);
END $$;
REVOKE ALL ON FUNCTION public.cl_finish_batch(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cl_finish_batch(uuid) TO service_role;
