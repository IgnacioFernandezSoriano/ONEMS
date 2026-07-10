-- The incidents CHECK constraint must allow 'unknown_tag' and still reject unknown values.
DO $$
DECLARE
  v_def text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_def
  FROM pg_constraint
  WHERE conrelid = 'public.incidents'::regclass
    AND conname = 'incidents_incident_type_check';

  IF v_def NOT LIKE '%unknown_tag%' THEN
    RAISE EXCEPTION 'FAIL: constraint does not allow unknown_tag: %', v_def;
  END IF;
  IF v_def NOT LIKE '%unknown_reader%' THEN
    RAISE EXCEPTION 'FAIL: constraint dropped unknown_reader: %', v_def;
  END IF;
  RAISE NOTICE 'PASS: incidents constraint allows unknown_tag';
END $$;
