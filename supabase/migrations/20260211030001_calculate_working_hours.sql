-- Sprint 10: Calculate Working Hours Function
-- This function calculates working hours between two timestamps considering:
-- 1. Cut-off times
-- 2. Working hours (start/end)
-- 3. Working days (Mon-Fri by default)
-- 4. Non-working days (holidays, closures)

CREATE OR REPLACE FUNCTION calculate_working_hours(
    p_start_timestamp TIMESTAMPTZ,
    p_end_timestamp TIMESTAMPTZ,
    p_account_id UUID,
    p_postal_center_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_cutoff_config RECORD;
    v_current_timestamp TIMESTAMPTZ;
    v_working_minutes INTEGER := 0;
    v_current_date DATE;
    v_day_of_week INTEGER;
    v_is_working_day BOOLEAN;
    v_is_non_working_day BOOLEAN;
    v_day_start TIMESTAMPTZ;
    v_day_end TIMESTAMPTZ;
    v_segment_start TIMESTAMPTZ;
    v_segment_end TIMESTAMPTZ;
    v_segment_minutes INTEGER;
BEGIN
    -- Validate inputs
    IF p_start_timestamp IS NULL OR p_end_timestamp IS NULL THEN
        RETURN 0;
    END IF;
    
    IF p_end_timestamp <= p_start_timestamp THEN
        RETURN 0;
    END IF;
    
    -- Get cut-off configuration for the postal center
    SELECT 
        cutoff_time,
        timezone,
        working_hours_start,
        working_hours_end,
        working_days
    INTO v_cutoff_config
    FROM postal_center_cutoffs
    WHERE account_id = p_account_id
      AND postal_center_id = p_postal_center_id
      AND is_active = true
    LIMIT 1;
    
    -- If no cut-off config exists, use defaults
    IF v_cutoff_config IS NULL THEN
        v_cutoff_config.working_hours_start := '09:00:00'::TIME;
        v_cutoff_config.working_hours_end := '18:00:00'::TIME;
        v_cutoff_config.working_days := ARRAY[1,2,3,4,5]; -- Mon-Fri
        v_cutoff_config.timezone := 'UTC';
    END IF;
    
    -- Iterate through each day between start and end
    v_current_timestamp := p_start_timestamp;
    
    WHILE v_current_timestamp < p_end_timestamp LOOP
        v_current_date := v_current_timestamp::DATE;
        v_day_of_week := EXTRACT(ISODOW FROM v_current_date); -- 1=Monday, 7=Sunday
        
        -- Check if it's a working day
        v_is_working_day := v_day_of_week = ANY(v_cutoff_config.working_days);
        
        -- Check if it's a non-working day (holiday)
        SELECT EXISTS(
            SELECT 1 FROM non_working_days
            WHERE account_id = p_account_id
              AND date = v_current_date
              AND (applies_to_all_centers = true 
                   OR p_postal_center_id = ANY(postal_center_ids))
        ) INTO v_is_non_working_day;
        
        -- Only count working hours if it's a working day and not a holiday
        IF v_is_working_day AND NOT v_is_non_working_day THEN
            -- Calculate working hours for this day
            v_day_start := v_current_date + v_cutoff_config.working_hours_start;
            v_day_end := v_current_date + v_cutoff_config.working_hours_end;
            
            -- Determine the actual segment to count
            v_segment_start := GREATEST(v_current_timestamp, v_day_start);
            v_segment_end := LEAST(p_end_timestamp, v_day_end);
            
            -- Only count if there's overlap with working hours
            IF v_segment_start < v_segment_end THEN
                v_segment_minutes := EXTRACT(EPOCH FROM (v_segment_end - v_segment_start))::INTEGER / 60;
                v_working_minutes := v_working_minutes + v_segment_minutes;
            END IF;
        END IF;
        
        -- Move to next day
        v_current_timestamp := (v_current_date + INTERVAL '1 day')::TIMESTAMPTZ;
    END LOOP;
    
    RETURN v_working_minutes;
END;
$$;

-- Comment
COMMENT ON FUNCTION calculate_working_hours IS 'Calculates working hours between two timestamps considering cut-off times, working hours, working days, and non-working days calendar';
