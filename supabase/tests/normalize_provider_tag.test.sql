DO $$
BEGIN
  -- urn:oid sample → last token, uppercased
  IF normalize_provider_tag('urn:oid:1.0.15961.14.B.A00122245737') IS DISTINCT FROM 'A00122245737' THEN
    RAISE EXCEPTION 'FAIL: urn:oid decode, got %', normalize_provider_tag('urn:oid:1.0.15961.14.B.A00122245737');
  END IF;
  -- already-hex passthrough, uppercased
  IF normalize_provider_tag('30b1d226a8240000b000650c') IS DISTINCT FROM '30B1D226A8240000B000650C' THEN
    RAISE EXCEPTION 'FAIL: hex passthrough';
  END IF;
  -- whitespace trimmed
  IF normalize_provider_tag('  01000FFFF12345635  ') IS DISTINCT FROM '01000FFFF12345635' THEN
    RAISE EXCEPTION 'FAIL: trim';
  END IF;
  -- non-hex urn last token → NULL
  IF normalize_provider_tag('urn:oid:1.0.15961.14.B.NOTHEX!!') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: non-hex urn token should be NULL';
  END IF;
  -- garbage → NULL
  IF normalize_provider_tag('hello world') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: garbage should be NULL';
  END IF;
  -- NULL in → NULL out
  IF normalize_provider_tag(NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: NULL should be NULL';
  END IF;
  RAISE NOTICE 'PASS: normalize_provider_tag';
END $$;
