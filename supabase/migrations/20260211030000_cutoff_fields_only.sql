-- Sprint 10: Add cut-off and working hours fields to postal_centers
-- (non_working_days table already exists, no changes needed)

-- Add missing fields to postal_centers
ALTER TABLE postal_centers
ADD COLUMN IF NOT EXISTS working_hours_end TIME,
ADD COLUMN IF NOT EXISTS working_days TEXT[] DEFAULT ARRAY['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
ADD COLUMN IF NOT EXISTS timezone TEXT DEFAULT 'UTC';

-- Set default working_hours_end if not set (18:00)
UPDATE postal_centers
SET working_hours_end = '18:00:00'
WHERE working_hours_end IS NULL;

-- Add comments
COMMENT ON COLUMN postal_centers.opening_hour IS 'Working hours start time';
COMMENT ON COLUMN postal_centers.cutoff_time IS 'Daily cut-off time for processing';
COMMENT ON COLUMN postal_centers.working_hours_end IS 'Working hours end time';
COMMENT ON COLUMN postal_centers.working_days IS 'Array of working days (Monday, Tuesday, etc.)';
COMMENT ON COLUMN postal_centers.timezone IS 'Timezone for this postal center (e.g., UTC, Europe/Madrid)';
