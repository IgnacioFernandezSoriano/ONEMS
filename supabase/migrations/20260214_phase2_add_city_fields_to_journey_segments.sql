-- ============================================================================
-- Add City Fields to journey_segments
-- ============================================================================
-- Adds city name fields to support complete journey path tracking
-- ============================================================================

-- Add origin and destination city names (from ONE DB via processed_events)
ALTER TABLE journey_segments
  ADD COLUMN IF NOT EXISTS origin_city_name TEXT,
  ADD COLUMN IF NOT EXISTS destination_city_name TEXT;

-- Add from/to postal center city names (for segment-level city tracking)
ALTER TABLE journey_segments
  ADD COLUMN IF NOT EXISTS from_postal_center_city TEXT,
  ADD COLUMN IF NOT EXISTS to_postal_center_city TEXT;

-- Add comments
COMMENT ON COLUMN journey_segments.origin_city_name IS 'Journey origin city from ONE DB';
COMMENT ON COLUMN journey_segments.destination_city_name IS 'Journey destination city from ONE DB';
COMMENT ON COLUMN journey_segments.from_postal_center_city IS 'City of the from postal center for this segment';
COMMENT ON COLUMN journey_segments.to_postal_center_city IS 'City of the to postal center for this segment';

-- Create indexes for query performance
CREATE INDEX IF NOT EXISTS idx_journey_segments_origin_city ON journey_segments(origin_city_name);
CREATE INDEX IF NOT EXISTS idx_journey_segments_destination_city ON journey_segments(destination_city_name);
CREATE INDEX IF NOT EXISTS idx_journey_segments_from_city ON journey_segments(from_postal_center_city);
CREATE INDEX IF NOT EXISTS idx_journey_segments_to_city ON journey_segments(to_postal_center_city);
