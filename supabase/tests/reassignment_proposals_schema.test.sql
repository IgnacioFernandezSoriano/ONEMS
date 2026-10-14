-- Verifica el esquema del motor de reasignación tras 20260804120000_*.
\set ON_ERROR_STOP on
BEGIN;

-- La tabla existe con sus checks
DO $$ BEGIN
  IF to_regclass('public.panelist_reassignment_proposal') IS NULL THEN
    RAISE EXCEPTION 'FAIL: tabla panelist_reassignment_proposal no existe';
  END IF;
  RAISE NOTICE 'PASS: tabla existe';
END $$;

-- review_status con default correcto
DO $$
DECLARE v_def text;
BEGIN
  SELECT column_default INTO v_def FROM information_schema.columns
    WHERE table_schema='public' AND table_name='panelist_unavailability' AND column_name='review_status';
  IF v_def IS NULL OR v_def NOT LIKE '%pending_review%' THEN
    RAISE EXCEPTION 'FAIL: review_status sin default pending_review (%)', v_def;
  END IF;
  RAISE NOTICE 'PASS: review_status default pending_review';
END $$;

-- El trigger auto ya NO existe
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'reassign_on_unavailability_trigger') THEN
    RAISE EXCEPTION 'FAIL: el trigger auto reassign_on_unavailability_trigger sigue activo';
  END IF;
  RAISE NOTICE 'PASS: trigger auto desactivado';
END $$;

-- RLS activo en la tabla
DO $$ BEGIN
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.panelist_reassignment_proposal'::regclass) THEN
    RAISE EXCEPTION 'FAIL: RLS no activo en panelist_reassignment_proposal';
  END IF;
  RAISE NOTICE 'PASS: RLS activo';
END $$;

ROLLBACK;
