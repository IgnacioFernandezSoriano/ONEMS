# Monitoring Contract (Plan A — ONEMS side) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose ONEMS RFID capture + ETL health as a stable, read-only `monitoring` schema (5 views) consumed by an external global monitoring platform via direct Postgres polling, plus a scoped `monitoring_reader` role and the handoff doc for the consuming project (Plan B).

**Architecture:** The global Ops/SRE platform already exists, already aggregates several solutions, polls (pull) and owns history + alerting. ONEMS becomes one more *source*: it publishes a versioned contract of SQL views (the interface), read by a least-privilege role. Views aggregate **system-wide across all tenants** (RLS bypassed via the view owner — intentional, this is a global health window) and **surface the AWS-provider capture state that today has no UI**. The platform reads the views; thresholds/alerts/history live on the platform side.

**Tech Stack:** Supabase (Postgres 17, project `onems-dev` = `sehbnpgzqljrsqimwyuz`), SQL views + Postgres roles. Migrations applied via the Supabase MCP `apply_migration`; SQL assertion tests run via MCP `execute_sql` (DO blocks raising EXCEPTION on failure). No local Supabase CLI. Work on branch `develop`, apply to `onems-dev` (team norm).

---

## Background / Decisions (read before starting)

- **Why views, not raw tables:** the existing LEG2 integration reads ONEMS tables directly with `service_role`. Reusing that *path* but exposing **views** gives a stable, versioned contract (internals can be refactored behind them) and least privilege. This is the "reuse + improve" the user asked for.
- **Why a dedicated role:** `monitoring_reader` gets `SELECT` only on the `monitoring` schema, never on base tables. Default Postgres views (`security_invoker = false`) run with the **view owner's** privileges, so the role does NOT need access to the underlying `public` tables — encapsulation by construction. The migration must be applied by a superuser/owner role (`postgres`, the MCP default) so the views' owner can read the base tables and bypass RLS.
- **`monitoring` schema is NOT exposed to PostgREST** (Supabase only exposes `public` / `graphql_public`). So the views are unreachable via the anon REST API; access is only via the direct Postgres connection. No RLS policies are needed on the views.
- **Do NOT use `rpc_get_pipeline_status`** inside the views: it resolves the account from the JWT and falls back to a hardcoded `account_id`. There is no JWT on a direct-connection poll, so the views compute plain system-wide aggregates instead.
- **Credential decision (default):** build the scoped `monitoring_reader` role (recommended). Grants are ALSO added to `service_role` so the platform can connect that way for consistency with LEG2 if it must. The role's **password is set out-of-band** (manual `ALTER ROLE` step), never committed — same pattern as the Edge Function secrets.
- **Live data sanity (2026-06-12):** `incidents` has 32 rows, all `severity='low'`; `rfid_provider_reads` is empty; `rfid_ingest_state` single row `id='aws-rfid-read-api'`, `last_status='ok'`. The health rollup tolerates these (e.g. `open_incidents_high` is currently 0).

## File Structure

- Create: `supabase/migrations/20260612100000_monitoring_contract.sql` — `monitoring` schema + 5 views + grants to `service_role`.
- Create: `supabase/migrations/20260612100100_monitoring_reader_role.sql` — `monitoring_reader` role (NOLOGIN) + grants + default privileges.
- Create: `supabase/tests/monitoring_views.test.sql` — asserts schema, the 5 views, shapes, `health` returns exactly 1 row.
- Create: `supabase/tests/monitoring_reader_role.test.sql` — asserts role exists, has SELECT on views, has NO access to base tables.
- Create: `docs/monitoring/MONITORING_CONTRACT.md` — versioned data dictionary + Plan B handoff (connection, alert thresholds, credential).

---

### Task 1: `monitoring` schema + 5 contract views

**Files:**
- Create: `supabase/tests/monitoring_views.test.sql`
- Create: `supabase/migrations/20260612100000_monitoring_contract.sql`

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/monitoring_views.test.sql`:

```sql
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run via MCP `execute_sql` on project `sehbnpgzqljrsqimwyuz` with the file contents.
Expected: ERROR `FAIL: schema monitoring does not exist` (or "relation monitoring.health does not exist").

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260612100000_monitoring_contract.sql`:

```sql
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
```

- [ ] **Step 4: Apply the migration**

Apply via MCP `apply_migration` on project `sehbnpgzqljrsqimwyuz`, name `monitoring_contract`, with the migration SQL above.
Expected: success, no error.

- [ ] **Step 5: Run the test to verify it passes**

Run `supabase/tests/monitoring_views.test.sql` via MCP `execute_sql`.
Expected: NOTICE `PASS: monitoring contract views present and healthy (status=ok)`.

- [ ] **Step 6: Sanity-check the payload the platform will read**

Run via MCP `execute_sql`:

```sql
SELECT row_to_json(h) FROM monitoring.health h;
SELECT * FROM monitoring.provider_reads_summary;
SELECT * FROM monitoring.pipeline_status;
```
Expected: one health JSON object with `overall_status='ok'`; `provider_reads_summary` may be empty (no provider rows yet); `pipeline_status` returns one row of counts.

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/20260612100000_monitoring_contract.sql supabase/tests/monitoring_views.test.sql
git commit -m "feat(monitoring): add monitoring schema contract views for external platform

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: `monitoring_reader` scoped read-only role

**Files:**
- Create: `supabase/tests/monitoring_reader_role.test.sql`
- Create: `supabase/migrations/20260612100100_monitoring_reader_role.sql`

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/monitoring_reader_role.test.sql`:

```sql
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run via MCP `execute_sql`.
Expected: ERROR `FAIL: role monitoring_reader does not exist`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260612100100_monitoring_reader_role.sql`:

```sql
-- =====================================================
-- monitoring_reader: least-privilege role for the external monitoring platform.
-- Created NOLOGIN; the password + LOGIN are set out-of-band (NOT committed):
--   ALTER ROLE monitoring_reader WITH LOGIN PASSWORD '<generated-secret>';
-- SELECT only on the monitoring schema -> cannot read base tables (views run as
-- their owner, so no underlying-table grants are needed).
-- =====================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'monitoring_reader') THEN
    CREATE ROLE monitoring_reader NOLOGIN;
  END IF;
END $$;

GRANT USAGE ON SCHEMA monitoring TO monitoring_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA monitoring TO monitoring_reader;

-- Future views added to the schema are auto-readable by the role.
ALTER DEFAULT PRIVILEGES IN SCHEMA monitoring
  GRANT SELECT ON TABLES TO monitoring_reader;

COMMENT ON ROLE monitoring_reader IS
  'Read-only role for the external global monitoring platform. SELECT on schema monitoring only. Password set out-of-band.';
```

- [ ] **Step 4: Apply the migration**

Apply via MCP `apply_migration` on project `sehbnpgzqljrsqimwyuz`, name `monitoring_reader_role`.
Expected: success.

- [ ] **Step 5: Run the test to verify it passes**

Run `supabase/tests/monitoring_reader_role.test.sql` via MCP `execute_sql`.
Expected: NOTICE `PASS: monitoring_reader scoped to monitoring views only`.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260612100100_monitoring_reader_role.sql supabase/tests/monitoring_reader_role.test.sql
git commit -m "feat(monitoring): add scoped monitoring_reader role (SELECT on monitoring schema)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 7: MANUAL step (user, out-of-band — do NOT commit)**

The role is created `NOLOGIN` with no password. To enable the platform to connect, the user runs once (value generated locally, shared with the platform team via a secret channel, never committed):

```sql
ALTER ROLE monitoring_reader WITH LOGIN PASSWORD '<generated-secret>';
```

Flag this to the user as the single manual step (mirrors the Edge Function secrets handoff).

---

### Task 3: Contract documentation + Plan B handoff

**Files:**
- Create: `docs/monitoring/MONITORING_CONTRACT.md`

- [ ] **Step 1: Write the contract doc**

Create `docs/monitoring/MONITORING_CONTRACT.md`:

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add docs/monitoring/MONITORING_CONTRACT.md
git commit -m "docs(monitoring): document the monitoring contract + Plan B handoff

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Plan B handoff (the consuming project — out of scope for this repo)

Plan A produces everything the global platform needs. To execute Plan B on the other project:

1. **Register ONEMS as a new source** (same as the LEG2 source).
2. **Configure the connection**: `monitoring_reader` connection string (host of `onems-dev`, schema `monitoring`); or `service_role` if required for consistency.
3. **Map views → widgets/SLIs**: `monitoring.health` to the health panel; `*_summary` to incident/ingest aggregates.
4. **Set alert thresholds** (see `docs/monitoring/MONITORING_CONTRACT.md`); or just alert on `overall_status`.
5. **Wire history**: point the platform's existing snapshot/store at the views (every ~5 min).
6. **Deep-link** incidents back to ONEMS's `/diagnosis/*` screens for triage.

Hand the platform team: the **connection string + `monitoring_reader` password** (secret channel) and `docs/monitoring/MONITORING_CONTRACT.md`.

---

## Self-Review

- **Spec coverage:** 5 views (health, ingest_state, provider_reads_summary, incidents_summary, pipeline_status) ✅; scoped role ✅; service_role fallback ✅; provider-capture gap surfaced ✅; no JWT-dependent RPC ✅; contract doc + Plan B handoff ✅; out-of-band password ✅.
- **Placeholder scan:** none — full SQL in every step; `<generated-secret>` is an intentional out-of-band manual value, not a code placeholder.
- **Type consistency:** view/column names in the migration, tests, and doc match (`overall_status`, `minutes_since_capture`, `backlog_pending`, `match_status`, etc.). Test references `monitoring.health/ingest_state/provider_reads_summary/incidents_summary/pipeline_status` — all created in Task 1.
- **Note to verify at execution:** `incidents.severity` currently only has `low`; `open_incidents_high` (high/critical) yields 0 today — correct and harmless. If the severity vocabulary is later confirmed/extended, no view change is needed.
```
