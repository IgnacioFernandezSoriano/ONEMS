-- =====================================================
-- Sprint 8: RFID Processing Pipeline
-- =====================================================
-- Description: Chained pipeline for consolidation + journey reconstruction
-- Author: Development Team
-- Date: 2026-02-11
-- =====================================================

-- =====================================================
-- Main Pipeline Function
-- =====================================================

CREATE OR REPLACE FUNCTION process_rfid_pipeline(
    p_account_id UUID DEFAULT NULL
)
RETURNS TABLE (
    phase TEXT,
    events_consolidated INTEGER,
    incidents_created INTEGER,
    segments_created INTEGER,
    events_processed INTEGER,
    execution_time_ms INTEGER,
    status TEXT,
    message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_phase_start TIMESTAMPTZ;
    v_consolidation_result RECORD;
    v_reconstruction_result RECORD;
    v_total_time INTEGER;
BEGIN
    v_start_time := clock_timestamp();
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'RFID Processing Pipeline Started';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Account ID: %', COALESCE(p_account_id::TEXT, 'ALL');
    RAISE NOTICE '';
    
    -- =====================================================
    -- PHASE 1: Event Consolidation
    -- =====================================================
    
    v_phase_start := clock_timestamp();
    RAISE NOTICE '📊 Phase 1: Event Consolidation';
    RAISE NOTICE '----------------------------------------';
    
    BEGIN
        -- Call consolidation function
        SELECT * INTO v_consolidation_result
        FROM consolidate_rfid_events(p_account_id);
        
        RAISE NOTICE '✅ Consolidation completed:';
        RAISE NOTICE '   - Events consolidated: %', v_consolidation_result.events_consolidated;
        RAISE NOTICE '   - Incidents created: %', v_consolidation_result.incidents_created;
        RAISE NOTICE '   - Execution time: % ms', v_consolidation_result.execution_time_ms;
        RAISE NOTICE '';
        
        -- Return consolidation results
        RETURN QUERY SELECT 
            'consolidation'::TEXT,
            v_consolidation_result.events_consolidated,
            v_consolidation_result.incidents_created,
            0::INTEGER, -- segments_created
            0::INTEGER, -- events_processed
            v_consolidation_result.execution_time_ms,
            'success'::TEXT,
            format('Consolidated %s events, created %s incidents', 
                v_consolidation_result.events_consolidated,
                v_consolidation_result.incidents_created)::TEXT;
        
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Consolidation phase failed: %', SQLERRM;
        
        RETURN QUERY SELECT 
            'consolidation'::TEXT,
            0::INTEGER,
            0::INTEGER,
            0::INTEGER,
            0::INTEGER,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'error'::TEXT,
            format('Consolidation failed: %s', SQLERRM)::TEXT;
        
        -- Don't proceed to reconstruction if consolidation failed
        RETURN;
    END;
    
    -- =====================================================
    -- PHASE 2: Journey Reconstruction
    -- =====================================================
    
    v_phase_start := clock_timestamp();
    RAISE NOTICE '🗺️  Phase 2: Journey Reconstruction';
    RAISE NOTICE '----------------------------------------';
    
    BEGIN
        -- Call reconstruction function
        SELECT * INTO v_reconstruction_result
        FROM reconstruct_journeys(p_account_id);
        
        RAISE NOTICE '✅ Reconstruction completed:';
        RAISE NOTICE '   - Segments created: %', v_reconstruction_result.segments_created;
        RAISE NOTICE '   - Events processed: %', v_reconstruction_result.events_processed;
        RAISE NOTICE '   - Execution time: % ms', v_reconstruction_result.execution_time_ms;
        RAISE NOTICE '';
        
        -- Return reconstruction results
        RETURN QUERY SELECT 
            'reconstruction'::TEXT,
            0::INTEGER, -- events_consolidated
            0::INTEGER, -- incidents_created
            v_reconstruction_result.segments_created,
            v_reconstruction_result.events_processed,
            v_reconstruction_result.execution_time_ms,
            'success'::TEXT,
            format('Created %s segments from %s events', 
                v_reconstruction_result.segments_created,
                v_reconstruction_result.events_processed)::TEXT;
        
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'Reconstruction phase failed: %', SQLERRM;
        
        RETURN QUERY SELECT 
            'reconstruction'::TEXT,
            0::INTEGER,
            0::INTEGER,
            0::INTEGER,
            0::INTEGER,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'error'::TEXT,
            format('Reconstruction failed: %s', SQLERRM)::TEXT;
        
        RETURN;
    END;
    
    -- =====================================================
    -- Pipeline Summary
    -- =====================================================
    
    v_total_time := EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_start_time))::INTEGER;
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Pipeline Summary';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Total execution time: % ms', v_total_time;
    RAISE NOTICE 'Events consolidated: %', v_consolidation_result.events_consolidated;
    RAISE NOTICE 'Incidents created: %', v_consolidation_result.incidents_created;
    RAISE NOTICE 'Segments created: %', v_reconstruction_result.segments_created;
    RAISE NOTICE 'Events processed: %', v_reconstruction_result.events_processed;
    RAISE NOTICE '========================================';
    
    -- Return summary
    RETURN QUERY SELECT 
        'summary'::TEXT,
        v_consolidation_result.events_consolidated,
        v_consolidation_result.incidents_created,
        v_reconstruction_result.segments_created,
        v_reconstruction_result.events_processed,
        v_total_time,
        'success'::TEXT,
        'Pipeline completed successfully'::TEXT;
END;
$$;

COMMENT ON FUNCTION process_rfid_pipeline IS 
'Complete RFID processing pipeline: consolidates raw events and reconstructs journey segments. Designed for cron job execution.';

-- Grant execute permission
GRANT EXECUTE ON FUNCTION process_rfid_pipeline(UUID) TO authenticated;

-- =====================================================
-- Summary
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '✅ RFID Pipeline function created';
    RAISE NOTICE '';
    RAISE NOTICE '📋 Function:';
    RAISE NOTICE '   - process_rfid_pipeline()';
    RAISE NOTICE '';
    RAISE NOTICE '🔍 Usage:';
    RAISE NOTICE '   - Process all accounts: SELECT * FROM process_rfid_pipeline();';
    RAISE NOTICE '   - Process specific account: SELECT * FROM process_rfid_pipeline(''account-uuid'');';
    RAISE NOTICE '';
    RAISE NOTICE '⏰ Ready for cron job integration';
END $$;
