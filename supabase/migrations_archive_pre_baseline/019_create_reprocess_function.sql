-- Migration 019: Create function to reprocess transfer errors
-- Version: 2.0
-- Date: 2025-12-10

-- Function to reprocess records with transfer_error status
CREATE OR REPLACE FUNCTION reprocess_transfer_errors(p_detail_ids UUID[])
RETURNS TABLE (
  detail_id UUID,
  success BOOLEAN,
  message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_detail_id UUID;
  v_current_status TEXT;
BEGIN
  -- Loop through each provided ID
  FOREACH v_detail_id IN ARRAY p_detail_ids LOOP
    -- Get current status
    SELECT status INTO v_current_status
    FROM allocation_plan_details
    WHERE id = v_detail_id;
    
    -- Only reprocess if status is 'transfer_error'
    IF v_current_status = 'transfer_error' THEN
      BEGIN
        -- Reset the status to 'received' to trigger the transfer again
        -- Clear the error message
        UPDATE allocation_plan_details
        SET 
          status = 'received',
          transfer_error_message = NULL
        WHERE id = v_detail_id;
        
        -- Return success
        detail_id := v_detail_id;
        success := TRUE;
        message := 'Reprocessing initiated';
        RETURN NEXT;
        
      EXCEPTION WHEN OTHERS THEN
        -- Return error
        detail_id := v_detail_id;
        success := FALSE;
        message := SQLERRM;
        RETURN NEXT;
      END;
    ELSE
      -- Return error: wrong status
      detail_id := v_detail_id;
      success := FALSE;
      message := 'Record status is not transfer_error (current: ' || v_current_status || ')';
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$$;

-- Add comment
COMMENT ON FUNCTION reprocess_transfer_errors IS 'Reprocesses records with transfer_error status by resetting them to received to trigger the transfer again';
