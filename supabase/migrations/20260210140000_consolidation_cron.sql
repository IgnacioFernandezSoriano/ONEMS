-- =====================================================
-- Sprint 7: Event Consolidation - Automated Cron Job
-- =====================================================
-- Description: Automated consolidation for all accounts (runs every hour)
-- Author: Development Team
-- Date: 2026-02-10
-- =====================================================

-- =====================================================
-- 1. Create function to consolidate all accounts
-- =====================================================

CREATE OR REPLACE FUNCTION consolidate_all_accounts()
RETURNS TABLE (
    account_id UUID,
    account_name TEXT,
    events_processed INTEGER,
    incidents_detected INTEGER,
    execution_time_ms INTEGER,
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
BEGIN
    -- Log cron job start
    RAISE NOTICE 'Starting automated consolidation for all accounts at %', NOW();
    
    -- Loop through all active accounts
    FOR v_account IN 
        SELECT id, name 
        FROM accounts 
        ORDER BY name
    LOOP
        BEGIN
            v_start_time := clock_timestamp();
            
            RAISE NOTICE 'Processing account: % (%)', v_account.name, v_account.id;
            
            -- Call consolidation function for this account
            SELECT * INTO v_result
            FROM consolidate_rfid_events(v_account.id);
            
            v_end_time := clock_timestamp();
            v_execution_time := EXTRACT(MILLISECONDS FROM (v_end_time - v_start_time))::INTEGER;
            
            RAISE NOTICE 'Account % completed: % events, % incidents, % ms', 
                v_account.name, 
                v_result.events_processed, 
                v_result.incidents_detected,
                v_execution_time;
            
            -- Return success result
            account_id := v_account.id;
            account_name := v_account.name;
            events_processed := v_result.events_processed;
            incidents_detected := v_result.incidents_detected;
            execution_time_ms := v_execution_time;
            success := TRUE;
            error_message := NULL;
            
            RETURN NEXT;
            
        EXCEPTION WHEN OTHERS THEN
            -- Log error and continue with next account
            RAISE WARNING 'Error processing account % (%): %', 
                v_account.name, v_account.id, SQLERRM;
            
            -- Return error result
            account_id := v_account.id;
            account_name := v_account.name;
            events_processed := 0;
            incidents_detected := 0;
            execution_time_ms := 0;
            success := FALSE;
            error_message := SQLERRM;
            
            RETURN NEXT;
        END;
    END LOOP;
    
    RAISE NOTICE 'Automated consolidation completed at %', NOW();
    
    RETURN;
END;
$$;

-- Grant execute permission to authenticated users (for manual testing)
GRANT EXECUTE ON FUNCTION consolidate_all_accounts() TO authenticated;

-- =====================================================
-- 2. Create cron job using pg_cron extension
-- =====================================================

-- Note: pg_cron must be enabled in Supabase dashboard first
-- Go to: Database > Extensions > Enable "pg_cron"

-- Schedule consolidation to run every hour at minute 0
-- Syntax: cron_schedule, job_name, sql_command

DO $$
BEGIN
    -- Check if pg_cron extension is available
    IF EXISTS (
        SELECT 1 FROM pg_extension WHERE extname = 'pg_cron'
    ) THEN
        -- Remove existing job if it exists
        IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'consolidate-rfid-events-hourly') THEN
            PERFORM cron.unschedule('consolidate-rfid-events-hourly');
        END IF;
        
        -- Schedule new job to run every hour
        PERFORM cron.schedule(
            'consolidate-rfid-events-hourly',  -- job name
            '0 * * * *',                        -- cron schedule (every hour at minute 0)
            'SELECT consolidate_all_accounts()'  -- SQL command
        );
        
        RAISE NOTICE '✅ Cron job scheduled: consolidate-rfid-events-hourly';
        RAISE NOTICE '   Schedule: Every hour at minute 0';
        RAISE NOTICE '   Next run: %', (SELECT next_run FROM cron.job WHERE jobname = 'consolidate-rfid-events-hourly');
    ELSE
        RAISE WARNING '⚠️  pg_cron extension is not enabled';
        RAISE WARNING '   Please enable it in Supabase Dashboard: Database > Extensions > pg_cron';
    END IF;
END $$;

-- =====================================================
-- 3. Helper queries for monitoring
-- =====================================================

-- View scheduled cron jobs
COMMENT ON FUNCTION consolidate_all_accounts() IS 
'Query to view all cron jobs:
SELECT * FROM cron.job ORDER BY jobname;

Query to view cron job history:
SELECT * FROM cron.job_run_details 
WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = ''consolidate-rfid-events-hourly'')
ORDER BY start_time DESC 
LIMIT 10;

Query to manually trigger consolidation:
SELECT * FROM consolidate_all_accounts();

Query to unschedule the job:
SELECT cron.unschedule(''consolidate-rfid-events-hourly'');

Query to reschedule with different timing:
SELECT cron.schedule(
    ''consolidate-rfid-events-hourly'',
    ''0 * * * *'',  -- Change this cron expression
    ''SELECT consolidate_all_accounts()''
);
';

-- =====================================================
-- Summary
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '✅ Automated consolidation setup complete';
    RAISE NOTICE '';
    RAISE NOTICE '📋 Configuration:';
    RAISE NOTICE '   - Function: consolidate_all_accounts()';
    RAISE NOTICE '   - Schedule: Every hour at minute 0';
    RAISE NOTICE '   - Processes: All accounts automatically';
    RAISE NOTICE '';
    RAISE NOTICE '🔍 Monitoring queries:';
    RAISE NOTICE '   - View jobs: SELECT * FROM cron.job;';
    RAISE NOTICE '   - View history: SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;';
    RAISE NOTICE '   - Manual run: SELECT * FROM consolidate_all_accounts();';
END $$;
