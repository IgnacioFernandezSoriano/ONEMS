# ONEMS Monitoring Contract (v1)

> Read-only interface for the external global monitoring platform. The platform
> polls these views over a direct Postgres connection. Internals of ONEMS may
> change; **only this contract is stable**. Breaking changes bump
> `monitoring.health.contract_version`.

## Connection

- **Project (dev):** `onems-dev` (`sehbnpgzqljrsqimwyuz`), region eu-central-2.
- **Recommended user:** `monitoring_reader` (SELECT on schema `monitoring` only).
- **Alternative:** `service_role` (same path as the LEG2 integration; full DB access — prefer `monitoring_reader`).
- **Schema:** `monitoring`. Not exposed via PostgREST — use the direct Postgres connection string (session port 5432 or pooler 6543).
- **Password:** set out-of-band; request via secret channel.
- Point at `onems-dev` first; switch the host to the production project when ONEMS promotes.

## Views (data dictionary)

### `monitoring.health` — 1 row, the alerting endpoint
| Column | Meaning |
|---|---|
| `contract_version` | Contract version (currently 1). |
| `overall_status` | `ok` / `warning` / `critical` (computed, see thresholds). |
| `capture_last_run_at` | Last AWS-provider poll run. |
| `minutes_since_capture` | Minutes since last poll (freshness). |
| `capture_status` | `ok` / `error` / `rate_limited` (last poll). |
| `capture_last_error` | Last poll error message, if any. |
| `next_cursor`, `backfill_since` | Ingestion cursor state. |
| `last_fetched` / `last_matched` / `last_unmatched` | Last poll counts. |
| `last_unmatched_rate` | unmatched / fetched (0..1). |
| `backlog_pending` | Unprocessed raw events (ETL backlog). |
| `open_incidents` / `open_incidents_high` | Open incident counts (all / high+critical). |
| `snapshot_at` | Server time when the row was computed. |

### `monitoring.ingest_state` — provider capture detail
Projection of the ingest state: `source_id, next_cursor, last_since, backfill_since, last_run_at, last_status, last_error, total_fetched, last_fetched, last_matched, last_unmatched, updated_at`.

### `monitoring.provider_reads_summary` — landing reads by status
`match_status` (`pending`/`matched`/`unknown_reader`/`tag_decode_failed`), `reads_count`, `last_ingested_at`, `last_resolved_at`.

### `monitoring.incidents_summary` — incident aggregates
`incident_type`, `severity`, `open_count`, `resolved_count`, `total_count`, `last_detected_at`.

### `monitoring.pipeline_status` — ETL counts (system-wide)
`raw_events_total`, `raw_events_pending`, `raw_events_processed`, `processed_events`, `journey_segments`, `journeys`, `journey_paths`, `last_processed_event_at`, `last_segment_at`.

## Suggested alert thresholds (platform side)

`overall_status` already encodes these; raw fields are exposed so the platform can override.

| Condition | Severity |
|---|---|
| `capture_last_run_at IS NULL` or `capture_status = 'error'` | critical |
| `minutes_since_capture > 90` (cron runs every 30 min) | critical |
| `capture_status = 'rate_limited'` | warning |
| `minutes_since_capture > 60` | warning |
| `backlog_pending` growing across consecutive polls | warning |
| `last_unmatched_rate` above your tolerance (e.g. > 0.2) | warning |
| `open_incidents_high > 0` | warning |

## Triage

This contract is read-only and Ops-focused. To **act** on an incident (register a
reader, resolve, reprocess), operators go to ONEMS: *Pipeline Monitor*
(`/diagnosis/pipeline-monitor`) and *Consolidación de Eventos*
(`/diagnosis/event-consolidation`). Deep-link from the platform back to those screens.

## Suggested polling cadence

Every 5 min is plenty (capture runs every 30). The views are cheap aggregates.
