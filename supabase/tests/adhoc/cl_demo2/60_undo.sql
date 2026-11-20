-- Carrier Link DEMO2 synthetic test, phase "undo-test" step 1 (WRITES; one transaction).
-- Undoes the latest 'sampled' batch of plan "Carrier Link DEMO" with cl_undo_batch and asserts, inside the same
-- transaction (any failed assertion rolls the undo back):
--   * its one_db rows (source = 'carrier') are gone and its samples are 'voided';
--   * the quotas it fed have samples_obtained recalculated (0) and are back to 'pending';
--   * the batch is 'undone' and its demand 'failed';
--   * DEMO2 panelist one_db rows are untouched.
-- The demo data is then restored by run.sh: 30_emit.sql asks the pending quotas again (new demand, new seed) and a new
-- batch is ingested through the Edge Function. (cl_undo_batch does not reset demands_count: the undone demand counts
-- as one of the 3 requests of each week only if it was emitted with the connector active.)
DO $$
DECLARE
  c_plan constant uuid := 'c1de2000-0000-4000-8000-0000000000a1';
  c_acc  constant uuid := 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
  v_batch  uuid;
  v_demand uuid;
  v_res    jsonb;
  v_pan    bigint;
  v_onedb  bigint;
  v_n      bigint;
BEGIN
  SELECT b.id, b.demand_id INTO v_batch, v_demand
    FROM public.cl_batches b JOIN public.cl_demands d ON d.id = b.demand_id
   WHERE d.plan_id = c_plan AND b.status = 'sampled'
   ORDER BY b.received_at DESC, b.id DESC LIMIT 1;
  IF v_batch IS NULL THEN RAISE EXCEPTION 'UNDO: no sampled batch for the DEMO plan'; END IF;

  SELECT count(*) INTO v_pan FROM public.one_db WHERE account_id = c_acc AND source = 'panelist';
  SELECT count(*) INTO v_onedb FROM public.one_db o JOIN public.cl_samples s ON s.id = o.cl_sample_id
   WHERE s.batch_id = v_batch AND s.status = 'active';
  IF v_onedb = 0 THEN RAISE EXCEPTION 'UNDO: the batch has no one_db rows to remove'; END IF;

  v_res := public.cl_undo_batch(v_batch);
  RAISE NOTICE 'cl_undo_batch: %', v_res;

  IF (v_res->>'one_db_deleted')::bigint <> v_onedb THEN
    RAISE EXCEPTION 'UNDO: one_db_deleted % <> %', v_res->>'one_db_deleted', v_onedb;
  END IF;
  SELECT count(*) INTO v_n FROM public.one_db o JOIN public.cl_samples s ON s.id = o.cl_sample_id WHERE s.batch_id = v_batch;
  IF v_n <> 0 THEN RAISE EXCEPTION 'UNDO: % one_db rows of the batch remain', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.cl_samples WHERE batch_id = v_batch AND status <> 'voided';
  IF v_n <> 0 THEN RAISE EXCEPTION 'UNDO: % samples not voided', v_n; END IF;
  IF (SELECT status FROM public.cl_batches WHERE id = v_batch) <> 'undone'
     OR (SELECT status FROM public.cl_demands WHERE id = v_demand) <> 'failed' THEN
    RAISE EXCEPTION 'UNDO: batch/demand status not undone/failed';
  END IF;
  SELECT count(*) INTO v_n FROM public.cl_plan_quotas
   WHERE plan_id = c_plan AND (samples_obtained <> 0 OR status <> 'pending');
  IF v_n <> 0 THEN RAISE EXCEPTION 'UNDO: % quotas not back to pending with samples_obtained 0', v_n; END IF;
  IF (SELECT count(*) FROM public.one_db WHERE account_id = c_acc AND source = 'panelist') <> v_pan THEN
    RAISE EXCEPTION 'UNDO: panelist one_db rows changed';
  END IF;
END $$;

SELECT jsonb_build_object(
  'batches', (SELECT jsonb_agg(jsonb_build_object('connector_batch_id', b.connector_batch_id, 'status', b.status) ORDER BY b.received_at)
                FROM public.cl_batches b JOIN public.cl_demands d ON d.id = b.demand_id
               WHERE d.plan_id = 'c1de2000-0000-4000-8000-0000000000a1'),
  'samples_active', (SELECT count(*) FROM public.cl_samples WHERE plan_id = 'c1de2000-0000-4000-8000-0000000000a1' AND status = 'active'),
  'samples_voided', (SELECT count(*) FROM public.cl_samples WHERE plan_id = 'c1de2000-0000-4000-8000-0000000000a1' AND status = 'voided'),
  'one_db_carrier', (SELECT count(*) FROM public.one_db WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e' AND source = 'carrier'),
  'quotas', (SELECT jsonb_agg(jsonb_build_object('week', q.iso_week, 'obtained', q.samples_obtained, 'status', q.status,
                                                 'demands_count', q.demands_count) ORDER BY q.iso_week, q.id)
               FROM public.cl_plan_quotas q WHERE q.plan_id = 'c1de2000-0000-4000-8000-0000000000a1')
) AS undo_result;
