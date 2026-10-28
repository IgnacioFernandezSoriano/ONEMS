# Muestras por compensar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pending shipments that cannot be sent or received (node without panelist, no valid day) are reassigned within the city or removed from the plan into a "deferred samples" register, reintroduced later by the balancer (POBOX draws from them before creating new ones), counted as pending in plan progress, and shown as a badge in the menu.

**Architecture:** One new migration adds the register table `deferred_samples`, a summary RPC, extends `generation_source` with `'compensation'`, and re-creates `rpc_balance_city_v2` (v3 body) with three new phases: 0 (reassign destination / mark for deferral before targets), R (reintroduction after fairness) and a POBOX change (reintroduce before create). The plan-progress view gains synthetic `deferred` rows. Frontend: one hook for the summary, a Sidebar badge, a read-only section, new preview columns and a recommendation finding.

**Tech Stack:** Postgres 17 / PL/pgSQL (psql tests in `supabase/tests`, local portable Postgres 127.0.0.1:5433), React 18 + TypeScript + Vite + Tailwind, vitest.

**Spec:** `docs/superpowers/specs/2026-10-28-muestras-por-compensar-design.md` (extends `docs/superpowers/specs/2026-10-27-load-balancing-v2-design.md`).

## Global Constraints

- ONE Supabase DB: onems-dev `sehbnpgzqljrsqimwyuz` (prod and dev share it). Nothing is applied remotely until Task 6, and only after the user confirms project + ref explicitly and after a backup table of pending rows exists. Never `db reset` / `db push`.
- One new migration: `supabase/migrations/20261028120000_deferred_samples.sql` (Tasks 1–4 append to it; forward-only; baseline untouched). `rpc_balance_city_v2` must be defined ONCE in it (CREATE OR REPLACE of the full body based on `20261027180000_balance_city_safeupdate.sql`).
- No `UPDATE`/`DELETE` without a top-level `WHERE` anywhere in the migration (PostgREST `safeupdate`; `src/lib/__tests__/migrationsSafeUpdate.test.ts` checks every `202610281*.sql` too — extend its filename regex to `202610(27|28)`).
- Only `status='pending'` shipments are ever reassigned, removed or reintroduced; never notified/sent/received/incident rows. Never schedule before `GREATEST(p_start_date, today in account tz)`, on a non-working day, on an absent panelist's day (origin AND destination), on a node without active panelist, nor outside the plan's `[start_date, end_date]`.
- Removal and annotation happen in the same transaction; preview (`p_apply_changes=false`) writes nothing (no plan rows, no register rows, no rotation offset). Per-city advisory lock already exists on apply.
- Reintroduction cap: at most 1 extra shipment per node and day above what is scheduled after the fairness phase; the rest wait (`waiting_reason='no_capacity'`). Route stays city→city; original node used if valid, else least loaded in the same city.
- POBOX creates a new sample only when no deferred sample of that city (active plan covering the day) can be reintroduced. POBOX-created rows (`generation_source='pobox'`) never reduce the deferred debt; only `'compensation'` rows do.
- Deferred samples count as pending in plan progress (Allocation Plans counters); E2E/SLA reports do not see them.
- All new RPCs: `SECURITY DEFINER`, `SET search_path = public`, same guard as `rpc_get_node_load_by_day` (superadmin or caller's account = target account ⇒ else 42501), `REVOKE ALL FROM PUBLIC, anon; GRANT EXECUTE TO authenticated, service_role`. `deferred_samples` has RLS by `account_id` (SELECT for account members/superadmin; no direct INSERT/UPDATE/DELETE policies — only the DEFINER functions write).
- All UI text via `useTranslation()`; keys added to all four `public/locales/{en,es,fr,ar}.csv` (append, keep CRLF, no duplicates).
- Quality gate per task: `npx tsc --noEmit -p .` clean, `npm run lint` 0 errors (≤48 warnings), `npm test` green, `bash supabase/tests/run_tests.sh <names>` PASS; the 8 pre-existing SQL failures (consolidate_capture_non_onedb, consolidate_unconsolidated_flag, landing_tables, monitoring_reader_role, monitoring_views, poll_cron, readers_reader_id_unique, resolve_provider_reads) are known and must not grow.
- Commits on `develop`, Spanish messages, trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`; add only task files (tree has unrelated dirty files). Do not push unless the controller says so.

## Review Focus

1. A city whose only node has no panelist and whose destinations are fine (Busia): preview must list N `removed` with reason `origin_no_panelist`, apply must insert N register rows AND delete N plan rows atomically, nothing else changes. → Task 2 case 1.
2. A shipment with destination node without panelist but another node with panelist in the same destination city: it must be **reassigned** (destination changes, trace set), not removed. → Task 2 case 2.
3. Reintroduction must never exceed 1 extra per node-day and must leave the rest waiting with `no_capacity`; a second run reintroduces them. → Task 3 case 2.
4. POBOX day uncovered with a deferred sample available for that city/plan/day: it reintroduces (row `generation_source='compensation'`, register row `reintroduced`) and does NOT create a new `pobox` row. → Task 3 case 4.
5. Plan progress: after removal, Allocation Plans still shows the original total and the deferred ones as pending; after reintroduction the synthetic row disappears and the real row appears (no double count). → Task 4 test + Task 5 UI check.

---

### Task 1: Register table, generation_source 'compensation', summary RPC

**Files:**
- Create: `supabase/migrations/20261028120000_deferred_samples.sql`
- Test: `supabase/tests/ds_register.test.sql`

**Interfaces:**
- Produces table `public.deferred_samples(id uuid PK default gen_random_uuid(), account_id uuid NOT NULL, plan_id uuid NOT NULL, origin_city_id uuid NOT NULL, dest_city_id uuid NOT NULL, origin_node_id uuid NOT NULL, destination_node_id uuid NOT NULL, fecha_programada date NOT NULL, reason text NOT NULL CHECK (reason IN ('origin_no_panelist','dest_no_panelist','no_valid_day')), row_snapshot jsonb NOT NULL, status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','reintroduced')), waiting_reason text NULL CHECK (waiting_reason IN ('no_origin_panelist','no_dest_panelist','no_capacity','plan_inactive','outside_period')), created_at timestamptz NOT NULL DEFAULT now(), created_by uuid NULL, reintroduced_at timestamptz NULL, reintroduced_detail_id uuid NULL)`, indexes on `(account_id, status)`, `(origin_city_id, status)`, `(plan_id, status)`. RLS enabled; policy `deferred_samples_select`: `account_id = current_user_account_id() OR is_superadmin()`.
- Produces: `generation_source` CHECKs on `allocation_plan_details` and `generated_allocation_plan_details` re-created as `IN ('plan','pobox','compensation')`.
- Produces: `public.rpc_deferred_samples_summary(p_account_id uuid) RETURNS jsonb` = `{pending_total int, by_city:[{city_id, city_name, count, waiting_reason}], by_plan:[{plan_id, plan_name, total_samples, scheduled, done, deferred, pobox_extra}]}` where `scheduled` = rows of the plan in `allocation_plan_details` with status in ('pending','notified'), `done` = status in ('sent','received'), `deferred` = register rows `pending` of that plan, `pobox_extra` = rows with `generation_source='pobox'`; `waiting_reason` per city = the most frequent non-null waiting_reason among its pending register rows (NULL if none set yet). Ordered by city_name / plan_name.

- [ ] **Step 1: Write the failing test** (pattern of `supabase/tests/lb2_policy_rpcs.test.sql`: fixture `incident_city.sql` + `no_incident_triggers.sql`, `pg_temp.fail_if`, BEGIN/ROLLBACK): (a) insert one register row for account 1 / plan `Mar27` / C1→C2 as superuser; `rpc_deferred_samples_summary(acc1)` with claim 99 ⇒ `pending_total=1`, `by_city[0].city_name='City1'`, `by_plan[0]` has `total_samples=10, deferred=1, scheduled=0, done=0, pobox_extra=0`; (b) after inserting 2 `allocation_plan_details` pending + 1 with `generation_source='pobox'` for that plan ⇒ `scheduled=3, pobox_extra=1`; (c) claim 98 (account 2) ⇒ error 42501; (d) `INSERT ... generation_source='compensation'` into `allocation_plan_details` succeeds.
- [ ] **Step 2: Run** `bash supabase/tests/run_tests.sh ds_register` → FAIL.
- [ ] **Step 3: Write the migration** header (Spanish, like `20261027120000_load_balancing_v2.sql`), the table, RLS, CHECK changes, the RPC + REVOKE/GRANT.
- [ ] **Step 4: Run** `bash supabase/tests/run_tests.sh ds_register lb2_balance_city lb2_pobox` → PASS.
- [ ] **Step 5: Commit** `feat(balanceo): registro de muestras por compensar y resumen por ciudad y plan`.

### Task 2: Phase 0 in `rpc_balance_city_v2` — reassign destination or defer

**Files:**
- Modify: `supabase/migrations/20261028120000_deferred_samples.sql` (append the full `CREATE OR REPLACE FUNCTION public.rpc_balance_city_v2(...)` copied from `20261027180000_balance_city_safeupdate.sql` and changed as below; REVOKE/GRANT re-stated)
- Test: `supabase/tests/ds_balance_defer.test.sql`

**Interfaces:**
- Signature unchanged. JSON gains `deferred: {removed:int, reassigned_dest:int, reintroduced:int, waiting:int, by_reason:{origin_no_panelist:int, dest_no_panelist:int, no_valid_day:int}}` and `warnings` may contain `{code:'deferred_removed', count, detail}`. Keeps all existing keys.
- Behaviour (spec §3.1 + precisions), executed after the shipment load (step 3 of the current body) and BEFORE targets (step 5):
  - **dest_bad rows:** find an alternative destination node in the SAME destination city (`nodes.status='active'` with active panelist, not absent on the shipment's current date, ≠ origin node) with the fewest incoming shipments in that ISO week (tie: fewest in period, then `auto_id`). If found: mark `new_dest_node` on the row (counts as `reassigned_dest`; the row is then treated as movable with that destination for absences). If none: mark `defer_reason='dest_no_panelist'`.
  - **origin invalid rows** (node inactive or without panelist) when the city has NO valid node at all: `defer_reason='origin_no_panelist'`. When the city has valid nodes, nothing changes (normal redistribution).
  - **no valid day:** rows that after step 6 remain `new_cell IS NULL` for lack of a compatible cell in their month get a second search over the other months of the period (cells within `[v_from, p_end]` ∩ plan dates, nearest date first, destination not absent); if still none → `defer_reason='no_valid_day'`. Rows with `od_conflict` keep the existing `origin_equals_destination` behaviour (not deferred).
  - Deferred rows are excluded from month totals, targets, `stddev_before/after` and matrices.
  - **Apply:** for each deferred row, in this order inside the same transaction: `INSERT INTO deferred_samples(... row_snapshot = to_jsonb(apd.*), created_by = auth.uid())` then `DELETE FROM allocation_plan_details WHERE id = <id> AND status='pending'`. For reassigned destinations: `UPDATE ... SET destination_node_id = new, original_destination_node_id = COALESCE(original_destination_node_id, destination_node_id), destination_panelist_id/name = (active panelist of new node), reassignment_reason='rebalancing', reassigned_at=now(), reassigned_by=auth.uid()` (plus date/origin changes from the normal phase).
  - Plan-date filter: cells for a shipment are restricted to its plan's `[start_date, end_date]` in the normal phase too (today only POBOX does it).

- [ ] **Step 1: Write the failing tests** (fixture: C1 = N1,N2,N3 / P1..P3; C2 = N4 / P4; plan `Mar27` 2027-03-01..31 active; dates 2027-03; claim 99):
  - Case 1 (origin city with no panelist): delete P1..P3; 6 pending N1→N4 on 2027-03-04; preview ⇒ `deferred.removed=6`, `by_reason.origin_no_panelist=6`, `movements_count=0`, register unchanged (0 rows), plan unchanged; apply ⇒ 6 register rows `pending` with `reason='origin_no_panelist'`, `row_snapshot->>'id'` = original ids, `plan_id=Mar27`, `origin_city_id=C1`, `dest_city_id=C2`; 0 pending rows left in C1; warning `deferred_removed` count 6.
  - Case 2 (destination reassigned): add node N5 in C2 with panelist P5 active; delete P4; 4 pending N1→N4 on 2027-03-04..05; apply ⇒ all 4 now `destination_node_id=N5`, `original_destination_node_id=N4`, `destination_panelist_id=P5`, `reassignment_reason='rebalancing'`, `deferred.reassigned_dest=4`, `removed=0`.
  - Case 3 (destination city with no panelist): delete P4, no N5; 3 pending N1→N4 ⇒ apply removes 3 with `reason='dest_no_panelist'`.
  - Case 4 (no valid day): P1 absent 2027-03-01..31 (whole plan period), 2 pending N1→N4 on 2027-03-10, P2/P3 deleted so N1 is the only node ⇒ `removed=2`, `reason='no_valid_day'`; variant: P1 absent only 2027-03-08..12 and plan ends 2027-03-31 ⇒ `removed=0`, the 2 rows land in another week of March (cross-month search not needed) — and variant with absence 2027-03-08..31 and plan `Mar27` extended to 2027-04-30 inside the test ⇒ rows land in April (cross-month), `removed=0`.
  - Case 5 (preview purity + atomicity): preview of case 1 inserts nothing; then apply inside a savepoint with a forced failure after the INSERT (e.g. a trigger `pg_temp` raising on DELETE) ⇒ after ROLLBACK TO SAVEPOINT both tables unchanged.
  - Case 6: `lb2_balance_city`, `lb2_pobox`, `balance_node_load_safe_dates` still PASS.
- [ ] **Step 2: Run** `bash supabase/tests/run_tests.sh ds_balance_defer` → FAIL.
- [ ] **Step 3: Implement** in the migration (copy the v2 body, add phase 0, the cross-month search, the apply block, the JSON keys; keep `pg_temp.` qualification and `WHERE` on every UPDATE/DELETE).
- [ ] **Step 4: Run** `bash supabase/tests/run_tests.sh ds_balance_defer ds_register lb2_balance_city lb2_pobox lb2_day_view lb2_working_days balance_node_load_safe_dates` → PASS; `npm test` (safeupdate guard) → PASS.
- [ ] **Step 5: Commit** `feat(balanceo): reasignar destino o apartar al registro las muestras sin panelista o sin dia valido`.

### Task 3: Reintroduction phase and POBOX integration

**Files:**
- Modify: `supabase/migrations/20261028120000_deferred_samples.sql` (same `rpc_balance_city_v2` definition — edit in place, still defined once)
- Test: `supabase/tests/ds_reintroduce.test.sql`

**Interfaces:**
- Phase R runs after fairness (step 6) and before POBOX (6P): candidates = `deferred_samples` with `status='pending'`, `origin_city_id = p_city_id`, plan `active`, and at least one valid day in `[v_from, p_end] ∩ [plan.start_date, plan.end_date]`. Placement per candidate: origin node = original if valid (active + panelist, not absent that day) else least-loaded valid node of the city; destination = original if valid else least-loaded valid node of `dest_city_id`; day = working, not absent for either, inside both ranges, with the fewest shipments of the origin node, honouring the cap (post-fairness load of that node-day + 1). Candidates not placeable get `waiting_reason` ∈ {`no_origin_panelist`,`no_dest_panelist`,`no_capacity`,`plan_inactive`,`outside_period`} (written on apply only). JSON `deferred.reintroduced` / `deferred.waiting` filled.
- POBOX (6P) change: when a day is uncovered and no surplus can be moved, first try a candidate from the register (same rules; the day forced to the uncovered day, cap ignored for POBOX since the day has 0); only then create. New JSON keys in `pobox`: `days_reintroduced:int`.
- Apply: `INSERT INTO allocation_plan_details(account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status='pending', generation_source='compensation', origin_panelist_id/name, destination_panelist_id/name, original_origin_node_id (if origin ≠ original), original_destination_node_id (if dest ≠ original))` then `UPDATE deferred_samples SET status='reintroduced', reintroduced_at=now(), reintroduced_detail_id=<new id>, waiting_reason=NULL WHERE id=<id> AND status='pending'`; waiting ones: `UPDATE deferred_samples SET waiting_reason=<reason> WHERE id=<id>`.

- [ ] **Step 1: Write the failing tests**:
  - Case 1: register 3 rows C1→C2 plan `Mar27` (valid nodes N1..N3, P4 valid), period March ⇒ apply reintroduces 3: new rows `generation_source='compensation'`, dates working days in March, `original_*` NULL when nodes unchanged; register rows `reintroduced` with `reintroduced_detail_id` = the new ids; a second apply reintroduces nothing (idempotent).
  - Case 2 (cap): only N1 valid in C1 (delete P2,P3), 5 working days in period 2027-03-08..12, 5 pending already (1 per day) + 8 register rows ⇒ apply reintroduces exactly 5 (one per day, now 2 per day), `deferred.waiting=3` with `waiting_reason='no_capacity'`; second apply on 2027-03-15..19 reintroduces the 3.
  - Case 3 (waiting reasons): dest city C2 without panelist ⇒ `waiting_reason='no_dest_panelist'`, nothing inserted; plan set `status='completed'` ⇒ `plan_inactive`.
  - Case 4 (POBOX draws from register): POBOX on for account 1; period 2027-03-08..09; 1 pending on 08, none on 09; 1 register row C1→C2 plan `Mar27` ⇒ apply: day 09 covered by a `compensation` row (not `pobox`), `pobox.days_reintroduced=1`, `days_created=0`, register row `reintroduced`; without register rows the same setup creates a `pobox` row (regression of `lb2_pobox` case 2).
  - Case 5: preview of cases 1 and 4 writes nothing to either table.
- [ ] **Step 2: Run** `bash supabase/tests/run_tests.sh ds_reintroduce` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** all `ds_*` + `lb2_*` + `balance_node_load_safe_dates` → PASS; `npm test` → PASS.
- [ ] **Step 5: Commit** `feat(balanceo): reintroducir muestras por compensar y POBOX las usa antes de crear`.

### Task 4: Plan progress counts deferred samples

**Files:**
- Modify: `supabase/migrations/20261028120000_deferred_samples.sql` (append)
- Test: `supabase/tests/ds_plan_progress.test.sql`
- Modify: `src/pages/AllocationPlans.tsx` (counters), `src/lib/types.ts` (status union gains `'deferred'` if typed), four locale CSVs (`allocation_plans.status_deferred`)

**Interfaces:**
- `CREATE OR REPLACE VIEW public.v_allocation_details_with_availability` = current definition `UNION ALL` synthetic rows from `deferred_samples` with `status='pending'`: `id = deferred_samples.id`, `status='deferred'`, `plan_id`, `origin/destination_node_id`, `fecha_programada`, `account_id`, city/panelist columns resolved as the view does for real rows, all other columns NULL. Read the live view definition first (`pg_get_viewdef`) — the migration must re-create it verbatim plus the union; RLS of the base table applies through the join to `deferred_samples` (security_invoker view).
- Frontend: the Pending counters (`AllocationPlans.tsx` lines ~541 and ~564) count `status === 'deferred'` as pending; the status filter dropdown gains "Deferred (to compensate)" via `t('allocation_plans.status_deferred')`; the row shows that status badge; rows with status `deferred` are read-only (no edit/send/receive buttons; reuse the existing per-row disabled pattern).

- [ ] **Step 1: Write the failing SQL test**: 1 register row pending for `Mar27` ⇒ view returns a row with `status='deferred'`, `plan_id=Mar27`, `origin_city_name='City1'`; after marking it `reintroduced` ⇒ no synthetic row; a real row never duplicates.
- [ ] **Step 2: Run** → FAIL; implement the view; → PASS.
- [ ] **Step 3: Frontend**: counters + filter + badge + read-only rows; keys in 4 CSVs; `npx tsc --noEmit -p .`, `npm run lint`, `npm test`.
- [ ] **Step 4: Commit** `feat(planes): las muestras por compensar cuentan como pendientes del plan`.

### Task 5: Hook, menu badge, section, preview columns, recommendations, i18n

**Files:**
- Create: `src/hooks/useDeferredSamples.ts`, `src/components/NodeLoadBalancing/DeferredSamplesSection.tsx`
- Modify: `src/components/layout/Sidebar.tsx` (badge on the Load Balancing item, same style as the incidents badges at ~line 629), `src/pages/NodeLoadBalancing.tsx`, `src/components/NodeLoadBalancing/BalancePreviewModal.tsx`, `src/hooks/useNodeLoadBalancing.ts` (types), `src/lib/balanceViews.ts` (+ test), `src/lib/cityAnalysis.ts` (+ test), four locale CSVs
- Test: `src/lib/__tests__/balanceViews.test.ts` (totals include deferred columns), `src/lib/__tests__/cityAnalysis.test.ts` (new findings)

**Interfaces:**
- `useDeferredSamples(): { summary: DeferredSummary | null; loading; error; refetch }` calling `rpc_deferred_samples_summary(useEffectiveAccountId())`; refetch is called by the page after any apply. `DeferredSummary` mirrors Task 1's JSON.
- `BalanceResult` gains `deferred?: { removed; reassigned_dest; reintroduced; waiting; by_reason }` and `pobox.days_reintroduced?`.
- Preview modal: in `all` mode new columns «Removed / Reassigned dest / Reintroduced / Waiting» (+ totals); in `city` mode a block with the four counters and, when `removed > 0`, a red banner `t('lb2.deferred.remove_warning', {count})` above the confirm button. Confirm button label unchanged.
- `DeferredSamplesSection` (collapsible, below the KPI cards): table by city (`count`, `waiting_reason` translated via `lb2.deferred.waiting.<reason>`), table by plan (`total_samples, scheduled, done, deferred, pobox_extra`). Empty state when `pending_total = 0`.
- Sidebar: badge with `summary.pending_total` when > 0 on `/node-load-balancing` (and on the collapsed-sidebar icon, like the incidents badges) — the hook is called once in Sidebar; superadmin without selected account ⇒ no badge.
- `analyzeCity` gains input `deferredPending: number` and `willRemove: number` ⇒ findings `deferred_waiting` (info, `{count}`) and `deferred_will_remove` (critical, `{count}`); keys `lb2.rec.deferred_waiting`, `lb2.rec.deferred_will_remove`.
- Keys (4 CSVs, prefix `lb2.deferred.`): `title, pending_total, by_city, by_plan, removed, reassigned_dest, reintroduced, waiting, remove_warning ({count}), col_total, col_scheduled, col_done, col_deferred, col_pobox_extra, waiting.no_origin_panelist, waiting.no_dest_panelist, waiting.no_capacity, waiting.plan_inactive, waiting.outside_period, empty, badge_tooltip`.

- [ ] **Step 1: Write the failing vitest cases** (totals of `all` mode include the four deferred counters; `analyzeCity` emits the two findings with exact params and severities).
- [ ] **Step 2: Run** `npm test` → FAIL; implement hook, section, modal, sidebar, findings, keys.
- [ ] **Step 3: Gate**: `npm test`, `npx tsc --noEmit -p .`, `npm run lint`, `npm run build`. State plainly that the browser was not used.
- [ ] **Step 4: Commit** `feat(balanceo): contador de muestras por compensar en el menu, seccion y vista previa`.

### Task 6: Replay, deploy to onems-dev (STOP for user), first preview

- [ ] **Step 1:** `bash supabase/tests/run_tests.sh` → only the 8 known failures; `npm test`, `npm run build` clean.
- [ ] **Step 2 (STOP — needs user):** ask the user to confirm applying `20261028120000_deferred_samples.sql` to **onems-dev `sehbnpgzqljrsqimwyuz`**. Before applying, create `public.backup_apd_pending_20261028 AS SELECT * FROM allocation_plan_details WHERE status='pending'` (RLS enabled, no policies) and tell the user the rollback statement. Apply with `apply_migration` (name `deferred_samples`); verify md5 of every function body in the migration against `pg_proc.prosrc`; verify `has_function_privilege('anon', …) = false`.
- [ ] **Step 3:** Read-only preview on KENYA (`rpc_balance_city_v2(..., false)` for Busia, Eldoret and one city with `dest_bad` rows) and report `deferred` counts; do NOT apply on KENYA without the user's go. Remind the user the first real apply removes ~600 Kenya rows into the register.
- [ ] **Step 4:** Push `develop` only when the user asks; the frontend must deploy AFTER the migration.
