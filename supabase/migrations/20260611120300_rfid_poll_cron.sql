-- =====================================================
-- Cron: replace 15-min ETL-only pipeline with a 30-min capture->ETL poll.
-- The ETL now runs INSIDE the edge function, after capture.
--
-- PREREQUISITES before applying (see plan Task 6 / spec §9):
--   * Edge function `rfid-provider-poll` deployed.
--   * Edge function secrets set: RFID_PROVIDER_API_URL, RFID_PROVIDER_API_KEY, CRON_SECRET.
--   * Vault secrets present: rfid_poll_function_url, rfid_poll_cron_secret
--     (rfid_poll_cron_secret MUST equal the edge function CRON_SECRET).
-- Applying this BEFORE the edge secrets are set would unschedule the ETL and
-- replace it with a poll that 401s -> the ETL would stop running.
-- =====================================================

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

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
