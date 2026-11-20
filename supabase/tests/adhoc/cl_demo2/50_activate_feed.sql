-- Carrier Link DEMO2 synthetic test, phase "activate-feed" (WRITES; idempotent).
-- Needed for real ingestion: carrier-link-ingest answers 403 CL_FEED_TESTING_DRY_RUN_ONLY to a non dry-run POST while
-- cl_feeds.status = 'testing' (index.ts). The open demand keeps feed_testing = true (it was emitted in testing): it
-- can still receive the batch; it just never counted in demands_count (I2).
UPDATE public.cl_feeds SET status = 'active'
 WHERE id = 'c1de2000-0000-4000-8000-0000000000f1'
   AND account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'
   AND status = 'testing';

SELECT id, name, status FROM public.cl_feeds WHERE id = 'c1de2000-0000-4000-8000-0000000000f1';
