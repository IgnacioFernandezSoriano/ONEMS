-- ============================================================================
-- Add Dual Time Tracking to journey_segments
-- ============================================================================
-- This migration adds natural_time and working_time fields to journey_segments
-- to always track both time calculations regardless of calculation_mode.
--
-- Logic:
-- - natural_time_minutes: Always the raw time difference (exit - entry)
-- - working_time_minutes: 
--   * If calculation_mode = 'natural_days': same as natural_time
--   * If calculation_mode = 'working_days': calculated excluding non-working hours
-- ============================================================================

-- Add new fields to journey_segments
ALTER TABLE journey_segments 
  ADD COLUMN IF NOT EXISTS natural_time_in_center_minutes INTEGER,
  ADD COLUMN IF NOT EXISTS working_time_in_center_minutes INTEGER,
  ADD COLUMN IF NOT EXISTS natural_transit_time_minutes INTEGER,
  ADD COLUMN IF NOT EXISTS working_transit_time_minutes INTEGER;

-- Add comments
COMMENT ON COLUMN journey_segments.natural_time_in_center_minutes IS 'Raw time in center (exit - entry), always calculated';
COMMENT ON COLUMN journey_segments.working_time_in_center_minutes IS 'Working time in center: same as natural if calculation_mode=natural_days, or excluding non-working hours if working_days';
COMMENT ON COLUMN journey_segments.natural_transit_time_minutes IS 'Raw transit time between centers (next_entry - exit), always calculated';
COMMENT ON COLUMN journey_segments.working_transit_time_minutes IS 'Working transit time: same as natural if calculation_mode=natural_days, or excluding non-working hours if working_days';

-- Update existing records to populate new fields from old fields
-- (Assuming actual_time_minutes was natural and adjusted_time_minutes was working)
UPDATE journey_segments
SET 
  natural_time_in_center_minutes = actual_time_minutes,
  working_time_in_center_minutes = adjusted_time_minutes
WHERE segment_type = 'operational';

UPDATE journey_segments
SET 
  natural_transit_time_minutes = actual_time_minutes,
  working_transit_time_minutes = adjusted_time_minutes
WHERE segment_type = 'distribution';

-- Optional: Drop old fields if no longer needed
-- (Keep them for now for backwards compatibility)
-- ALTER TABLE journey_segments DROP COLUMN actual_time_minutes;
-- ALTER TABLE journey_segments DROP COLUMN adjusted_time_minutes;

-- Add constraints to ensure times are non-negative
ALTER TABLE journey_segments
  ADD CONSTRAINT journey_segments_natural_time_check 
    CHECK (natural_time_in_center_minutes >= 0 OR natural_time_in_center_minutes IS NULL),
  ADD CONSTRAINT journey_segments_working_time_check 
    CHECK (working_time_in_center_minutes >= 0 OR working_time_in_center_minutes IS NULL),
  ADD CONSTRAINT journey_segments_natural_transit_check 
    CHECK (natural_transit_time_minutes >= 0 OR natural_transit_time_minutes IS NULL),
  ADD CONSTRAINT journey_segments_working_transit_check 
    CHECK (working_transit_time_minutes >= 0 OR working_transit_time_minutes IS NULL);
