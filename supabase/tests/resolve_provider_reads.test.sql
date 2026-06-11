BEGIN;

DO $$
DECLARE
  v_account uuid;
  v_status text;
  v_raw_count int;
BEGIN
  SELECT id INTO v_account FROM public.accounts ORDER BY name LIMIT 1;
  IF v_account IS NULL THEN
    RAISE EXCEPTION 'FAIL: no accounts to test against';
  END IF;

  INSERT INTO public.readers (id, account_id, reader_id, name, type, is_active)
  VALUES (gen_random_uuid(), v_account, 'ZZTEST-READER-01', 'ZZTEST reader', 'Entry', true);

  INSERT INTO public.rfid_provider_reads
    (id, location, reader_id, tag_id_raw, read_local_datetime, ingested_at, match_status)
  VALUES
    (gen_random_uuid(), 'BR | X | Y | GO', 'ZZTEST-READER-01',
     'urn:oid:1.0.15961.14.B.A00122245737', now(), now(), 'pending'),
    (gen_random_uuid(), 'BR | X | Y | GO', 'ZZTEST-UNKNOWN-READER',
     '30B1D226A8240000B000650C', now(), now(), 'pending'),
    (gen_random_uuid(), 'BR | X | Y | GO', 'ZZTEST-READER-01',
     'urn:oid:1.0.15961.14.B.NOTHEX!!', now(), now(), 'pending');

  PERFORM public.resolve_provider_reads();

  SELECT count(*) INTO v_raw_count FROM public.rfid_events_raw
    WHERE account_id = v_account AND tag_id = 'A00122245737';
  IF v_raw_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: expected 1 matched raw row, got %', v_raw_count;
  END IF;

  SELECT match_status INTO v_status FROM public.rfid_provider_reads
    WHERE reader_id='ZZTEST-READER-01' AND tag_id_raw LIKE '%A00122245737';
  IF v_status <> 'matched' THEN
    RAISE EXCEPTION 'FAIL: expected matched, got %', v_status;
  END IF;

  SELECT match_status INTO v_status FROM public.rfid_provider_reads
    WHERE reader_id='ZZTEST-UNKNOWN-READER';
  IF v_status <> 'unknown_reader' THEN
    RAISE EXCEPTION 'FAIL: expected unknown_reader, got %', v_status;
  END IF;

  SELECT match_status INTO v_status FROM public.rfid_provider_reads
    WHERE tag_id_raw LIKE '%NOTHEX%';
  IF v_status <> 'tag_decode_failed' THEN
    RAISE EXCEPTION 'FAIL: expected tag_decode_failed, got %', v_status;
  END IF;

  PERFORM public.resolve_provider_reads();
  SELECT count(*) INTO v_raw_count FROM public.rfid_events_raw
    WHERE account_id = v_account AND tag_id = 'A00122245737';
  IF v_raw_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: idempotency broken, got % raw rows', v_raw_count;
  END IF;

  RAISE NOTICE 'PASS: resolve_provider_reads';
END $$;

ROLLBACK;
