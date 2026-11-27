# Carrier Link `GET /query` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The carrier's connector can call `GET /query?db=postgresql|oracle|sqlserver` and receive the extraction SQL for its next delivery, already filled with its own configuration.

**Architecture:** A pure TypeScript builder `buildCarrierQuery(config, db)` turns the JSON of `cl_connector_config` (the same object `GET /config` returns) into SQL text. The Edge Function `carrier-link-ingest` gets a new `query` route that calls `cl_connector_config` and returns the builder's output. No database change.

**Tech Stack:** Deno (Edge Function + `deno test`), Python 3 (carrier simulator), PostgreSQL 17 portable (local validation).

**Spec:** `docs/superpowers/specs/2026-11-25-cl-consulta-carrier-design.md`

## Global Constraints

- Worktree `C:\Users\fernandezi\projects\ONEMS_wt_cl_query`, branch `feat/cl-consulta-carrier`. Commit per task; **never push**.
- **No Supabase writes** in any task (no migrations, no `execute_sql`, no deploy). Deploy is a separate controller step with explicit user confirmation on onems-dev `sehbnpgzqljrsqimwyuz`.
- Route: `GET /query`, query parameter `db` ∈ `postgresql` | `oracle` | `sqlserver`, default `postgresql`. Any other value → `CL_BAD_REQUEST` (400). Same auth, key scope (`carrier_feed`), rate limit and feed binding as `config`. Endpoint label for the rate limiter: `/carrier-link-ingest/query`.
- Response 200 JSON: `{ "db": string, "tested": boolean, "period_start": string|null, "period_end": string|null, "table_placeholder": "carrier_scans", "sql": string }`. `tested` is `true` only for `postgresql`.
- `config.mapping_complete !== true` → `CL_MAPPING_INCOMPLETE` (422, already defined in `lib.ts`).
- No routes/route lists anywhere in the SQL. Rule = manual §5.1, identical to `complete_shipments` in `tools/carrier-simulator/carrier_sim/connector.py`.
- Oracle and SQL Server SQL carry a header line `-- SIN PROBAR / UNTESTED` (both words).
- Carrier-facing SQL comments in **English** (the manual's API is English-facing; the Spanish manual explains them).
- Never log request content or SQL text.

## Review Focus

1. A carrier code or field name containing `'`, `"`, `]` or `--` must not break or inject into the SQL — escape literals by doubling `'`; quote identifiers per dialect (`"x"` doubling `"`; `[x]` doubling `]`).
2. Optional mappings absent (`product` or `mode_ref` missing in `fields`): no product filter / points match on place only — exactly like the simulator.
3. `next_period` null: SQL still returned, period parameters are visible placeholders and `period_start`/`period_end` are null.
4. Empty `products` or `points` lists: SQL must still be valid and return zero rows (no `IN ()` syntax errors).
5. A point with `mode_ref` null matches any event code at that place; place/mode values compared trimmed, empty string = null.

---

### Task 1: SQL builder

**Files:**
- Create: `supabase/functions/carrier-link-ingest/query.ts`
- Test: `supabase/functions/carrier-link-ingest/query.test.ts`

**Interfaces:**
- Produces: `export type QueryDb = 'postgresql' | 'oracle' | 'sqlserver'`; `export const QUERY_DBS: readonly QueryDb[]`; `export const TABLE_PLACEHOLDER = 'carrier_scans'`;
  `export function buildCarrierQuery(config: ConnectorConfig, db: QueryDb): { db: QueryDb; tested: boolean; period_start: string | null; period_end: string | null; table_placeholder: string; sql: string }`
  where `ConnectorConfig` is a local interface covering the keys used: `fields`, `extra_fields`, `products[].carrier_codes`, `points[]{place_ref, mode_ref, role}`, `date_timezone`, `include_all_scans`, `next_period{period_start, period_end} | null`, `connector{name, carrier}`.
  `export const IANA_TO_WINDOWS: Record<string, string>` (at least Africa/Nairobi→"E. Africa Standard Time", Africa/Dakar→"Greenwich Standard Time", Europe/Madrid→"Romance Standard Time", America/New_York→"Eastern Standard Time", Etc/UTC and UTC→"UTC").

SQL shape (all dialects): header comment (connector, carrier, generated-for period, "replace carrier_scans with your table", "scan time column assumed a native date/time without time zone in <scan tz>; if it already carries a time zone drop the first conversion", untested line where applicable) → period parameters at top → CTEs: `s` (scans with trimmed place/mode, local date of the scan in `date_timezone`, flags is_arrival/is_departure/is_agreed computed against an inline VALUES list of points), `arrival` (latest arrival per item via `ROW_NUMBER() OVER (PARTITION BY item ORDER BY scan DESC)`), `product` (product of the earliest readable scan, only if product mapped), `complete` (arrival local date in period, product in the inline list of all `carrier_codes`, exists an origin scan earlier than the arrival) → file SELECT of the mapped fields + extra fields, aliased to the carrier's own names, `WHERE is_agreed` unless `include_all_scans` → second statement: control totals grouped by arrival place, mode, product. Scan tz = `fields.scan_at.timezone` or `UTC`.

Dialect specifics: PostgreSQL params via `\set p_start '...'` style is NOT portable — use a leading `WITH params AS (SELECT DATE '…' AS p_start, DATE '…' AS p_end)` CTE in all dialects (Oracle: `FROM dual`; SQL Server: plain SELECT). Placeholder when no period: `DATE '<PERIOD_START>'` literal text inside the params CTE plus a comment saying to replace it. Time zone: PG `(col AT TIME ZONE 'S') AT TIME ZONE 'D'`; Oracle `CAST(FROM_TZ(CAST(col AS TIMESTAMP), 'S') AT TIME ZONE 'D' AS DATE)` truncated with `TRUNC`; SQL Server `CAST((col AT TIME ZONE 'WinS') AT TIME ZONE 'WinD' AS date)`, unknown IANA zone → `'<WINDOWS_TIME_ZONE_FOR_x>'` plus a comment.

- [ ] **Step 1: Write failing tests** in `query.test.ts` using the config of `tools/carrier-simulator/examples/01-get-config.json` (`.body`), inlined as a fixture constant:
  - `postgresql`: `tested === true`, `period_start === '2026-11-02'`, `period_end === '2026-11-04'`, `table_placeholder === 'carrier_scans'`, sql contains `"tracking_no"`, `"event_ts"`, `"weight_g"`, `AT TIME ZONE 'Africa/Nairobi'`, `ROW_NUMBER()`, does not contain `DISTINCT ON`, contains every carrier code of every product and every point `place_ref`.
  - `oracle`: `tested === false`, sql contains `SIN PROBAR / UNTESTED`, `FROM_TZ(`, `FROM dual`.
  - `sqlserver`: `tested === false`, contains `[tracking_no]`, `'E. Africa Standard Time'`, `SIN PROBAR / UNTESTED`.
  - `next_period: null` → `period_start === null` and sql contains `<PERIOD_START>` and `<PERIOD_END>`.
  - `include_all_scans: true` → the file SELECT has no `is_agreed` filter (assert the text `WHERE s.is_agreed` absent; false case present).
  - Without `fields.product`: sql has no product CTE/filter (assert the product carrier codes are absent); without `fields.mode_ref`: mode column absent from the file SELECT.
  - A carrier code `O'BRIEN` appears as `'O''BRIEN'`; field name `we"ird` as `"we""ird"` (pg) and `[we"ird]` (sqlserver); a field `a]b` as `[a]]b]`.
  - Empty `products` and `points`: sql contains no `IN ()` and no `VALUES ` with zero rows (use a never-matching construct, e.g. `1 = 0`).
  - Unknown `date_timezone` `Mars/Base` for sqlserver → contains `<WINDOWS_TIME_ZONE_FOR_Mars/Base>`.
- [ ] **Step 2: Run** `deno test supabase/functions/carrier-link-ingest/query.test.ts` → FAIL (module not found).
- [ ] **Step 3: Implement** `query.ts` per Interfaces and SQL shape.
- [ ] **Step 4: Run** the same command → PASS; also `deno test supabase/functions/carrier-link-ingest/` → all PASS; `deno lint supabase/functions/carrier-link-ingest/` clean.
- [ ] **Step 5: Commit** `feat(carrier-link): constructor de la consulta de extracción del carrier (3 dialectos)`.

### Task 2: `GET /query` route

**Files:**
- Modify: `supabase/functions/carrier-link-ingest/lib.ts` (Route union, `ROUTE_METHOD`, `parseRoute`)
- Modify: `supabase/functions/carrier-link-ingest/handler.ts` (header comment + branch)
- Test: `supabase/functions/carrier-link-ingest/lib.test.ts`, `handler.test.ts`

**Interfaces:**
- Consumes: `buildCarrierQuery`, `QUERY_DBS` from Task 1.
- Produces: route `{ kind: 'query' }`, method `GET`.

- [ ] **Step 1: Failing tests:**
  - lib: `parseRoute(new URL('https://x/carrier-link-ingest/query'))` → `{ kind: 'query' }`; `ROUTE_METHOD.query === 'GET'`.
  - handler (with the existing `mock`): `GET /query` with valid key and `cl_connector_config` answering the fixture → 200, body.db `postgresql`, body.tested true, rpc called once with `{ p_feed_id: FEED }`, rate limiter endpoint `/carrier-link-ingest/query`; `?db=oracle` → body.db `oracle`, tested false; `?db=mysql` → 400 `CL_BAD_REQUEST` with no rpc call; config with `mapping_complete: false` → 422 `CL_MAPPING_INCOMPLETE`; no key → 401; `POST /query` → 405 with `Allow: GET`.
- [ ] **Step 2: Run** `deno test supabase/functions/carrier-link-ingest/` → the new tests FAIL.
- [ ] **Step 3: Implement**: validate `db` before authentication is NOT required — validate after auth and rate limit, before the RPC (so the 400 has no DB work but unauthenticated callers still get 401 first).
- [ ] **Step 4: Run** tests + `deno lint` → PASS/clean.
- [ ] **Step 5: Commit** `feat(carrier-link): GET /query devuelve la consulta de extracción`.

### Task 3: Real PostgreSQL check against the simulator

**Files:**
- Create: `supabase/functions/carrier-link-ingest/query_cli.ts` — `deno run --allow-read query_cli.ts <config.json> <db>` prints `sql` to stdout (accepts a file that is either the config or `{http_status, body}`).
- Create: `tools/carrier-simulator/e2e/query_pg_check.py`
- Modify: `tools/carrier-simulator/README.md` (one section: how to run the check)

`query_pg_check.py` (run with `python -I`): uses the simulator's own dataset generation (`carrier_sim.dataset`) and config `examples/01-get-config.json` to produce the scans; loads them via `psql` (`C:\Users\fernandezi\pgportable\pgsql\bin\psql.exe`, `127.0.0.1:5433`, a throwaway schema created and dropped by the script) into table `carrier_scans` with the carrier's column names and `event_ts timestamp`; gets the SQL from `query_cli.ts` (postgresql), substitutes nothing but the schema search_path, runs both statements, and compares: (a) set of item ids in the file = items of `complete_shipments(...)`; (b) file rows = the rows `build_delivery` would write (same scans, same columns; compare as multisets ignoring order); (c) control totals = the manifest/control totals of `build_delivery`. Also run once with `include_all_scans` true. Exit 0 and print `OK n_items=… n_rows=…` on match, non-zero with the first differences otherwise. If Postgres is not reachable, print how to start it and exit 2.

- [ ] **Step 1:** Write `query_cli.ts` and the script.
- [ ] **Step 2:** Start the portable Postgres if needed (see `supabase/tests/run_tests.sh`) and run `python -I tools/carrier-simulator/e2e/query_pg_check.py` → expected `OK …` for both runs. Any mismatch is a Task 1 bug: fix `query.ts`, re-run Task 1 tests.
- [ ] **Step 3:** `python -I tools/carrier-simulator/tests/test_simulator.py` still passes.
- [ ] **Step 4: Commit** `test(carrier-link): la consulta generada coincide con el simulador en PostgreSQL`.

### Task 4: Documentation

**Files:**
- Modify: `docs/carrier-link/manual-conexion.es.md` — flow diagram (§2) adds `GET /query`; §5.2 says the ready query comes from `GET /query?db=…` (the example stays as reference); new requirement row `CL-REQ-024 | El conector DEBERÍA obtener la consulta de extracción de GET /query (o aplicar §5.1 con el mismo resultado). Oracle y SQL Server se publican sin probar. | 5.2`; endpoint reference section for `/query` (parameters, response fields, errors 400/401/422/429).
- Modify: `docs/carrier-link/openapi.yaml` — path `/query` (GET, `db` enum, default postgresql, 200 schema per Global Constraints, 400/401/422/429 using existing error components).
- Modify: `docs/carrier-link/guia-usuario.es.md` — one line in the connectors part: the carrier gets its extraction query by itself from the API; nothing to send.
- Create: `tools/carrier-simulator/examples/19-get-query.json` — `{http_status: 200, body: …}` generated with `query_cli.ts` from `01-get-config.json` (postgresql) wrapped in the response shape.

- [ ] **Step 1:** Edit the docs and generate the example.
- [ ] **Step 2:** `python -I tools/carrier-simulator/tests/test_docs.py` → PASS (OpenAPI still valid).
- [ ] **Step 3: Commit** `docs(carrier-link): GET /query en el manual, OpenAPI y guía`.

### After the tasks (controller, not a subagent)

Final whole-branch review; then ask Ignacio for explicit confirmation to deploy `carrier-link-ingest` on onems-dev `sehbnpgzqljrsqimwyuz`; after deploy, call `GET /query` (and `?db=oracle`, `?db=sqlserver`) with the DEMO2 connector key from the simulator config (never print the key) and check 200 + period of `next_period`. Then hand the PR fields to Ignacio (base `develop`).
