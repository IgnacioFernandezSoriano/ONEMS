-- Scope filter: resolve_provider_reads must DELETE landing reads whose tag does
-- not start with 'G.1UPU.01000FFFF' (not ours) and keep/process the ones that do.
DO $$
DECLARE
  v_reader  text := 'FILTERTEST';
  v_ours    text := 'G.1UPU.01000FFFFAA00TEST';   -- matches prefix -> kept
  v_notours text := 'G.1UPU.01 NOTOURS00C4A9';     -- no prefix     -> deleted
  v_ours_left    int;
  v_notours_left int;
BEGIN
  INSERT INTO rfid_provider_reads (id, tag_id_raw, reader_id, read_local_datetime, ingested_at, match_status)
  VALUES (gen_random_uuid(), v_ours,    v_reader, now(), now(), 'pending'),
         (gen_random_uuid(), v_notours, v_reader, now(), now(), 'pending');

  PERFORM public.resolve_provider_reads();

  SELECT count(*) INTO v_notours_left FROM rfid_provider_reads WHERE tag_id_raw = v_notours;
  SELECT count(*) INTO v_ours_left    FROM rfid_provider_reads WHERE tag_id_raw = v_ours;

  IF v_notours_left <> 0 THEN
    RAISE EXCEPTION 'FAIL: non-matching tag not deleted (% left)', v_notours_left;
  END IF;
  IF v_ours_left < 1 THEN
    RAISE EXCEPTION 'FAIL: matching tag was removed (should be kept)';
  END IF;

  -- cleanup (FK-safe: these never reached rfid_events_raw)
  DELETE FROM rfid_provider_reads WHERE reader_id = v_reader;
  DELETE FROM incidents WHERE metadata->>'reader_lpi' = v_reader;
  RAISE NOTICE 'PASS: scope filter keeps prefix tags, deletes others';
END $$;
