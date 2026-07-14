-- Migration 018: Create trigger for automatic transfer to ONE_DB
-- Version: 2.0
-- Date: 2025-12-10

-- Function to transfer validated records to ONE_DB
CREATE OR REPLACE FUNCTION transfer_to_one_db()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_errors TEXT[] := '{}';
  v_account_id UUID;
  v_plan_name TEXT;
  v_carrier_name TEXT;
  v_product_name TEXT;
  v_origin_city_name TEXT;
  v_destination_city_name TEXT;
  v_total_transit_days INTEGER;
  v_business_transit_days INTEGER;
  v_on_time_delivery BOOLEAN := NULL;
  v_delivery_standard INTEGER;
BEGIN
  -- Only process if status changed to 'received' and not already transferred
  IF NEW.status = 'received' AND OLD.status != 'received' AND NEW.transferred_to_one_db_at IS NULL THEN
    
    -- STEP 1: VALIDATION
    -- Reset validation errors
    v_errors := '{}';
    
    -- Validate: sent_at must not be NULL
    IF NEW.sent_at IS NULL THEN
      v_errors := array_append(v_errors, 'Missing sent date');
    END IF;
    
    -- Validate: received_at must not be NULL
    IF NEW.received_at IS NULL THEN
      v_errors := array_append(v_errors, 'Missing received date');
    END IF;
    
    -- Validate: sent_at must be before or equal to received_at
    IF NEW.sent_at IS NOT NULL AND NEW.received_at IS NOT NULL AND NEW.sent_at > NEW.received_at THEN
      v_errors := array_append(v_errors, 'Sent date is after received date');
    END IF;
    
    -- Validate: tag_id must not be NULL or empty
    IF NEW.tag_id IS NULL OR trim(NEW.tag_id) = '' THEN
      v_errors := array_append(v_errors, 'Missing Tag ID');
    END IF;
    
    -- Validate: origin_panelist_id must not be NULL
    IF NEW.origin_panelist_id IS NULL THEN
      v_errors := array_append(v_errors, 'Missing origin panelist');
    END IF;
    
    -- Validate: destination_panelist_id must not be NULL
    IF NEW.destination_panelist_id IS NULL THEN
      v_errors := array_append(v_errors, 'Missing destination panelist');
    END IF;
    
    -- If validation failed, mark as invalid
    IF array_length(v_errors, 1) > 0 THEN
      UPDATE allocation_plan_details 
      SET 
        status = 'invalid',
        validation_errors = v_errors
      WHERE id = NEW.id;
      
      RETURN NEW;
    END IF;
    
    -- STEP 2: GATHER DATA FOR TRANSFER
    BEGIN
      -- Get account_id from the allocation plan
      SELECT ap.account_id, ap.plan_name
      INTO v_account_id, v_plan_name
      FROM allocation_plans ap
      WHERE ap.id = NEW.plan_id;
      
      -- Get carrier name
      SELECT c.name
      INTO v_carrier_name
      FROM carriers c
      WHERE c.id = NEW.carrier_id;
      
      -- Get product name
      SELECT p.description
      INTO v_product_name
      FROM products p
      WHERE p.id = NEW.product_id;
      
      -- Get origin city name
      SELECT c.name
      INTO v_origin_city_name
      FROM cities c
      WHERE c.id = NEW.origin_city_id;
      
      -- Get destination city name
      SELECT c.name
      INTO v_destination_city_name
      FROM cities c
      WHERE c.id = NEW.destination_city_id;
      
      -- Calculate total transit days
      v_total_transit_days := EXTRACT(DAY FROM (NEW.received_at - NEW.sent_at))::INTEGER;
      
      -- Calculate business transit days
      v_business_transit_days := calculate_business_days(NEW.sent_at, NEW.received_at, v_account_id);
      
      -- Calculate on_time_delivery based on delivery_standards
      SELECT ds.delivery_time
      INTO v_delivery_standard
      FROM delivery_standards ds
      WHERE ds.carrier_id = NEW.carrier_id
        AND ds.product_id = NEW.product_id
        AND ds.origin_city_id = NEW.origin_city_id
        AND ds.destination_city_id = NEW.destination_city_id
      LIMIT 1;
      
      IF v_delivery_standard IS NOT NULL THEN
        v_on_time_delivery := (v_total_transit_days <= v_delivery_standard);
      END IF;
      
      -- STEP 3: INSERT INTO ONE_DB
      INSERT INTO one_db (
        account_id,
        allocation_detail_id,
        tag_id,
        plan_name,
        carrier_name,
        product_name,
        origin_city_name,
        destination_city_name,
        sent_at,
        received_at,
        total_transit_days,
        business_transit_days,
        on_time_delivery,
        source_data_snapshot
      ) VALUES (
        v_account_id,
        NEW.id,
        NEW.tag_id,
        v_plan_name,
        v_carrier_name,
        v_product_name,
        v_origin_city_name,
        v_destination_city_name,
        NEW.sent_at,
        NEW.received_at,
        v_total_transit_days,
        v_business_transit_days,
        v_on_time_delivery,
        to_jsonb(NEW)
      );
      
      -- STEP 4: MARK AS TRANSFERRED
      UPDATE allocation_plan_details 
      SET transferred_to_one_db_at = NOW()
      WHERE id = NEW.id;
      
    EXCEPTION WHEN OTHERS THEN
      -- STEP 5: HANDLE TRANSFER ERRORS
      UPDATE allocation_plan_details 
      SET 
        status = 'transfer_error',
        transfer_error_message = SQLERRM
      WHERE id = NEW.id;
      
      -- Log the error (optional: create a separate error log table)
      RAISE WARNING 'Transfer to ONE_DB failed for allocation_detail_id %: %', NEW.id, SQLERRM;
    END;
    
  END IF;
  
  RETURN NEW;
END;
$$;

-- Create trigger
DROP TRIGGER IF EXISTS trigger_transfer_to_one_db ON allocation_plan_details;
CREATE TRIGGER trigger_transfer_to_one_db
  AFTER UPDATE ON allocation_plan_details
  FOR EACH ROW
  EXECUTE FUNCTION transfer_to_one_db();

-- Add comment
COMMENT ON FUNCTION transfer_to_one_db IS 'Validates and transfers received records to ONE_DB, marking as invalid or transfer_error if issues occur';
