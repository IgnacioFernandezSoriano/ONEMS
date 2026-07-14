-- =====================================================
-- Update RFID Pipeline to include Journey Assembly
-- =====================================================

CREATE OR REPLACE FUNCTION process_rfid_pipeline(p_account_id UUID)
RETURNS TABLE (
    phase TEXT,
    status TEXT,
    records_affected INTEGER,
    execution_time_ms INTEGER,
    error_message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_phase_start TIMESTAMPTZ;
    v_consolidation_result RECORD;
    v_reconstruction_result RECORD;
    v_assembly_result RECORD;
BEGIN
    RAISE NOTICE 'Starting RFID pipeline for account: %', p_account_id;
    
    -- ===== PHASE 1: Event Consolidation =====
    BEGIN
        v_phase_start := clock_timestamp();
        
        SELECT * INTO v_consolidation_result
        FROM consolidate_rfid_events(p_account_id);
        
        RETURN QUERY SELECT
            'consolidation'::TEXT,
            'success'::TEXT,
            v_consolidation_result.events_consolidated,
            EXTRACT(EPOCH FROM (clock_timestamp() - v_phase_start))::INTEGER * 1000,
            NULL::TEXT;
            
        RAISE NOTICE 'Phase 1 complete: % events consolidated', v_consolidation_result.events_consolidated;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT
            'consolidation'::TEXT,
            'error'::TEXT,
            0,
            EXTRACT(EPOCH FROM (clock_timestamp() - v_phase_start))::INTEGER * 1000,
            SQLERRM;
        RAISE WARNING 'Phase 1 failed: %', SQLERRM;
        RETURN;
    END;
    
    -- ===== PHASE 2: Journey Reconstruction =====
    BEGIN
        v_phase_start := clock_timestamp();
        
        SELECT * INTO v_reconstruction_result
        FROM reconstruct_journeys(p_account_id);
        
        RETURN QUERY SELECT
            'reconstruction'::TEXT,
            'success'::TEXT,
            v_reconstruction_result.segments_created::INTEGER,
            EXTRACT(EPOCH FROM (clock_timestamp() - v_phase_start))::INTEGER * 1000,
            NULL::TEXT;
            
        RAISE NOTICE 'Phase 2 complete: % segments created', v_reconstruction_result.segments_created;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT
            'reconstruction'::TEXT,
            'error'::TEXT,
            0,
            EXTRACT(EPOCH FROM (clock_timestamp() - v_phase_start))::INTEGER * 1000,
            SQLERRM;
        RAISE WARNING 'Phase 2 failed: %', SQLERRM;
        RETURN;
    END;
    
    -- ===== PHASE 3: Journey Assembly =====
    BEGIN
        v_phase_start := clock_timestamp();
        
        SELECT * INTO v_assembly_result
        FROM assemble_journeys(p_account_id);
        
        RETURN QUERY SELECT
            'assembly'::TEXT,
            'success'::TEXT,
            v_assembly_result.journeys_created + v_assembly_result.journeys_updated,
            EXTRACT(EPOCH FROM (clock_timestamp() - v_phase_start))::INTEGER * 1000,
            NULL::TEXT;
            
        RAISE NOTICE 'Phase 3 complete: % journeys created, % updated', 
            v_assembly_result.journeys_created, v_assembly_result.journeys_updated;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT
            'assembly'::TEXT,
            'error'::TEXT,
            0,
            EXTRACT(EPOCH FROM (clock_timestamp() - v_phase_start))::INTEGER * 1000,
            SQLERRM;
        RAISE WARNING 'Phase 3 failed: %', SQLERRM;
        RETURN;
    END;
    
    -- ===== SUMMARY =====
    RETURN QUERY SELECT
        'summary'::TEXT,
        'success'::TEXT,
        (v_consolidation_result.events_consolidated + 
         v_reconstruction_result.segments_created::INTEGER + 
         v_assembly_result.journeys_created + 
         v_assembly_result.journeys_updated),
        (v_consolidation_result.execution_time_ms + 
         v_reconstruction_result.execution_time_ms::INTEGER + 
         v_assembly_result.execution_time_ms),
        NULL::TEXT;
        
    RAISE NOTICE 'RFID pipeline completed successfully';
END;
$$;

COMMENT ON FUNCTION process_rfid_pipeline IS 
'Complete RFID processing pipeline: consolidation → reconstruction → assembly. Returns detailed metrics for each phase.';
