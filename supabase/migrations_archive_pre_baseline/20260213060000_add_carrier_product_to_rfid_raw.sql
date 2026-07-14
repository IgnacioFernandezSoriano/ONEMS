-- =====================================================
-- Migration: Add carrier and product to rfid_events_raw
-- =====================================================
-- Description: Adds carrier_id and product_id to raw EPCIS events table
-- Date: 2026-02-13
-- =====================================================

-- Step 1: Add columns
ALTER TABLE rfid_events_raw 
ADD COLUMN IF NOT EXISTS carrier_id UUID REFERENCES carriers(id),
ADD COLUMN IF NOT EXISTS product_id UUID REFERENCES products(id);

-- Step 2: Create index for performance
CREATE INDEX IF NOT EXISTS idx_rfid_raw_carrier_product 
ON rfid_events_raw(account_id, carrier_id, product_id);

-- Step 3: Add comment
COMMENT ON COLUMN rfid_events_raw.carrier_id IS 'Reference to the carrier handling this shipment';
COMMENT ON COLUMN rfid_events_raw.product_id IS 'Reference to the product/service type (e.g., EXPRESS, STANDARD)';

-- Verification query
SELECT 
    column_name, 
    data_type, 
    is_nullable
FROM information_schema.columns
WHERE table_name = 'rfid_events_raw'
AND column_name IN ('carrier_id', 'product_id')
ORDER BY ordinal_position;
