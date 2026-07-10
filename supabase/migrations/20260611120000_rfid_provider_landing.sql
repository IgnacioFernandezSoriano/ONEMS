-- =====================================================
-- RFID AWS Provider Ingestion: landing + state tables
-- =====================================================

CREATE TABLE IF NOT EXISTS public.rfid_provider_reads (
  id                   uuid PRIMARY KEY,                 -- provider 'id' (idempotency). No DEFAULT on purpose: the provider uuid is always supplied explicitly.
  location             text,                             -- raw "Country | City | Site | State"
  reader_id            text NOT NULL,                    -- provider readerId
  tag_id_raw           text NOT NULL,                    -- provider tagId, verbatim
  read_local_datetime  timestamptz NOT NULL,             -- provider timestamp
  ingested_at          timestamptz NOT NULL,             -- provider ingested_at (cursor traceability)
  tag_id_normalized    text,                             -- set by resolver
  resolved_account_id  uuid REFERENCES public.accounts(id) ON DELETE SET NULL,
  match_status         text NOT NULL DEFAULT 'pending',
  unmatch_reason       text,
  -- No FK to rfid_events_raw(id) on purpose: the ETL archives and DELETES raw rows
  -- (archive_raw_events), so a FK with ON DELETE SET NULL would erase this trace exactly
  -- when the raw row is archived. Kept as a loose uuid to preserve historical linkage.
  rfid_events_raw_id   uuid,
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
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT rfid_ingest_state_last_status_chk
    CHECK (last_status IS NULL OR last_status IN ('ok','error','rate_limited'))
);

-- Seed the single source row. backfill_since left NULL until decided (spec §8.4);
-- the Edge Function treats NULL backfill_since by defaulting to now() - 24 months on first run.
INSERT INTO public.rfid_ingest_state (id)
VALUES ('aws-rfid-read-api')
ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- RLS: mirror the project pattern. The Edge Function (service_role) and the
-- SECURITY DEFINER resolver bypass RLS, so the ingestion path is unaffected.
-- Regular users get account-scoped / superadmin read only; no write policies = deny.
-- =====================================================
ALTER TABLE public.rfid_provider_reads ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rfid_provider_reads_select_account ON public.rfid_provider_reads;
CREATE POLICY rfid_provider_reads_select_account ON public.rfid_provider_reads
  FOR SELECT USING (resolved_account_id = current_user_account_id());
DROP POLICY IF EXISTS rfid_provider_reads_select_superadmin ON public.rfid_provider_reads;
CREATE POLICY rfid_provider_reads_select_superadmin ON public.rfid_provider_reads
  FOR SELECT USING (is_superadmin());

ALTER TABLE public.rfid_ingest_state ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rfid_ingest_state_select_superadmin ON public.rfid_ingest_state;
CREATE POLICY rfid_ingest_state_select_superadmin ON public.rfid_ingest_state
  FOR SELECT USING (is_superadmin());
