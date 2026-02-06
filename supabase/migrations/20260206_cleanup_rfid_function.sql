-- ============================================
-- RFID INTERMEDIATE DB - CLEANUP FUNCTION
-- ============================================
-- This function deletes processed RFID events from the intermediate database
-- to keep the table clean and performant

CREATE OR REPLACE FUNCTION cleanup_processed_rfid_events(
  p_account_id UUID DEFAULT NULL,
  p_older_than_hours INTEGER DEFAULT 24
)
RETURNS TABLE (
  deleted_count INTEGER,
  account_id UUID,
  oldest_processed_at TIMESTAMPTZ,
  newest_processed_at TIMESTAMPTZ
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_deleted_count INTEGER;
  v_oldest_processed TIMESTAMPTZ;
  v_newest_processed TIMESTAMPTZ;
  v_cutoff_time TIMESTAMPTZ;
BEGIN
  -- Calculate cutoff time (only delete events processed more than X hours ago)
  v_cutoff_time := NOW() - (p_older_than_hours || ' hours')::INTERVAL;

  -- Get statistics before deletion
  SELECT 
    MIN(processed_at),
    MAX(processed_at)
  INTO 
    v_oldest_processed,
    v_newest_processed
  FROM rfid_intermediate_db
  WHERE processed_at IS NOT NULL
    AND processed_at < v_cutoff_time
    AND (p_account_id IS NULL OR account_id = p_account_id);

  -- Delete processed events
  WITH deleted AS (
    DELETE FROM rfid_intermediate_db
    WHERE processed_at IS NOT NULL
      AND processed_at < v_cutoff_time
      AND (p_account_id IS NULL OR account_id = p_account_id)
    RETURNING *
  )
  SELECT COUNT(*)::INTEGER INTO v_deleted_count FROM deleted;

  -- Return results
  RETURN QUERY SELECT 
    v_deleted_count,
    p_account_id,
    v_oldest_processed,
    v_newest_processed;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION cleanup_processed_rfid_events(UUID, INTEGER) TO authenticated;

-- Add comment
COMMENT ON FUNCTION cleanup_processed_rfid_events IS 
'Deletes processed RFID events from rfid_intermediate_db. 
Parameters:
- p_account_id: Optional UUID to limit cleanup to specific account (NULL = all accounts)
- p_older_than_hours: Only delete events processed more than X hours ago (default: 24)
Returns: Statistics about deleted records';

-- Verify
SELECT 'RFID cleanup function created successfully' as status;
