-- =====================================================
-- Sprint 8: Update Cron Job to Use Pipeline
-- =====================================================
-- Description: Replace consolidation-only cron with full pipeline
-- Author: Development Team
-- Date: 2026-02-11
-- =====================================================

-- =====================================================
-- 1. Create wrapper function for all accounts pipeline
-- =====================================================

CREATE OR REPLACE FUNCTION process_all_accounts_pipeline()
RETURNS TABLE (
    account_id UUID,
    account_name TEXT,
    events_consolidated INTEGER,
    incidents_created INTEGER,
    segments_created INTEGER,
    events_processed INTEGER,
    total_execution_time_ms INTEGER,
    success BOOLEAN,
    error_message TEXT
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_account RECORD;
    v_result RECORD;
    v_start_time TIMESTAMPTZ;
    v_end_time TIMESTAMPTZ;
    v_execution_time INTEGER;
    v_events_consolidated INTEGER := 0;
    v_incidents_created INTEGER := 0;
    v_segments_created INTEGER := 0;
    v_events_processed INTEGER := 0;
BEGIN
    -- Log cron job start
    RAISE NOTICE '========================================';
    RAISE NOTICE 'RFID Pipeline - All Accounts';
    RAISE NOTICE 'Started at: %', NOW();
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    
    -- Loop through all active accounts
    FOR v_account IN 
        SELECT id, name 
        FROM accounts 
        ORDER BY name
    LOOP
        BEGIN
            v_start_time := clock_timestamp();
            
            RAISE NOTICE '🏢 Processing account: % (%)', v_account.name, v_account.id;
            RAISE NOTICE '----------------------------------------';
            
            -- Reset counters for this account
            v_events_consolidated := 0;
            v_incidents_created := 0;
            v_segments_created := 0;
            v_events_processed := 0;
            
            -- Call pipeline function for this account
            -- Aggregate results from all phases
            FOR v_result IN
                SELECT * FROM process_rfid_pipeline(v_account.id)
            LOOP
                -- Accumulate metrics from each phase
                v_events_consolidated := v_events_consolidated + COALESCE(v_result.events_consolidated, 0);
                v_incidents_created := v_incidents_created + COALESCE(v_result.incidents_created, 0);
                v_segments_created := v_segments_created + COALESCE(v_result.segments_created, 0);
                v_events_processed := v_events_processed + COALESCE(v_result.events_processed, 0);
            END LOOP;
            
            v_end_time := clock_timestamp();
            v_execution_time := EXTRACT(MILLISECONDS FROM (v_end_time - v_start_time))::INTEGER;
            
            RAISE NOTICE '✅ Account % completed:', v_account.name;
            RAISE NOTICE '   - Events consolidated: %', v_events_consolidated;
            RAISE NOTICE '   - Incidents created: %', v_incidents_created;
            RAISE NOTICE '   - Segments created: %', v_segments_created;
            RAISE NOTICE '   - Events processed: %', v_events_processed;
            RAISE NOTICE '   - Total time: % ms', v_execution_time;
            RAISE NOTICE '';
            
            -- Return success result
            account_id := v_account.id;
            account_name := v_account.name;
            events_consolidated := v_events_consolidated;
            incidents_created := v_incidents_created;
            segments_created := v_segments_created;
            events_processed := v_events_processed;
            total_execution_time_ms := v_execution_time;
            success := TRUE;
            error_message := NULL;
            
            RETURN NEXT;
            
        EXCEPTION WHEN OTHERS THEN
            -- Log error and continue with next account
            RAISE WARNING '❌ Error processing account % (%): %', 
                v_account.name, v_account.id, SQLERRM;
            
            -- Return error result
            account_id := v_account.id;
            account_name := v_account.name;
            events_consolidated := 0;
            incidents_created := 0;
            segments_created := 0;
            events_processed := 0;
            total_execution_time_ms := 0;
            success := FALSE;
            error_message := SQLERRM;
            
            RETURN NEXT;
        END;
    END LOOP;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Pipeline completed at: %', NOW();
    RAISE NOTICE '========================================';
    
    RETURN;
END;
$$;

COMMENT ON FUNCTION process_all_accounts_pipeline IS 
'Processes RFID pipeline (consolidation + journey reconstruction) for all accounts. Designed for cron job execution.';

-- Grant execute permission
GRANT EXECUTE ON FUNCTION process_all_accounts_pipeline() TO authenticated;

-- =====================================================
-- 2. Update cron job to use pipeline
-- =====================================================

DO $$
BEGIN
    -- Check if pg_cron extension is available
    IF EXISTS (
        SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
    ) THEN
        -- Remove old consolidation-only job if it exists
        IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'consolidate-rfid-events-hourly') THEN
            PERFORM cron.unschedule('consolidate-rfid-events-hourly');
            RAISE NOTICE '🗑️  Removed old job: consolidate-rfid-events-hourly';
        END IF;
        
        -- Remove pipeline job if it exists (for re-creation)
        IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'rfid-pipeline-every-15min') THEN
            PERFORM cron.unschedule('rfid-pipeline-every-15min');
            RAISE NOTICE '🗑️  Removed existing pipeline job for re-creation';
        END IF;
        
        -- Schedule new pipeline job to run every 15 minutes
        PERFORM cron.schedule(
            'rfid-pipeline-every-15min',              -- job name
            '*/15 * * * *',                           -- cron schedule (every 15 minutes)
            'SELECT process_all_accounts_pipeline()'  -- SQL command
        );
        
        RAISE NOTICE '✅ Cron job scheduled: rfid-pipeline-every-15min';
        RAISE NOTICE '   Schedule: Every 15 minutes';
        RAISE NOTICE '   Function: process_all_accounts_pipeline()';
        RAISE NOTICE '   Includes: Consolidation + Journey Reconstruction';
    ELSE
        RAISE WARNING '⚠️  pg_cron extension is not enabled';
        RAISE WARNING '   Please enable it in Supabase Dashboard: Database > Extensions > pg_cron';
    END IF;
END $$;

-- =====================================================
-- 3. Helper queries for monitoring
-- =====================================================

COMMENT ON FUNCTION process_all_accounts_pipeline IS 
'RFID Pipeline - Monitoring Queries:

View scheduled cron jobs:
  SELECT * FROM cron.job ORDER BY jobname;

View cron job history:
  SELECT * FROM cron.job_run_details 
  WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = ''rfid-pipeline-every-15min'')
  ORDER BY start_time DESC 
  LIMIT 10;

Manual trigger (all accounts):
  SELECT * FROM process_all_accounts_pipeline();

Manual trigger (single account):
  SELECT * FROM process_rfid_pipeline(''account-uuid'');

Unschedule the job:
  SELECT cron.unschedule(''rfid-pipeline-every-15min'');

Reschedule with different timing (e.g., every 30 minutes):
  SELECT cron.schedule(
    ''rfid-pipeline-every-15min'',
    ''*/30 * * * *'',
    ''SELECT process_all_accounts_pipeline()''
  );
';

-- =====================================================
-- Summary
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '✅ RFID Pipeline Cron Job Updated';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '📋 Configuration:';
    RAISE NOTICE '   - Job Name: rfid-pipeline-every-15min';
    RAISE NOTICE '   - Schedule: Every 15 minutes';
    RAISE NOTICE '   - Function: process_all_accounts_pipeline()';
    RAISE NOTICE '   - Processes: All accounts automatically';
    RAISE NOTICE '';
    RAISE NOTICE '🔄 Pipeline Phases:';
    RAISE NOTICE '   1. Event Consolidation (raw → processed)';
    RAISE NOTICE '   2. Journey Reconstruction (processed → segments)';
    RAISE NOTICE '';
    RAISE NOTICE '🔍 Monitoring:';
    RAISE NOTICE '   - View jobs: SELECT * FROM cron.job;';
    RAISE NOTICE '   - View history: SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;';
    RAISE NOTICE '   - Manual run: SELECT * FROM process_all_accounts_pipeline();';
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
END $$;
