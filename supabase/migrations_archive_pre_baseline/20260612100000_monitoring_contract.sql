-- =====================================================
-- Monitoring contract: read-only views for the external global monitoring
-- platform (pull/polling). System-wide aggregates across all tenants.
-- Surfaces the AWS-provider capture state (rfid_ingest_state / rfid_provider_reads)
-- which has no UI today. Do NOT call rpc_get_pipeline_status here (JWT-dependent).
-- Views are owned by the migration runner (postgres) -> run with owner privileges
-- (security_invoker=false default) -> RLS bypassed, base tables not exposed to readers.
-- The `monitoring` schema is NOT added to PostgREST exposed schemas (no REST access).
-- =====================================================

CREATE SCHEMA IF NOT EXISTS monitoring;

-- 1) Provider capture / ingest state (single source row, projected cleanly)
CREATE OR REPLACE VIEW monitoring.ingest_state AS
SELECT
  id            AS source_id,
  next_cursor,
  last_since,
  backfill_since,
  last_run_at,
  last_status,
  last_error,
  total_fetched,
  last_fetched,
  last_matched,
  last_unmatched,
  updated_at
FROM public.rfid_ingest_state;

-- 2) Landing reads broken down by match_status (pending/matched/unknown_reader/tag_decode_failed)
CREATE OR REPLACE VIEW monitoring.provider_reads_summary AS
SELECT
  match_status,
  count(*)          AS reads_count,
  max(ingested_at)  AS last_ingested_at,
  max(resolved_at)  AS last_resolved_at
FROM public.rfid_provider_reads
GROUP BY match_status;

-- 3) Incident aggregates (open vs resolved) by type + severity
CREATE OR REPLACE VIEW monitoring.incidents_summary AS
SELECT
  incident_type,
  severity,
  count(*) FILTER (WHERE is_resolved = false) AS open_count,
  count(*) FILTER (WHERE is_resolved = true)  AS resolved_count,
  count(*)                                    AS total_count,
  max(detected_at)                            AS last_detected_at
FROM public.incidents
GROUP BY incident_type, severity;

-- 4) ETL pipeline counts, system-wide (no JWT)
CREATE OR REPLACE VIEW monitoring.pipeline_status AS
SELECT
  (SELECT count(*) FROM public.rfid_events_raw)                          AS raw_events_total,
  (SELECT count(*) FROM public.rfid_events_raw WHERE is_processed = false) AS raw_events_pending,
  (SELECT count(*) FROM public.rfid_events_raw WHERE is_processed = true)  AS raw_events_processed,
  (SELECT count(*) FROM public.processed_events)                         AS processed_events,
  (SELECT count(*) FROM public.journey_segments)                         AS journey_segments,
  (SELECT count(*) FROM public.journeys)                                 AS journeys,
  (SELECT count(*) FROM public.journey_paths)                            AS journey_paths,
  (SELECT max(created_at) FROM public.processed_events)                  AS last_processed_event_at,
  (SELECT max(created_at) FROM public.journey_segments)                  AS last_segment_at;

-- 5) Health rollup (exactly 1 row) — the endpoint the platform alerts on.
--    contract_version lets the consumer detect breaking changes.
CREATE OR REPLACE VIEW monitoring.health AS
WITH ingest AS (
  SELECT * FROM public.rfid_ingest_state WHERE id = 'aws-rfid-read-api'
),
backlog AS (
  SELECT count(*) AS pending FROM public.rfid_events_raw WHERE is_processed = false
),
inc AS (
  SELECT
    count(*)                                              AS open_total,
    count(*) FILTER (WHERE severity IN ('high','critical')) AS open_high
  FROM public.incidents
  WHERE is_resolved = false
)
SELECT
  1                                                       AS contract_version,
  i.last_run_at                                           AS capture_last_run_at,
  round((extract(epoch FROM (now() - i.last_run_at)) / 60.0)::numeric, 1) AS minutes_since_capture,
  i.last_status                                           AS capture_status,
  i.last_error                                            AS capture_last_error,
  i.next_cursor,
  i.backfill_since,
  i.last_fetched,
  i.last_matched,
  i.last_unmatched,
  CASE WHEN coalesce(i.last_fetched, 0) > 0
       THEN round(i.last_unmatched::numeric / i.last_fetched, 4)
       ELSE 0 END                                         AS last_unmatched_rate,
  b.pending                                               AS backlog_pending,
  inc.open_total                                          AS open_incidents,
  inc.open_high                                           AS open_incidents_high,
  CASE
    WHEN i.last_run_at IS NULL                            THEN 'critical'
    WHEN i.last_status = 'error'                          THEN 'critical'
    WHEN (now() - i.last_run_at) > interval '90 minutes'  THEN 'critical'
    WHEN i.last_status = 'rate_limited'                   THEN 'warning'
    WHEN (now() - i.last_run_at) > interval '60 minutes'  THEN 'warning'
    WHEN inc.open_high > 0                                THEN 'warning'
    ELSE 'ok'
  END                                                     AS overall_status,
  now()                                                   AS snapshot_at
FROM ingest i
CROSS JOIN backlog b
CROSS JOIN inc;

-- Grant to service_role too (LEG2-consistency option). monitoring_reader grants in next migration.
GRANT USAGE ON SCHEMA monitoring TO service_role;
GRANT SELECT ON ALL TABLES IN SCHEMA monitoring TO service_role;

COMMENT ON SCHEMA monitoring IS
  'Read-only contract for the external global monitoring platform (pull). Versioned via monitoring.health.contract_version. NOT exposed to PostgREST.';
