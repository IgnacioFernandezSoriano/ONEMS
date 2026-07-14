-- Fix detect_missing_exits() to include reader snapshots and carrier/product

CREATE OR REPLACE FUNCTION detect_missing_exits(
    p_account_id UUID
) RETURNS INTEGER AS $$
DECLARE
    v_missing_exit RECORD;
    v_estimated_exit_timestamp TIMESTAMPTZ;
    v_sla_minutes INTEGER;
    v_count INTEGER := 0;
    v_reader_type TEXT;
BEGIN
    FOR v_missing_exit IN
        SELECT DISTINCT ON (pe_entry.tag_id, pe_entry.postal_center_id)
            pe_entry.tag_id,
            pe_entry.postal_center_id,
            pe_entry.reader_id,
            pe_entry.timestamp AS entry_timestamp,
            pe_entry.analysis_datetime AS entry_analysis_datetime,
            pe_entry.carrier_id,
            pe_entry.product_id,
            pc.name AS postal_center_name,
            pc.code AS postal_center_code,
            sla.expected_time_minutes
        FROM processed_events pe_entry
        JOIN postal_centers pc ON pe_entry.postal_center_id = pc.id
        LEFT JOIN processed_events pe_exit
            ON pe_entry.tag_id = pe_exit.tag_id
            AND pe_entry.postal_center_id = pe_exit.postal_center_id
            AND pe_exit.event_type = 'exit'
            AND pe_exit.timestamp > pe_entry.timestamp
        LEFT JOIN slas sla
            ON sla.postal_center_id = pe_entry.postal_center_id
            AND sla.sla_type = 'operational'
            AND sla.carrier_id = pe_entry.carrier_id
            AND sla.product_id = pe_entry.product_id
            AND sla.deleted_at IS NULL
        WHERE pe_entry.account_id = p_account_id
        AND pe_entry.event_type = 'entry'
        AND pe_exit.id IS NULL
        AND pe_entry.timestamp < NOW() - INTERVAL '24 hours'
        AND pe_entry.is_estimated = FALSE
        ORDER BY pe_entry.tag_id, pe_entry.postal_center_id, pe_entry.timestamp DESC
    LOOP
        -- Get SLA time or default to 3 hours
        v_sla_minutes := COALESCE(v_missing_exit.expected_time_minutes, 180);
        
        -- Calculate estimated exit timestamp
        v_estimated_exit_timestamp := v_missing_exit.entry_timestamp + 
                                      (v_sla_minutes || ' minutes')::INTERVAL;
        
        -- Get reader type (assume Exit for missing exits)
        SELECT type INTO v_reader_type
        FROM readers
        WHERE id = v_missing_exit.reader_id
        AND type = 'Exit'
        LIMIT 1;
        
        -- If no exit reader found, use the entry reader
        IF v_reader_type IS NULL THEN
            SELECT type INTO v_reader_type
            FROM readers
            WHERE id = v_missing_exit.reader_id
            LIMIT 1;
        END IF;
        
        -- Create estimated exit event (UPDATED with reader snapshots and carrier/product)
        INSERT INTO processed_events (
            account_id,
            tag_id,
            reader_id,
            postal_center_id,
            postal_center_name_snapshot,
            postal_center_code_snapshot,
            reader_id_snapshot,
            reader_type_snapshot,
            event_type,
            timestamp,
            analysis_datetime,
            raw_event_count,
            is_consolidated,
            is_estimated,
            carrier_id,
            product_id
        ) VALUES (
            p_account_id,
            v_missing_exit.tag_id,
            v_missing_exit.reader_id,
            v_missing_exit.postal_center_id,
            v_missing_exit.postal_center_name,
            v_missing_exit.postal_center_code,
            v_missing_exit.reader_id::TEXT,
            COALESCE(v_reader_type, 'Exit'),
            'exit',
            v_estimated_exit_timestamp,
            v_estimated_exit_timestamp,
            0,
            TRUE,
            TRUE,
            v_missing_exit.carrier_id,
            v_missing_exit.product_id
        );
        
        -- Create incident
        INSERT INTO incidents (
            account_id,
            tag_id,
            incident_type,
            severity,
            description,
            detected_at,
            metadata
        ) VALUES (
            p_account_id,
            v_missing_exit.tag_id,
            'missing_exit',
            'medium',
            'Exit event missing for ' || v_missing_exit.tag_id || ' at ' || 
            v_missing_exit.postal_center_name || '. Exit estimated using SLA (' || 
            v_sla_minutes || ' minutes).',
            NOW(),
            jsonb_build_object(
                'postal_center_id', v_missing_exit.postal_center_id,
                'entry_timestamp', v_missing_exit.entry_timestamp,
                'estimated_exit_timestamp', v_estimated_exit_timestamp,
                'sla_minutes', v_sla_minutes,
                'carrier_id', v_missing_exit.carrier_id,
                'product_id', v_missing_exit.product_id
            )
        );
        
        v_count := v_count + 1;
    END LOOP;
    
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

SELECT 'detect_missing_exits function updated' AS status;
