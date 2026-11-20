-- Carrier Link DEMO2 synthetic test, phase "cleanup" (WRITES; one transaction). NOT part of the demo run: it removes
-- the demo data from the E2E reports. Run only when the owner asks for DEMO2 to be left clean.
-- Removes everything the test created (fixed ids c1de2000-..., plan "Carrier Link DEMO"), in FK-safe order:
--   one_db carrier rows of the plan (one_db.cl_sample_id is ON DELETE RESTRICT) -> alerts -> sampling runs ->
--   samples (+ sample scans, cascade) -> batches (+ batch scans, cascade) -> demands -> plan (+ quotas, cascade) ->
--   API key of the connector (+ api_usage_log, cascade) -> mappings / extra field -> connector -> reading points;
-- and puts back cl_last_mile_time = 0 on the two standards the setup changed (only if still 1).
-- Never touches panelist rows (asserted).
DO $$
DECLARE
  c_acc  constant uuid := 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
  c_car  constant uuid := '856b4a5c-1716-4110-ac5e-0d7c909b9237';
  c_plan constant uuid := 'c1de2000-0000-4000-8000-0000000000a1';
  c_feed constant uuid := 'c1de2000-0000-4000-8000-0000000000f1';
  v_pan  bigint;
  v_cnt  jsonb := '{}'::jsonb;
  v_n    bigint;
BEGIN
  IF (SELECT slug FROM public.accounts WHERE id = c_acc) IS DISTINCT FROM 'DEMO2' THEN
    RAISE EXCEPTION 'GUARD: account % is not DEMO2', c_acc;
  END IF;
  IF EXISTS (SELECT 1 FROM public.cl_plans WHERE id = c_plan AND account_id <> c_acc)
     OR EXISTS (SELECT 1 FROM public.cl_feeds WHERE id = c_feed AND account_id <> c_acc) THEN
    RAISE EXCEPTION 'GUARD: test ids belong to another account';
  END IF;
  SELECT count(*) INTO v_pan FROM public.one_db WHERE source = 'panelist';

  DELETE FROM public.one_db o USING public.cl_samples s
   WHERE o.cl_sample_id = s.id AND s.plan_id = c_plan AND o.account_id = c_acc;
  GET DIAGNOSTICS v_n = ROW_COUNT; v_cnt := v_cnt || jsonb_build_object('one_db', v_n);

  DELETE FROM public.cl_alerts WHERE plan_id = c_plan AND account_id = c_acc;
  GET DIAGNOSTICS v_n = ROW_COUNT; v_cnt := v_cnt || jsonb_build_object('cl_alerts', v_n);

  DELETE FROM public.cl_sampling_runs
   WHERE account_id = c_acc AND demand_id IN (SELECT id FROM public.cl_demands WHERE plan_id = c_plan);
  GET DIAGNOSTICS v_n = ROW_COUNT; v_cnt := v_cnt || jsonb_build_object('cl_sampling_runs', v_n);

  DELETE FROM public.cl_samples WHERE plan_id = c_plan AND account_id = c_acc;      -- cl_sample_scans cascade
  GET DIAGNOSTICS v_n = ROW_COUNT; v_cnt := v_cnt || jsonb_build_object('cl_samples', v_n);

  DELETE FROM public.cl_batches                                                    -- cl_batch_scans cascade
   WHERE account_id = c_acc AND demand_id IN (SELECT id FROM public.cl_demands WHERE plan_id = c_plan);
  GET DIAGNOSTICS v_n = ROW_COUNT; v_cnt := v_cnt || jsonb_build_object('cl_batches', v_n);

  DELETE FROM public.cl_demands WHERE plan_id = c_plan AND account_id = c_acc;
  GET DIAGNOSTICS v_n = ROW_COUNT; v_cnt := v_cnt || jsonb_build_object('cl_demands', v_n);

  DELETE FROM public.cl_plans WHERE id = c_plan AND account_id = c_acc;            -- cl_plan_quotas cascade
  GET DIAGNOSTICS v_n = ROW_COUNT; v_cnt := v_cnt || jsonb_build_object('cl_plans', v_n);

  DELETE FROM public.api_keys WHERE feed_id = c_feed AND account_id = c_acc;       -- api_usage_log cascade
  GET DIAGNOSTICS v_n = ROW_COUNT; v_cnt := v_cnt || jsonb_build_object('api_keys', v_n);

  DELETE FROM public.cl_value_mappings
   WHERE account_id = c_acc AND carrier_id = c_car AND kind = 'product' AND carrier_value = 'STD' AND onems_value = 'A STANDARD';
  DELETE FROM public.cl_extra_fields WHERE account_id = c_acc AND carrier_id = c_car AND carrier_field = 'weight_kg';
  DELETE FROM public.cl_field_mappings
   WHERE account_id = c_acc AND carrier_id = c_car
     AND (standard_field, carrier_field) IN (('item_id','tracking_number'), ('product','service_code'), ('scan_at','event_time'),
                                             ('place_ref','facility_id'), ('mode_ref','event_code'));
  GET DIAGNOSTICS v_n = ROW_COUNT; v_cnt := v_cnt || jsonb_build_object('cl_field_mappings', v_n);

  DELETE FROM public.cl_feeds WHERE id = c_feed AND account_id = c_acc;
  GET DIAGNOSTICS v_n = ROW_COUNT; v_cnt := v_cnt || jsonb_build_object('cl_feeds', v_n);

  DELETE FROM public.readers
   WHERE account_id = c_acc AND capture_source = 'carrier_scan' AND id::text LIKE 'c1de2000-0000-4000-8000-000000000%';
  GET DIAGNOSTICS v_n = ROW_COUNT; v_cnt := v_cnt || jsonb_build_object('readers', v_n);

  UPDATE public.delivery_standards SET cl_last_mile_time = 0
   WHERE account_id = c_acc AND cl_first_mile_time = 0 AND cl_last_mile_time = 1
     AND id IN ('8afdb952-be52-450b-ac44-323f9c2973e3', '79c2d399-1e46-44bd-b6d5-799af726ef03');
  GET DIAGNOSTICS v_n = ROW_COUNT; v_cnt := v_cnt || jsonb_build_object('standards_reset', v_n);

  IF (SELECT count(*) FROM public.one_db WHERE source = 'panelist') <> v_pan THEN
    RAISE EXCEPTION 'CLEANUP: panelist one_db rows changed';
  END IF;
  RAISE NOTICE 'cleanup: %', v_cnt;
END $$;

SELECT (SELECT count(*) FROM public.cl_feeds WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e') AS feeds,
       (SELECT count(*) FROM public.cl_plans WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e') AS plans,
       (SELECT count(*) FROM public.cl_demands WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e') AS demands,
       (SELECT count(*) FROM public.cl_samples WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e') AS samples,
       (SELECT count(*) FROM public.cl_alerts WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e') AS alerts,
       (SELECT count(*) FROM public.readers WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e' AND capture_source = 'carrier_scan') AS carrier_points,
       (SELECT count(*) FROM public.api_keys WHERE feed_id IS NOT NULL AND account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e') AS carrier_keys,
       (SELECT count(*) FROM public.one_db WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e' AND source = 'carrier') AS one_db_carrier,
       (SELECT count(*) FROM public.cl_field_mappings WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e') AS field_mappings,
       (SELECT max(cl_last_mile_time) FROM public.delivery_standards
         WHERE id IN ('8afdb952-be52-450b-ac44-323f9c2973e3', '79c2d399-1e46-44bd-b6d5-799af726ef03')) AS max_last_mile;
