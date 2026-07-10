-- After consolidation, the DEMO2 test tags (not in one_db) must be CAPTURED:
-- raw rows marked processed, and processed_events created with NULL carrier.
DO $$
DECLARE
  v_result json;
  v_raw_pending int;
  v_processed int;
BEGIN
  v_result := public.consolidate_rfid_events('f4d823d2-93e6-4755-9a89-9da87e7fa86e');

  IF (v_result->>'success')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL: consolidation returned success=false: %', v_result->>'error';
  END IF;

  SELECT count(*) INTO v_raw_pending
  FROM public.rfid_events_raw
  WHERE tag_id IN ('G.1UPU.01000FFFF00000007','G.1UPU.01000FFFF00000008')
    AND is_processed = false;
  IF v_raw_pending <> 0 THEN
    RAISE EXCEPTION 'FAIL: % raw test events still unprocessed', v_raw_pending;
  END IF;

  SELECT count(*) INTO v_processed
  FROM public.processed_events
  WHERE tag_id IN ('G.1UPU.01000FFFF00000007','G.1UPU.01000FFFF00000008')
    AND carrier_id IS NULL;
  IF v_processed < 1 THEN
    RAISE EXCEPTION 'FAIL: expected processed_events with NULL carrier for non-one_db tags, got %', v_processed;
  END IF;

  RAISE NOTICE 'PASS: non-one_db tags captured (% processed_events, NULL carrier)', v_processed;
END $$;
