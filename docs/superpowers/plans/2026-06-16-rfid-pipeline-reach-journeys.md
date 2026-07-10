# RFID Pipeline — Reach Journeys (Extension Plan)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`).

**Goal:** Make the RFID pipeline run fully end-to-end (consolidation → reconstruction → assembly → journeys) by fixing two pre-existing downstream bugs exposed after the first plan.

**Architecture:** Two `CREATE OR REPLACE FUNCTION` migrations on Supabase `onems-dev` (`sehbnpgzqljrsqimwyuz`), each with a SQL test. Builds on the already-applied migrations `20260616130000` (process_rfid_pipeline PHASE 2 alias) and `20260616130200` (consolidate_rfid_events capture).

**Tech Stack:** PostgreSQL plpgsql, Supabase migrations + `.test.sql` DO-block tests via the Supabase MCP.

---

## Decisions

- **Bug A — assembly read:** `process_rfid_pipeline` PHASE 3 reads `assemble_journeys()` (which RETURNS `TABLE(journeys_created, journeys_updated, execution_time_ms)`) as if it were JSON (`->>'journeys_created'`) → `operator does not exist: record ->> unknown`, and it calls the function twice. Fix: alias the set-returning call and read columns once — exactly the pattern used for PHASE 2.
- **Bug B — `is_consolidated` flag:** `consolidate_rfid_events` inserts `processed_events` with `is_consolidated = TRUE`, but the column means "already turned into a journey_segment" (column comment + default `false` + partial index `WHERE is_consolidated=false` + seed data all use `false`). `reconstruct_journeys` only processes `is_consolidated = false` and flips it to `true` after building a segment. Fix: consolidate must insert `is_consolidated = FALSE` in all three reader branches so reconstruction can pick the events up. `reconstruct_journeys` remains the only writer of `true`.

## File Structure

- `supabase/migrations/20260616140000_fix_pipeline_assembly_read.sql` — new; `CREATE OR REPLACE process_rfid_pipeline` with PHASE 3 fixed (PHASE 2 alias retained).
- `supabase/tests/pipeline_assembly_phase.test.sql` — new; assert the assembly phase status = 'success'.
- `supabase/migrations/20260616140100_consolidate_unconsolidated_flag.sql` — new; `CREATE OR REPLACE consolidate_rfid_events` with `is_consolidated = FALSE` in the three INSERTs.
- `supabase/tests/consolidate_unconsolidated_flag.test.sql` — new; assert consolidate produces `processed_events` with `is_consolidated = false`.

---

## Task A: Fix assembly-phase read in `process_rfid_pipeline`

**Files:**
- Create: `supabase/migrations/20260616140000_fix_pipeline_assembly_read.sql`
- Test: `supabase/tests/pipeline_assembly_phase.test.sql`

- [ ] **Step 1: Write the failing test** — `supabase/tests/pipeline_assembly_phase.test.sql`:

```sql
-- process_rfid_pipeline PHASE 3 (assembly) must not raise "record ->> unknown".
DO $$
DECLARE
  v_status text;
BEGIN
  SELECT status INTO v_status
  FROM public.process_rfid_pipeline('f4d823d2-93e6-4755-9a89-9da87e7fa86e')
  WHERE phase = 'assembly';
  IF v_status IS DISTINCT FROM 'success' THEN
    RAISE EXCEPTION 'FAIL: assembly phase status = % (expected success)', v_status;
  END IF;
  RAISE NOTICE 'PASS: assembly phase OK';
END $$;
```

- [ ] **Step 2: Run it — expect FAIL** (`assembly phase status = error`, message `operator does not exist: record ->> unknown`).

- [ ] **Step 3: Implement** — `supabase/migrations/20260616140000_fix_pipeline_assembly_read.sql`. Full `CREATE OR REPLACE FUNCTION public.process_rfid_pipeline` identical to migration `20260616130000` except PHASE 3's block, which becomes:

```sql
    -- PHASE 3: Assembly
    v_phase_start := clock_timestamp();
    BEGIN
        SELECT aj.journeys_created, aj.journeys_updated
        INTO v_assembly_created, v_assembly_updated
        FROM assemble_journeys(p_account_id) aj;

        RETURN QUERY SELECT
            'assembly'::TEXT, 0,0,0,
            (v_assembly_created + v_assembly_updated)::INTEGER,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'success'::TEXT,
            format('Created %s journeys', v_assembly_created + v_assembly_updated)::TEXT;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT
            'assembly'::TEXT, 0,0,0,0,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'error'::TEXT, SQLERRM::TEXT;
        RETURN;
    END;
```

The full function (copy from `supabase/migrations/20260616130000_fix_pipeline_assembly_read.sql` is NOT valid — copy from `20260616130000_fix_pipeline_ambiguous_column.sql` and replace only the PHASE 3 block above). `v_assembly_created`/`v_assembly_updated` are declared INTEGER; `assemble_journeys` returns bigint columns — the assignment implicitly casts. The summary block at the end already references `v_assembly_created + v_assembly_updated`; leave it unchanged.

Apply via `apply_migration` (name `fix_pipeline_assembly_read`).

- [ ] **Step 4: Run the test — expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260616140000_fix_pipeline_assembly_read.sql supabase/tests/pipeline_assembly_phase.test.sql
git commit -m "fix(etl): read assemble_journeys() as a set-returning function in process_rfid_pipeline PHASE 3"
```

---

## Task B: `consolidate_rfid_events` inserts `is_consolidated = FALSE`

**Files:**
- Create: `supabase/migrations/20260616140100_consolidate_unconsolidated_flag.sql`
- Test: `supabase/tests/consolidate_unconsolidated_flag.test.sql`

**Change:** In the current `consolidate_rfid_events` (migration `20260616130200`), the three `INSERT INTO processed_events (...) VALUES (..., TRUE, FALSE)` calls (Entry, Exit, Mixed branches) end with `is_consolidated = TRUE, is_estimated = FALSE`. Change the `is_consolidated` value from `TRUE` to `FALSE` in all three (the trailing `..., TRUE, FALSE)` becomes `..., FALSE, FALSE)`). Everything else is identical.

- [ ] **Step 1: Write the failing test** — `supabase/tests/consolidate_unconsolidated_flag.test.sql`:

```sql
-- Consolidated processed_events must start unconsolidated (is_consolidated=false)
-- so reconstruct_journeys can pick them up. Uses a throwaway tag via a fixture.
DO $$
DECLARE
  v_account uuid := 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
  v_reader text := 'STEFANTESTONE';
  v_tag text := 'FLAGTEST-0001';
  v_pe_total int;
  v_pe_unconsolidated int;
BEGIN
  -- fixture: two raw reads far enough apart to split entry/exit on the Mixed reader
  INSERT INTO rfid_events_raw (account_id, event_id, read_local_datetime, reader_id, tag_id, is_processed)
  VALUES (v_account, 'flagtest-1', now() - interval '4 hours', v_reader, v_tag, false),
         (v_account, 'flagtest-2', now(),                      v_reader, v_tag, false);

  PERFORM public.consolidate_rfid_events(v_account);

  SELECT count(*), count(*) FILTER (WHERE is_consolidated = false)
    INTO v_pe_total, v_pe_unconsolidated
  FROM processed_events WHERE tag_id = v_tag;

  IF v_pe_total < 1 THEN
    RAISE EXCEPTION 'FAIL: no processed_events created for fixture tag';
  END IF;
  IF v_pe_unconsolidated <> v_pe_total THEN
    RAISE EXCEPTION 'FAIL: % of % processed_events are is_consolidated=true (expected all false)',
      v_pe_total - v_pe_unconsolidated, v_pe_total;
  END IF;

  -- cleanup (FK-safe: no segments built yet because we did not run reconstruct)
  DELETE FROM processed_events WHERE tag_id = v_tag;
  DELETE FROM rfid_events_raw WHERE tag_id = v_tag;
  DELETE FROM incidents WHERE tag_id = v_tag;
  RAISE NOTICE 'PASS: consolidate inserts is_consolidated=false';
END $$;
```

- [ ] **Step 2: Run it — expect FAIL** (`processed_events are is_consolidated=true`). The DO block cleans up its own fixture even on the assertion path? No — on RAISE EXCEPTION the whole block rolls back, so the fixture is auto-removed. Good.

- [ ] **Step 3: Implement** — `supabase/migrations/20260616140100_consolidate_unconsolidated_flag.sql`: reproduce the full `consolidate_rfid_events` from migration `20260616130200`, changing the three `processed_events` INSERT value lists from `..., TRUE, FALSE);` to `..., FALSE, FALSE);` (i.e. `is_consolidated` → FALSE). Apply via `apply_migration` (name `consolidate_unconsolidated_flag`).

- [ ] **Step 4: Run the test — expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260616140100_consolidate_unconsolidated_flag.sql supabase/tests/consolidate_unconsolidated_flag.test.sql
git commit -m "fix(etl): consolidate_rfid_events inserts processed_events as unconsolidated so reconstruction picks them up"
```

---

## Task C: End-to-end verification (controller) + push

**Files:** none.

- [ ] **Step 1:** Reset the already-captured test events so reconstruction can pick them up (one-time data correction; they were inserted as `is_consolidated=true` by Task 3 before Bug B was fixed):
```sql
UPDATE processed_events SET is_consolidated = false
WHERE tag_id IN ('G.1UPU.01000FFFF00000007','G.1UPU.01000FFFF00000008');
```

- [ ] **Step 2:** Run the full pipeline and confirm all phases success:
```sql
SELECT phase, segments_created, events_processed, status, message
FROM public.process_rfid_pipeline('f4d823d2-93e6-4755-9a89-9da87e7fa86e');
```
Expected: consolidation/reconstruction/assembly/summary all `status=success`; reconstruction `segments_created >= 1` (each tag has entry→exit at the same center → operational segment).

- [ ] **Step 3:** Confirm final placement of the 6 test events:
```sql
SELECT
  (SELECT count(*) FROM journey_segments WHERE tag_id IN ('G.1UPU.01000FFFF00000007','G.1UPU.01000FFFF00000008')) AS segments,
  (SELECT count(*) FROM journeys WHERE tag_id IN ('G.1UPU.01000FFFF00000007','G.1UPU.01000FFFF00000008')) AS journeys;
```
Report the journey for the tags. If `journeys` table has no `tag_id` column, adapt the count to the actual schema.

- [ ] **Step 4:** Push (requires explicit user confirmation) all commits from both plans to `develop`.

---

## Self-Review

- Bug A (assembly `->>`) → Task A. ✓
- Bug B (`is_consolidated` flag) → Task B. ✓
- End-to-end to journeys → Task C. ✓
- No placeholders; full SQL change described for each function; fixture test cleans up via rollback-on-fail and explicit DELETE on success. ✓
- Type consistency: `aj.journeys_created/journeys_updated` match `assemble_journeys` OUT columns; `is_consolidated=false` matches column default/comment/index and `reconstruct_journeys`'s `WHERE is_consolidated=false`. ✓
