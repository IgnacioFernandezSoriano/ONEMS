-- Verifies the 15-min ETL-only cron was replaced by the 30-min capture->ETL poll.
-- Run AFTER applying 20260611120300_rfid_poll_cron.sql.
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
