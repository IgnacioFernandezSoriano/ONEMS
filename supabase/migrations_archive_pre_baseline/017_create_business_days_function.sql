-- Migration 017: Create function to calculate business days
-- Version: 2.0
-- Date: 2025-12-10

-- Function to calculate business days (Monday-Friday)
-- Optionally excludes holidays if a holidays table exists for the account
CREATE OR REPLACE FUNCTION calculate_business_days(
  p_start_date TIMESTAMPTZ,
  p_end_date TIMESTAMPTZ,
  p_account_id UUID DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_business_days INTEGER := 0;
  v_current_date DATE;
  v_end_date DATE;
  v_day_of_week INTEGER;
  v_is_holiday BOOLEAN;
BEGIN
  -- Convert timestamps to dates
  v_current_date := p_start_date::DATE;
  v_end_date := p_end_date::DATE;
  
  -- Loop through each day
  WHILE v_current_date < v_end_date LOOP
    -- Get day of week (0=Sunday, 6=Saturday)
    v_day_of_week := EXTRACT(DOW FROM v_current_date);
    
    -- Check if it's a weekday (Monday-Friday)
    IF v_day_of_week BETWEEN 1 AND 5 THEN
      -- Check if it's a holiday (if holidays table exists)
      v_is_holiday := FALSE;
      
      -- TODO: Implement holiday check when holidays table is created
      -- IF EXISTS (SELECT 1 FROM holidays WHERE account_id = p_account_id AND holiday_date = v_current_date) THEN
      --   v_is_holiday := TRUE;
      -- END IF;
      
      -- Count as business day if not a holiday
      IF NOT v_is_holiday THEN
        v_business_days := v_business_days + 1;
      END IF;
    END IF;
    
    -- Move to next day
    v_current_date := v_current_date + INTERVAL '1 day';
  END LOOP;
  
  RETURN v_business_days;
END;
$$;

-- Add comment
COMMENT ON FUNCTION calculate_business_days IS 'Calculates business days (Mon-Fri) between two timestamps, optionally excluding holidays';
