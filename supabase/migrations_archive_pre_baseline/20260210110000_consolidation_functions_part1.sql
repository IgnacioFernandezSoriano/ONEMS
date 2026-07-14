-- =====================================================
-- Sprint 7: Event Consolidation - SQL Functions (Part 1)
-- =====================================================
-- Description: Helper functions for event consolidation
-- Author: Development Team
-- Date: 2026-02-10
-- =====================================================

-- =====================================================
-- 1. Calculate Next Working Datetime
-- =====================================================
-- Adjusts timestamp to next working hour considering holidays and schedule

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
    v_max_iterations INTEGER := 365; -- Prevent infinite loop
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
            -- Move to next day at midnight
            v_current_date := v_current_date + INTERVAL '1 day';
            v_current_time := '00:00:00'::TIME;
            CONTINUE;
        END IF;
        
        -- Get schedule for current day
        v_day_of_week := EXTRACT(ISODOW FROM v_current_date); -- 1=Monday, 7=Sunday
        
        SELECT 
            open_time, 
            close_time, 
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

-- =====================================================
-- 2. Calculate Working Days Time
-- =====================================================
-- Calculates time excluding non-working periods (holidays, outside hours)

CREATE OR REPLACE FUNCTION calculate_working_days_time(
    p_start_datetime TIMESTAMPTZ,
    p_end_datetime TIMESTAMPTZ,
    p_postal_center_id UUID
) RETURNS INTEGER AS $$
DECLARE
    v_adjusted_minutes INTEGER := 0;
    v_current_date DATE;
    v_end_date DATE;
    v_day_of_week INTEGER;
    v_open_time TIME;
    v_close_time TIME;
    v_is_working_day BOOLEAN;
    v_period_start TIMESTAMPTZ;
    v_period_end TIMESTAMPTZ;
    v_work_start TIMESTAMPTZ;
    v_work_end TIMESTAMPTZ;
    v_max_days INTEGER := 365; -- Prevent infinite loop
    v_days_processed INTEGER := 0;
BEGIN
    v_current_date := p_start_datetime::DATE;
    v_end_date := p_end_datetime::DATE;
    
    WHILE v_current_date <= v_end_date AND v_days_processed < v_max_days LOOP
        v_days_processed := v_days_processed + 1;
        
        -- Check if it's a holiday
        IF EXISTS (
            SELECT 1 FROM non_working_days
            WHERE postal_center_id = p_postal_center_id
            AND date = v_current_date
        ) THEN
            v_current_date := v_current_date + INTERVAL '1 day';
            CONTINUE;
        END IF;
        
        -- Get schedule for current day
        v_day_of_week := EXTRACT(ISODOW FROM v_current_date);
        
        SELECT 
            open_time, 
            close_time, 
            is_working_day
        INTO 
            v_open_time, 
            v_close_time, 
            v_is_working_day
        FROM weekly_schedule
        WHERE postal_center_id = p_postal_center_id
        AND day_of_week = v_day_of_week;
        
        -- If no schedule or not working day, skip
        IF v_open_time IS NULL OR v_is_working_day = FALSE THEN
            v_current_date := v_current_date + INTERVAL '1 day';
            CONTINUE;
        END IF;
        
        -- Calculate intersection with working hours
        v_work_start := (v_current_date + v_open_time)::TIMESTAMPTZ;
        v_work_end := (v_current_date + v_close_time)::TIMESTAMPTZ;
        
        v_period_start := GREATEST(p_start_datetime, v_work_start);
        v_period_end := LEAST(p_end_datetime, v_work_end);
        
        -- If there's intersection, add minutes
        IF v_period_start < v_period_end THEN
            v_adjusted_minutes := v_adjusted_minutes + 
                EXTRACT(EPOCH FROM (v_period_end - v_period_start))::INTEGER / 60;
        END IF;
        
        v_current_date := v_current_date + INTERVAL '1 day';
    END LOOP;
    
    RETURN v_adjusted_minutes;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 3. Get Reader Info
-- =====================================================
-- Helper function to get reader information by code

CREATE OR REPLACE FUNCTION get_reader_info(
    p_reader_code TEXT,
    p_account_id UUID
) RETURNS TABLE (
    reader_id UUID,
    reader_type TEXT,
    postal_center_id UUID,
    postal_center_name TEXT,
    postal_center_code TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        r.id,
        r.type,
        r.postal_center_id,
        pc.name,
        pc.code
    FROM readers r
    JOIN postal_centers pc ON r.postal_center_id = pc.id
    WHERE r.code = p_reader_code
    AND r.account_id = p_account_id
    AND r.deleted_at IS NULL
    AND pc.deleted_at IS NULL;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- Summary
-- =====================================================

DO $$
BEGIN
    RAISE NOTICE '✅ Consolidation helper functions created successfully';
    RAISE NOTICE '   - calculate_next_working_datetime()';
    RAISE NOTICE '   - calculate_working_days_time()';
    RAISE NOTICE '   - get_reader_info()';
END $$;
