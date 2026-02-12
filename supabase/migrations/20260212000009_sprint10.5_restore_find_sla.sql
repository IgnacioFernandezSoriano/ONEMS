-- =====================================================
-- Restore original find_applicable_sla (without carrier)
-- =====================================================

DROP FUNCTION IF EXISTS find_applicable_sla CASCADE;

CREATE OR REPLACE FUNCTION find_applicable_sla(
    p_account_id UUID,
    p_segment_type TEXT,
    p_postal_center_id UUID DEFAULT NULL,
    p_from_postal_center_id UUID DEFAULT NULL,
    p_to_postal_center_id UUID DEFAULT NULL
)
RETURNS TABLE (
    sla_id UUID,
    expected_time_minutes INTEGER,
    on_time_percentage INTEGER,
    warning_threshold INTEGER,
    critical_threshold INTEGER
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    IF p_segment_type = 'operational' THEN
        -- Find operational SLA
        RETURN QUERY
        SELECT 
            s.id,
            s.expected_time_minutes,
            s.on_time_percentage,
            s.warning_threshold,
            s.critical_threshold
        FROM slas s
        WHERE s.account_id = p_account_id
          AND s.sla_type = 'operational'
          AND s.postal_center_id = p_postal_center_id
          AND s.is_active = true
          AND s.deleted_at IS NULL
          AND s.carrier_id IS NULL  -- Only match SLAs without carrier
        LIMIT 1;
    ELSE
        -- Find distribution SLA
        RETURN QUERY
        SELECT 
            s.id,
            s.expected_time_minutes,
            s.on_time_percentage,
            s.warning_threshold,
            s.critical_threshold
        FROM slas s
        WHERE s.account_id = p_account_id
          AND s.sla_type = 'distribution'
          AND s.from_postal_center_id = p_from_postal_center_id
          AND s.to_postal_center_id = p_to_postal_center_id
          AND s.is_active = true
          AND s.deleted_at IS NULL
          AND s.carrier_id IS NULL  -- Only match SLAs without carrier
        LIMIT 1;
    END IF;
END;
$$;

COMMENT ON FUNCTION find_applicable_sla IS 
'Finds applicable SLA for operational or distribution segments (without carrier support).';
