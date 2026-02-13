-- =====================================================
-- PHASE 2: Add Carrier and Product to processed_events
-- =====================================================

-- Step 1: Add columns to processed_events table
ALTER TABLE processed_events
ADD COLUMN IF NOT EXISTS carrier_id UUID REFERENCES carriers(id),
ADD COLUMN IF NOT EXISTS product_id UUID REFERENCES products(id);

-- Step 2: Create index for performance
CREATE INDEX IF NOT EXISTS idx_processed_events_carrier_product
ON processed_events(account_id, carrier_id, product_id);

-- Step 3: Verify schema
SELECT 
    column_name, 
    data_type, 
    is_nullable
FROM information_schema.columns
WHERE table_name = 'processed_events'
AND column_name IN ('carrier_id', 'product_id')
ORDER BY ordinal_position;
