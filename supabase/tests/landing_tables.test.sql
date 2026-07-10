-- Verifies the landing + state tables exist with the expected columns/constraints,
-- the seed row is present, and the core constraints actually reject bad data.

-- 1. Existence + structural checks
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
  IF NOT EXISTS (SELECT 1 FROM public.rfid_ingest_state WHERE id = 'aws-rfid-read-api') THEN
    RAISE EXCEPTION 'FAIL: seed row aws-rfid-read-api missing';
  END IF;
  -- RLS enabled on both tables
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.rfid_provider_reads'::regclass) THEN
    RAISE EXCEPTION 'FAIL: RLS not enabled on rfid_provider_reads';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.rfid_ingest_state'::regclass) THEN
    RAISE EXCEPTION 'FAIL: RLS not enabled on rfid_ingest_state';
  END IF;
  RAISE NOTICE 'PASS: landing tables structure';
END $$;

-- 2. Behavioral checks (wrapped so nothing persists)
BEGIN;
DO $$
DECLARE
  v_id uuid := gen_random_uuid();
BEGIN
  -- invalid match_status must be rejected by the CHECK
  BEGIN
    INSERT INTO public.rfid_provider_reads (id, reader_id, tag_id_raw, read_local_datetime, ingested_at, match_status)
    VALUES (gen_random_uuid(), 'R', 'T', now(), now(), 'bogus');
    RAISE EXCEPTION 'FAIL: invalid match_status was accepted';
  EXCEPTION WHEN check_violation THEN
    NULL;  -- expected
  END;

  -- duplicate provider id must be rejected by the PK
  INSERT INTO public.rfid_provider_reads (id, reader_id, tag_id_raw, read_local_datetime, ingested_at)
  VALUES (v_id, 'R', 'T', now(), now());
  BEGIN
    INSERT INTO public.rfid_provider_reads (id, reader_id, tag_id_raw, read_local_datetime, ingested_at)
    VALUES (v_id, 'R2', 'T2', now(), now());
    RAISE EXCEPTION 'FAIL: duplicate id was accepted';
  EXCEPTION WHEN unique_violation THEN
    NULL;  -- expected
  END;

  RAISE NOTICE 'PASS: landing table behavior';
END $$;
ROLLBACK;
