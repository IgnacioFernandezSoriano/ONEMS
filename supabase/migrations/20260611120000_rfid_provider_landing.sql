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
