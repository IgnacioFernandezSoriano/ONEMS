# RFID Consolidation Fix + Capture Non-ONE-DB Tags — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the RFID consolidation pipeline actually run end-to-end, and let tags that are not in `one_db` be captured (consolidated into `processed_events` with NULL enrichment) instead of being silently dropped.

**Architecture:** Three Postgres functions are patched via migrations on Supabase `onems-dev`: `process_rfid_pipeline` (alias an ambiguous column), the `incidents` CHECK constraint (allow `unknown_tag`), and `consolidate_rfid_events` (capture non-ONE-DB tags with NULL enrichment, fix the Mixed-reader insert path, isolate per-tag errors). Each change is paired with a SQL test (DO block that raises on failure) run via the Supabase MCP `execute_sql`.

**Tech Stack:** PostgreSQL 17 (plpgsql, SECURITY DEFINER functions), Supabase migrations (`supabase/migrations/*.sql`) + SQL tests (`supabase/tests/*.test.sql`), applied through the Supabase MCP (`apply_migration` / `execute_sql`). When the auto-mode classifier blocks a DDL/constraint migration, the same SQL is run by the user in the Supabase SQL Editor.

---

## Decisions (confirm at review)

1. **Non-ONE-DB tags are captured, not dropped.** When `one_db` has no row for a tag, consolidation proceeds with `carrier_id`, `product_id`, `origin_city_name`, `destination_city_name` = NULL and still creates the `processed_event`.
2. **Observability incident kept, non-blocking.** A `unknown_tag` incident (severity `low`) is still recorded so Ops can see which tags lacked ONE DB enrichment — but it never blocks consolidation. This is why the constraint fix (Task 2) is still required. If this proves noisy, the single INSERT in Task 3 can be removed later without other changes.
3. **Unknown *reader* still blocks that tag** (incident `unknown_reader`, events marked processed, skip). A read with no reader in the catalog genuinely cannot be located. Unchanged.
4. **Expected outcome for the 6 test events:** reader `STEFANTESTONE` is `Mixed`, all reads are at one location within a few minutes (< gap threshold). Consolidation will create **one `entry` `processed_event` per tag (2 total)** with NULL enrichment, and mark all 6 raw rows processed. `reconstruct_journeys` will create **0 segments / 0 journeys** (a journey needs entry→exit in one center or exit→entry across centers; we only have entries at one reader). That is correct, not a failure.

## File Structure

- `supabase/migrations/20260616130000_fix_pipeline_ambiguous_column.sql` — new; `CREATE OR REPLACE FUNCTION process_rfid_pipeline` with the aliased subquery.
- `supabase/tests/pipeline_ambiguous_column.test.sql` — new; regression test that the reconstruction phase no longer errors.
- `supabase/migrations/20260616130100_incidents_allow_unknown_tag.sql` — new; drop+recreate the `incidents_incident_type_check` constraint including `unknown_tag`.
- `supabase/tests/incidents_unknown_tag.test.sql` — new; assert the constraint admits `unknown_tag` and still rejects garbage.
- `supabase/migrations/20260616130200_consolidate_capture_non_onedb.sql` — new; `CREATE OR REPLACE FUNCTION consolidate_rfid_events` with the three behavior changes.
- `supabase/tests/consolidate_capture_non_onedb.test.sql` — new; assert the 6 DEMO2 test events are captured with NULL enrichment and marked processed.

---

## Task 1: Fix ambiguous `segments_created` in `process_rfid_pipeline`

**Files:**
- Create: `supabase/migrations/20260616130000_fix_pipeline_ambiguous_column.sql`
- Test: `supabase/tests/pipeline_ambiguous_column.test.sql`

**Root cause:** `process_rfid_pipeline` declares OUT columns `segments_created` and `events_processed`; in PHASE 2 it runs `SELECT segments_created, events_processed INTO v_reconstruction_segments, v_reconstruction_events FROM reconstruct_journeys(p_account_id)`. Those bare names match both the function's own OUT columns and the subquery's columns → `column reference "segments_created" is ambiguous`. Fix: alias the set-returning call (`rj`) and qualify the columns. Only PHASE 2's SELECT changes; the rest of the function is reproduced verbatim so `CREATE OR REPLACE` is complete.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/pipeline_ambiguous_column.test.sql`:

```sql
-- Regression: process_rfid_pipeline PHASE 2 must not raise
-- "column reference segments_created is ambiguous".
-- Run via MCP execute_sql against onems-dev (account DEMO2).
DO $$
DECLARE
  v_reconstruction_status text;
BEGIN
  SELECT status INTO v_reconstruction_status
  FROM public.process_rfid_pipeline('f4d823d2-93e6-4755-9a89-9da87e7fa86e')
  WHERE phase = 'reconstruction';

  IF v_reconstruction_status IS DISTINCT FROM 'success' THEN
    RAISE EXCEPTION 'FAIL: reconstruction phase status = % (expected success)', v_reconstruction_status;
  END IF;
  RAISE NOTICE 'PASS: process_rfid_pipeline reconstruction phase OK';
END $$;
```

- [ ] **Step 2: Run test to verify it fails**

Run via Supabase MCP `execute_sql` (project `sehbnpgzqljrsqimwyuz`): paste the file contents.
Expected: FAIL — `reconstruction phase status = error` (the ambiguous-column error).

- [ ] **Step 3: Write minimal implementation**

Create `supabase/migrations/20260616130000_fix_pipeline_ambiguous_column.sql`. Reproduce the current function body exactly, changing **only** the PHASE 2 SELECT:

```sql
-- Fix ambiguous column refs in PHASE 2: alias the reconstruct_journeys() call.
CREATE OR REPLACE FUNCTION public.process_rfid_pipeline(p_account_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(phase text, events_consolidated integer, incidents_created integer, segments_created integer, events_processed integer, execution_time_ms integer, status text, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_phase_start TIMESTAMPTZ;
    v_consolidation_result JSON;
    v_reconstruction_segments INTEGER;
    v_reconstruction_events INTEGER;
    v_assembly_created INTEGER;
    v_assembly_updated INTEGER;
    v_total_time INTEGER;
BEGIN
    v_start_time := clock_timestamp();

    -- PHASE 1: Consolidation
    v_phase_start := clock_timestamp();
    BEGIN
        v_consolidation_result := consolidate_rfid_events(p_account_id);
        RETURN QUERY SELECT
            'consolidation'::TEXT,
            (v_consolidation_result->>'events_created')::INTEGER,
            (v_consolidation_result->>'incidents_created')::INTEGER,
            0::INTEGER,
            (v_consolidation_result->>'events_processed')::INTEGER,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'success'::TEXT,
            format('Processed %s events', (v_consolidation_result->>'events_processed')::INTEGER)::TEXT;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT
            'consolidation'::TEXT, 0,0,0,0,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'error'::TEXT, SQLERRM::TEXT;
        RETURN;
    END;

    -- PHASE 2: Reconstruction
    v_phase_start := clock_timestamp();
    BEGIN
        SELECT rj.segments_created, rj.events_processed
        INTO v_reconstruction_segments, v_reconstruction_events
        FROM reconstruct_journeys(p_account_id) rj;

        RETURN QUERY SELECT
            'reconstruction'::TEXT,
            0,0,
            v_reconstruction_segments,
            v_reconstruction_events,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'success'::TEXT,
            format('Created %s segments', v_reconstruction_segments)::TEXT;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT
            'reconstruction'::TEXT, 0,0,0,0,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'error'::TEXT, SQLERRM::TEXT;
        RETURN;
    END;

    -- PHASE 3: Assembly
    v_phase_start := clock_timestamp();
    BEGIN
        SELECT
            (assemble_journeys(p_account_id)->>'journeys_created')::INTEGER,
            (assemble_journeys(p_account_id)->>'journeys_updated')::INTEGER
        INTO v_assembly_created, v_assembly_updated;

        RETURN QUERY SELECT
            'assembly'::TEXT, 0,0,0,
            v_assembly_created + v_assembly_updated,
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

    -- Summary
    v_total_time := EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_start_time))::INTEGER;
    RETURN QUERY SELECT
        'summary'::TEXT,
        (v_consolidation_result->>'events_created')::INTEGER,
        (v_consolidation_result->>'incidents_created')::INTEGER,
        v_reconstruction_segments,
        v_assembly_created + v_assembly_updated,
        v_total_time,
        'success'::TEXT,
        'Pipeline completed'::TEXT;
END;
$function$;
```

Apply via Supabase MCP `apply_migration` (name `fix_pipeline_ambiguous_column`). If blocked by the classifier, run the same SQL in the SQL Editor.

- [ ] **Step 4: Run test to verify it passes**

Re-run `supabase/tests/pipeline_ambiguous_column.test.sql` via `execute_sql`.
Expected: PASS (no rows / NOTICE `PASS`). Note: consolidation PHASE 1 may still report null counts until Task 3 — this test only checks the reconstruction phase no longer errors.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260616130000_fix_pipeline_ambiguous_column.sql supabase/tests/pipeline_ambiguous_column.test.sql
git commit -m "fix(etl): alias reconstruct_journeys() to resolve ambiguous segments_created in process_rfid_pipeline"
```

---

## Task 2: Allow `unknown_tag` in the `incidents` CHECK constraint

**Files:**
- Create: `supabase/migrations/20260616130100_incidents_allow_unknown_tag.sql`
- Test: `supabase/tests/incidents_unknown_tag.test.sql`

**Root cause:** `consolidate_rfid_events` inserts `incident_type = 'unknown_tag'`, but `incidents_incident_type_check` only permits `exit_before_entry, missing_entry, missing_exit, sla_violation, stuck_sample, missroute, duplicate_event, invalid_sequence, unknown_reader`. The insert violates the constraint, aborting the whole consolidation.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/incidents_unknown_tag.test.sql`:

```sql
-- The incidents CHECK constraint must allow 'unknown_tag' and still reject unknown values.
DO $$
DECLARE
  v_def text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO v_def
  FROM pg_constraint
  WHERE conrelid = 'public.incidents'::regclass
    AND conname = 'incidents_incident_type_check';

  IF v_def NOT LIKE '%unknown_tag%' THEN
    RAISE EXCEPTION 'FAIL: constraint does not allow unknown_tag: %', v_def;
  END IF;
  IF v_def NOT LIKE '%unknown_reader%' THEN
    RAISE EXCEPTION 'FAIL: constraint dropped unknown_reader: %', v_def;
  END IF;
  RAISE NOTICE 'PASS: incidents constraint allows unknown_tag';
END $$;
```

- [ ] **Step 2: Run test to verify it fails**

Run via `execute_sql`. Expected: FAIL — `constraint does not allow unknown_tag`.

- [ ] **Step 3: Write minimal implementation**

Create `supabase/migrations/20260616130100_incidents_allow_unknown_tag.sql`:

```sql
-- Allow 'unknown_tag' incidents (consolidate_rfid_events records them when a tag
-- has no ONE DB enrichment). Keep all previously-allowed values.
ALTER TABLE public.incidents DROP CONSTRAINT IF EXISTS incidents_incident_type_check;
ALTER TABLE public.incidents ADD CONSTRAINT incidents_incident_type_check
  CHECK (incident_type = ANY (ARRAY[
    'exit_before_entry','missing_entry','missing_exit','sla_violation',
    'stuck_sample','missroute','duplicate_event','invalid_sequence',
    'unknown_reader','unknown_tag'
  ]::text[]));
```

Apply via `apply_migration` (name `incidents_allow_unknown_tag`). If the classifier blocks it (constraint change), run the SQL in the SQL Editor.

- [ ] **Step 4: Run test to verify it passes**

Re-run `supabase/tests/incidents_unknown_tag.test.sql`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260616130100_incidents_allow_unknown_tag.sql supabase/tests/incidents_unknown_tag.test.sql
git commit -m "fix(etl): allow unknown_tag incident_type in incidents check constraint"
```

---

## Task 3: Capture non-ONE-DB tags + fix Mixed path + isolate per-tag errors

**Files:**
- Create: `supabase/migrations/20260616130200_consolidate_capture_non_onedb.sql`
- Test: `supabase/tests/consolidate_capture_non_onedb.test.sql`

**Changes to `consolidate_rfid_events`:**
1. **Reset `v_carrier_id`/`v_product_id` to NULL** at the top of each loop iteration (they are function-scoped and currently leak across tags).
2. **Non-ONE-DB tag → capture, don't skip.** Remove the `CONTINUE` in the "unknown tag" branch; record a `low` `unknown_tag` incident, then fall through to STEP 4 with NULL enrichment.
3. **Mixed reader path → actually insert.** Replace the broken 10-arg `PERFORM consolidate_mixed_reader_events(...)` with a loop over the existing 4-arg `consolidate_mixed_reader_events(account, tag, reader_code, gap)` that returns the entry/exit split, inserting one `processed_events` row per returned row (mirroring the Entry/Exit branches).
4. **Per-tag error isolation.** Wrap each iteration's work in a nested `BEGIN ... EXCEPTION WHEN OTHERS` that increments `v_errors` and logs a WARNING, so one bad tag no longer rolls back the whole account. Add `errors` to the result JSON.

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/consolidate_capture_non_onedb.test.sql`:

```sql
-- After consolidation, the DEMO2 test tags (not in one_db) must be CAPTURED:
-- raw rows marked processed, and processed_events created with NULL carrier.
DO $$
DECLARE
  v_result json;
  v_raw_pending int;
  v_processed int;
BEGIN
  v_result := public.consolidate_rfid_events('f4d823d2-93e6-4755-9a89-9da87e7fa86e');

  IF (v_result->>'success')::boolean IS NOT TRUE THEN
    RAISE EXCEPTION 'FAIL: consolidation returned success=false: %', v_result->>'error';
  END IF;

  SELECT count(*) INTO v_raw_pending
  FROM public.rfid_events_raw
  WHERE tag_id IN ('G.1UPU.01000FFFF00000007','G.1UPU.01000FFFF00000008')
    AND is_processed = false;
  IF v_raw_pending <> 0 THEN
    RAISE EXCEPTION 'FAIL: % raw test events still unprocessed', v_raw_pending;
  END IF;

  SELECT count(*) INTO v_processed
  FROM public.processed_events
  WHERE tag_id IN ('G.1UPU.01000FFFF00000007','G.1UPU.01000FFFF00000008')
    AND carrier_id IS NULL;
  IF v_processed < 1 THEN
    RAISE EXCEPTION 'FAIL: expected processed_events with NULL carrier for non-one_db tags, got %', v_processed;
  END IF;

  RAISE NOTICE 'PASS: non-one_db tags captured (% processed_events, NULL carrier)', v_processed;
END $$;
```

- [ ] **Step 2: Run test to verify it fails**

Run via `execute_sql`. Expected: FAIL — `success=false: new row for relation "incidents" violates check constraint` (if Task 2 not yet applied) or, once Task 2 is applied, `success=false` from the broken Mixed 10-arg call (`function consolidate_mixed_reader_events(...) does not exist`). Either way, red.

- [ ] **Step 3: Write minimal implementation**

Create `supabase/migrations/20260616130200_consolidate_capture_non_onedb.sql`:

```sql
CREATE OR REPLACE FUNCTION public.consolidate_rfid_events(p_account_id uuid)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_raw_event RECORD;
    v_reader_info RECORD;
    v_one_db_info RECORD;
    v_carrier_id UUID;
    v_product_id UUID;
    v_consolidated_event RECORD;
    v_analysis_datetime TIMESTAMPTZ;
    v_calculation_mode TEXT;
    v_gap_threshold_minutes INTEGER;
    v_events_processed INTEGER := 0;
    v_events_created INTEGER := 0;
    v_incidents_created INTEGER := 0;
    v_unknown_readers INTEGER := 0;
    v_unknown_tags INTEGER := 0;
    v_errors INTEGER := 0;
    v_start_time TIMESTAMPTZ := NOW();
BEGIN
    SELECT calculation_mode, gap_threshold_minutes
      INTO v_calculation_mode, v_gap_threshold_minutes
      FROM accounts WHERE id = p_account_id;
    v_calculation_mode := COALESCE(v_calculation_mode, 'natural_days');
    v_gap_threshold_minutes := COALESCE(v_gap_threshold_minutes, 30);

    FOR v_raw_event IN
        SELECT DISTINCT tag_id, reader_id
        FROM rfid_events_raw
        WHERE account_id = p_account_id AND is_processed = FALSE
        ORDER BY tag_id, reader_id
    LOOP
      BEGIN  -- per-tag isolation: one bad tag must not roll back the batch
        v_carrier_id := NULL;   -- reset per iteration (function-scoped vars leak otherwise)
        v_product_id := NULL;
        v_one_db_info := NULL;

        -- STEP 1: reader by LPI (must exist + be mapped to a postal center)
        SELECT r.id AS reader_uuid, r.reader_id AS reader_lpi, r.type AS reader_type,
               r.mixed_reader_gap_minutes,
               pc.id AS postal_center_id, pc.name AS postal_center_name,
               pc.code AS postal_center_code, pc.city AS postal_center_city,
               pc.calculation_mode AS postal_center_calculation_mode
          INTO v_reader_info
          FROM readers r
          JOIN postal_centers pc ON pc.id = r.postal_center_id
          WHERE r.reader_id = v_raw_event.reader_id AND r.account_id = p_account_id;

        IF v_reader_info.reader_uuid IS NULL THEN
            INSERT INTO incidents (account_id, tag_id, incident_type, severity, description, detected_at, metadata)
            VALUES (p_account_id, v_raw_event.tag_id, 'unknown_reader', 'low',
                    'Events detected from unknown reader LPI: ' || v_raw_event.reader_id, NOW(),
                    jsonb_build_object('reader_lpi', v_raw_event.reader_id, 'tag_id', v_raw_event.tag_id));
            v_unknown_readers := v_unknown_readers + 1;
            v_incidents_created := v_incidents_created + 1;
            UPDATE rfid_events_raw SET is_processed = TRUE
              WHERE account_id = p_account_id AND tag_id = v_raw_event.tag_id
                AND reader_id = v_raw_event.reader_id AND is_processed = FALSE;
            CONTINUE;
        END IF;

        -- STEP 2: optional ONE DB enrichment. Missing -> capture anyway (NULL enrichment).
        SELECT carrier_name, product_name, origin_city_name, destination_city_name
          INTO v_one_db_info
          FROM one_db
          WHERE tag_id = v_raw_event.tag_id AND account_id = p_account_id
          LIMIT 1;

        IF v_one_db_info.carrier_name IS NULL THEN
            INSERT INTO incidents (account_id, tag_id, incident_type, severity, description, detected_at, metadata)
            VALUES (p_account_id, v_raw_event.tag_id, 'unknown_tag', 'low',
                    'Tag not found in ONE DB; captured without enrichment: ' || v_raw_event.tag_id, NOW(),
                    jsonb_build_object('tag_id', v_raw_event.tag_id, 'reader_lpi', v_raw_event.reader_id));
            v_unknown_tags := v_unknown_tags + 1;
            v_incidents_created := v_incidents_created + 1;
            -- NO CONTINUE: fall through and consolidate with NULL carrier/product/cities.
        ELSE
            -- STEP 3: names -> ids (only when enriched)
            SELECT id INTO v_carrier_id FROM carriers
              WHERE name = v_one_db_info.carrier_name AND account_id = p_account_id LIMIT 1;
            SELECT id INTO v_product_id FROM products
              WHERE code = v_one_db_info.product_name AND carrier_id = v_carrier_id LIMIT 1;
        END IF;

        -- STEP 4: consolidate by reader type
        IF v_reader_info.reader_type = 'Entry' THEN
            FOR v_consolidated_event IN
                SELECT 'entry' AS event_type, MIN(read_local_datetime) AS timestamp, COUNT(*) AS raw_event_count
                FROM rfid_events_raw
                WHERE account_id = p_account_id AND tag_id = v_raw_event.tag_id
                  AND reader_id = v_raw_event.reader_id AND is_processed = FALSE
            LOOP
                IF v_reader_info.postal_center_calculation_mode = 'working_days' THEN
                    v_analysis_datetime := calculate_next_working_datetime(v_consolidated_event.timestamp, v_reader_info.postal_center_id);
                ELSE
                    v_analysis_datetime := v_consolidated_event.timestamp;
                END IF;
                INSERT INTO processed_events (account_id, tag_id, reader_id, reader_id_snapshot, reader_type_snapshot,
                    postal_center_id, postal_center_name_snapshot, postal_center_code_snapshot, postal_center_city_snapshot,
                    carrier_id, product_id, origin_city_name, destination_city_name, event_type, timestamp,
                    analysis_datetime, raw_event_count, is_consolidated, is_estimated)
                VALUES (p_account_id, v_raw_event.tag_id, v_reader_info.reader_uuid, v_reader_info.reader_lpi, v_reader_info.reader_type,
                    v_reader_info.postal_center_id, v_reader_info.postal_center_name, v_reader_info.postal_center_code, v_reader_info.postal_center_city,
                    v_carrier_id, v_product_id, v_one_db_info.origin_city_name, v_one_db_info.destination_city_name,
                    v_consolidated_event.event_type, v_consolidated_event.timestamp, v_analysis_datetime,
                    v_consolidated_event.raw_event_count, TRUE, FALSE);
                v_events_created := v_events_created + 1;
            END LOOP;

        ELSIF v_reader_info.reader_type = 'Exit' THEN
            FOR v_consolidated_event IN
                SELECT 'exit' AS event_type, MAX(read_local_datetime) AS timestamp, COUNT(*) AS raw_event_count
                FROM rfid_events_raw
                WHERE account_id = p_account_id AND tag_id = v_raw_event.tag_id
                  AND reader_id = v_raw_event.reader_id AND is_processed = FALSE
            LOOP
                INSERT INTO processed_events (account_id, tag_id, reader_id, reader_id_snapshot, reader_type_snapshot,
                    postal_center_id, postal_center_name_snapshot, postal_center_code_snapshot, postal_center_city_snapshot,
                    carrier_id, product_id, origin_city_name, destination_city_name, event_type, timestamp,
                    analysis_datetime, raw_event_count, is_consolidated, is_estimated)
                VALUES (p_account_id, v_raw_event.tag_id, v_reader_info.reader_uuid, v_reader_info.reader_lpi, v_reader_info.reader_type,
                    v_reader_info.postal_center_id, v_reader_info.postal_center_name, v_reader_info.postal_center_code, v_reader_info.postal_center_city,
                    v_carrier_id, v_product_id, v_one_db_info.origin_city_name, v_one_db_info.destination_city_name,
                    v_consolidated_event.event_type, v_consolidated_event.timestamp, v_consolidated_event.timestamp,
                    v_consolidated_event.raw_event_count, TRUE, FALSE);
                v_events_created := v_events_created + 1;
            END LOOP;

        ELSIF v_reader_info.reader_type = 'Mixed' THEN
            -- Use the existing 4-arg splitter and INSERT each returned row (like Entry/Exit).
            FOR v_consolidated_event IN
                SELECT * FROM consolidate_mixed_reader_events(
                    p_account_id, v_raw_event.tag_id, v_raw_event.reader_id,
                    COALESCE(v_reader_info.mixed_reader_gap_minutes, v_gap_threshold_minutes))
            LOOP
                IF v_consolidated_event.event_type = 'entry'
                   AND v_reader_info.postal_center_calculation_mode = 'working_days' THEN
                    v_analysis_datetime := calculate_next_working_datetime(v_consolidated_event.timestamp, v_reader_info.postal_center_id);
                ELSE
                    v_analysis_datetime := v_consolidated_event.timestamp;
                END IF;
                INSERT INTO processed_events (account_id, tag_id, reader_id, reader_id_snapshot, reader_type_snapshot,
                    postal_center_id, postal_center_name_snapshot, postal_center_code_snapshot, postal_center_city_snapshot,
                    carrier_id, product_id, origin_city_name, destination_city_name, event_type, timestamp,
                    analysis_datetime, raw_event_count, is_consolidated, is_estimated)
                VALUES (p_account_id, v_raw_event.tag_id, v_reader_info.reader_uuid, v_reader_info.reader_lpi, v_reader_info.reader_type,
                    v_reader_info.postal_center_id, v_reader_info.postal_center_name, v_reader_info.postal_center_code, v_reader_info.postal_center_city,
                    v_carrier_id, v_product_id, v_one_db_info.origin_city_name, v_one_db_info.destination_city_name,
                    v_consolidated_event.event_type, v_consolidated_event.timestamp, v_analysis_datetime,
                    v_consolidated_event.raw_event_count, TRUE, FALSE);
                v_events_created := v_events_created + 1;
            END LOOP;
        END IF;

        -- Mark raw events processed
        UPDATE rfid_events_raw SET is_processed = TRUE
          WHERE account_id = p_account_id AND tag_id = v_raw_event.tag_id
            AND reader_id = v_raw_event.reader_id AND is_processed = FALSE;
        v_events_processed := v_events_processed + 1;

      EXCEPTION WHEN OTHERS THEN
        v_errors := v_errors + 1;
        RAISE WARNING 'consolidate_rfid_events: tag % reader % failed: %',
            v_raw_event.tag_id, v_raw_event.reader_id, SQLERRM;
      END;
    END LOOP;

    RETURN json_build_object(
        'success', TRUE,
        'events_processed', v_events_processed,
        'events_created', v_events_created,
        'incidents_created', v_incidents_created,
        'unknown_readers', v_unknown_readers,
        'unknown_tags', v_unknown_tags,
        'errors', v_errors,
        'duration_seconds', EXTRACT(EPOCH FROM (NOW() - v_start_time))
    );
END;
$function$;
```

Apply via `apply_migration` (name `consolidate_capture_non_onedb`).

- [ ] **Step 4: Run test to verify it passes**

Re-run `supabase/tests/consolidate_capture_non_onedb.test.sql` via `execute_sql`.
Expected: PASS — `success=true`, 0 raw test events pending, ≥1 `processed_events` row with NULL carrier.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260616130200_consolidate_capture_non_onedb.sql supabase/tests/consolidate_capture_non_onedb.test.sql
git commit -m "feat(etl): capture non-ONE-DB tags, fix Mixed reader insert path, isolate per-tag errors in consolidate_rfid_events"
```

---

## Task 4: End-to-end verification + push

**Files:** none (verification only).

- [ ] **Step 1: Run the full pipeline for DEMO2**

Run via `execute_sql`:
```sql
SELECT phase, events_consolidated, segments_created, events_processed, status, message
FROM public.process_rfid_pipeline('f4d823d2-93e6-4755-9a89-9da87e7fa86e');
```
Expected: every phase `status = success`; consolidation `events_processed >= 2`.

- [ ] **Step 2: Confirm final placement of the 6 test events**

Run via `execute_sql`:
```sql
SELECT
  (SELECT count(*) FROM rfid_events_raw WHERE tag_id IN ('G.1UPU.01000FFFF00000007','G.1UPU.01000FFFF00000008') AND is_processed=false) AS raw_pending,
  (SELECT count(*) FROM processed_events WHERE tag_id IN ('G.1UPU.01000FFFF00000007','G.1UPU.01000FFFF00000008')) AS processed_events,
  (SELECT count(*) FROM journey_segments WHERE tag_id IN ('G.1UPU.01000FFFF00000007','G.1UPU.01000FFFF00000008')) AS segments;
```
Expected: `raw_pending = 0`, `processed_events >= 2`, `segments = 0` (correct — see Decision 4; entries at one Mixed reader cannot form a journey).

- [ ] **Step 3: Push the branch**

Requires explicit user confirmation before pushing to `develop`.
```bash
git push origin develop
```

---

## Self-Review

**1. Spec coverage:**
- (1) constraint `unknown_tag` → Task 2. ✓
- (2) ambiguous `segments_created` → Task 1 (corrected: lives in `process_rfid_pipeline`). ✓
- (3) per-tag error isolation → Task 3, change 4. ✓
- (4) Mixed path (10-arg vs 4-arg, no insert) → Task 3, change 3. ✓
- (5) capture non-ONE-DB tags → Task 3, change 2. ✓
- Verification with the 6 DEMO2 events → Tasks 3 (test) + 4 (e2e). ✓

**2. Placeholder scan:** No TBD/TODO/"handle edge cases"; all functions reproduced in full; all SQL concrete. ✓

**3. Type/name consistency:** `consolidate_mixed_reader_events(uuid,text,text,integer)` matches the deployed 4-arg signature; result JSON keys (`events_processed`, `events_created`, `incidents_created`) match what `process_rfid_pipeline` reads; `rj.segments_created`/`rj.events_processed` match `reconstruct_journeys`'s OUT columns. ✓
