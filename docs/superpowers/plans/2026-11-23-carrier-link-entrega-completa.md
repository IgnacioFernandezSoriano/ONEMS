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

### Task 1: Delivery intake model (DB)
New migration: `cl_deliveries` (account, feed, period_start, period_end, file path, content sha256, declared control totals jsonb, status received|processing|processed|failed|rejected, counts, timings, error), `cl_delivery_strata` (delivery, stratum quota id, population, selected, quota_for_delivery, seed), UNLOGGED staging `cl_delivery_rows` (delivery_id + standardized columns + raw allowed extras), private storage bucket `cl-deliveries` with per-account path and storage RLS (connector key via Edge Function only; humans with cl_connectors edit for manual upload). Config function `cl_connector_config(p_feed_id)` (products with carrier codes, points with role/city, field mappings needed, calendar, next period to deliver, limits). Tests.

### Task 2: Processing (DB, background)
`cl_process_delivery(p_delivery_id, p_chunk int)` driven by a pg_cron job every minute: stream-parse the file (JSON Lines or CSV) into staging in chunks (Edge Function or SQL via storage? — decide: Edge Function worker reads the file from Storage and inserts rows in chunks through a SECURITY DEFINER RPC; document), then set-based: apply equivalences, validate rows/items (reuse cl_ingest_batch rules: closed record, latest end in period, product, points, reasons), compute population per stratum (route × ISO week of arrival), quota per delivery = remaining weekly quota × working days of the delivery inside that week / remaining working days of the week (deficit carried by existing settle logic at week end), deterministic draw md5(seed‖item), transfer drawn items (cl_samples, cl_sample_scans, one_db) and their scans to diagnosis staging if the plan has diagnosis, write audit, TRUNCATE/DELETE staging rows of that delivery, mark processed. Resumable and idempotent. Volume test with 2 M rows locally.

### Task 3: Edge Function contract
Replace demand/candidate endpoints with: `GET /config`; `POST /deliveries` {period_start, period_end, sha256, control_totals, format} → returns delivery id + signed upload URL (size cap configurable, default e.g. 500 MB); `POST /deliveries/{id}/complete` → queues processing; `GET /deliveries/{id}` → status and summary (counts, rejected reasons, drawn count, alerts). Keep x-api-key/Bearer auth, carrier_feed scope, rate limit. Remove old routes (no carriers connected yet) — keep a 410 Gone with a clear message.

### Task 4: Audits — DEFERRED (owner 23/11: "De momento no implementaremos la auditoría")
Only store the declared control totals with each delivery (no comparison logic, no witness, no distribution test, no alerts). To be designed later.

### Task 5: Screens (also: Carrier Link "Incidencias" screen for Task 8 — list, filters, detail with periods, assignee, notes, manual close; feed contact_email field in Conectores)
Conectores: deliveries list per connector (period, status, counts, drawn, alerts), manual upload of a delivery file (same pipeline), calendar shows delivery frequency (daily…weekly). Monitor: deliveries instead of demands/batches. Remove demand/candidate UI that no longer applies. Help + i18n.

### Task 6: Simulator, technical spec, user guide
Simulator: full-delivery mode (period files with all complete shipments + control totals; witnesses). Technical spec (docs/carrier-link/manual-conexion.es.md + openapi.yaml + schemas): new contract, normative definition of "envío completo" with a sample query, file formats, control totals, upload flow, statuses, errors, conformance tests. User guide updated. Republish both Claude Docs.

### Task 7: Diagnosis (phase 4)
Design study task-d-design.md (option A) adapted: scans of drawn shipments (all scans if the plan has diagnosis) go to rfid_events_raw with source marker; owner answers pending.

### Task 8: Carrier Link incident control (spec v4.1, R29-R32, D24-D28 — approved by owner 23/11). Runs after Task 3, before Task 5.
DB: `cl_incidents` (account_id RLS, type missing_delivery|delivery_rejected|high_rejection|unknown_data|quota_unfilled, feed, plan, status open|in_progress|resolved, periods jsonb list, assignee, notes, closed_how manual|auto, timestamps), unique open incident per (feed, type) so a new missed period is appended to it (R32); `cl_feeds.contact_email` (carrier technical contact; no carrier email without it); `cl_feeds.config.missing_grace_hours` default 6. Hourly pg_cron watcher: per active feed, compare the delivery calendar with deliveries received → open/append missing_delivery; auto-close on the next delivery received (R31); week settlement 3 days after week end when no delivery covered it (D27, reuse settle logic). Hooks from Task 2 processing: rejected / retries exhausted → delivery_rejected (auto-close when that period is processed OK); rejection ratio above threshold → high_rejection; unknown points/products → unknown_data (auto-close when registered); week settled under quota → quota_unfilled (manual close only). RPCs for authenticated with cl_incidents view/edit: list, set status/assignee/note, close manually (filtered writes, account isolation, 42501 identical). Notifications: queue `cl_notifications` (incident, recipient kind account_manager|carrier, period, status) — one email per incident opening and per newly appended missed period; recipients = account users with AM role of that account + feed contact_email when the case is the carrier's (missing_delivery, delivery_rejected, high_rejection). Edge Function `carrier-link-notify` (cron-kicked, Vault/Env secret, Resend API key from env, never in git) sends short emails in the account language (5 languages: en es fr ar pt), only periods and counts, no shipment data; idempotent (no double send on retry). New permission option `cl_incidents` granted only in DEMO2 (not in access_template for other accounts). Tests: SQL (open/append/auto-close/manual close, one email per missed period, no carrier email without contact_email, isolation), deno (email rendering per language, idempotency, no secret logged). Screen comes in Task 5.
