-- Sprint 10: Update calculate_adjusted_time to use working hours
-- This migration updates the calculate_adjusted_time function to use calculate_working_hours

DROP FUNCTION IF EXISTS calculate_adjusted_time(TIMESTAMPTZ, TIMESTAMPTZ, UUID, UUID);

CREATE OR REPLACE FUNCTION calculate_adjusted_time(
    p_entry_timestamp TIMESTAMPTZ,
    p_exit_timestamp TIMESTAMPTZ,
    p_account_id UUID,
    p_postal_center_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_working_minutes INTEGER;
BEGIN
    -- Use the new calculate_working_hours function
    v_working_minutes := calculate_working_hours(
        p_entry_timestamp,
        p_exit_timestamp,
        p_account_id,
        p_postal_center_id
    );
    
    RETURN v_working_minutes;
END;
$$;

COMMENT ON FUNCTION calculate_adjusted_time IS 'Calculates adjusted time in minutes between entry and exit timestamps using working hours logic (cut-offs, working days, holidays)';
