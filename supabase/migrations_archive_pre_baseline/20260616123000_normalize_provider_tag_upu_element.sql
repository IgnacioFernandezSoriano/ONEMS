-- =====================================================
-- normalize_provider_tag v2: accept the provider's canonical UPU element-string
-- format `G.<issuer>.<hex-serial>` (e.g. 'G.1UPU.01000FFFF00000007').
-- Confirmed with the provider: reads ALWAYS arrive in this format and it is the
-- correct, definitive tag identifier -> store the FULL string as-is (trim +
-- uppercase), do not strip the prefix/issuer. Previously this format returned
-- NULL -> reads landed as tag_decode_failed and never reached rfid_events_raw.
-- =====================================================
CREATE OR REPLACE FUNCTION public.normalize_provider_tag(p_raw text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v text;
  v_candidate text;
BEGIN
  IF p_raw IS NULL THEN
    RETURN NULL;
  END IF;
  v := trim(p_raw);
  IF v = '' THEN
    RETURN NULL;
  END IF;

  -- Already a hex EPC string -> uppercase passthrough
  IF v ~ '^[0-9A-Fa-f]+$' THEN
    RETURN upper(v);
  END IF;

  -- Provider UPU element string: G.<issuer>.<hex-serial>
  -- This IS the canonical tag id -> keep the full string (uppercased).
  IF v ~* '^G\.[0-9A-Za-z]+\.[0-9A-Fa-f]+$' THEN
    RETURN upper(v);
  END IF;

  -- urn:oid form -> take the last dot-separated token if it is hex
  IF lower(v) LIKE 'urn:oid:%' THEN
    v_candidate := split_part(v, '.', array_length(string_to_array(v, '.'), 1));
    IF v_candidate ~ '^[0-9A-Fa-f]+$' THEN
      RETURN upper(v_candidate);
    END IF;
    RETURN NULL;
  END IF;

  -- Unrecognized format
  RETURN NULL;
END $$;

COMMENT ON FUNCTION public.normalize_provider_tag(text) IS
'Normalizes a provider tagId. Rules: hex passthrough; UPU element string G.<issuer>.<hex> kept full (canonical id, confirmed with provider); urn:oid last token if hex; else NULL.';
