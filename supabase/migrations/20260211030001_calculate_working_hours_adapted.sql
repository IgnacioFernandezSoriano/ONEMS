-- Sprint 10: Calculate Working Hours Function (Adapted)
-- Uses postal_centers.opening_hour, working_hours_end, working_days, timezone

CREATE OR REPLACE FUNCTION calculate_working_hours(
    p_start_time TIMESTAMPTZ,
    p_end_time TIMESTAMPTZ,
    p_account_id UUID,
    p_postal_center_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_working_hours_start TIME;
    v_working_hours_end TIME;
    v_working_days TEXT[];
    v_timezone TEXT;
    v_current_date DATE;
    v_end_date DATE;
    v_total_minutes INTEGER := 0;
    v_day_start TIMESTAMPTZ;
    v_day_end TIMESTAMPTZ;
    v_day_name TEXT;
    v_is_working_day BOOLEAN;
    v_is_non_working_day BOOLEAN;
    v_work_start TIMESTAMPTZ;
    v_work_end TIMESTAMPTZ;
    v_overlap_start TIMESTAMPTZ;
    v_overlap_end TIMESTAMPTZ;
BEGIN
    -- Get postal center configuration
    SELECT 
        COALESCE(opening_hour, '09:00:00'::TIME),
        COALESCE(working_hours_end, '18:00:00'::TIME),
        COALESCE(working_days, ARRAY['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday']),
        COALESCE(timezone, 'UTC')
    INTO 
        v_working_hours_start,
        v_working_hours_end,
        v_working_days,
        v_timezone
    FROM postal_centers
    WHERE id = p_postal_center_id
      AND account_id = p_account_id
      AND deleted_at IS NULL;
    
    -- If no configuration found, use defaults
    IF v_working_hours_start IS NULL THEN
        v_working_hours_start := '09:00:00'::TIME;
        v_working_hours_end := '18:00:00'::TIME;
        v_working_days := ARRAY['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
        v_timezone := 'UTC';
    END IF;
    
    -- Convert timestamps to postal center timezone
    v_current_date := (p_start_time AT TIME ZONE v_timezone)::DATE;
    v_end_date := (p_end_time AT TIME ZONE v_timezone)::DATE;
    
    -- Loop through each day in the range
    WHILE v_current_date <= v_end_date LOOP
        -- Get day name
        v_day_name := TO_CHAR(v_current_date, 'Day');
        v_day_name := TRIM(v_day_name);
        v_day_name := INITCAP(v_day_name);
        
        -- Check if it's a working day
        v_is_working_day := v_day_name = ANY(v_working_days);
        
        -- Check if it's a non-working day (holiday/closure)
        SELECT EXISTS(
            SELECT 1
            FROM non_working_days nwd
            WHERE nwd.account_id = p_account_id
              AND nwd.date = v_current_date
              AND (
                  nwd.applies_to_all_centers = true
                  OR p_postal_center_id = ANY(nwd.postal_center_ids)
              )
              AND nwd.deleted_at IS NULL
        ) INTO v_is_non_working_day;
        
        -- Only count working hours if it's a working day and not a holiday
        IF v_is_working_day AND NOT v_is_non_working_day THEN
            -- Calculate working hours for this day
            v_day_start := (v_current_date || ' 00:00:00')::TIMESTAMP AT TIME ZONE v_timezone;
            v_day_end := (v_current_date || ' 23:59:59')::TIMESTAMP AT TIME ZONE v_timezone;
            
            v_work_start := (v_current_date || ' ' || v_working_hours_start::TEXT)::TIMESTAMP AT TIME ZONE v_timezone;
            v_work_end := (v_current_date || ' ' || v_working_hours_end::TEXT)::TIMESTAMP AT TIME ZONE v_timezone;
            
            -- Calculate overlap between work hours and time range
            v_overlap_start := GREATEST(v_work_start, p_start_time);
            v_overlap_end := LEAST(v_work_end, p_end_time);
            
            -- Add minutes if there's overlap
            IF v_overlap_start < v_overlap_end THEN
                v_total_minutes := v_total_minutes + EXTRACT(EPOCH FROM (v_overlap_end - v_overlap_start))::INTEGER / 60;
            END IF;
        END IF;
        
        -- Move to next day
        v_current_date := v_current_date + INTERVAL '1 day';
    END LOOP;
    
    RETURN v_total_minutes;
END;
$$;

COMMENT ON FUNCTION calculate_working_hours IS 'Calculate working hours between two timestamps considering working days, working hours, and non-working days (holidays)';
