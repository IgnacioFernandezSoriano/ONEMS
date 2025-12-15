-- Migration 022: Add population field to cities table
-- Purpose: Enable population-based impact analysis in Territory Equity Report
-- Date: 2025-12-13

-- Add population field
ALTER TABLE cities ADD COLUMN IF NOT EXISTS population INTEGER;

-- Add constraint
ALTER TABLE cities ADD CONSTRAINT cities_population_positive 
  CHECK (population IS NULL OR population > 0);

-- Add comment
COMMENT ON COLUMN cities.population IS 
  'Total population of the city (used for impact analysis in reporting)';

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_cities_population ON cities(population) 
  WHERE population IS NOT NULL;

-- Verify
SELECT 'Migration 022: population field added to cities table' as status;
