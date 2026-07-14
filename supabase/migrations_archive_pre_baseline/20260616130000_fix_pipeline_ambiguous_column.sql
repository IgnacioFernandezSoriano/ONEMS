-- Fix ambiguous column refs in PHASE 2: alias the reconstruct_journeys() call.
CREATE OR REPLACE FUNCTION public.process_rfid_pipeline(p_account_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(phase text, events_consolidated integer, incidents_created integer, segments_created integer, events_processed integer, execution_time_ms integer, status text, message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_phase_start TIMESTAMPTZ;
    v_consolidation_result JSON;
    v_reconstruction_segments INTEGER;
    v_reconstruction_events INTEGER;
    v_assembly_created INTEGER;
    v_assembly_updated INTEGER;
    v_total_time INTEGER;
BEGIN
    v_start_time := clock_timestamp();

    -- PHASE 1: Consolidation
    v_phase_start := clock_timestamp();
    BEGIN
        v_consolidation_result := consolidate_rfid_events(p_account_id);
        RETURN QUERY SELECT
            'consolidation'::TEXT,
            (v_consolidation_result->>'events_created')::INTEGER,
            (v_consolidation_result->>'incidents_created')::INTEGER,
            0::INTEGER,
            (v_consolidation_result->>'events_processed')::INTEGER,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'success'::TEXT,
            format('Processed %s events', (v_consolidation_result->>'events_processed')::INTEGER)::TEXT;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT
            'consolidation'::TEXT, 0,0,0,0,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'error'::TEXT, SQLERRM::TEXT;
        RETURN;
    END;

    -- PHASE 2: Reconstruction
    v_phase_start := clock_timestamp();
    BEGIN
        SELECT rj.segments_created, rj.events_processed
        INTO v_reconstruction_segments, v_reconstruction_events
        FROM reconstruct_journeys(p_account_id) rj;

        RETURN QUERY SELECT
            'reconstruction'::TEXT,
            0,0,
            v_reconstruction_segments,
            v_reconstruction_events,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'success'::TEXT,
            format('Created %s segments', v_reconstruction_segments)::TEXT;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT
            'reconstruction'::TEXT, 0,0,0,0,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'error'::TEXT, SQLERRM::TEXT;
        RETURN;
    END;

    -- PHASE 3: Assembly
    v_phase_start := clock_timestamp();
    BEGIN
        SELECT
            (assemble_journeys(p_account_id)->>'journeys_created')::INTEGER,
            (assemble_journeys(p_account_id)->>'journeys_updated')::INTEGER
        INTO v_assembly_created, v_assembly_updated;

        RETURN QUERY SELECT
            'assembly'::TEXT, 0,0,0,
            v_assembly_created + v_assembly_updated,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'success'::TEXT,
            format('Created %s journeys', v_assembly_created + v_assembly_updated)::TEXT;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT
            'assembly'::TEXT, 0,0,0,0,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'error'::TEXT, SQLERRM::TEXT;
        RETURN;
    END;

    -- Summary
    v_total_time := EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_start_time))::INTEGER;
    RETURN QUERY SELECT
        'summary'::TEXT,
        (v_consolidation_result->>'events_created')::INTEGER,
        (v_consolidation_result->>'incidents_created')::INTEGER,
        v_reconstruction_segments,
        v_assembly_created + v_assembly_updated,
        v_total_time,
        'success'::TEXT,
        'Pipeline completed'::TEXT;
END;
$function$;
