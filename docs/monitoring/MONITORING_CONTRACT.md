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

---

## Consumer runbook (Plan B — global monitoring platform)

Step-by-step for the team integrating ONEMS as a source. Assumes the same direct-Postgres polling used for the LEG2 source.

### 1. Credentials (from the ONEMS team)
- host `db.sehbnpgzqljrsqimwyuz.supabase.co`, port `5432`, db `postgres`
- user `monitoring_reader`, password (out-of-band)
- IPv4-only network: use the pooler with user `monitoring_reader.sehbnpgzqljrsqimwyuz`. Since you already connect to this project for LEG2, reuse that connection and just swap user/password.

### 2. Test the connection (once)
```bash
psql "postgresql://monitoring_reader:PASSWORD@db.sehbnpgzqljrsqimwyuz.supabase.co:5432/postgres" \
  -c "SELECT overall_status, minutes_since_capture, backlog_pending FROM monitoring.health;"
```
Expected: one row (e.g. `ok | 1.5 | 0`).

### 3. Register ONEMS as a new source (like LEG2)
- connection: above
- poll interval: 5 min
- health query: `SELECT * FROM monitoring.health;`

### 4. Per-poll query (1 row) → map to your SLIs
```sql
SELECT * FROM monitoring.health;
```
Map `overall_status` to the source status; store `minutes_since_capture`, `capture_status`, `backlog_pending`, `last_unmatched_rate`, `open_incidents` as metrics/series.

### 5. Drill-down queries (on alert)
```sql
SELECT * FROM monitoring.ingest_state;
SELECT * FROM monitoring.provider_reads_summary ORDER BY reads_count DESC;
SELECT * FROM monitoring.incidents_summary WHERE open_count > 0 ORDER BY open_count DESC;
SELECT * FROM monitoring.pipeline_status;
```

### 6. Alert rules
Alert on `overall_status` (it already encodes the main conditions), or use the raw-field thresholds in "Suggested alert thresholds" above for custom limits.

### 7. Triage (read-only platform)
Don't resolve incidents from the platform; deep-link back to ONEMS:
- Pipeline Monitor: `<ONEMS_URL>/diagnosis/pipeline-monitor`
- Consolidación de Eventos: `<ONEMS_URL>/diagnosis/event-consolidation`

In short: connect as `monitoring_reader` → poll `monitoring.health` every 5 min → alert on `overall_status`/thresholds → deep-link to ONEMS for triage. Read-only end to end.
