-- Regression: process_rfid_pipeline PHASE 2 must not raise
-- "column reference segments_created is ambiguous".
-- Run via MCP execute_sql against onems-dev (account DEMO2).
DO $$
DECLARE
  v_reconstruction_status text;
BEGIN
  SELECT status INTO v_reconstruction_status
  FROM public.process_rfid_pipeline('f4d823d2-93e6-4755-9a89-9da87e7fa86e')
  WHERE phase = 'reconstruction';

  IF v_reconstruction_status IS DISTINCT FROM 'success' THEN
    RAISE EXCEPTION 'FAIL: reconstruction phase status = % (expected success)', v_reconstruction_status;
  END IF;
  RAISE NOTICE 'PASS: process_rfid_pipeline reconstruction phase OK';
END $$;
