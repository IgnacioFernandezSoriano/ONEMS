-- DEMO2 Account Reset Script
-- Corrected version with proper foreign key constraint handling
-- This script deletes operational data while preserving configuration

-- Get DEMO2 account ID
DO $$
DECLARE
  demo2_account_id UUID;
  deleted_counts JSONB := '{}'::jsonb;
BEGIN
  -- Get DEMO2 account ID
  SELECT id INTO demo2_account_id FROM accounts WHERE name = 'DEMO2';
  
  IF demo2_account_id IS NULL THEN
    RAISE EXCEPTION 'DEMO2 account not found';
  END IF;

  -- Delete in correct order to respect foreign key constraints
  
  -- 1. Delete SLAs first (depends on products)
  WITH deleted AS (
    DELETE FROM slas 
    WHERE account_id = demo2_account_id
    RETURNING *
  )
  SELECT count(*) INTO deleted_counts FROM deleted;
  RAISE NOTICE 'Deleted % SLAs', deleted_counts;

  -- 2. Delete allocation plans
  WITH deleted AS (
    DELETE FROM allocation_plans 
    WHERE account_id = demo2_account_id
    RETURNING *
  )
  SELECT count(*) INTO deleted_counts FROM deleted;
  RAISE NOTICE 'Deleted % allocation plans', deleted_counts;

  -- 3. Delete applied allocation plans
  WITH deleted AS (
    DELETE FROM applied_allocation_plans 
    WHERE account_id = demo2_account_id
    RETURNING *
  )
  SELECT count(*) INTO deleted_counts FROM deleted;
  RAISE NOTICE 'Deleted % applied allocation plans', deleted_counts;

  -- 4. Delete panelist unavailability
  WITH deleted AS (
    DELETE FROM panelist_unavailability 
    WHERE account_id = demo2_account_id
    RETURNING *
  )
  SELECT count(*) INTO deleted_counts FROM deleted;
  RAISE NOTICE 'Deleted % panelist unavailability records', deleted_counts;

  -- 5. Delete stock alerts
  WITH deleted AS (
    DELETE FROM stock_alerts 
    WHERE account_id = demo2_account_id
    RETURNING *
  )
  SELECT count(*) INTO deleted_counts FROM deleted;
  RAISE NOTICE 'Deleted % stock alerts', deleted_counts;

  -- 6. Delete panelist stock
  WITH deleted AS (
    DELETE FROM panelist_stock 
    WHERE account_id = demo2_account_id
    RETURNING *
  )
  SELECT count(*) INTO deleted_counts FROM deleted;
  RAISE NOTICE 'Deleted % panelist stock records', deleted_counts;

  -- 7. Delete regulator stock
  WITH deleted AS (
    DELETE FROM regulator_stock 
    WHERE account_id = demo2_account_id
    RETURNING *
  )
  SELECT count(*) INTO deleted_counts FROM deleted;
  RAISE NOTICE 'Deleted % regulator stock records', deleted_counts;

  -- 8. Delete proposed shipments
  WITH deleted AS (
    DELETE FROM proposed_shipments 
    WHERE account_id = demo2_account_id
    RETURNING *
  )
  SELECT count(*) INTO deleted_counts FROM deleted;
  RAISE NOTICE 'Deleted % proposed shipments', deleted_counts;

  -- 9. Delete complete journeys
  WITH deleted AS (
    DELETE FROM complete_journeys 
    WHERE account_id = demo2_account_id
    RETURNING *
  )
  SELECT count(*) INTO deleted_counts FROM deleted;
  RAISE NOTICE 'Deleted % complete journeys', deleted_counts;

  -- 10. Delete journey segments
  WITH deleted AS (
    DELETE FROM journey_segments 
    WHERE account_id = demo2_account_id
    RETURNING *
  )
  SELECT count(*) INTO deleted_counts FROM deleted;
  RAISE NOTICE 'Deleted % journey segments', deleted_counts;

  -- 11. Delete processed events
  WITH deleted AS (
    DELETE FROM processed_events 
    WHERE account_id = demo2_account_id
    RETURNING *
  )
  SELECT count(*) INTO deleted_counts FROM deleted;
  RAISE NOTICE 'Deleted % processed events', deleted_counts;

  -- 12. Delete reader location history
  WITH deleted AS (
    DELETE FROM reader_location_history 
    WHERE account_id = demo2_account_id
    RETURNING *
  )
  SELECT count(*) INTO deleted_counts FROM deleted;
  RAISE NOTICE 'Deleted % reader location history records', deleted_counts;

  RAISE NOTICE 'DEMO2 account reset completed successfully';
END $$;
