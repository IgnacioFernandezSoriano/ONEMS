-- Verifies the scoped monitoring_reader role: exists, can read the monitoring
-- views, and has NO access to the underlying public base tables.
-- Run via MCP execute_sql AFTER applying 20260612100100_monitoring_reader_role.sql.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'monitoring_reader') THEN
    RAISE EXCEPTION 'FAIL: role monitoring_reader does not exist';
  END IF;

  IF NOT has_schema_privilege('monitoring_reader', 'monitoring', 'USAGE') THEN
    RAISE EXCEPTION 'FAIL: monitoring_reader lacks USAGE on schema monitoring';
  END IF;

  -- Can read every contract view
  IF NOT (
    has_table_privilege('monitoring_reader','monitoring.health','SELECT')
    AND has_table_privilege('monitoring_reader','monitoring.ingest_state','SELECT')
    AND has_table_privilege('monitoring_reader','monitoring.provider_reads_summary','SELECT')
    AND has_table_privilege('monitoring_reader','monitoring.incidents_summary','SELECT')
    AND has_table_privilege('monitoring_reader','monitoring.pipeline_status','SELECT')
  ) THEN
    RAISE EXCEPTION 'FAIL: monitoring_reader missing SELECT on one or more monitoring views';
  END IF;

  -- Must NOT reach base tables directly (encapsulation)
  IF has_table_privilege('monitoring_reader','public.rfid_events_raw','SELECT')
     OR has_table_privilege('monitoring_reader','public.incidents','SELECT')
     OR has_table_privilege('monitoring_reader','public.rfid_ingest_state','SELECT') THEN
    RAISE EXCEPTION 'FAIL: monitoring_reader should NOT have SELECT on public base tables';
  END IF;

  RAISE NOTICE 'PASS: monitoring_reader scoped to monitoring views only';
END $$;
