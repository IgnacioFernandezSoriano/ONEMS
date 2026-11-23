# Carrier Link v4 — Entrega completa por periodo y sorteo ONEMS — Plan de implementación

> For agentic workers: REQUIRED SUB-SKILL: superpowers:subagent-driven-development.

**Goal:** Replace the demand/candidates exchange with: the carrier uploads, per delivery period (daily…weekly), ALL complete shipments of the period; ONEMS validates, counts, draws its own sample, keeps only the drawn shipments, empties the staging area and audits integrity.

**Spec:** docs/superpowers/specs/2026-11-19-carrier-link-design.md — section "v4 (23/11/2026)" (R24-R28, definición de envío completo, D19-D23). Owner 23/11: witness items carry an RFID tag with their own number and follow the panelist procedure.

## Global Constraints
- Single DB onems-dev (sehbnpgzqljrsqimwyuz): no remote write/deploy without explicit owner confirmation; local Postgres for SQL tests (`bash .superpowers/sdd/runlocal.sh`).
- Carrier Link UI only with isCarrierLinkEnabled() (DEV); production and Kenya/Senegal unchanged; nothing in the RFID/panelist pipelines changes behaviour.
- The staging table holds at most one delivery; it is emptied after processing (R25). Only hash, per-stratum counts, control totals and drawn items are kept.
- No PostgREST call may need > 8 s; heavy processing runs in background (pg_cron as postgres, chunked, idempotent, resumable).
- SECURITY DEFINER + `SET search_path = public, extensions`; REVOKE PUBLIC/anon; identical 42501 for missing/foreign; pg-safeupdate; account isolation everywhere (storage paths per account; RLS on storage.objects).
- No personal data stored (closed list of allowed fields, as today).
- Reuse the existing engine: plans, quotas, carry-over, samples, one_db transfer with equivalence time, alerts, undo.
- i18n 5 CSVs (CRLF); npm test/build/lint (baseline 47) and SQL suite pass.

## Review Focus
- A delivery twice (same file / same period) → processed once (idempotent by content hash + period).
- A delivery spanning two ISO weeks (e.g. Sat–Mon) → each shipment counted in the stratum of its arrival week; quotas of both weeks handled.
- Staging never keeps rows after processing (also after a failure mid-way: resumable then emptied).
- Large file (e.g. 2 M rows) → processed in chunks without hitting timeouts; memory bounded.
- Witness shipment delivered in the period but absent → alert; present with a very different time → alert.

### Task 1: Delivery intake model (DB)
New migration: `cl_deliveries` (account, feed, period_start, period_end, file path, content sha256, declared control totals jsonb, status received|processing|processed|failed|rejected, counts, timings, error), `cl_delivery_strata` (delivery, stratum quota id, population, selected, quota_for_delivery, seed), UNLOGGED staging `cl_delivery_rows` (delivery_id + standardized columns + raw allowed extras), private storage bucket `cl-deliveries` with per-account path and storage RLS (connector key via Edge Function only; humans with cl_connectors edit for manual upload). Config function `cl_connector_config(p_feed_id)` (products with carrier codes, points with role/city, field mappings needed, calendar, next period to deliver, limits). Tests.

### Task 2: Processing (DB, background)
`cl_process_delivery(p_delivery_id, p_chunk int)` driven by a pg_cron job every minute: stream-parse the file (JSON Lines or CSV) into staging in chunks (Edge Function or SQL via storage? — decide: Edge Function worker reads the file from Storage and inserts rows in chunks through a SECURITY DEFINER RPC; document), then set-based: apply equivalences, validate rows/items (reuse cl_ingest_batch rules: closed record, latest end in period, product, points, reasons), compute population per stratum (route × ISO week of arrival), quota per delivery = remaining weekly quota × working days of the delivery inside that week / remaining working days of the week (deficit carried by existing settle logic at week end), deterministic draw md5(seed‖item), transfer drawn items (cl_samples, cl_sample_scans, one_db) and their scans to diagnosis staging if the plan has diagnosis, write audit, TRUNCATE/DELETE staging rows of that delivery, mark processed. Resumable and idempotent. Volume test with 2 M rows locally.

### Task 3: Edge Function contract
Replace demand/candidate endpoints with: `GET /config`; `POST /deliveries` {period_start, period_end, sha256, control_totals, format} → returns delivery id + signed upload URL (size cap configurable, default e.g. 500 MB); `POST /deliveries/{id}/complete` → queues processing; `GET /deliveries/{id}` → status and summary (counts, rejected reasons, drawn count, alerts). Keep x-api-key/Bearer auth, carrier_feed scope, rate limit. Remove old routes (no carriers connected yet) — keep a 410 Gone with a clear message.

### Task 4: Audits
(a) Witnesses: panelist shipments that travel with that carrier carry an RFID tag with their own number and follow the panelist procedure; to match them with the carrier's records ONEMS needs the carrier tracking number of each witness → add `carrier_tracking_no` to the panelist shipment record (column only; capture in the panelist bot is a separate n8n task, DEV first) and an audit that, per delivery, flags witnesses delivered in the period that are missing or whose carrier times differ from the panelist/RFID times beyond a tolerance. (b) Distribution: compare carrier transit distribution vs panelists on the same route/week (e.g. percentile gap / KS test with minimum n), alert when the slow tail is missing. (c) Control totals: declared vs received per arrival point. (d) Volume anomaly vs median of recent deliveries. Alerts in cl_alerts with plain-language texts.

### Task 5: Screens
Conectores: deliveries list per connector (period, status, counts, drawn, alerts), manual upload of a delivery file (same pipeline), calendar shows delivery frequency (daily…weekly). Monitor: deliveries and audits instead of demands/batches. Remove demand/candidate UI that no longer applies. Help + i18n.

### Task 6: Simulator, technical spec, user guide
Simulator: full-delivery mode (period files with all complete shipments + control totals; witnesses; a "cheating" mode that drops slow shipments to prove the audits). Technical spec (docs/carrier-link/manual-conexion.es.md + openapi.yaml + schemas): new contract, normative definition of "envío completo" with a sample query, file formats, control totals, upload flow, statuses, errors, conformance tests. User guide updated. Republish both Claude Docs.

### Task 7: Diagnosis (phase 4)
Design study task-d-design.md (option A) adapted: scans of drawn shipments (all scans if the plan has diagnosis) go to rfid_events_raw with source marker; owner answers pending.
