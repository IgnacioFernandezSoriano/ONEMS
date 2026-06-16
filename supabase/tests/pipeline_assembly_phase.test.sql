-- process_rfid_pipeline PHASE 3 (assembly) must not raise "record ->> unknown".
DO $$
DECLARE
  v_status text;
BEGIN
  SELECT status INTO v_status
  FROM public.process_rfid_pipeline('f4d823d2-93e6-4755-9a89-9da87e7fa86e')
  WHERE phase = 'assembly';
  IF v_status IS DISTINCT FROM 'success' THEN
    RAISE EXCEPTION 'FAIL: assembly phase status = % (expected success)', v_status;
  END IF;
  RAISE NOTICE 'PASS: assembly phase OK';
END $$;
