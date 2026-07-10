-- Consolidated processed_events must start unconsolidated (is_consolidated=false)
-- so reconstruct_journeys can pick them up. Uses a throwaway fixture tag.
DO $$
DECLARE
  v_account uuid := 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
  v_reader text := 'STEFANTESTONE';
  v_tag text := 'FLAGTEST-0001';
  v_pe_total int;
  v_pe_unconsolidated int;
BEGIN
  INSERT INTO rfid_events_raw (account_id, event_id, read_local_datetime, reader_id, tag_id, is_processed)
  VALUES (v_account, 'flagtest-1', now() - interval '4 hours', v_reader, v_tag, false),
         (v_account, 'flagtest-2', now(),                      v_reader, v_tag, false);

  PERFORM public.consolidate_rfid_events(v_account);

  SELECT count(*), count(*) FILTER (WHERE is_consolidated = false)
    INTO v_pe_total, v_pe_unconsolidated
  FROM processed_events WHERE tag_id = v_tag;

  IF v_pe_total < 1 THEN
    RAISE EXCEPTION 'FAIL: no processed_events created for fixture tag';
  END IF;
  IF v_pe_unconsolidated <> v_pe_total THEN
    RAISE EXCEPTION 'FAIL: % of % processed_events are is_consolidated=true (expected all false)',
      v_pe_total - v_pe_unconsolidated, v_pe_total;
  END IF;

  DELETE FROM processed_events WHERE tag_id = v_tag;
  DELETE FROM rfid_events_raw WHERE tag_id = v_tag;
  DELETE FROM incidents WHERE tag_id = v_tag;
  RAISE NOTICE 'PASS: consolidate inserts is_consolidated=false';
END $$;
