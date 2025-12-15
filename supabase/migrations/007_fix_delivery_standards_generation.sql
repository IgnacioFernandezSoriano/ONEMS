-- ============================================
-- FIX: Generate delivery standards only for carrier's own products
-- ============================================

-- Drop the old function
DROP FUNCTION IF EXISTS generate_delivery_standards(UUID[], UUID[], UUID[]);

-- Create corrected function that respects carrier-product relationship
CREATE OR REPLACE FUNCTION generate_delivery_standards(
  p_carrier_ids UUID[],
  p_product_ids UUID[],
  p_city_ids UUID[] DEFAULT NULL
)
RETURNS TABLE(
  inserted_count INTEGER,
  skipped_count INTEGER
) AS $$
DECLARE
  v_account_id UUID;
  v_carrier_id UUID;
  v_product_id UUID;
  v_origin_city_id UUID;
  v_destination_city_id UUID;
  v_inserted INTEGER := 0;
  v_skipped INTEGER := 0;
  v_cities UUID[];
  v_product_carrier_id UUID;
BEGIN
  -- Get current user's account_id
  v_account_id := current_user_account_id();
  
  -- If no cities specified, get all cities for the account
  IF p_city_ids IS NULL THEN
    SELECT ARRAY_AGG(id) INTO v_cities
    FROM cities
    WHERE account_id = v_account_id AND status = 'active';
  ELSE
    v_cities := p_city_ids;
  END IF;
  
  -- Loop through carriers
  FOREACH v_carrier_id IN ARRAY p_carrier_ids
  LOOP
    -- Loop through products
    FOREACH v_product_id IN ARRAY p_product_ids
    LOOP
      -- Check if this product belongs to this carrier
      SELECT carrier_id INTO v_product_carrier_id
      FROM products
      WHERE id = v_product_id;
      
      -- Only generate combinations if product belongs to this carrier
      IF v_product_carrier_id = v_carrier_id THEN
        -- Loop through origin cities
        FOREACH v_origin_city_id IN ARRAY v_cities
        LOOP
          -- Loop through destination cities
          FOREACH v_destination_city_id IN ARRAY v_cities
          LOOP
            -- Skip if same city
            IF v_origin_city_id != v_destination_city_id THEN
              -- Try to insert, skip if already exists
              BEGIN
                INSERT INTO delivery_standards (
                  carrier_id,
                  product_id,
                  origin_city_id,
                  destination_city_id
                ) VALUES (
                  v_carrier_id,
                  v_product_id,
                  v_origin_city_id,
                  v_destination_city_id
                );
                v_inserted := v_inserted + 1;
              EXCEPTION WHEN unique_violation THEN
                v_skipped := v_skipped + 1;
              END;
            END IF;
          END LOOP;
        END LOOP;
      END IF;
    END LOOP;
  END LOOP;
  
  RETURN QUERY SELECT v_inserted, v_skipped;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

SELECT 'Delivery standards generation function fixed' as status;
