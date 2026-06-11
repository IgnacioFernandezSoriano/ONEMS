-- Verifies the partial unique index exists and actually rejects duplicate
-- active reader_id values (wrapped so nothing persists).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND indexname='uq_readers_reader_id_active'
  ) THEN
    RAISE EXCEPTION 'FAIL: uq_readers_reader_id_active index missing';
  END IF;
  RAISE NOTICE 'PASS: index present';
END $$;

BEGIN;
DO $$
DECLARE
  v_account uuid;
BEGIN
  SELECT id INTO v_account FROM public.accounts ORDER BY name LIMIT 1;
  INSERT INTO public.readers (id, account_id, reader_id, name, type, is_active)
  VALUES (gen_random_uuid(), v_account, 'ZZTEST-UNIQ-01', 'ZZTEST a', 'Entry', true);
  BEGIN
    INSERT INTO public.readers (id, account_id, reader_id, name, type, is_active)
    VALUES (gen_random_uuid(), v_account, 'ZZTEST-UNIQ-01', 'ZZTEST b', 'Entry', true);
    RAISE EXCEPTION 'FAIL: duplicate active reader_id was accepted';
  EXCEPTION WHEN unique_violation THEN
    NULL;  -- expected
  END;
  RAISE NOTICE 'PASS: duplicate active reader_id rejected';
END $$;
ROLLBACK;
