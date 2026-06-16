-- Verifies the monitoring contract: schema, 5 views, and health rollup shape.
-- Run via MCP execute_sql AFTER applying 20260612100000_monitoring_contract.sql.
DO $$
DECLARE
  v_missing text;
  v_health_rows int;
  v_status text;
BEGIN
  -- schema exists
  IF NOT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = 'monitoring') THEN
    RAISE EXCEPTION 'FAIL: schema monitoring does not exist';
  END IF;

  -- all 5 views exist
  SELECT string_agg(v, ', ') INTO v_missing
  FROM (VALUES ('health'),('ingest_state'),('provider_reads_summary'),
               ('incidents_summary'),('pipeline_status')) AS t(v)
  WHERE NOT EXISTS (
    SELECT 1 FROM information_schema.views
    WHERE table_schema = 'monitoring' AND table_name = t.v
  );
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: missing monitoring views: %', v_missing;
  END IF;

  -- health returns exactly one row
  SELECT count(*) INTO v_health_rows FROM monitoring.health;
  IF v_health_rows <> 1 THEN
    RAISE EXCEPTION 'FAIL: monitoring.health returned % rows, expected 1', v_health_rows;
  END IF;

  -- overall_status is one of the known values
  SELECT overall_status INTO v_status FROM monitoring.health;
  IF v_status NOT IN ('ok','warning','critical') THEN
    RAISE EXCEPTION 'FAIL: overall_status = %, expected ok|warning|critical', v_status;
  END IF;

  RAISE NOTICE 'PASS: monitoring contract views present and healthy (status=%)', v_status;
END $$;
