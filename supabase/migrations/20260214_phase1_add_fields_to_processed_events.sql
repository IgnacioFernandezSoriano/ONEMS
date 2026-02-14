-- ============================================================================
-- Add Missing Fields to processed_events
-- ============================================================================
-- Adds carrier_id, product_id, origin/destination city fields to support
-- complete EPCIS data flow from ONE DB.
-- ============================================================================

-- Add carrier and product dimensions
ALTER TABLE processed_events
  ADD COLUMN IF NOT EXISTS carrier_id UUID REFERENCES carriers(id),
  ADD COLUMN IF NOT EXISTS product_id UUID REFERENCES products(id);

-- Add origin and destination city names (from ONE DB)
ALTER TABLE processed_events
  ADD COLUMN IF NOT EXISTS origin_city_name TEXT,
  ADD COLUMN IF NOT EXISTS destination_city_name TEXT;

-- Add comments
COMMENT ON COLUMN processed_events.carrier_id IS 'Carrier ID from ONE DB lookup by tag_id';
COMMENT ON COLUMN processed_events.product_id IS 'Product ID from ONE DB lookup by tag_id';
COMMENT ON COLUMN processed_events.origin_city_name IS 'Origin city from ONE DB (journey start)';
COMMENT ON COLUMN processed_events.destination_city_name IS 'Destination city from ONE DB (journey end)';

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_processed_events_carrier_id ON processed_events(carrier_id);
CREATE INDEX IF NOT EXISTS idx_processed_events_product_id ON processed_events(product_id);
CREATE INDEX IF NOT EXISTS idx_processed_events_origin_city ON processed_events(origin_city_name);
CREATE INDEX IF NOT EXISTS idx_processed_events_destination_city ON processed_events(destination_city_name);
