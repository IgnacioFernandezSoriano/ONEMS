# Load Balancing v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Account-level balancing policies (working days, weekly/daily date policy, POBOX) applied by both the DB balancer and the plan generator, with fair distribution across days, weeks and nodes, a day/week/month view with shaded unavailability, and a "balance all cities" action.

**Architecture:** The balancing engine stays in Postgres (`rpc_balance_city_v2`), driven by `account_config` + per-city overrides in `cities`; the React page calls it per city (looping for "all cities"). The generator (`allocationPlanCalculator.ts`) gets the same inputs (working weekdays, policy, unavailability, POBOX) and applies the same rules client-side. New pure TS helpers live in `src/lib/workingDays.ts` and are unit-tested with vitest; SQL logic is tested with the existing psql test runner.

**Tech Stack:** React 18 + TypeScript + Vite + Tailwind; Supabase (Postgres 17, PL/pgSQL); vitest (new devDependency, see Global Constraints); psql tests in `supabase/tests` against the portable Postgres on 127.0.0.1:5433.

**Spec:** `docs/superpowers/specs/2026-10-27-load-balancing-v2-design.md`

## Global Constraints

- ONE Supabase DB: onems-dev `sehbnpgzqljrsqimwyuz`. Nothing is applied remotely until Task 12, and only after the user confirms the project + ref explicitly. Never `db reset` / `db push`.
- One new migration only: `supabase/migrations/20261027120000_load_balancing_v2.sql` (Tasks 1–4 append to this same file; forward-only, baseline untouched).
- `rpc_balance_node_load_by_period` must keep working unchanged (old tests `balance_node_load_safe_dates` must still pass).
- Only `status = 'pending'` shipments are ever moved or created. Never schedule before `GREATEST(p_start_date, today in account tz)`, on a non-working day, on a node without an active panelist, or on a day the node's panelist has an active unavailability.
- Trace on every moved row: `original_fecha_programada`, `original_origin_node_id` (first time only), `reassignment_reason`, `reassigned_at`, `reassigned_by = auth.uid()`. `reassignment_reason` values: `'rebalancing'`, `'pobox_move'`. New shipments: `generation_source = 'pobox'`.
- Destination node is never changed by the balancer.
- Policy values: `date_policy ∈ ('weekly','daily')`, default `'daily'`; `pobox_enabled boolean` default false; POBOX forces effective `date_policy = 'daily'`. Effective policy of a city = city value if not null, else account value.
- Working day = `weekly_schedule.is_working_day` for that `day_of_week` (0=Sunday … 6=Saturday; no rows for the account ⇒ Mon–Fri) AND not in `non_working_days` (account rows, `postal_center_id IS NULL`).
- All new UI text goes through `useTranslation()` with keys added to all four `public/locales/{en,es,fr,ar}.csv`.
- Quality gate per task: `npx tsc --noEmit -p .` clean and `npm run lint` with 0 errors (warnings ≤ 48 baseline). SQL tasks: `bash supabase/tests/run_tests.sh <test names>` prints `PASS`.
- Frontend unit tests: vitest, added in Task 5 (`npm test`). No other new runtime dependency.
- Windows/CRLF: `.tsx`/`.ts`/`.csv` in this repo use CRLF; the Edit tool handles it, do not rewrite whole files.
- Commits: on branch `develop`, message in Spanish like the repo (`feat(balanceo): …`), ending with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`. Do not push.

## Review Focus

1. A city where **every** node is unavailable for a whole week: nothing must be moved into that week and the preview must list the shipments already there as warnings, not silently leave them on an absent panelist. → Task 3 test case 4.
2. Account **without** `weekly_schedule` rows (Senegal): everything must behave as Mon–Fri, not "all days working". → Task 1 test.
3. Period starting mid-week in the past under `weekly` policy: the week's date must be the first working day ≥ today, never Monday in the past. → Task 3 test case 3.
4. POBOX with a single plan whose end date is before the uncovered day: no new shipment may be created outside any active plan's period; the day is reported as uncovered. → Task 4 test case 3.
5. "Balance all" where one city's RPC throws: the loop must continue, report that city as failed, and still refresh the data. → Task 7 unit test of the loop with a mocked failing RPC.

---

### Task 1: Migration base — policy columns and account working days

**Files:**
- Create: `supabase/migrations/20261027120000_load_balancing_v2.sql`
- Test: `supabase/tests/lb2_working_days.test.sql`

**Interfaces:**
- Produces: `public.is_account_working_day(p_account_id uuid, p_date date) RETURNS boolean` (STABLE, SQL). `public.working_day_in_range(p_account_id, p_preferred, p_from, p_to)` now delegates to it (same signature). Columns: `account_config.date_policy text NOT NULL DEFAULT 'daily' CHECK (date_policy IN ('weekly','daily'))`, `account_config.pobox_enabled boolean NOT NULL DEFAULT false`, `cities.date_policy text NULL CHECK (…)`, `cities.pobox_enabled boolean NULL`, `cities.balance_rotation_offset integer NOT NULL DEFAULT 0`, `allocation_plan_details.generation_source text NOT NULL DEFAULT 'plan' CHECK (generation_source IN ('plan','pobox'))`, same column on `generated_allocation_plan_details`.
- Produces: `public.effective_city_policy(p_city_id uuid) RETURNS TABLE(account_id uuid, date_policy text, pobox_enabled boolean)` — applies the POBOX-forces-daily rule.

- [ ] **Step 1: Write the failing test** `supabase/tests/lb2_working_days.test.sql` (pattern: `\ir fixtures/incident_city.sql`, `pg_temp.fail_if`, BEGIN/ROLLBACK per case):
  - Case A: account 1 with no `weekly_schedule` rows → `is_account_working_day(acc1, '2027-03-06')` (Saturday) is false, `'2027-03-08'` (Monday) true.
  - Case B: insert `weekly_schedule` rows for acc1 with Sunday–Thursday working (`day_of_week` 0..4 true, 5,6 false) → `'2027-03-07'` (Sunday) true, `'2027-03-05'` (Friday) false.
  - Case C: `non_working_days` row `'2027-03-08'` → false even though Monday.
  - Case D: `working_day_in_range(acc1, '2027-03-05', '2027-03-01', '2027-03-12')` with the Sun–Thu schedule returns `'2027-03-07'` (next working day after a non-working Friday; existing tie rule: preferred, then forward, then backward).
  - Case E: `effective_city_policy(C1)`: with account defaults → `('daily', false)`; after `UPDATE cities SET date_policy='weekly'` → `'weekly'`; after `UPDATE cities SET pobox_enabled=true` → `('daily', true)`.
- [ ] **Step 2: Run** `bash supabase/tests/run_tests.sh lb2_working_days` → FAIL (function does not exist).
- [ ] **Step 3: Write the migration** header comment (Spanish, like `20261026140000_balance_node_load_safe_dates.sql`), the `ALTER TABLE`s above, `is_account_working_day`, `effective_city_policy`, and `CREATE OR REPLACE` of `working_day_in_range` replacing `EXTRACT(isodow FROM d) <= 5 AND NOT EXISTS (non_working_days…)` with `public.is_account_working_day(p_account_id, d::date)`.
- [ ] **Step 4: Run** `bash supabase/tests/run_tests.sh lb2_working_days balance_node_load_safe_dates` → both PASS.
- [ ] **Step 5: Commit** `feat(balanceo): politicas de cuenta/ciudad y dias laborables desde weekly_schedule`.

### Task 2: Day-level load data for the day/month view

**Files:**
- Modify: `supabase/migrations/20261027120000_load_balancing_v2.sql` (append)
- Test: `supabase/tests/lb2_day_view.test.sql`

**Interfaces:**
- Produces: `public.rpc_get_node_load_by_day(p_account_id uuid, p_start_date date, p_end_date date) RETURNS TABLE(city_id uuid, city_name text, node_id uuid, node_code text, panelist_name text, day date, shipment_count integer, pending_count integer, is_working_day boolean, is_unavailable boolean)` — one row per (node with `city_id`, day in period), SECURITY DEFINER like `rpc_get_node_load_by_period`, guarded by `p_account_id = (SELECT account_id FROM profiles WHERE id = auth.uid())` OR superadmin (copy the guard pattern used by `rpc_get_node_load_by_period` if present; otherwise rely on the same SECURITY DEFINER + explicit account filter). `shipment_count` counts `allocation_plan_details` with `origin_node_id = node` and `fecha_programada = day` (all statuses); `pending_count` only `'pending'`. `is_unavailable` = exists `panelist_unavailability` with `status='active'` for the node's active panelist covering `day`.

- [ ] **Step 1: Write the failing test**: fixture + 3 pending shipments N1 on `'2027-03-04'`, 1 on `'2027-03-06'` (Saturday); `panelist_unavailability` for P2 `'2027-03-08'..'2027-03-09'` status active (insert directly; `\ir fixtures/no_incident_triggers.sql` first). Assert: row (N1, 2027-03-04) `shipment_count = 3`; (N1, 2027-03-06) `is_working_day = false` and `shipment_count = 1`; (N2, 2027-03-08) `is_unavailable = true`; (N2, 2027-03-10) `is_unavailable = false`; row count = 4 nodes × 31 days for March 2027.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** the function (generate_series × nodes LEFT JOIN details, LEFT JOIN panelists active, LEFT JOIN LATERAL unavailability).
- [ ] **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat(balanceo): rpc_get_node_load_by_day para la vista diaria`.

### Task 3: `rpc_balance_city_v2` — fair distribution (no POBOX yet)

**Files:**
- Modify: `supabase/migrations/20261027120000_load_balancing_v2.sql` (append)
- Test: `supabase/tests/lb2_balance_city.test.sql`

**Interfaces:**
- Produces: `public.rpc_balance_city_v2(p_city_id uuid, p_start_date date, p_end_date date, p_apply_changes boolean DEFAULT false) RETURNS jsonb` with keys: `success, movements_count, stddev_before, stddev_after, improvement_percentage, movements (array of {from_node_code, from_date, to_node_code, to_date, count}, max 100), matrix_before, matrix_after (array of {node_code, week_num, day (null in weekly), load_count}), warnings (array of {code, count, detail}), policy {date_policy, pobox_enabled}, pobox {days_missing, days_moved, days_created, days_uncovered} (all 0 in this task), message, error`.
- Consumes: Task 1 functions and columns.

Algorithm (the tests do not pin it; follow this):
1. Resolve `v_account_id`, tz, `v_from = GREATEST(p_start_date, today_tz)`, policy via `effective_city_policy`.
2. Valid nodes: `nodes n JOIN panelists p ON p.node_id = n.id AND p.status = 'active'` where `n.city_id = p_city_id AND n.status = 'active'`.
3. Shipments: `pending` rows with origin in **any** node of the city (valid or not) and `fecha_programada BETWEEN p_start_date AND p_end_date`.
4. Cells (temp table `cells(node_id, week_start, cell_date, month, current_load, target, new_load)`):
   - `daily`: one per valid node × day `d` in `[v_from, p_end_date]` where `is_account_working_day` and the node's panelist is not unavailable on `d`.
   - `weekly`: one per valid node × ISO week; `cell_date` = first `d` of that week ≥ `v_from` that is working and not unavailable for that node; weeks with no such day for a node get no cell for that node.
5. Targets, computed per month (seasonality preserved — spec §5 rule 5): `month_total` = count of shipments whose current date is in that month (shipments dated before `v_from` count in the month of `v_from`). Split `month_total` among the month's weeks proportionally to the number of working days each week has in the period (floor + largest-remainder). Split each week's share equally among its cells (nodes, and in `daily` the node's days) with floor; the remainder `+1`s go round-robin over cells ordered by `node auto_id` then date, **starting at index `balance_rotation_offset mod cell_count`**.
6. Assignment with minimal moves: shipments already in an existing cell with `current_load ≤ target` stay. Build `excess` = shipments in cells over target (take the latest-dated first) plus every shipment not in any existing cell (absent/non-working/past/invalid node). Fill `deficit` cells ordered by date distance from the shipment's current date (nearest first; tie → earlier). Shipments left with no deficit cell stay put and produce warning `{code:'no_valid_cell', count, detail: node codes}`.
7. `IF p_apply_changes`: `UPDATE` moved rows (`origin_node_id`, `fecha_programada`, `week_number = EXTRACT(week)`, `month`, `year`, trace fields, `reassignment_reason='rebalancing'`), then `UPDATE cities SET balance_rotation_offset = balance_rotation_offset + 1 WHERE id = p_city_id AND <remainder > 0>`.
8. Stddev before/after over cell loads; matrices as above.

- [ ] **Step 1: Write the failing tests** (fixture; actor 99; dates in 2027; `no_incident_triggers`):
  - Case 1 `daily`: 30 pending on N1 `'2027-03-04'`, period `'2027-03-04'..'2027-03-19'` (12 working days, 3 nodes = 36 cells). Preview moves nothing; apply → `movements_count > 0`; per (node, date) load `max - min ≤ 1`; no date outside period, weekend or past; trace fields set; `reassignment_reason='rebalancing'`.
  - Case 2 minimal moves: same setup but 36 shipments already perfectly spread (1 per cell) → apply returns `movements_count = 0`.
  - Case 3 `weekly` + past start: `UPDATE cities SET date_policy='weekly'`; 9 pending spread over `current_date + 2 .. current_date + 16`, period `current_date - 3 .. current_date + 18`; apply → every `fecha_programada` ∈ set of "first working day ≥ current_date of each ISO week in period"; and every date ≥ `current_date`.
  - Case 4 absences: P2 unavailable `'2027-03-08'..'2027-03-12'` active; N3 has no panelist (delete P3); 20 pending on N1 `'2027-03-08'`, period `'2027-03-08'..'2027-03-12'`; apply → zero rows on N3; zero rows on N2 that week; all on N1; stddev reported; and a second scenario where P1 is also unavailable that week → nothing moves, `warnings[0].code = 'no_valid_cell'`, `warnings[0].count = 20`.
  - Case 5 rotation: 7 shipments, 3 nodes, 1 working day; apply twice (re-insert) → the node that got the `+1` differs between runs; `balance_rotation_offset` = 2 after two applies, preview does not change it.
  - Case 6 months: 10 pending in March, 2 in April, period March–April → after apply March still has 10 and April 2.
- [ ] **Step 2: Run** `bash supabase/tests/run_tests.sh lb2_balance_city` → FAIL.
- [ ] **Step 3: Implement** `rpc_balance_city_v2` in the migration (PL/pgSQL, `SET search_path = public`, temp tables `ON COMMIT DROP`, same style as `rpc_balance_node_load_by_period`).
- [ ] **Step 4: Run** → PASS; also `balance_node_load_safe_dates` still PASS.
- [ ] **Step 5: Commit** `feat(balanceo): rpc_balance_city_v2 con reparto equitativo por dia, semana y nodo`.

### Task 4: POBOX and city list

**Files:**
- Modify: `supabase/migrations/20261027120000_load_balancing_v2.sql` (append; extend `rpc_balance_city_v2`)
- Test: `supabase/tests/lb2_pobox.test.sql`

**Interfaces:**
- Produces: `public.rpc_balance_cities_pending(p_account_id uuid, p_start_date date, p_end_date date) RETURNS TABLE(city_id uuid, city_name text, pending_count integer)` ordered by city_name.
- `rpc_balance_city_v2` now fills `pobox` counts and, when effective `pobox_enabled`, runs after step 6 of Task 3:
  - For each working day `d` in `[v_from, p_end_date]` with no shipment (status ≠ cancelled) whose origin is in the city: (a) **move**: pick a `pending` shipment of the city from the nearest date having ≥ 2 shipments (search same ISO week first, backward then forward from `d`, then weeks ±1, ±2… up to period end), skipping dates < `v_from`; keep its nodes; set `fecha_programada = d`, `reassignment_reason='pobox_move'`, trace fields; the origin node must be valid and available on `d`, otherwise try the next candidate. (b) **create**: if none, choose plan = `allocation_plans` `status='active'`, `account_id`, `start_date ≤ d ≤ end_date`, lowest `(count non-pending / count total)` then latest `end_date`; origin = valid, available node of the city with the fewest origin shipments in `d`'s ISO week (tie: fewest in period); destination = valid, available node of another city with the fewest destination shipments in that week, preferring nodes of cities that already appear as destination in that plan from this city (tie: fewest in period); insert with `generation_source='pobox'`, `status='pending'`, `week_number/month/year` from `d`. If no plan or no node → `days_uncovered += 1`, warning `{code:'pobox_uncovered', count, detail: dates}`. In preview mode nothing is written; counts are computed on a temp copy.

- [ ] **Step 1: Write the failing tests**:
  - Case 1 move: `UPDATE account_config SET pobox_enabled=true` (insert row for acc1 if the fixture has none); 2 pending on N1 `'2027-03-08'`, 0 on 9th, period `'2027-03-08'..'2027-03-09'`; apply → one shipment now on `'2027-03-09'` with `reassignment_reason='pobox_move'`, `pobox.days_moved = 1`, no new rows.
  - Case 2 create: 1 pending on `'2027-03-08'`, period 8th–10th; plan `Mar27` active → 2 new rows with `generation_source='pobox'`, `plan_id = Mar27`, origin ∈ C1 nodes, destination = N4 (C2); `pobox.days_created = 2`; preview first → no rows created and the same counts.
  - Case 3 no plan: period `'2027-05-03'..'2027-05-04'` (no active plan covers May) → `days_uncovered = 2`, no rows, warning code `pobox_uncovered`.
  - Case 4 `rpc_balance_cities_pending(acc1, '2027-03-01', '2027-03-31')` returns C1 only (C2 has no pending origin shipments).
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** both.
- [ ] **Step 4: Run** `lb2_pobox lb2_balance_city` → PASS.
- [ ] **Step 5: Commit** `feat(balanceo): politica POBOX y lista de ciudades con pendientes`.

### Task 5: vitest + working-day helpers

**Files:**
- Modify: `package.json` (devDependency `vitest@^2`, script `"test": "vitest run"`), `tsconfig.json` only if `vitest` types need `"types": ["vitest/globals"]` (prefer explicit imports instead).
- Create: `src/lib/workingDays.ts`, `src/lib/__tests__/workingDays.test.ts`

**Interfaces:**
- Produces:
  - `type DatePolicy = 'weekly' | 'daily'`
  - `interface WorkingCalendar { workingDows: Set<number> /* 0..6, JS getDay */; nonWorkingDays: Set<string> /* yyyy-MM-dd */ }`
  - `workingDowsFromSchedule(rows: Array<{ day_of_week: number; is_working_day: boolean }>): Set<number>` — no rows ⇒ `{1,2,3,4,5}`.
  - `isWorkingDay(d: Date, cal: WorkingCalendar): boolean`
  - `localDateKey(d: Date): string` (move the existing one out of `allocationPlanCalculator.ts` and re-export it there).
  - `firstWorkingDayOfWeek(anyDayOfWeek: Date, cal: WorkingCalendar, notBefore?: Date, blocked?: Set<string>): Date | null` — ISO week Mon–Sun; `blocked` are yyyy-MM-dd keys (unavailability).
  - `unavailabilityKeys(periods: Array<{ node_id: string; start_date: string; end_date: string }>): Map<string /*node_id*/, Set<string>>`
  - `effectivePolicy(account: { date_policy: DatePolicy; pobox_enabled: boolean }, city?: { date_policy: DatePolicy | null; pobox_enabled: boolean | null } | null): { datePolicy: DatePolicy; pobox: boolean }` — POBOX forces `'daily'`.

- [ ] **Step 1:** `npm i -D vitest@^2.1.0`; add the script. Run `npm test` → "no test files found" (exit 1 acceptable).
- [ ] **Step 2: Write the failing tests** with exact values: no schedule ⇒ Saturday 2027-03-06 not working; Sun–Thu schedule ⇒ Sunday 2027-03-07 working, Friday not; `nonWorkingDays` has `2027-03-08` ⇒ false; `firstWorkingDayOfWeek(new Date(2027,2,10), cal, new Date(2027,2,9))` ⇒ `2027-03-09`; with `blocked={'2027-03-09'}` ⇒ `2027-03-10`; all week blocked ⇒ `null`; `effectivePolicy({date_policy:'weekly',pobox_enabled:false},{date_policy:null,pobox_enabled:true})` ⇒ `{datePolicy:'daily',pobox:true}`.
- [ ] **Step 3: Run** `npm test` → FAIL.
- [ ] **Step 4: Implement** `src/lib/workingDays.ts`; replace the private `localDateKey` in `allocationPlanCalculator.ts` with the import.
- [ ] **Step 5: Run** `npm test`, `npx tsc --noEmit -p .`, `npm run lint` → PASS / clean.
- [ ] **Step 6: Commit** `chore(test): vitest y helpers de dias laborables`.

### Task 6: Generator applies the policies

**Files:**
- Modify: `src/lib/allocationPlanCalculator.ts`
- Test: `src/lib/__tests__/allocationPlanCalculator.test.ts`

**Interfaces:**
- Consumes: Task 5 helpers.
- `AllocationPlanParams` gains: `workingDows?: Set<number>` (default Mon–Fri), `datePolicy?: DatePolicy` (default `'daily'`), `pobox?: boolean` (default false), `unavailabilityByNode?: Map<string, Set<string>>`. Keep `nonWorkingDays`, `eligibleNodeIds`.
- `AllocationEntry` gains `generationSource: 'plan' | 'pobox'`.
- Produces: `generateAllocationPlan(params): AllocationEntry[]` (same name) and exported `summarizeGeneration(entries): { total: number; pobox: number }`.
- Behaviour changes:
  1. `buildPlanWeeks` uses `isWorkingDay` with `workingDows` + `nonWorkingDays`.
  2. Day choice inside a week (`generateEntriesForRoute`): in `daily`, instead of `Math.random()`, assign days **round-robin per origin node** across the week's days (a per-node cursor map shared across routes, so a node sending 3 shipments in a 5-day week gets 3 different days, and days with the fewest shipments for that node are chosen first); skip days blocked for that node (unavailability); if all blocked, skip the node for that week (its samples go to the other origin nodes of the city for that week; if none, the samples are dropped and counted in a `warnings` array returned via a new optional `onWarning?: (w: {code:string; count:number}) => void` param — keep it simple: console.warn + counted).
  3. `weekly`: every entry of the week gets `firstWorkingDayOfWeek(week.days[0], cal, undefined, blockedForNode)`.
  4. POBOX (`pobox === true`): after all routes, for each origin city and each working day of the period with no entry from that city: move one entry from the nearest date with ≥ 2 entries of that city (same rules as DB), else create one: origin = eligible node of the city with the fewest entries that week, destination = eligible node of another city with the fewest destination entries that week (prefer cities already paired with this origin city); `generationSource='pobox'`.
- [ ] **Step 1: Write the failing tests** with a fixed fixture (2 cities A/B, 2 nodes each, matrix `AB=100`, period 2027-03-01..2027-03-12, `totalSamples=20`): (a) all dates are Mon–Fri and none in `nonWorkingDays=['2027-03-08']`; (b) with Sun–Thu `workingDows` no Friday/Saturday; (c) `datePolicy='weekly'` ⇒ only two distinct dates, `2027-03-01` and `2027-03-09` (8th blocked); (d) `daily` ⇒ for each origin node and week, `max - min ≤ 1` shipments per day; (e) `unavailabilityByNode` blocking node A1 all of week 1 ⇒ no A1 entries dated in week 1; (f) `pobox=true`, `totalSamples=2` ⇒ every working day of the period has ≥ 1 entry from city A and `summarizeGeneration(entries).pobox === entries.length - 2`.
- [ ] **Step 2: Run** `npm test` → FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `npm test`, tsc, lint → clean.
- [ ] **Step 5: Commit** `feat(generador): dias laborables de la cuenta, politica semanal/diaria, ausencias y POBOX`.

### Task 7: Hooks — policies, overrides, day data, balance all

**Files:**
- Modify: `src/hooks/useAccountConfig.ts`, `src/hooks/useNodeLoadBalancing.ts`
- Create: `src/hooks/useBalancePolicies.ts`, `src/hooks/__tests__/balanceAll.test.ts`, `src/lib/balanceAll.ts`

**Interfaces:**
- `AccountConfig` gains `date_policy: DatePolicy`, `pobox_enabled: boolean`. `useAccountConfig()` gains `setWorkingDay(dayOfWeek: number, isWorking: boolean)` (wraps `updateWeeklySchedule`).
- `useBalancePolicies()` (new; uses `useEffectiveAccountId`): returns `{ account: {date_policy, pobox_enabled} | null, cities: Array<{ id, name, date_policy, pobox_enabled }>, updateAccountPolicy(p: Partial<{date_policy; pobox_enabled}>), updateCityPolicy(cityId, p: {date_policy?: DatePolicy|null; pobox_enabled?: boolean|null}), effectiveFor(cityId): {datePolicy; pobox}, loading, refetch }`. If `account_config` has no row for the account, `updateAccountPolicy` upserts one (`calculation_mode` default `'natural_days'`).
- `export interface NodeDayLoad { city_id: string; city_name: string; node_id: string; node_code: string; panelist_name: string | null; day: string /* yyyy-MM-dd */; shipment_count: number; pending_count: number; is_working_day: boolean; is_unavailable: boolean }` (row of `rpc_get_node_load_by_day`, exported from `useNodeLoadBalancing.ts`).
- `useNodeLoadBalancing` gains: `dayData: NodeDayLoad[]` (from `rpc_get_node_load_by_day`, same period), `previewBalanceV2(cityId)`, `applyBalanceV2(cityId)` calling `rpc_balance_city_v2`; `BalanceResult` gains `warnings`, `policy`, `pobox` (typed as in Task 3). Old `previewBalance/applyBalance` remain until Task 10 deletes their callers.
- `src/lib/balanceAll.ts` (pure, testable): `runForCities<T>(cityIds: string[], run: (id) => Promise<T>, onProgress: (done: number, total: number) => void): Promise<Array<{ cityId: string; result?: T; error?: string }>>` — sequential, never throws, continues after an error.
- `useNodeLoadBalancing` gains `listPendingCities()` → `rpc_balance_cities_pending`, `previewAll(onProgress)` and `applyAll(onProgress)` built on `runForCities`; `applyAll` calls `fetchLoadData()` at the end even if some city failed.

- [ ] **Step 1: Write the failing test** `balanceAll.test.ts`: 3 ids, second `run` rejects with `Error('boom')` → result length 3, `[1].error === 'boom'`, `[0].result` and `[2].result` defined, `onProgress` called with `(1,3),(2,3),(3,3)`.
- [ ] **Step 2: Run** `npm test` → FAIL.
- [ ] **Step 3: Implement** `balanceAll.ts`, then the hook changes.
- [ ] **Step 4: Run** `npm test`, tsc, lint → clean.
- [ ] **Step 5: Commit** `feat(balanceo): hooks de politicas, datos diarios y balanceo de todas las ciudades`.

### Task 8: Header policies panel + i18n

**Files:**
- Create: `src/components/NodeLoadBalancing/BalancePoliciesPanel.tsx`
- Modify: `src/pages/NodeLoadBalancing.tsx`, `public/locales/en.csv`, `es.csv`, `fr.csv`, `ar.csv`

**Interfaces:**
- `BalancePoliciesPanel` props: `{ workingDows: Set<number>; onToggleDay(dow: number, on: boolean): void; datePolicy: DatePolicy; pobox: boolean; onChangePolicy(p: {date_policy?: DatePolicy; pobox_enabled?: boolean}): void; onBalanceAll(): void; balancingAll?: { done: number; total: number } | null; disabled?: boolean }`. Seven toggle chips Mon…Sun (order starts Monday; labels via `t('lb2.day_short.1')`…`'lb2.day_short.0'`), a two-option segmented control for the date policy (disabled + tooltip `t('lb2.pobox_forces_daily')` when `pobox`), a POBOX checkbox, and the "Balance all cities" button with a progress text `done/total` while running.
- Translation keys (add to all 4 CSVs, prefix `lb2.`): `policies_title, working_days, date_policy, date_policy_daily, date_policy_weekly, date_policy_help, pobox, pobox_help, pobox_forces_daily, balance_all, balance_all_progress ({done}/{total}), day_short.0 … day_short.6, scale_day, scale_week, scale_month, unavailable_legend, non_working_legend, conflict_legend, city_policy_inherit, warnings_title, warning.no_valid_cell, warning.pobox_uncovered, pobox_days_missing, pobox_days_moved, pobox_days_created, pobox_days_uncovered, applied_ok, applied_error, city_failed`.
- The page renders the panel above the Filters card, wired to `useAccountConfig().weeklySchedule/setWorkingDay` and `useBalancePolicies()`.

- [ ] **Step 1:** Add the keys to the four CSVs (English, Spanish, French, Arabic; Arabic RTL text, keep CSV quoting rules used in the files).
- [ ] **Step 2:** Implement the component and wire it in the page (the "Balance all" button opens the preview modal in "all cities" mode — the modal change is Task 10; until then the handler may only call `previewAll` and `console.log`).
- [ ] **Step 3:** `npx tsc --noEmit -p .`, `npm run lint`, `npm run dev` and check the panel renders, toggles persist after reload (verify in the Account Configuration page that the same weekday changed).
- [ ] **Step 4: Commit** `feat(balanceo): panel de politicas en la cabecera (dias laborables, fecha, POBOX)`.

### Task 9: City card — day/week/month scale, shading, city overrides

**Files:**
- Modify: `src/components/NodeLoadBalancing/CityLoadCard.tsx`, `src/pages/NodeLoadBalancing.tsx`

**Interfaces:**
- `CityLoadCardProps` gains: `dayData: NodeDayLoad[]` (this city's rows), `scale: 'day' | 'week' | 'month'`, `onScaleChange(s)`, `policy: { datePolicy: DatePolicy; pobox: boolean; cityOverride: { date_policy: DatePolicy|null; pobox_enabled: boolean|null } }`, `onCityPolicyChange(p: { date_policy?: DatePolicy|null; pobox_enabled?: boolean|null })`.
- Rendering rules: `week` = current table unchanged; `month` = columns per `yyyy-MM` summing `dayData.shipment_count`, "average" column = per-month mean; `day` = one column per day in period, table in an `overflow-x-auto` wrapper with sticky first column; cell classes: `is_unavailable` → `bg-gray-200 bg-[repeating-linear-gradient(45deg,transparent,transparent_4px,rgba(0,0,0,.08)_4px,rgba(0,0,0,.08)_8px)]`; `!is_working_day` → `bg-gray-100`; shaded cell with `shipment_count > 0` → number in `text-red-700 font-semibold`. Legend row under the table with the three cases (keys from Task 8). Override controls beside the city name: select with `t('lb2.city_policy_inherit')` / daily / weekly and a POBOX tri-state checkbox (inherit / on / off).
- The page holds `scale` state per city (`Record<cityId, Scale>`, default `'week'`).

- [ ] **Step 1:** Implement.
- [ ] **Step 2:** tsc, lint, `npm run dev`: switch Bomet to Day; a weekend column is grey, a node with an active unavailability shows stripes on those days; a shipment on a weekend shows red.
- [ ] **Step 3: Commit** `feat(balanceo): vista dia/semana/mes con ausencias y dias no laborables sombreados`.

### Task 10: Preview modal — v2 results, all cities, POBOX, no alert()

**Files:**
- Modify: `src/components/NodeLoadBalancing/BalancePreviewModal.tsx`, `src/pages/NodeLoadBalancing.tsx`, `src/hooks/useNodeLoadBalancing.ts` (remove old `previewBalance/applyBalance` once unused)

**Interfaces:**
- `BalancePreviewModalProps` becomes `{ isOpen; mode: 'city' | 'all'; cityName?: string; results: Array<{ cityId: string; cityName: string; result?: BalanceResult; error?: string }>; loading: boolean; progress?: { done; total } | null; onClose; onConfirm }`.
- `all` mode: table with one row per city: movements, stddev before → after, improvement %, POBOX moved/created/uncovered, warnings count; totals row; failed cities in red with `t('lb2.city_failed')`. `city` mode: existing layout plus a POBOX block (4 counters) and a warnings list (`t('lb2.warning.' + code)` + count + detail).
- Success / error after apply: an inline banner in the page (state `notice: {type:'ok'|'error'; text}`), replacing both `alert()` calls; auto-hide after 8 s.

- [ ] **Step 1:** Implement; city button → `previewBalanceV2`; confirm → `applyBalanceV2`; header button → `previewAll` → modal `all` → `applyAll`.
- [ ] **Step 2:** tsc, lint; `npm run dev` on DEMO2: preview a city, confirm, banner shows; "Balance all" shows progress and per-city rows.
- [ ] **Step 3: Commit** `feat(balanceo): vista previa v2, balanceo de todas las ciudades y avisos en pantalla`.

### Task 11: Generator form uses the policies

**Files:**
- Modify: `src/hooks/useAllocationPlans.ts`, `src/components/allocation-plans/AllocationPlanGeneratorForm.tsx`, `src/pages/AllocationPlanGenerator.tsx`, four locale CSVs

**Interfaces:**
- `useAllocationPlans()` additionally returns `workingDows: Set<number>` (from `weekly_schedule` account rows), `accountPolicy: {date_policy; pobox_enabled} | null`, `cityPolicies: Array<{id; date_policy; pobox_enabled}>`, `unavailabilityByNode: Map<string, Set<string>>` (active `panelist_unavailability` joined to `panelists.node_id`, account-scoped). `applyPlan` copies `generation_source` into `allocation_plan_details`; `createPlan` details include `generation_source`.
- Form: passes `workingDows`, `datePolicy`/`pobox` from `effectivePolicy(accountPolicy, null)` (account level; per-city overrides are applied inside the calculator through a new param `cityPolicies?: Map<cityId, {datePolicy; pobox}>` — add it to `AllocationPlanParams` in this task, default = account policy), `unavailabilityByNode`. After generation shows `t('allocation_generator.policy_summary')` (policy + working days) and, if `summarizeGeneration(entries).pobox > 0`, `t('allocation_generator.pobox_added', { count })`.
- Keys: `allocation_generator.policy_summary`, `allocation_generator.pobox_added`.

- [ ] **Step 1:** Extend the calculator test (Task 6 file) with one case: `cityPolicies` sets city B to `weekly` while account is `daily` → B-origin entries share one date per week, A-origin entries do not.
- [ ] **Step 2:** `npm test` → FAIL; implement calculator param, hook, form, page, keys.
- [ ] **Step 3:** `npm test`, tsc, lint clean; `npm run dev`: generate a DEMO2 plan with POBOX on and check the notice.
- [ ] **Step 4: Commit** `feat(generador): aplica politicas de cuenta y ciudad y avisa de envios POBOX`.

### Task 12: Replay, deploy to onems-dev, backup

**Files:**
- No code. Uses `supabase/tests/replay.ps1`, `run_tests.sh`, MCP `apply_migration`.

- [ ] **Step 1:** `powershell -File supabase\tests\replay.ps1` → all migrations apply. `bash supabase/tests/run_tests.sh` → the 5 new tests and `balance_node_load_safe_dates` PASS (pre-existing failing tests unrelated to this work are listed, not fixed).
- [ ] **Step 2:** `npm run build` clean.
- [ ] **Step 3 (STOP — needs user):** Ask the user to confirm applying `20261027120000_load_balancing_v2.sql` to **onems-dev `sehbnpgzqljrsqimwyuz`**. Before applying, create `public.backup_pending_dates_20261027 AS SELECT id, fecha_programada, origin_node_id FROM allocation_plan_details WHERE status='pending'` (RLS enabled, no policies) and tell the user the rollback statement. Apply with `apply_migration` (name `load_balancing_v2`).
- [ ] **Step 4:** In the DEV frontend (branch develop deploy) run a preview on KENYA for one city; do **not** apply on KENYA without the user's go.
- [ ] **Step 5:** Report: migration applied, backup table name, test results, what was and was not verified.
