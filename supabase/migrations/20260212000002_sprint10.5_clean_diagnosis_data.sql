-- =====================================================
-- Sprint 10.5: Data Architecture & Preparation
-- Phase 3: Clean Diagnosis Data
-- Date: 2026-02-12
-- =====================================================

-- =====================================================
-- WARNING: This script will DELETE all diagnosis data
-- Only run this in development/testing environments
-- =====================================================

-- Clean journey data (cascades to journey_segments via FK)
TRUNCATE TABLE journeys CASCADE;

-- Clean journey segments (should be empty after journeys truncate)
TRUNCATE TABLE journey_segments CASCADE;

-- Clean incidents
TRUNCATE TABLE incidents CASCADE;

-- Clean processed events
TRUNCATE TABLE processed_events CASCADE;

-- Clean raw events
TRUNCATE TABLE rfid_events_raw CASCADE;

-- Clean audit table
TRUNCATE TABLE audit_raw_reads CASCADE;

-- Verification
DO $$
DECLARE
    v_journeys_count INT;
    v_segments_count INT;
    v_incidents_count INT;
    v_processed_count INT;
    v_raw_count INT;
BEGIN
    SELECT COUNT(*) INTO v_journeys_count FROM journeys;
    SELECT COUNT(*) INTO v_segments_count FROM journey_segments;
    SELECT COUNT(*) INTO v_incidents_count FROM incidents;
    SELECT COUNT(*) INTO v_processed_count FROM processed_events;
    SELECT COUNT(*) INTO v_raw_count FROM rfid_events_raw;
    
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Diagnosis Data Cleanup Summary';
    RAISE NOTICE '==============================================';
    RAISE NOTICE 'Journeys: % rows', v_journeys_count;
    RAISE NOTICE 'Journey Segments: % rows', v_segments_count;
    RAISE NOTICE 'Incidents: % rows', v_incidents_count;
    RAISE NOTICE 'Processed Events: % rows', v_processed_count;
    RAISE NOTICE 'Raw Events: % rows', v_raw_count;
    RAISE NOTICE '==============================================';
    
    IF v_journeys_count = 0 AND v_segments_count = 0 AND v_processed_count = 0 AND v_raw_count = 0 THEN
        RAISE NOTICE '✅ All diagnosis data successfully cleaned';
    ELSE
        RAISE WARNING '⚠️  Some data remains after cleanup';
    END IF;
END $$;

-- =====================================================
-- END OF MIGRATION
-- =====================================================
