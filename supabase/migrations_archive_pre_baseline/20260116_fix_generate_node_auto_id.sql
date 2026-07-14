-- Fix generate_node_auto_id to handle multiple cities with same code across accounts
-- The issue: When there are 2 cities with code "MAD" in different regions/accounts,
-- the JOIN returns multiple rows causing "Cannot coerce to single JSON object" error

CREATE OR REPLACE FUNCTION generate_node_auto_id(
  p_city_id UUID
)
RETURNS TEXT
LANGUAGE plpgsql
AS $$
DECLARE
  v_region_code TEXT;
  v_city_code TEXT;
  v_node_count INT;
  v_auto_id TEXT;
  v_account_id UUID;
BEGIN
  -- Get account_id, region and city codes in a single query
  SELECT c.account_id, r.code, c.code
  INTO v_account_id, v_region_code, v_city_code
  FROM cities c
  JOIN regions r ON c.region_id = r.id
  WHERE c.id = p_city_id
  LIMIT 1;  -- Ensure single row even if there are duplicates
  
  -- Count existing nodes in this city (filtered by account_id for safety)
  SELECT COUNT(*) + 1
  INTO v_node_count
  FROM nodes
  WHERE city_id = p_city_id
    AND account_id = v_account_id;
  
  -- Generate auto_id: REGION-CITY-NNN
  v_auto_id := v_region_code || '-' || v_city_code || '-' || LPAD(v_node_count::TEXT, 3, '0');
  
  RETURN v_auto_id;
END;
$$;
