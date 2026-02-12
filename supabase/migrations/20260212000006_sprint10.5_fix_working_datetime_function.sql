-- =====================================================
-- Sprint 10.5: Fix calculate_next_working_datetime
-- =====================================================
-- Fix day_of_week mapping: ISODOW (1-7) → table (0-6)
-- ISODOW: 1=Monday, 7=Sunday
-- Table: 0=Sunday, 1=Monday, ..., 6=Saturday

CREATE OR REPLACE FUNCTION calculate_next_working_datetime(
    p_timestamp TIMESTAMPTZ,
    p_postal_center_id UUID
) RETURNS TIMESTAMPTZ AS $$
DECLARE
    v_current_date DATE;
    v_current_time TIME;
    v_day_of_week INTEGER;
    v_open_time TIME;
    v_close_time TIME;
    v_is_working_day BOOLEAN;
    v_max_iterations INTEGER := 365;
    v_iteration INTEGER := 0;
BEGIN
    v_current_date := p_timestamp::DATE;
    v_current_time := p_timestamp::TIME;
    
    WHILE v_iteration < v_max_iterations LOOP
        v_iteration := v_iteration + 1;
        
        -- Check if it's a holiday
        IF EXISTS (
            SELECT 1 FROM non_working_days
            WHERE postal_center_id = p_postal_center_id
            AND date = v_current_date
        ) THEN
            v_current_date := v_current_date + INTERVAL '1 day';
            v_current_time := '00:00:00'::TIME;
            CONTINUE;
        END IF;
        
        -- Get day of week and convert ISODOW (1-7) to table format (0-6)
        -- ISODOW: 1=Mon, 2=Tue, ..., 7=Sun
        -- Table: 0=Sun, 1=Mon, ..., 6=Sat
        v_day_of_week := EXTRACT(ISODOW FROM v_current_date)::INTEGER;
        IF v_day_of_week = 7 THEN
            v_day_of_week := 0;  -- Sunday: ISODOW 7 → table 0
        END IF;
        
        -- Get schedule for current day
        SELECT 
            opening_hour, 
            cutoff_time, 
            is_working_day
        INTO 
            v_open_time, 
            v_close_time, 
            v_is_working_day
        FROM weekly_schedule
        WHERE postal_center_id = p_postal_center_id
        AND day_of_week = v_day_of_week;
        
        -- If no schedule or not a working day, move to next day
        IF v_open_time IS NULL OR v_is_working_day = FALSE THEN
            v_current_date := v_current_date + INTERVAL '1 day';
            v_current_time := '00:00:00'::TIME;
            CONTINUE;
        END IF;
        
        -- Check if current time is before opening
        IF v_current_time < v_open_time THEN
            RETURN (v_current_date + v_open_time)::TIMESTAMPTZ;
        END IF;
        
        -- Check if current time is after closing
        IF v_current_time > v_close_time THEN
            v_current_date := v_current_date + INTERVAL '1 day';
            v_current_time := '00:00:00'::TIME;
            CONTINUE;
        END IF;
        
        -- Current time is within working hours
        RETURN p_timestamp;
    END LOOP;
    
    -- If we reach here, something went wrong
    RAISE EXCEPTION 'Could not find next working datetime after % iterations', v_max_iterations;
END;
$$ LANGUAGE plpgsql;
