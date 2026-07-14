-- ============================================================================
-- Create journey_paths Table
-- ============================================================================
-- Stores aggregated route performance data for analysis and visualization.
-- Each row represents a unique path (sequence of postal centers) taken by
-- tags with the same carrier/product/origin/destination combination.
-- ============================================================================

CREATE TABLE IF NOT EXISTS journey_paths (
  -- Primary key
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Account isolation
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  
  -- Journey dimensions
  carrier_id UUID NOT NULL REFERENCES carriers(id),
  product_id UUID NOT NULL REFERENCES products(id),
  origin_city_name TEXT NOT NULL,
  destination_city_name TEXT NOT NULL,
  
  -- Path signature (unique identifier for this route)
  path_signature TEXT NOT NULL,
  -- Example: "Baltimore→Philadelphia→New York"
  
  -- Path segments (ordered list of centers)
  path_segments JSONB NOT NULL,
  -- Example: [
  --   {"from": "Baltimore", "to": "Philadelphia", "from_center_id": "uuid1", "to_center_id": "uuid2"},
  --   {"from": "Philadelphia", "to": "New York", "from_center_id": "uuid2", "to_center_id": "uuid3"}
  -- ]
  
  -- Aggregated metrics
  total_tags INTEGER NOT NULL DEFAULT 0,
  -- Number of tags that took this path
  
  avg_natural_time_minutes INTEGER,
  -- Average total natural time for this path
  
  avg_working_time_minutes INTEGER,
  -- Average total working time for this path
  
  expected_time_minutes INTEGER,
  -- Expected time from delivery_standards (if applicable)
  
  compliance_rate NUMERIC(5,2),
  -- Percentage of tags that met SLA (0-100)
  
  -- Segment-level details (for drill-down)
  segment_details JSONB,
  -- Example: [
  --   {
  --     "from": "Baltimore",
  --     "to": "Philadelphia",
  --     "avg_time_in_center": 15,
  --     "avg_transit_time": 45,
  --     "avg_total_time": 60,
  --     "expected_time": 60,
  --     "compliance_rate": 0.95,
  --     "tags_count": 8500
  --   },
  --   ...
  -- ]
  
  -- Timestamps
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  
  -- Unique constraint on path per account/carrier/product/origin/destination
  CONSTRAINT journey_paths_unique_path UNIQUE (
    account_id, 
    carrier_id, 
    product_id, 
    origin_city_name, 
    destination_city_name, 
    path_signature
  )
);

-- Indexes for query performance
CREATE INDEX idx_journey_paths_account_id ON journey_paths(account_id);
CREATE INDEX idx_journey_paths_carrier_id ON journey_paths(carrier_id);
CREATE INDEX idx_journey_paths_product_id ON journey_paths(product_id);
CREATE INDEX idx_journey_paths_origin_city ON journey_paths(origin_city_name);
CREATE INDEX idx_journey_paths_destination_city ON journey_paths(destination_city_name);
CREATE INDEX idx_journey_paths_path_signature ON journey_paths(path_signature);
CREATE INDEX idx_journey_paths_total_tags ON journey_paths(total_tags DESC);
CREATE INDEX idx_journey_paths_compliance_rate ON journey_paths(compliance_rate);

-- Comments
COMMENT ON TABLE journey_paths IS 'Aggregated route performance data for analysis';
COMMENT ON COLUMN journey_paths.path_signature IS 'Unique identifier for route sequence (e.g., "Baltimore→Philadelphia→NYC")';
COMMENT ON COLUMN journey_paths.path_segments IS 'Ordered list of center-to-center segments in this route';
COMMENT ON COLUMN journey_paths.total_tags IS 'Number of tags that took this specific path';
COMMENT ON COLUMN journey_paths.avg_natural_time_minutes IS 'Average total natural time for this path';
COMMENT ON COLUMN journey_paths.avg_working_time_minutes IS 'Average total working time for this path';
COMMENT ON COLUMN journey_paths.compliance_rate IS 'Percentage of tags meeting SLA (0-100)';
COMMENT ON COLUMN journey_paths.segment_details IS 'Detailed metrics for each segment in the path';

-- Enable Row Level Security
ALTER TABLE journey_paths ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can only see paths from their account
CREATE POLICY journey_paths_account_isolation ON journey_paths
  FOR ALL
  USING (account_id = auth.uid()::uuid);
