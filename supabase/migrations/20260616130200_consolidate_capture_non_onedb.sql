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
                    v_consolidated_event.raw_event_count, TRUE, FALSE);
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
                    v_consolidated_event.raw_event_count, TRUE, FALSE);
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
                    v_consolidated_event.raw_event_count, TRUE, FALSE);
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
