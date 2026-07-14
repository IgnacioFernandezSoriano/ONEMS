-- =====================================================
-- normalize_provider_tag: provider tagId -> EPC hex (provisional v1, spec §8.1)
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
'Normalizes a provider tagId to EPC hex. PROVISIONAL v1 rule (spec §8.1): hex passthrough; urn:oid last token if hex; else NULL. Confirm exact rule with provider (Stefan Gelov).';
