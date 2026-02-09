-- Remove mixed_reader_gap_minutes from postal_centers table
-- This parameter is specific to individual readers (only Mixed type), not postal centers

ALTER TABLE postal_centers 
DROP COLUMN IF EXISTS mixed_reader_gap_minutes;

-- Add comment to readers table to clarify usage
COMMENT ON COLUMN readers.mixed_reader_gap_minutes IS 'Time gap in minutes to separate entry/exit events. Only applicable for Mixed type readers. NULL means inherit from account configuration.';
