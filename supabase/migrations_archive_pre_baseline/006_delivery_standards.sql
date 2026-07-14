-- ============================================
-- DELIVERY STANDARDS MODULE
-- ============================================

-- Step 1: Add time_unit to products table
ALTER TABLE products 
  ADD COLUMN time_unit TEXT DEFAULT 'hours' CHECK (time_unit IN ('hours', 'days'));

-- Update existing products to use 'hours' as default
UPDATE products SET time_unit = 'hours' WHERE time_unit IS NULL;

-- Step 2: Create delivery_standards table
CREATE TABLE delivery_standards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  carrier_id UUID NOT NULL REFERENCES carriers(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  origin_city_id UUID NOT NULL REFERENCES cities(id) ON DELETE CASCADE,
  destination_city_id UUID NOT NULL REFERENCES cities(id) ON DELETE CASCADE,
  
  -- Standard delivery configuration
  standard_time DECIMAL(10,2), -- Can be null initially
  success_percentage DECIMAL(5,2) CHECK (success_percentage >= 0 AND success_percentage <= 100), -- Can be null initially
  time_unit TEXT DEFAULT 'hours' CHECK (time_unit IN ('hours', 'days')),
  
  -- Metadata
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  -- Constraints
  CONSTRAINT delivery_standards_unique UNIQUE (carrier_id, product_id, origin_city_id, destination_city_id),
  CONSTRAINT delivery_standards_different_cities CHECK (origin_city_id != destination_city_id)
);

-- Step 3: Create indexes for performance
CREATE INDEX delivery_standards_account_id_idx ON delivery_standards(account_id);
CREATE INDEX delivery_standards_carrier_id_idx ON delivery_standards(carrier_id);
CREATE INDEX delivery_standards_product_id_idx ON delivery_standards(product_id);
CREATE INDEX delivery_standards_origin_city_id_idx ON delivery_standards(origin_city_id);
CREATE INDEX delivery_standards_destination_city_id_idx ON delivery_standards(destination_city_id);
CREATE INDEX delivery_standards_pending_idx ON delivery_standards(standard_time, success_percentage) 
  WHERE standard_time IS NULL OR success_percentage IS NULL;

-- Step 4: Create triggers for account_id
CREATE TRIGGER set_delivery_standards_account_id
  BEFORE INSERT ON delivery_standards
  FOR EACH ROW
  EXECUTE FUNCTION set_account_id();

CREATE TRIGGER prevent_delivery_standards_account_change
  BEFORE UPDATE ON delivery_standards
  FOR EACH ROW
  EXECUTE FUNCTION prevent_account_id_change();

-- Step 5: Create trigger for updated_at
CREATE TRIGGER update_delivery_standards_updated_at
  BEFORE UPDATE ON delivery_standards
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- ============================================
-- RLS POLICIES
-- ============================================

ALTER TABLE delivery_standards ENABLE ROW LEVEL SECURITY;

-- Select policy
CREATE POLICY "delivery_standards_select"
  ON delivery_standards FOR SELECT
  USING (
    current_user_role() = 'superadmin' OR
    account_id = current_user_account_id()
  );

-- Insert policy
CREATE POLICY "delivery_standards_insert"
  ON delivery_standards FOR INSERT
  WITH CHECK (
    current_user_role() IN ('superadmin', 'admin')
  );

-- Update policy
CREATE POLICY "delivery_standards_update"
  ON delivery_standards FOR UPDATE
  USING (
    current_user_role() = 'superadmin' OR
    (current_user_role() = 'admin' AND account_id = current_user_account_id())
  );

-- Delete policy
CREATE POLICY "delivery_standards_delete"
  ON delivery_standards FOR DELETE
  USING (
    current_user_role() = 'superadmin' OR
    (current_user_role() = 'admin' AND account_id = current_user_account_id())
  );

-- ============================================
-- HELPER FUNCTION: Generate combinations
-- ============================================

CREATE OR REPLACE FUNCTION generate_delivery_standards(
  p_carrier_ids UUID[],
  p_product_ids UUID[],
  p_city_ids UUID[] DEFAULT NULL -- If NULL, use all cities for the account
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
    END LOOP;
  END LOOP;
  
  RETURN QUERY SELECT v_inserted, v_skipped;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Verify tables created
SELECT 'Delivery standards module created successfully' as status;
