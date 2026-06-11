# RFID AWS Provider Ingestion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture RFID reads incrementally from the AWS provider API every 30 minutes, normalize them into the schema the ETL expects, and chain the ETL pipeline immediately after each capture.

**Architecture:** A landing table (`rfid_provider_reads`) receives provider records verbatim (idempotent by provider `id`). A resolver RPC normalizes `tagId` and resolves `account_id` from `readerId`, inserting matched reads into `rfid_events_raw`. An Edge Function (`rfid-provider-poll`) polls the AWS API with an incremental cursor, upserts to the landing table, then calls the resolver and finally the ETL pipeline. A `pg_cron` job triggers the function every 30 minutes.

**Tech Stack:** Supabase Postgres (PL/pgSQL functions, migrations), `pg_cron` + `pg_net`, Deno Edge Function (TypeScript). No local Supabase CLI or test harness: migrations applied via Supabase MCP `apply_migration`, Edge Functions via `deploy_edge_function`, SQL assertions run via `execute_sql`, Edge helper unit tests via `deno test`.

**Project:** `onems-dev` (`sehbnpgzqljrsqimwyuz`). Spec: [docs/superpowers/specs/2026-06-11-rfid-aws-ingestion-design.md](../specs/2026-06-11-rfid-aws-ingestion-design.md).

---

## Conventions for this plan

- **"Apply migration"** = call Supabase MCP `apply_migration` with the migration name and the SQL body, AND save the same SQL to `supabase/migrations/<timestamp>_<name>.sql` so the repo stays the source of truth. Use timestamp format `YYYYMMDDHHMMSS` (e.g. `20260611120000`). Use a strictly increasing timestamp per migration in this plan.
- **"Run SQL test"** = call Supabase MCP `execute_sql` with the test script against `onems-dev`. A test PASSES if it returns without raising; it FAILS if a `RAISE EXCEPTION` fires.
- **"Deploy function"** = call Supabase MCP `deploy_edge_function` for `rfid-provider-poll`.
- All test fixtures use the marker prefix `ZZTEST-` so cleanup is unambiguous. Test scripts wrap fixtures in `BEGIN; … ROLLBACK;` so nothing persists.
- Commit after each task. Branch: `develop` (team commits directly to develop).

---

## File Structure

- `supabase/migrations/20260611120000_rfid_provider_landing.sql` — Create `rfid_provider_reads` and `rfid_ingest_state` tables + indexes + CHECK.
- `supabase/migrations/20260611120100_normalize_provider_tag.sql` — `normalize_provider_tag(text) returns text`.
- `supabase/migrations/20260611120200_resolve_provider_reads.sql` — `resolve_provider_reads() returns table(...)`.
- `supabase/migrations/20260611120300_rfid_poll_cron.sql` — Unschedule 15-min pipeline cron; schedule 30-min poll cron via `pg_net`.
- `supabase/tests/normalize_provider_tag.test.sql` — SQL assertions for the normalizer.
- `supabase/tests/resolve_provider_reads.test.sql` — SQL assertions for the resolver (fixtures + ROLLBACK).
- `supabase/functions/rfid-provider-poll/lib.ts` — Pure helpers (URL building, record validation, Retry-After parsing, landing-row mapping).
- `supabase/functions/rfid-provider-poll/lib.test.ts` — Deno unit tests for `lib.ts`.
- `supabase/functions/rfid-provider-poll/index.ts` — Edge Function orchestration (auth, poll loop, chain resolver + ETL).
- `docs/ETL/ETL_RFID_PIPELINE_TECNICO.md` — Update §2 to document the new ingestion path and mark `rpc_ingest_epcis_events` legacy.

---

## Task 1: Landing + state tables

**Files:**
- Create: `supabase/migrations/20260611120000_rfid_provider_landing.sql`
- Test: `supabase/tests/landing_tables.test.sql`

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/landing_tables.test.sql`:

```sql
-- Verifies the landing + state tables exist with the expected columns/constraints.
DO $$
BEGIN
  IF to_regclass('public.rfid_provider_reads') IS NULL THEN
    RAISE EXCEPTION 'FAIL: rfid_provider_reads does not exist';
  END IF;
  IF to_regclass('public.rfid_ingest_state') IS NULL THEN
    RAISE EXCEPTION 'FAIL: rfid_ingest_state does not exist';
  END IF;
  -- match_status CHECK present
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.rfid_provider_reads'::regclass
      AND contype = 'c' AND conname = 'rfid_provider_reads_match_status_chk'
  ) THEN
    RAISE EXCEPTION 'FAIL: match_status CHECK constraint missing';
  END IF;
  -- id is primary key (idempotency)
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.rfid_provider_reads'::regclass AND contype = 'p'
  ) THEN
    RAISE EXCEPTION 'FAIL: rfid_provider_reads has no primary key';
  END IF;
  RAISE NOTICE 'PASS: landing tables present';
END $$;
```

- [ ] **Step 2: Run test to verify it fails**

Run SQL test: `supabase/tests/landing_tables.test.sql` against `onems-dev`.
Expected: FAIL with `rfid_provider_reads does not exist`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260611120000_rfid_provider_landing.sql`:

```sql
-- =====================================================
-- RFID AWS Provider Ingestion: landing + state tables
-- =====================================================

CREATE TABLE IF NOT EXISTS public.rfid_provider_reads (
  id                   uuid PRIMARY KEY,                 -- provider 'id' (idempotency)
  location             text,                             -- raw "Country | City | Site | State"
  reader_id            text NOT NULL,                    -- provider readerId
  tag_id_raw           text NOT NULL,                    -- provider tagId, verbatim
  read_local_datetime  timestamptz NOT NULL,             -- provider timestamp
  ingested_at          timestamptz NOT NULL,             -- provider ingested_at (cursor traceability)
  tag_id_normalized    text,                             -- set by resolver
  resolved_account_id  uuid REFERENCES public.accounts(id) ON DELETE SET NULL,
  match_status         text NOT NULL DEFAULT 'pending',
  unmatch_reason       text,
  rfid_events_raw_id   uuid,                             -- traceability to inserted raw row
  created_at           timestamptz NOT NULL DEFAULT now(),
  resolved_at          timestamptz,
  CONSTRAINT rfid_provider_reads_match_status_chk
    CHECK (match_status IN ('pending','matched','unknown_reader','tag_decode_failed'))
);

CREATE INDEX IF NOT EXISTS idx_rfid_provider_reads_match_status
  ON public.rfid_provider_reads (match_status);
CREATE INDEX IF NOT EXISTS idx_rfid_provider_reads_reader_id
  ON public.rfid_provider_reads (reader_id);
CREATE INDEX IF NOT EXISTS idx_rfid_provider_reads_ingested_at
  ON public.rfid_provider_reads (ingested_at);

CREATE TABLE IF NOT EXISTS public.rfid_ingest_state (
  id              text PRIMARY KEY,            -- e.g. 'aws-rfid-read-api'
  next_cursor     text,
  last_since      timestamptz,
  backfill_since  timestamptz,                 -- first-run start date (config)
  last_run_at     timestamptz,
  last_status     text,                        -- 'ok' | 'error' | 'rate_limited'
  last_error      text,
  total_fetched   bigint NOT NULL DEFAULT 0,
  last_fetched    integer NOT NULL DEFAULT 0,
  last_matched    integer NOT NULL DEFAULT 0,
  last_unmatched  integer NOT NULL DEFAULT 0,
  updated_at      timestamptz NOT NULL DEFAULT now()
);

-- Seed the single source row. backfill_since left NULL until decided (spec §8.4);
-- the Edge Function treats NULL backfill_since by defaulting to now() - 24 months on first run.
INSERT INTO public.rfid_ingest_state (id)
VALUES ('aws-rfid-read-api')
ON CONFLICT (id) DO NOTHING;
```

- [ ] **Step 4: Apply migration and re-run test**

Apply migration `20260611120000_rfid_provider_landing`, then run SQL test `supabase/tests/landing_tables.test.sql`.
Expected: PASS (`PASS: landing tables present`).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260611120000_rfid_provider_landing.sql supabase/tests/landing_tables.test.sql
git commit -m "feat(etl): add RFID provider landing + ingest-state tables"
```

---

## Task 2: `normalize_provider_tag()`

> **Note (spec §8.1):** the exact `urn:oid → EPC hex` rule is unconfirmed by the provider. This is the **provisional v1 rule**: hex input passes through (uppercased); a `urn:oid:` value yields its last dot-separated token if that token is hex, else NULL; anything else NULL. The function is the single point to change once Stefan confirms.

**Files:**
- Create: `supabase/migrations/20260611120100_normalize_provider_tag.sql`
- Test: `supabase/tests/normalize_provider_tag.test.sql`

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/normalize_provider_tag.test.sql`:

```sql
DO $$
BEGIN
  -- urn:oid sample → last token, uppercased
  IF normalize_provider_tag('urn:oid:1.0.15961.14.B.A00122245737') IS DISTINCT FROM 'A00122245737' THEN
    RAISE EXCEPTION 'FAIL: urn:oid decode, got %', normalize_provider_tag('urn:oid:1.0.15961.14.B.A00122245737');
  END IF;
  -- already-hex passthrough, uppercased
  IF normalize_provider_tag('30b1d226a8240000b000650c') IS DISTINCT FROM '30B1D226A8240000B000650C' THEN
    RAISE EXCEPTION 'FAIL: hex passthrough';
  END IF;
  -- whitespace trimmed
  IF normalize_provider_tag('  01000FFFF12345635  ') IS DISTINCT FROM '01000FFFF12345635' THEN
    RAISE EXCEPTION 'FAIL: trim';
  END IF;
  -- non-hex urn last token → NULL
  IF normalize_provider_tag('urn:oid:1.0.15961.14.B.NOTHEX!!') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: non-hex urn token should be NULL';
  END IF;
  -- garbage → NULL
  IF normalize_provider_tag('hello world') IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: garbage should be NULL';
  END IF;
  -- NULL in → NULL out
  IF normalize_provider_tag(NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: NULL should be NULL';
  END IF;
  RAISE NOTICE 'PASS: normalize_provider_tag';
END $$;
```

- [ ] **Step 2: Run test to verify it fails**

Run SQL test `supabase/tests/normalize_provider_tag.test.sql`.
Expected: FAIL with `function normalize_provider_tag(...) does not exist`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260611120100_normalize_provider_tag.sql`:

```sql
-- =====================================================
-- normalize_provider_tag: provider tagId -> EPC hex (provisional v1, spec §8.1)
-- =====================================================
CREATE OR REPLACE FUNCTION public.normalize_provider_tag(p_raw text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v text;
  v_candidate text;
BEGIN
  IF p_raw IS NULL THEN
    RETURN NULL;
  END IF;
  v := trim(p_raw);
  IF v = '' THEN
    RETURN NULL;
  END IF;

  -- Already a hex EPC string -> uppercase passthrough
  IF v ~ '^[0-9A-Fa-f]+$' THEN
    RETURN upper(v);
  END IF;

  -- urn:oid form -> take the last dot-separated token if it is hex
  IF lower(v) LIKE 'urn:oid:%' THEN
    v_candidate := split_part(v, '.', array_length(string_to_array(v, '.'), 1));
    IF v_candidate ~ '^[0-9A-Fa-f]+$' THEN
      RETURN upper(v_candidate);
    END IF;
    RETURN NULL;
  END IF;

  -- Unrecognized format
  RETURN NULL;
END $$;

COMMENT ON FUNCTION public.normalize_provider_tag(text) IS
'Normalizes a provider tagId to EPC hex. PROVISIONAL v1 rule (spec §8.1): hex passthrough; urn:oid last token if hex; else NULL. Confirm exact rule with provider (Stefan Gelov).';
```

- [ ] **Step 4: Apply migration and re-run test**

Apply migration `20260611120100_normalize_provider_tag`, then run the SQL test.
Expected: PASS (`PASS: normalize_provider_tag`).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260611120100_normalize_provider_tag.sql supabase/tests/normalize_provider_tag.test.sql
git commit -m "feat(etl): add normalize_provider_tag (provisional urn:oid->EPC hex)"
```

---

## Task 3: `resolve_provider_reads()`

**Files:**
- Create: `supabase/migrations/20260611120200_resolve_provider_reads.sql`
- Test: `supabase/tests/resolve_provider_reads.test.sql`

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/resolve_provider_reads.test.sql`. It seeds a test reader + three landing rows inside a transaction, runs the resolver, asserts, and ROLLBACKs so nothing persists:

```sql
BEGIN;

-- Pick any existing account to attach a test reader to.
DO $$
DECLARE
  v_account uuid;
  v_matched_event text;
  v_status text;
  v_raw_count int;
BEGIN
  SELECT id INTO v_account FROM public.accounts ORDER BY name LIMIT 1;
  IF v_account IS NULL THEN
    RAISE EXCEPTION 'FAIL: no accounts to test against';
  END IF;

  -- Fixture reader (matches the LPI of one landing row)
  INSERT INTO public.readers (id, account_id, reader_id, name, type, is_active)
  VALUES (gen_random_uuid(), v_account, 'ZZTEST-READER-01', 'ZZTEST reader', 'Entry', true);

  -- Landing rows: 1 matched, 1 unknown_reader, 1 tag_decode_failed
  INSERT INTO public.rfid_provider_reads
    (id, location, reader_id, tag_id_raw, read_local_datetime, ingested_at, match_status)
  VALUES
    (gen_random_uuid(), 'BR | X | Y | GO', 'ZZTEST-READER-01',
     'urn:oid:1.0.15961.14.B.A00122245737', now(), now(), 'pending'),
    (gen_random_uuid(), 'BR | X | Y | GO', 'ZZTEST-UNKNOWN-READER',
     '30B1D226A8240000B000650C', now(), now(), 'pending'),
    (gen_random_uuid(), 'BR | X | Y | GO', 'ZZTEST-READER-01',
     'urn:oid:1.0.15961.14.B.NOTHEX!!', now(), now(), 'pending');

  PERFORM public.resolve_provider_reads();

  -- matched row inserted into rfid_events_raw with normalized tag
  SELECT count(*) INTO v_raw_count FROM public.rfid_events_raw
    WHERE account_id = v_account AND tag_id = 'A00122245737';
  IF v_raw_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: expected 1 matched raw row, got %', v_raw_count;
  END IF;

  SELECT match_status INTO v_status FROM public.rfid_provider_reads
    WHERE reader_id='ZZTEST-READER-01' AND tag_id_raw LIKE '%A00122245737';
  IF v_status <> 'matched' THEN
    RAISE EXCEPTION 'FAIL: expected matched, got %', v_status;
  END IF;

  SELECT match_status INTO v_status FROM public.rfid_provider_reads
    WHERE reader_id='ZZTEST-UNKNOWN-READER';
  IF v_status <> 'unknown_reader' THEN
    RAISE EXCEPTION 'FAIL: expected unknown_reader, got %', v_status;
  END IF;

  SELECT match_status INTO v_status FROM public.rfid_provider_reads
    WHERE tag_id_raw LIKE '%NOTHEX%';
  IF v_status <> 'tag_decode_failed' THEN
    RAISE EXCEPTION 'FAIL: expected tag_decode_failed, got %', v_status;
  END IF;

  -- Idempotency: a second run inserts no duplicate raw rows
  PERFORM public.resolve_provider_reads();
  SELECT count(*) INTO v_raw_count FROM public.rfid_events_raw
    WHERE account_id = v_account AND tag_id = 'A00122245737';
  IF v_raw_count <> 1 THEN
    RAISE EXCEPTION 'FAIL: idempotency broken, got % raw rows', v_raw_count;
  END IF;

  RAISE NOTICE 'PASS: resolve_provider_reads';
END $$;

ROLLBACK;
```

- [ ] **Step 2: Run test to verify it fails**

Run SQL test `supabase/tests/resolve_provider_reads.test.sql`.
Expected: FAIL with `function public.resolve_provider_reads() does not exist` (or similar).

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260611120200_resolve_provider_reads.sql`:

```sql
-- =====================================================
-- resolve_provider_reads: landing -> rfid_events_raw (account + tag resolution)
-- =====================================================
CREATE OR REPLACE FUNCTION public.resolve_provider_reads()
RETURNS TABLE (
  processed         integer,
  matched           integer,
  unknown_reader    integer,
  tag_decode_failed integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
  v_account uuid;
  v_norm text;
  v_raw_id uuid;
  c_processed integer := 0;
  c_matched integer := 0;
  c_unknown integer := 0;
  c_decode integer := 0;
BEGIN
  FOR r IN
    SELECT * FROM public.rfid_provider_reads
    WHERE match_status IN ('pending','unknown_reader','tag_decode_failed')
    ORDER BY ingested_at
  LOOP
    c_processed := c_processed + 1;

    v_norm := public.normalize_provider_tag(r.tag_id_raw);

    SELECT account_id INTO v_account
    FROM public.readers
    WHERE reader_id = r.reader_id AND deleted_at IS NULL
    LIMIT 1;

    IF v_account IS NULL THEN
      UPDATE public.rfid_provider_reads
      SET match_status='unknown_reader',
          unmatch_reason='reader_id not found in readers catalog',
          tag_id_normalized=v_norm,
          resolved_at=now()
      WHERE id = r.id;
      c_unknown := c_unknown + 1;
      CONTINUE;
    END IF;

    IF v_norm IS NULL THEN
      UPDATE public.rfid_provider_reads
      SET match_status='tag_decode_failed',
          unmatch_reason='could not normalize tagId to EPC hex',
          resolved_account_id=v_account,
          resolved_at=now()
      WHERE id = r.id;
      c_decode := c_decode + 1;
      CONTINUE;
    END IF;

    INSERT INTO public.rfid_events_raw
      (account_id, event_id, read_local_datetime, reader_id, tag_id, is_processed)
    VALUES
      (v_account, r.id::text, r.read_local_datetime, r.reader_id, v_norm, false)
    ON CONFLICT (account_id, event_id) DO NOTHING
    RETURNING id INTO v_raw_id;

    IF v_raw_id IS NULL THEN
      SELECT id INTO v_raw_id FROM public.rfid_events_raw
      WHERE account_id = v_account AND event_id = r.id::text;
    END IF;

    UPDATE public.rfid_provider_reads
    SET match_status='matched',
        resolved_account_id=v_account,
        tag_id_normalized=v_norm,
        rfid_events_raw_id=v_raw_id,
        unmatch_reason=NULL,
        resolved_at=now()
    WHERE id = r.id;
    c_matched := c_matched + 1;
  END LOOP;

  RETURN QUERY SELECT c_processed, c_matched, c_unknown, c_decode;
END $$;

REVOKE ALL ON FUNCTION public.resolve_provider_reads() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_provider_reads() TO service_role;

COMMENT ON FUNCTION public.resolve_provider_reads() IS
'Resolves landing rows (rfid_provider_reads) into rfid_events_raw: normalizes tagId, resolves account_id from readerId. Reprocesses pending/unknown_reader/tag_decode_failed rows (auto-heals as catalog/decode improve).';
```

- [ ] **Step 4: Apply migration and re-run test**

Apply migration `20260611120200_resolve_provider_reads`, then run the SQL test.
Expected: PASS (`PASS: resolve_provider_reads`). Confirm no `ZZTEST-` rows persist:

Run SQL: `SELECT count(*) FROM readers WHERE reader_id LIKE 'ZZTEST-%';` → expected `0` (ROLLBACK discarded fixtures).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260611120200_resolve_provider_reads.sql supabase/tests/resolve_provider_reads.test.sql
git commit -m "feat(etl): add resolve_provider_reads (landing -> rfid_events_raw)"
```

---

## Task 4: Edge Function pure helpers (`lib.ts`)

**Files:**
- Create: `supabase/functions/rfid-provider-poll/lib.ts`
- Test: `supabase/functions/rfid-provider-poll/lib.test.ts`

- [ ] **Step 1: Write the failing test**

Create `supabase/functions/rfid-provider-poll/lib.test.ts`:

```typescript
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { buildReadsUrl, parseRetryAfter, isValidRecord, toLandingRow } from './lib.ts'

Deno.test('buildReadsUrl uses cursor when present', () => {
  const url = buildReadsUrl('https://api.example.com/v1/reads', { cursor: 'abc', limit: 1000 })
  assertEquals(url, 'https://api.example.com/v1/reads?cursor=abc&limit=1000')
})

Deno.test('buildReadsUrl uses since when no cursor', () => {
  const url = buildReadsUrl('https://api.example.com/v1/reads', { since: '2024-01-01T00:00:00Z', limit: 500 })
  assertEquals(url, 'https://api.example.com/v1/reads?since=2024-01-01T00%3A00%3A00Z&limit=500')
})

Deno.test('parseRetryAfter parses seconds, defaults on garbage', () => {
  assertEquals(parseRetryAfter('5'), 5)
  assertEquals(parseRetryAfter(null), 1)
  assertEquals(parseRetryAfter('not-a-number'), 1)
})

Deno.test('isValidRecord requires tagId and location', () => {
  assertEquals(isValidRecord({ id: '1', tagId: 't', location: 'a|b|c|d', readerId: 'r', timestamp: 'x', ingested_at: 'y' }), true)
  assertEquals(isValidRecord({ id: '1', tagId: '', location: 'a', readerId: 'r', timestamp: 'x', ingested_at: 'y' }), false)
  assertEquals(isValidRecord({ id: '1', location: 'a', readerId: 'r', timestamp: 'x', ingested_at: 'y' } as never), false)
})

Deno.test('toLandingRow maps provider record to DB columns', () => {
  const row = toLandingRow({
    id: '1a66a44f-c905-4ac4-a8b0-3d1811ef86f0',
    location: 'Brazil | X | Y | GO',
    readerId: 'J11DBRA02100000319',
    tagId: 'urn:oid:1.0.15961.14.B.A00122245737',
    timestamp: '2024-05-07T09:53:06.238-03:00',
    ingested_at: '2024-05-07T12:53:08.412Z',
  })
  assertEquals(row, {
    id: '1a66a44f-c905-4ac4-a8b0-3d1811ef86f0',
    location: 'Brazil | X | Y | GO',
    reader_id: 'J11DBRA02100000319',
    tag_id_raw: 'urn:oid:1.0.15961.14.B.A00122245737',
    read_local_datetime: '2024-05-07T09:53:06.238-03:00',
    ingested_at: '2024-05-07T12:53:08.412Z',
    match_status: 'pending',
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `deno test supabase/functions/rfid-provider-poll/lib.test.ts --allow-net`
Expected: FAIL — `Module not found "lib.ts"`.

- [ ] **Step 3: Write the implementation**

Create `supabase/functions/rfid-provider-poll/lib.ts`:

```typescript
export interface ProviderRecord {
  id: string
  location: string
  readerId: string
  tagId: string
  timestamp: string
  ingested_at: string
}

export interface LandingRow {
  id: string
  location: string
  reader_id: string
  tag_id_raw: string
  read_local_datetime: string
  ingested_at: string
  match_status: 'pending'
}

/** Build the reads URL. Exactly one of cursor|since is sent (cursor wins). */
export function buildReadsUrl(
  baseUrl: string,
  opts: { cursor?: string | null; since?: string | null; limit: number },
): string {
  const params = new URLSearchParams()
  if (opts.cursor) {
    params.set('cursor', opts.cursor)
  } else if (opts.since) {
    params.set('since', opts.since)
  }
  params.set('limit', String(opts.limit))
  return `${baseUrl}?${params.toString()}`
}

/** Parse Retry-After header (seconds). Defaults to 1s on missing/invalid. */
export function parseRetryAfter(headerValue: string | null): number {
  if (!headerValue) return 1
  const n = parseInt(headerValue, 10)
  return Number.isFinite(n) && n > 0 ? n : 1
}

/** Provider guarantees tagId + location populated; defend anyway. */
export function isValidRecord(rec: ProviderRecord): boolean {
  return Boolean(rec && rec.id && rec.tagId && rec.location)
}

export function toLandingRow(rec: ProviderRecord): LandingRow {
  return {
    id: rec.id,
    location: rec.location,
    reader_id: rec.readerId,
    tag_id_raw: rec.tagId,
    read_local_datetime: rec.timestamp,
    ingested_at: rec.ingested_at,
    match_status: 'pending',
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `deno test supabase/functions/rfid-provider-poll/lib.test.ts --allow-net`
Expected: PASS (5 tests ok).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/rfid-provider-poll/lib.ts supabase/functions/rfid-provider-poll/lib.test.ts
git commit -m "feat(etl): add rfid-provider-poll pure helpers + unit tests"
```

---

## Task 5: Edge Function orchestration (`index.ts`)

**Files:**
- Create: `supabase/functions/rfid-provider-poll/index.ts`

> No automated test for the orchestration (no local Supabase function harness). It is validated by the manual smoke test in Task 7. The pure logic it relies on is already covered by Task 4.

- [ ] **Step 1: Write the implementation**

Create `supabase/functions/rfid-provider-poll/index.ts`:

```typescript
// =====================================================
// rfid-provider-poll: incremental capture from AWS RFID Read API,
// then resolve landing rows and run the ETL pipeline. (spec 2026-06-11)
// =====================================================
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { buildReadsUrl, parseRetryAfter, isValidRecord, toLandingRow, ProviderRecord } from './lib.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const SOURCE_ID = 'aws-rfid-read-api'
const PAGE_LIMIT = 1000
const MAX_PAGES_PER_RUN = 20          // up to 20k records/run; protects rate limit + function timeout
const MAX_RETRIES = 4

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms))

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // Auth: cron secret (same pattern as consolidate-rfid-events-cron)
  const authHeader = req.headers.get('Authorization')
  const cronSecret = Deno.env.get('CRON_SECRET')
  if (!authHeader || authHeader !== `Bearer ${cronSecret}`) {
    return jsonResponse({ error: 'Unauthorized' }, 401)
  }

  const apiUrl = Deno.env.get('RFID_PROVIDER_API_URL')
  const apiKey = Deno.env.get('RFID_PROVIDER_API_KEY')
  if (!apiUrl || !apiKey) {
    return jsonResponse({ error: 'Missing RFID_PROVIDER_API_URL / RFID_PROVIDER_API_KEY' }, 500)
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
  )

  // 1. Load ingest state
  const { data: state, error: stateErr } = await supabase
    .from('rfid_ingest_state')
    .select('*')
    .eq('id', SOURCE_ID)
    .single()
  if (stateErr || !state) {
    return jsonResponse({ error: 'ingest_state row missing', details: stateErr?.message }, 500)
  }

  let cursor: string | null = state.next_cursor
  // First run: use since (backfill_since, or 24 months ago as a safe default — spec §8.4)
  let since: string | null = null
  if (!cursor) {
    since = state.backfill_since
      ?? new Date(Date.now() - 24 * 30 * 24 * 60 * 60 * 1000).toISOString()
  }

  let totalFetched = 0
  let pages = 0
  let rateLimited = false

  try {
    while (pages < MAX_PAGES_PER_RUN) {
      const url = buildReadsUrl(apiUrl, { cursor, since, limit: PAGE_LIMIT })

      // Fetch with retry/backoff
      let resp: Response | null = null
      for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
        resp = await fetch(url, { headers: { 'x-api-key': apiKey } })
        if (resp.status === 429) {
          rateLimited = true
          await sleep(parseRetryAfter(resp.headers.get('Retry-After')) * 1000)
          continue
        }
        if (resp.status >= 500) {
          await sleep(Math.min(2 ** attempt, 8) * 1000)
          continue
        }
        break
      }
      if (!resp) throw new Error('no response from provider')
      if (resp.status === 401 || resp.status === 403) {
        throw new Error(`provider auth error ${resp.status}`)
      }
      if (!resp.ok) {
        throw new Error(`provider error ${resp.status}: ${await resp.text()}`)
      }

      const payload = await resp.json() as { data: ProviderRecord[]; next_cursor: string | null }
      const records = (payload.data ?? []).filter(isValidRecord)

      if (records.length > 0) {
        const rows = records.map(toLandingRow)
        const { error: upsertErr } = await supabase
          .from('rfid_provider_reads')
          .upsert(rows, { onConflict: 'id', ignoreDuplicates: true })
        if (upsertErr) throw new Error(`landing upsert failed: ${upsertErr.message}`)
        totalFetched += records.length
      }

      // Advance + persist high-water mark after every page (resumable)
      cursor = payload.next_cursor
      since = null
      await supabase.from('rfid_ingest_state').update({
        next_cursor: cursor,
        last_since: state.backfill_since,
        updated_at: new Date().toISOString(),
      }).eq('id', SOURCE_ID)

      pages++
      if (!cursor) break          // caught up
    }

    // 2. Resolve landing rows into rfid_events_raw
    const { data: resolved, error: resolveErr } = await supabase.rpc('resolve_provider_reads')
    if (resolveErr) throw new Error(`resolve_provider_reads failed: ${resolveErr.message}`)
    const res = Array.isArray(resolved) ? resolved[0] : resolved

    // 3. Run the ETL pipeline (sequential, after capture)
    const { data: pipeline, error: pipelineErr } = await supabase.rpc('process_all_accounts_pipeline')
    if (pipelineErr) throw new Error(`process_all_accounts_pipeline failed: ${pipelineErr.message}`)

    // 4. Persist run stats
    await supabase.from('rfid_ingest_state').update({
      last_run_at: new Date().toISOString(),
      last_status: rateLimited ? 'rate_limited' : 'ok',
      last_error: null,
      total_fetched: (state.total_fetched ?? 0) + totalFetched,
      last_fetched: totalFetched,
      last_matched: res?.matched ?? 0,
      last_unmatched: (res?.unknown_reader ?? 0) + (res?.tag_decode_failed ?? 0),
      updated_at: new Date().toISOString(),
    }).eq('id', SOURCE_ID)

    return jsonResponse({
      success: true,
      fetched: totalFetched,
      pages,
      resolve: res,
      pipeline_accounts: Array.isArray(pipeline) ? pipeline.length : 0,
    })
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    await supabase.from('rfid_ingest_state').update({
      last_run_at: new Date().toISOString(),
      last_status: 'error',
      last_error: message,
      updated_at: new Date().toISOString(),
    }).eq('id', SOURCE_ID)
    return jsonResponse({ success: false, error: message }, 500)
  }
})
```

- [ ] **Step 2: Type-check the function**

Run: `deno check supabase/functions/rfid-provider-poll/index.ts`
Expected: no type errors.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/rfid-provider-poll/index.ts
git commit -m "feat(etl): add rfid-provider-poll edge function (capture -> resolve -> ETL)"
```

---

## Task 6: Cron — unschedule 15-min pipeline, schedule 30-min poll

> **Manual prerequisites (do these first, document outcomes):**
> 1. **Edge Function secrets** (Supabase Dashboard → Edge Functions → `rfid-provider-poll` → Secrets, or via API): set `RFID_PROVIDER_API_URL`, `RFID_PROVIDER_API_KEY`, `CRON_SECRET`. The API key must be the (preferably rotated — spec §9) provider key, never committed.
> 2. **Vault secrets** for the cron HTTP call: create `rfid_poll_function_url` (the deployed function URL) and `rfid_poll_cron_secret` (same value as `CRON_SECRET`) in Supabase Vault.
> 3. Ensure `pg_net` and `pg_cron` extensions are enabled.

**Files:**
- Create: `supabase/migrations/20260611120300_rfid_poll_cron.sql`
- Test: `supabase/tests/poll_cron.test.sql`

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/poll_cron.test.sql`:

```sql
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rfid-pipeline-every-15min') THEN
    RAISE EXCEPTION 'FAIL: 15-min pipeline cron still scheduled';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM cron.job
    WHERE jobname = 'rfid-provider-poll-every-30min' AND schedule = '*/30 * * * *'
  ) THEN
    RAISE EXCEPTION 'FAIL: 30-min poll cron not scheduled';
  END IF;
  RAISE NOTICE 'PASS: cron jobs configured';
END $$;
```

- [ ] **Step 2: Run test to verify it fails**

Run SQL test `supabase/tests/poll_cron.test.sql`.
Expected: FAIL — either the 15-min job still exists or the 30-min job is missing.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260611120300_rfid_poll_cron.sql`:

```sql
-- =====================================================
-- Cron: replace 15-min ETL-only pipeline with a 30-min capture->ETL poll.
-- The ETL now runs INSIDE the edge function, after capture.
-- =====================================================
DO $$
DECLARE
  v_url text;
  v_secret text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    RAISE WARNING 'pg_cron not enabled; skipping cron setup';
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    RAISE WARNING 'pg_net not enabled; enable it before scheduling the HTTP poll';
    RETURN;
  END IF;

  -- 1. Remove the old ETL-only job (ETL now chained by the poll function)
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rfid-pipeline-every-15min') THEN
    PERFORM cron.unschedule('rfid-pipeline-every-15min');
    RAISE NOTICE 'Unscheduled rfid-pipeline-every-15min';
  END IF;

  -- 2. Recreate the poll job
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rfid-provider-poll-every-30min') THEN
    PERFORM cron.unschedule('rfid-provider-poll-every-30min');
  END IF;

  SELECT decrypted_secret INTO v_url
  FROM vault.decrypted_secrets WHERE name = 'rfid_poll_function_url';
  SELECT decrypted_secret INTO v_secret
  FROM vault.decrypted_secrets WHERE name = 'rfid_poll_cron_secret';

  IF v_url IS NULL OR v_secret IS NULL THEN
    RAISE EXCEPTION 'Vault secrets rfid_poll_function_url / rfid_poll_cron_secret missing (see Task 6 prerequisites)';
  END IF;

  PERFORM cron.schedule(
    'rfid-provider-poll-every-30min',
    '*/30 * * * *',
    format(
      $cmd$
      SELECT net.http_post(
        url := %L,
        headers := jsonb_build_object(
          'Authorization', 'Bearer ' || %L,
          'Content-Type', 'application/json'
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 280000
      );
      $cmd$, v_url, v_secret)
  );
  RAISE NOTICE 'Scheduled rfid-provider-poll-every-30min';
END $$;
```

- [ ] **Step 4: Apply migration and re-run test**

Apply migration `20260611120300_rfid_poll_cron`, then run `supabase/tests/poll_cron.test.sql`.
Expected: PASS (`PASS: cron jobs configured`).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260611120300_rfid_poll_cron.sql supabase/tests/poll_cron.test.sql
git commit -m "feat(etl): swap 15-min ETL cron for 30-min capture->ETL poll"
```

---

## Task 7: Deploy + manual smoke test

**Files:** none (deployment + verification).

- [ ] **Step 1: Deploy the edge function**

Deploy function `rfid-provider-poll` (Supabase MCP `deploy_edge_function`). Confirm it appears in `list_edge_functions`.

- [ ] **Step 2: Health-check style invocation (heartbeat)**

Temporarily set `backfill_since` to `now()` so the first call returns ~0 records (heartbeat per provider §9):

Run SQL: `UPDATE rfid_ingest_state SET backfill_since = now(), next_cursor = NULL WHERE id = 'aws-rfid-read-api';`

Invoke the function with the cron secret:

```bash
curl -s -X POST "https://sehbnpgzqljrsqimwyuz.supabase.co/functions/v1/rfid-provider-poll" \
  -H "Authorization: Bearer <CRON_SECRET>" -H "Content-Type: application/json" -d '{}'
```

Expected: `{"success":true,"fetched":0,...}` (or a small number), HTTP 200. A `401` means the secret is wrong; a `500` with `Missing RFID_PROVIDER_API_URL...` means secrets are unset.

- [ ] **Step 3: Verify state + no errors**

Run SQL: `SELECT last_status, last_error, last_run_at, last_fetched, next_cursor FROM rfid_ingest_state WHERE id='aws-rfid-read-api';`
Expected: `last_status = 'ok'`, `last_error` NULL, `last_run_at` recent.

- [ ] **Step 4: Verify the cron job will fire**

Run SQL: `SELECT jobname, schedule, active FROM cron.job WHERE jobname='rfid-provider-poll-every-30min';`
Expected: one active row, schedule `*/30 * * * *`.

- [ ] **Step 5: Record results**

Note in the PR/commit description: records fetched, match breakdown (`SELECT match_status, count(*) FROM rfid_provider_reads GROUP BY match_status;`), and any `unknown_reader`/`tag_decode_failed` counts (expected high until real LPIs are loaded and the decode rule is confirmed — spec §8.1/§8.2).

---

## Task 8: Document the new ingestion path

**Files:**
- Modify: `docs/ETL/ETL_RFID_PIPELINE_TECNICO.md` (§2 "Fuentes de datos")

- [ ] **Step 1: Update the source-of-data table**

In `docs/ETL/ETL_RFID_PIPELINE_TECNICO.md`, change the row for source #1 (proveedor externo) from "Pendiente de integración" to reference the implemented path, and add a one-line note that the legacy `rpc_ingest_epcis_events` (§7 #1) is bypassed by the new resolver. Replace the existing source-#1 row text:

Find:
```
| 1 | **Proveedor RFID externo (AWS)** | ONEMS hace **polling incremental** contra la BD/API del proveedor y persiste en `rfid_events_raw`. El proveedor es pasivo (no hace push). | **Pendiente de integración** (spec en borrador, ver abajo) |
```
Replace with:
```
| 1 | **Proveedor RFID externo (AWS)** | Edge Function `rfid-provider-poll` (cron 30 min) hace **polling incremental** (cursor) → landing `rfid_provider_reads` → `resolve_provider_reads()` normaliza tag y resuelve cuenta → `rfid_events_raw`. Encadena el ETL tras capturar. | **Implementado** (ver `docs/superpowers/specs/2026-06-11-rfid-aws-ingestion-design.md`). Bypassa la `rpc_ingest_epcis_events` heredada (§7 #1). |
```

- [ ] **Step 2: Commit**

```bash
git add docs/ETL/ETL_RFID_PIPELINE_TECNICO.md
git commit -m "docs(etl): document AWS provider ingestion path"
```

---

## Self-Review (completed during authoring)

- **Spec coverage:** §2 record structure → Task 4 (`toLandingRow`) + Task 1 columns. §4 cadence/order → Task 5 (chained RPCs) + Task 6 (30-min cron). §5.1 tables → Task 1. §5.2 edge function → Tasks 4–5. §5.3 resolver → Task 3. §5.4 normalizer → Task 2. §5.5 cron → Task 6. §6 field mapping → Tasks 1/4/3. §7 ETL impact (bypass legacy RPC) → Task 8 doc + Task 3 insert path. §8 open items → flagged in Tasks 2/6/7. §9 security → Task 6 prerequisites + Task 7. §10 testing → Tasks 1–4 tests + Task 7 smoke.
- **Placeholder scan:** no TBD/TODO; the provisional normalize rule is concrete and tested (Task 2).
- **Type consistency:** `resolve_provider_reads` returns `processed/matched/unknown_reader/tag_decode_failed` — consumed by that name in `index.ts` (`res.matched`, `res.unknown_reader`, `res.tag_decode_failed`). `LandingRow`/`ProviderRecord` field names match the upsert columns and Task 1 table. `match_status` values match the CHECK constraint in Task 1.
