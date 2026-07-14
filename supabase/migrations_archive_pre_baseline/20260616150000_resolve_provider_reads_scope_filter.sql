-- =====================================================
-- Scope filter: only tags starting with 'G.1UPU.01000FFFF' are ours.
-- Reads whose tag_id_raw does NOT start with that prefix are not for us:
-- they are deleted from the landing table and never enter the ETL.
-- Everything else is unchanged from the previous resolve_provider_reads.
-- =====================================================
CREATE OR REPLACE FUNCTION public.resolve_provider_reads()
RETURNS TABLE (
  processed         integer,
  matched           integer,
  unknown_reader    integer,
  tag_decode_failed integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  v_account uuid;
  v_norm text;
  v_raw_id uuid;
  c_processed integer := 0;
  c_matched integer := 0;
  c_unknown integer := 0;
  c_decode integer := 0;
BEGIN
  -- Scope filter: drop reads that are not ours (tag prefix). Out of ETL scope.
  DELETE FROM public.rfid_provider_reads
  WHERE tag_id_raw NOT LIKE 'G.1UPU.01000FFFF%'
    AND match_status IN ('pending','unknown_reader','tag_decode_failed');

  FOR r IN
    SELECT * FROM public.rfid_provider_reads
    WHERE match_status IN ('pending','unknown_reader','tag_decode_failed')
    ORDER BY ingested_at
  LOOP
    c_processed := c_processed + 1;

    v_norm := public.normalize_provider_tag(r.tag_id_raw);

    SELECT account_id INTO v_account
    FROM public.readers
    WHERE reader_id = r.reader_id AND deleted_at IS NULL
    LIMIT 1;

    IF v_account IS NULL THEN
      UPDATE public.rfid_provider_reads
      SET match_status='unknown_reader',
          unmatch_reason='reader_id not found in readers catalog',
          tag_id_normalized=v_norm,
          resolved_at=now()
      WHERE id = r.id;
      c_unknown := c_unknown + 1;
      CONTINUE;
    END IF;

    IF v_norm IS NULL THEN
      UPDATE public.rfid_provider_reads
      SET match_status='tag_decode_failed',
          unmatch_reason='could not normalize tagId to EPC hex',
          resolved_account_id=v_account,
          resolved_at=now()
      WHERE id = r.id;
      c_decode := c_decode + 1;
      CONTINUE;
    END IF;

    INSERT INTO public.rfid_events_raw
      (account_id, event_id, read_local_datetime, reader_id, tag_id, is_processed)
    VALUES
      (v_account, r.id::text, r.read_local_datetime, r.reader_id, v_norm, false)
    ON CONFLICT (account_id, event_id) DO NOTHING
    RETURNING id INTO v_raw_id;

    IF v_raw_id IS NULL THEN
      SELECT id INTO v_raw_id FROM public.rfid_events_raw
      WHERE account_id = v_account AND event_id = r.id::text;
    END IF;

    UPDATE public.rfid_provider_reads
    SET match_status='matched',
        resolved_account_id=v_account,
        tag_id_normalized=v_norm,
        rfid_events_raw_id=v_raw_id,
        unmatch_reason=NULL,
        resolved_at=now()
    WHERE id = r.id;
    c_matched := c_matched + 1;
  END LOOP;

  RETURN QUERY SELECT c_processed, c_matched, c_unknown, c_decode;
END $$;

REVOKE ALL ON FUNCTION public.resolve_provider_reads() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_provider_reads() TO service_role;

COMMENT ON FUNCTION public.resolve_provider_reads() IS
'Resolves landing rows (rfid_provider_reads) into rfid_events_raw: normalizes tagId, resolves account_id from readerId. Scope filter: deletes reads whose tag does not start with G.1UPU.01000FFFF (not ours). Reprocesses pending/unknown_reader/tag_decode_failed rows (auto-heals as catalog/decode improve).';
