-- ============================================================
-- ONEMS · delta de BD para alinear la base compartida con develop
-- Base: sehbnpgzqljrsqimwyuz (unica, compartida prod+dev)
-- Generado: 2026-07-10
-- Todo idempotente. Transaccional (BEGIN/COMMIT) = todo o nada.
-- Omitidas por estar ya AL DIA o superseded: #2-7,#10,#11,#12,#15,#16 y cron.
-- ============================================================

BEGIN;

-- >>>>>>>>>>>>>>>>>>>> 20260611000000_panelist_city_normalization.sql >>>>>>>>>>>>>>>>>>>>
-- Panelist city normalization
-- ---------------------------------------------------------------------------
-- The "city" of a record was modelled twice across the schema: as a normalized
-- FK (city_id -> cities.id) and as free text (address_city / city_name). The
-- text was used as the de-facto join key, which is fragile because cities.name
-- was not even unique. This migration anchors the panelist's residence city to
-- the account's city catalog (cities) via city_id, keeping address_city only as
-- an optional free-text detail (locality / neighbourhood).
--
-- Scope: panelists only. ETL tables (journeys, one_db, processed_events) are
-- intentionally out of scope until the new provider API is defined.

-- 1. Harden the catalog: make city name a reliable alternate key per account.
--    No duplicates exist today (verified), so this is safe.
CREATE UNIQUE INDEX IF NOT EXISTS cities_account_lower_name_key
  ON public.cities (account_id, lower(trim(name)));

-- 2. Backfill panelists.city_id from address_city, matched case-insensitively
--    and scoped to the same account. Only fills rows that don't already have a
--    city_id and whose address_city maps unambiguously to one catalog city.
--    Sub-localities with no matching city (e.g. Nairobi-GPO, JKIA, Kwale/Diani,
--    Buruburu) and cross-account names (Barcelona in an account without it) are
--    intentionally left NULL for manual review.
UPDATE public.panelists p
SET city_id = c.id
FROM public.cities c
WHERE p.city_id IS NULL
  AND p.address_city IS NOT NULL
  AND c.account_id = p.account_id
  AND lower(trim(c.name)) = lower(trim(p.address_city))
  AND (
    SELECT count(*) FROM public.cities c2
    WHERE c2.account_id = p.account_id
      AND lower(trim(c2.name)) = lower(trim(p.address_city))
  ) = 1;

-- <<<<<<<<<<<<<<<<<<<< fin 20260611000000_panelist_city_normalization <<<<<<<<<<<<<<<<<<<<

-- >>>>>>>>>>>>>>>>>>>> 20260616120000_readers_superadmin_write_policies.sql >>>>>>>>>>>>>>>>>>>>
-- =====================================================
-- readers: allow superadmin to write (INSERT/UPDATE/DELETE) for ANY account.
-- A superadmin has no own account_id, so the existing *_own_account write
-- policies (account_id = current_user_account_id()) never pass -> creating a
-- reader from the Readers Management screen failed with
-- "new row violates row-level security policy for table readers".
-- This mirrors the existing read policy `readers_select_superadmin`.
-- =====================================================

DROP POLICY IF EXISTS readers_insert_superadmin ON public.readers;
CREATE POLICY readers_insert_superadmin ON public.readers
  FOR INSERT TO authenticated
  WITH CHECK (current_user_role() = 'superadmin');

DROP POLICY IF EXISTS readers_update_superadmin ON public.readers;
CREATE POLICY readers_update_superadmin ON public.readers
  FOR UPDATE TO authenticated
  USING (current_user_role() = 'superadmin')
  WITH CHECK (current_user_role() = 'superadmin');

DROP POLICY IF EXISTS readers_delete_superadmin ON public.readers;
CREATE POLICY readers_delete_superadmin ON public.readers
  FOR DELETE TO authenticated
  USING (current_user_role() = 'superadmin');

-- <<<<<<<<<<<<<<<<<<<< fin 20260616120000_readers_superadmin_write_policies <<<<<<<<<<<<<<<<<<<<

-- >>>>>>>>>>>>>>>>>>>> 20260616123000_normalize_provider_tag_upu_element.sql >>>>>>>>>>>>>>>>>>>>
-- =====================================================
-- normalize_provider_tag v2: accept the provider's canonical UPU element-string
-- format `G.<issuer>.<hex-serial>` (e.g. 'G.1UPU.01000FFFF00000007').
-- Confirmed with the provider: reads ALWAYS arrive in this format and it is the
-- correct, definitive tag identifier -> store the FULL string as-is (trim +
-- uppercase), do not strip the prefix/issuer. Previously this format returned
-- NULL -> reads landed as tag_decode_failed and never reached rfid_events_raw.
-- =====================================================
CREATE OR REPLACE FUNCTION public.normalize_provider_tag(p_raw text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v text;
  v_candidate text;
BEGIN
  IF p_raw IS NULL THEN
    RETURN NULL;
  END IF;
  v := trim(p_raw);
  IF v = '' THEN
    RETURN NULL;
  END IF;

  -- Already a hex EPC string -> uppercase passthrough
  IF v ~ '^[0-9A-Fa-f]+$' THEN
    RETURN upper(v);
  END IF;

  -- Provider UPU element string: G.<issuer>.<hex-serial>
  -- This IS the canonical tag id -> keep the full string (uppercased).
  IF v ~* '^G\.[0-9A-Za-z]+\.[0-9A-Fa-f]+$' THEN
    RETURN upper(v);
  END IF;

  -- urn:oid form -> take the last dot-separated token if it is hex
  IF lower(v) LIKE 'urn:oid:%' THEN
    v_candidate := split_part(v, '.', array_length(string_to_array(v, '.'), 1));
    IF v_candidate ~ '^[0-9A-Fa-f]+$' THEN
      RETURN upper(v_candidate);
    END IF;
    RETURN NULL;
  END IF;

  -- Unrecognized format
  RETURN NULL;
END $$;

COMMENT ON FUNCTION public.normalize_provider_tag(text) IS
'Normalizes a provider tagId. Rules: hex passthrough; UPU element string G.<issuer>.<hex> kept full (canonical id, confirmed with provider); urn:oid last token if hex; else NULL.';

-- <<<<<<<<<<<<<<<<<<<< fin 20260616123000_normalize_provider_tag_upu_element <<<<<<<<<<<<<<<<<<<<

-- >>>>>>>>>>>>>>>>>>>> 20260616140000_fix_pipeline_assembly_read.sql >>>>>>>>>>>>>>>>>>>>
-- Fix PHASE 3: read assemble_journeys() as a set-returning function (it RETURNS TABLE),
-- not as JSON. Alias the call and read its columns once (same pattern as the PHASE 2 fix).
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
        SELECT aj.journeys_created, aj.journeys_updated
        INTO v_assembly_created, v_assembly_updated
        FROM assemble_journeys(p_account_id) aj;

        RETURN QUERY SELECT
            'assembly'::TEXT, 0,0,0,
            (v_assembly_created + v_assembly_updated)::INTEGER,
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

-- <<<<<<<<<<<<<<<<<<<< fin 20260616140000_fix_pipeline_assembly_read <<<<<<<<<<<<<<<<<<<<

-- >>>>>>>>>>>>>>>>>>>> 20260616140100_consolidate_unconsolidated_flag.sql >>>>>>>>>>>>>>>>>>>>
CREATE OR REPLACE FUNCTION public.consolidate_rfid_events(p_account_id uuid)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_raw_event RECORD;
    v_reader_info RECORD;
    v_one_db_info RECORD;
    v_carrier_id UUID;
    v_product_id UUID;
    v_consolidated_event RECORD;
    v_analysis_datetime TIMESTAMPTZ;
    v_calculation_mode TEXT;
    v_gap_threshold_minutes INTEGER;
    v_events_processed INTEGER := 0;
    v_events_created INTEGER := 0;
    v_incidents_created INTEGER := 0;
    v_unknown_readers INTEGER := 0;
    v_unknown_tags INTEGER := 0;
    v_errors INTEGER := 0;
    v_start_time TIMESTAMPTZ := NOW();
BEGIN
    SELECT calculation_mode, gap_threshold_minutes
      INTO v_calculation_mode, v_gap_threshold_minutes
      FROM accounts WHERE id = p_account_id;
    v_calculation_mode := COALESCE(v_calculation_mode, 'natural_days');
    v_gap_threshold_minutes := COALESCE(v_gap_threshold_minutes, 30);

    FOR v_raw_event IN
        SELECT DISTINCT tag_id, reader_id
        FROM rfid_events_raw
        WHERE account_id = p_account_id AND is_processed = FALSE
        ORDER BY tag_id, reader_id
    LOOP
      BEGIN  -- per-tag isolation: one bad tag must not roll back the batch
        v_carrier_id := NULL;   -- reset per iteration (function-scoped vars leak otherwise)
        v_product_id := NULL;
        v_one_db_info := NULL;

        -- STEP 1: reader by LPI (must exist + be mapped to a postal center)
        SELECT r.id AS reader_uuid, r.reader_id AS reader_lpi, r.type AS reader_type,
               r.mixed_reader_gap_minutes,
               pc.id AS postal_center_id, pc.name AS postal_center_name,
               pc.code AS postal_center_code, pc.city AS postal_center_city,
               pc.calculation_mode AS postal_center_calculation_mode
          INTO v_reader_info
          FROM readers r
          JOIN postal_centers pc ON pc.id = r.postal_center_id
          WHERE r.reader_id = v_raw_event.reader_id AND r.account_id = p_account_id;

        IF v_reader_info.reader_uuid IS NULL THEN
            INSERT INTO incidents (account_id, tag_id, incident_type, severity, description, detected_at, metadata)
            VALUES (p_account_id, v_raw_event.tag_id, 'unknown_reader', 'low',
                    'Events detected from unknown reader LPI: ' || v_raw_event.reader_id, NOW(),
                    jsonb_build_object('reader_lpi', v_raw_event.reader_id, 'tag_id', v_raw_event.tag_id));
            v_unknown_readers := v_unknown_readers + 1;
            v_incidents_created := v_incidents_created + 1;
            UPDATE rfid_events_raw SET is_processed = TRUE
              WHERE account_id = p_account_id AND tag_id = v_raw_event.tag_id
                AND reader_id = v_raw_event.reader_id AND is_processed = FALSE;
            CONTINUE;
        END IF;

        -- STEP 2: optional ONE DB enrichment. Missing -> capture anyway (NULL enrichment).
        SELECT carrier_name, product_name, origin_city_name, destination_city_name
          INTO v_one_db_info
          FROM one_db
          WHERE tag_id = v_raw_event.tag_id AND account_id = p_account_id
          LIMIT 1;

        IF v_one_db_info.carrier_name IS NULL THEN
            INSERT INTO incidents (account_id, tag_id, incident_type, severity, description, detected_at, metadata)
            VALUES (p_account_id, v_raw_event.tag_id, 'unknown_tag', 'low',
                    'Tag not found in ONE DB; captured without enrichment: ' || v_raw_event.tag_id, NOW(),
                    jsonb_build_object('tag_id', v_raw_event.tag_id, 'reader_lpi', v_raw_event.reader_id));
            v_unknown_tags := v_unknown_tags + 1;
            v_incidents_created := v_incidents_created + 1;
            -- NO CONTINUE: fall through and consolidate with NULL carrier/product/cities.
        ELSE
            -- STEP 3: names -> ids (only when enriched)
            SELECT id INTO v_carrier_id FROM carriers
              WHERE name = v_one_db_info.carrier_name AND account_id = p_account_id LIMIT 1;
            SELECT id INTO v_product_id FROM products
              WHERE code = v_one_db_info.product_name AND carrier_id = v_carrier_id LIMIT 1;
        END IF;

        -- STEP 4: consolidate by reader type
        IF v_reader_info.reader_type = 'Entry' THEN
            FOR v_consolidated_event IN
                SELECT 'entry' AS event_type, MIN(read_local_datetime) AS timestamp, COUNT(*) AS raw_event_count
                FROM rfid_events_raw
                WHERE account_id = p_account_id AND tag_id = v_raw_event.tag_id
                  AND reader_id = v_raw_event.reader_id AND is_processed = FALSE
            LOOP
                IF v_reader_info.postal_center_calculation_mode = 'working_days' THEN
                    v_analysis_datetime := calculate_next_working_datetime(v_consolidated_event.timestamp, v_reader_info.postal_center_id);
                ELSE
                    v_analysis_datetime := v_consolidated_event.timestamp;
                END IF;
                INSERT INTO processed_events (account_id, tag_id, reader_id, reader_id_snapshot, reader_type_snapshot,
                    postal_center_id, postal_center_name_snapshot, postal_center_code_snapshot, postal_center_city_snapshot,
                    carrier_id, product_id, origin_city_name, destination_city_name, event_type, timestamp,
                    analysis_datetime, raw_event_count, is_consolidated, is_estimated)
                VALUES (p_account_id, v_raw_event.tag_id, v_reader_info.reader_uuid, v_reader_info.reader_lpi, v_reader_info.reader_type,
                    v_reader_info.postal_center_id, v_reader_info.postal_center_name, v_reader_info.postal_center_code, v_reader_info.postal_center_city,
                    v_carrier_id, v_product_id, v_one_db_info.origin_city_name, v_one_db_info.destination_city_name,
                    v_consolidated_event.event_type, v_consolidated_event.timestamp, v_analysis_datetime,
                    v_consolidated_event.raw_event_count, FALSE, FALSE);
                v_events_created := v_events_created + 1;
            END LOOP;

        ELSIF v_reader_info.reader_type = 'Exit' THEN
            FOR v_consolidated_event IN
                SELECT 'exit' AS event_type, MAX(read_local_datetime) AS timestamp, COUNT(*) AS raw_event_count
                FROM rfid_events_raw
                WHERE account_id = p_account_id AND tag_id = v_raw_event.tag_id
                  AND reader_id = v_raw_event.reader_id AND is_processed = FALSE
            LOOP
                INSERT INTO processed_events (account_id, tag_id, reader_id, reader_id_snapshot, reader_type_snapshot,
                    postal_center_id, postal_center_name_snapshot, postal_center_code_snapshot, postal_center_city_snapshot,
                    carrier_id, product_id, origin_city_name, destination_city_name, event_type, timestamp,
                    analysis_datetime, raw_event_count, is_consolidated, is_estimated)
                VALUES (p_account_id, v_raw_event.tag_id, v_reader_info.reader_uuid, v_reader_info.reader_lpi, v_reader_info.reader_type,
                    v_reader_info.postal_center_id, v_reader_info.postal_center_name, v_reader_info.postal_center_code, v_reader_info.postal_center_city,
                    v_carrier_id, v_product_id, v_one_db_info.origin_city_name, v_one_db_info.destination_city_name,
                    v_consolidated_event.event_type, v_consolidated_event.timestamp, v_consolidated_event.timestamp,
                    v_consolidated_event.raw_event_count, FALSE, FALSE);
                v_events_created := v_events_created + 1;
            END LOOP;

        ELSIF v_reader_info.reader_type = 'Mixed' THEN
            -- Use the existing 4-arg splitter and INSERT each returned row (like Entry/Exit).
            FOR v_consolidated_event IN
                SELECT * FROM consolidate_mixed_reader_events(
                    p_account_id, v_raw_event.tag_id, v_raw_event.reader_id,
                    COALESCE(v_reader_info.mixed_reader_gap_minutes, v_gap_threshold_minutes))
            LOOP
                IF v_consolidated_event.event_type = 'entry'
                   AND v_reader_info.postal_center_calculation_mode = 'working_days' THEN
                    v_analysis_datetime := calculate_next_working_datetime(v_consolidated_event.timestamp, v_reader_info.postal_center_id);
                ELSE
                    v_analysis_datetime := v_consolidated_event.timestamp;
                END IF;
                INSERT INTO processed_events (account_id, tag_id, reader_id, reader_id_snapshot, reader_type_snapshot,
                    postal_center_id, postal_center_name_snapshot, postal_center_code_snapshot, postal_center_city_snapshot,
                    carrier_id, product_id, origin_city_name, destination_city_name, event_type, timestamp,
                    analysis_datetime, raw_event_count, is_consolidated, is_estimated)
                VALUES (p_account_id, v_raw_event.tag_id, v_reader_info.reader_uuid, v_reader_info.reader_lpi, v_reader_info.reader_type,
                    v_reader_info.postal_center_id, v_reader_info.postal_center_name, v_reader_info.postal_center_code, v_reader_info.postal_center_city,
                    v_carrier_id, v_product_id, v_one_db_info.origin_city_name, v_one_db_info.destination_city_name,
                    v_consolidated_event.event_type, v_consolidated_event.timestamp, v_analysis_datetime,
                    v_consolidated_event.raw_event_count, FALSE, FALSE);
                v_events_created := v_events_created + 1;
            END LOOP;
        END IF;

        -- Mark raw events processed
        UPDATE rfid_events_raw SET is_processed = TRUE
          WHERE account_id = p_account_id AND tag_id = v_raw_event.tag_id
            AND reader_id = v_raw_event.reader_id AND is_processed = FALSE;
        v_events_processed := v_events_processed + 1;

      EXCEPTION WHEN OTHERS THEN
        v_errors := v_errors + 1;
        RAISE WARNING 'consolidate_rfid_events: tag % reader % failed: %',
            v_raw_event.tag_id, v_raw_event.reader_id, SQLERRM;
      END;
    END LOOP;

    RETURN json_build_object(
        'success', TRUE,
        'events_processed', v_events_processed,
        'events_created', v_events_created,
        'incidents_created', v_incidents_created,
        'unknown_readers', v_unknown_readers,
        'unknown_tags', v_unknown_tags,
        'errors', v_errors,
        'duration_seconds', EXTRACT(EPOCH FROM (NOW() - v_start_time))
    );
END;
$function$;

-- <<<<<<<<<<<<<<<<<<<< fin 20260616140100_consolidate_unconsolidated_flag <<<<<<<<<<<<<<<<<<<<

COMMIT;
