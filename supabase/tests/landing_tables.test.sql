-- Verifies the landing + state tables exist with the expected columns/constraints.
DO $$
BEGIN
  IF to_regclass('public.rfid_provider_reads') IS NULL THEN
    RAISE EXCEPTION 'FAIL: rfid_provider_reads does not exist';
  END IF;
  IF to_regclass('public.rfid_ingest_state') IS NULL THEN
    RAISE EXCEPTION 'FAIL: rfid_ingest_state does not exist';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.rfid_provider_reads'::regclass
      AND contype = 'c' AND conname = 'rfid_provider_reads_match_status_chk'
  ) THEN
    RAISE EXCEPTION 'FAIL: match_status CHECK constraint missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.rfid_provider_reads'::regclass AND contype = 'p'
  ) THEN
    RAISE EXCEPTION 'FAIL: rfid_provider_reads has no primary key';
  END IF;
  RAISE NOTICE 'PASS: landing tables present';
END $$;
