-- =====================================================
-- Enforce reader_id uniqueness among active readers.
-- resolve_provider_reads() resolves a read's account_id from reader_id; in a
-- multi-tenant DB a duplicate reader_id would let reads be attributed to the
-- wrong account. A partial unique index makes the lookup deterministic and the
-- invariant explicit, while still allowing soft-deleted (deleted_at) duplicates.
-- =====================================================
CREATE UNIQUE INDEX IF NOT EXISTS uq_readers_reader_id_active
  ON public.readers (reader_id)
  WHERE deleted_at IS NULL;
