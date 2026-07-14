-- =====================================================
-- PHASE 3: Add Carrier and Product to journey_segments
-- =====================================================

-- Step 1: Add columns to journey_segments table
ALTER TABLE journey_segments
ADD COLUMN IF NOT EXISTS carrier_id UUID REFERENCES carriers(id),
ADD COLUMN IF NOT EXISTS product_id UUID REFERENCES products(id);

-- Step 2: Create index for performance
CREATE INDEX IF NOT EXISTS idx_journey_segments_carrier_product
ON journey_segments(account_id, carrier_id, product_id);

-- Step 3: Verify schema
SELECT 
    column_name, 
    data_type, 
    is_nullable
FROM information_schema.columns
WHERE table_name = 'journey_segments'
AND column_name IN ('carrier_id', 'product_id')
ORDER BY ordinal_position;
