-- ============================================
-- SMART GENERATION: Optional parameters with intelligent defaults
-- ============================================

-- Drop the old function
DROP FUNCTION IF EXISTS generate_delivery_standards(UUID[], UUID[], UUID[]);

-- Create smart generation function with optional parameters
CREATE OR REPLACE FUNCTION generate_delivery_standards(
  p_carrier_ids UUID[] DEFAULT NULL,
  p_product_ids UUID[] DEFAULT NULL,
  p_origin_city_ids UUID[] DEFAULT NULL,
  p_destination_city_ids UUID[] DEFAULT NULL
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
  v_carriers UUID[];
  v_products UUID[];
  v_origin_cities UUID[];
  v_destination_cities UUID[];
  v_carrier_products UUID[];
BEGIN
  -- Get current user's account_id
  v_account_id := current_user_account_id();
  
  -- If no carriers specified, get ALL carriers for the account
  IF p_carrier_ids IS NULL OR array_length(p_carrier_ids, 1) IS NULL THEN
    SELECT ARRAY_AGG(id) INTO v_carriers
    FROM carriers
    WHERE account_id = v_account_id AND status = 'active';
  ELSE
    v_carriers := p_carrier_ids;
  END IF;
  
  -- If no origin cities specified, get ALL cities for the account
  IF p_origin_city_ids IS NULL OR array_length(p_origin_city_ids, 1) IS NULL THEN
    SELECT ARRAY_AGG(id) INTO v_origin_cities
    FROM cities
    WHERE account_id = v_account_id AND status = 'active';
  ELSE
    v_origin_cities := p_origin_city_ids;
  END IF;
  
  -- If no destination cities specified, get ALL cities for the account
  IF p_destination_city_ids IS NULL OR array_length(p_destination_city_ids, 1) IS NULL THEN
    SELECT ARRAY_AGG(id) INTO v_destination_cities
    FROM cities
    WHERE account_id = v_account_id AND status = 'active';
  ELSE
    v_destination_cities := p_destination_city_ids;
  END IF;
  
  -- Loop through carriers
  FOREACH v_carrier_id IN ARRAY v_carriers
  LOOP
    -- Get products for this carrier
    -- If products were specified, filter to only those that belong to this carrier
    -- If no products specified, get ALL products for this carrier
    IF p_product_ids IS NULL OR array_length(p_product_ids, 1) IS NULL THEN
      -- Get ALL products for this carrier
      SELECT ARRAY_AGG(id) INTO v_carrier_products
      FROM products
      WHERE carrier_id = v_carrier_id AND status = 'active';
    ELSE
      -- Get only specified products that belong to this carrier
      SELECT ARRAY_AGG(id) INTO v_carrier_products
      FROM products
      WHERE carrier_id = v_carrier_id 
        AND id = ANY(p_product_ids)
        AND status = 'active';
    END IF;
    
    -- Skip if no products found for this carrier
    IF v_carrier_products IS NULL OR array_length(v_carrier_products, 1) IS NULL THEN
      CONTINUE;
    END IF;
    
    -- Loop through products of this carrier
    FOREACH v_product_id IN ARRAY v_carrier_products
    LOOP
      -- Loop through origin cities
      FOREACH v_origin_city_id IN ARRAY v_origin_cities
      LOOP
        -- Loop through destination cities
        FOREACH v_destination_city_id IN ARRAY v_destination_cities
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
    END LOOP;
  END LOOP;
  
  RETURN QUERY SELECT v_inserted, v_skipped;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

SELECT 'Smart delivery standards generation implemented' as status;
