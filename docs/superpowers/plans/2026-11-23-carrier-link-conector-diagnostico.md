# Carrier Link — manual de conexión, carrier simulado, subida manual, diagnóstico y pendientes

> For agentic workers: REQUIRED SUB-SKILL: superpowers:subagent-driven-development.

**Owner decisions (23/11):** no real carrier yet → simulate; connection manual for carriers in SPANISH first (for review; EN/FR later); order A+B → C → D → E; everything to develop/DEV only; production only when all phases are done and tested.
**Spec:** docs/superpowers/specs/2026-11-19-carrier-link-design.md (§4 contract, §5, §9 phases 3-4, R23). Live engine: supabase/migrations/2026112*.sql; Edge Function supabase/functions/carrier-link-ingest/.

## Global Constraints
- Single DB onems-dev (sehbnpgzqljrsqimwyuz): no remote write without explicit owner confirmation; local Postgres for tests (`bash .superpowers/sdd/runlocal.sh`).
- Carrier Link UI only when isCarrierLinkEnabled() (DEV); production unchanged; Kenya/Senegal unchanged.
- i18n 5 CSVs (CRLF), permissions via usePermissions, filtered writes, PostgREST 1000-row cap / 8 s timeout / pg-safeupdate.
- npm test, build, lint (baseline 47) and SQL suite pass.

## Task B: Carrier simulado — tools/carrier-simulator/
Synthetic but realistic dataset generator (items with acceptance → processing → delivery scans at carrier places/modes, product codes, local timestamps, some intermediate scans, some misrouted, some never delivered, some invalid) + a reference connector that: reads open demands (GET /demands with a connector key), selects CLOSED items per stratum uniformly at random (R23), counts population, builds batches (≤ row limit, several batches per demand when needed), optionally dry_run, posts, prints responses. Config file for base URL/key/seed. Local mode against the local DB (same SQL functions as the Edge Function, in the same order) for automated tests; DEV mode against onems-dev (needs a connector key — owner confirmation before any remote run). Deterministic with a seed; batches validate without errors in local mode; README in Spanish. Its output provides the manual's worked example.

## Task A: Manual de conexión (ES) — docs/carrier-link/manual-conexion.es.md
Audience: the carrier's IT team. EXACT to the implemented contract (read the Edge Function, lib.ts, migrations): base URL, authentication (x-api-key / Bearer), key lifecycle (issued by ONEMS, shown once, expiry), limits (body bytes, rows per batch, requests/min), calendar (ONEMS emits demands on the connector's local schedule; GET /demands), demand JSON (strata, start/end points with carrier place/mode values, period, samples_required, candidates_requested), what the connector must do (only closed records with end inside the period; uniform random selection within stratum; population count; return all readings of the selected items at start/end points of ANY city; no personal data), batch JSON (demand_id, batch_id idempotency, strata[].stratum_id, population_size, selection_method 'uniform_random_within_stratum', rows with the carrier's own field names), equivalences configured in ONEMS (item_id, product, scan_at with format/timezone, place_ref, mode_ref, allowed extra fields), dry_run and certification (testing connector = dry runs only), responses (status codes with CL_* codes and meaning, partial results, replay of the same batch_id), several batches per demand, demand expiry (7 days), go-live checklist, full worked example from Task B, FAQ, glossary.

## Task C: Subida manual de un lote desde Conectores
"Cargar lote" next to "Probar lote (ensayo)" for an active connector: upload JSON → dry-run preview → confirm → real ingest + sampling + finish exactly like the Edge Function. SECURITY DEFINER RPC for authenticated with edit on cl_connectors (e.g. cl_manual_batch) — within the 8 s timeout at ~5,000 rows (measure; else sample per stratum from the client with progress). New migration; tests; owner confirmation to apply.

## Task D: Fase 4 — Diagnóstico
Spec §5 "Entrada en diagnóstico" + §9 phase 4: plans with feed_diagnosis request all scans (include_all_scans), sampling inserts one rfid_events_raw row per reading at a known point (tag_id = item id, carrier_id, reader id as the RFID pipeline expects, event_id fingerprint), so the existing consolidation/diagnosis shows them; unknown points kept with alert unknown_reading_point and re-sent when registered; capture origin visible in diagnosis screens; "Diagnóstico" checkbox in the generator for Carrier Link. Must not alter Kenya's RFID data. Design-first: study the RFID pipeline and report the design before implementing if it needs changes.

## Task E: Pendientes
Matrix shows out-of-plan weeks; balancing proposal must improve after locks; set_quotas vs activate race; cities source consistency in plan records; help static files reachable by URL in production; roles screen shows cl_* options in production; get_mobile_readers_summary returns carrier points; reader_location_history superadmin SELECT policy; HelpCenter hasAnyEdit; cl_ prefix exclusion in route test.
